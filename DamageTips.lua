--[[
    DamageTips
    Copyright (C) 2026 Malikor - GPL-3.0-or-later (see LICENSE.txt)

    Adds DPS, DPM (damage per minute), optional damage per mana, and mana cost
    to spell tooltips on the action bars and in the spellbook.

    Slash commands: /damagetips (opens settings), /damagetips help
]]

local ADDON_NAME, addon = ...
local Estimates = addon.SpellEstimates

----------------------------------------------------------------------
-- Cached globals (Lua 5.1: avoid repeated _G lookups in hover paths)
----------------------------------------------------------------------
local _G = _G
local pairs, ipairs, type, tonumber, tostring, pcall = pairs, ipairs, type, tonumber, tostring, pcall
local math_max, math_min, math_floor = math.max, math.min, math.floor
local string_format, table_concat, table_sort = string.format, table.concat, table.sort
local wipe, tinsert, print = wipe, tinsert, print
local CreateFrame, hooksecurefunc, GetTime = CreateFrame, hooksecurefunc, GetTime
local IsShiftKeyDown = IsShiftKeyDown
local UnitPowerMax, GetActionInfo = UnitPowerMax, GetActionInfo
local GetMacroSpell, GetSpellBaseCooldown = GetMacroSpell, GetSpellBaseCooldown
local C_Spell, C_SpellBook, C_TooltipInfo = C_Spell, C_SpellBook, C_TooltipInfo
local GameTooltip = GameTooltip

-- Forever follows Midnight's secret-value rules: tainted code may not read,
-- compare or do maths on secret values, so every game value is checked first.
local IsSecret = issecretvalue or function() return false end

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
local FONT_MIN, FONT_MAX = 8, 20
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local BANK_PLAYER = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
local BANK_PET = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet) or 1
local ACTION, BOOK = 1, 2
local OUTLINES = { "", "OUTLINE", "THICKOUTLINE" }
local DPS_FORMATS = { [0] = "%.0f", [1] = "%.1f", [2] = "%.2f" }

local DEBUG = false
local DB
local BuildMinimapButton, RefreshMinimapButton, RefreshConfig

local DEFAULTS = {
    showDPS       = true,   -- "DPS: x"
    showDPM       = true,   -- "DPM: x" (damage per minute)
    showHealing   = true,   -- "HPS: x   HPM: y" and the absorb line on healing spells
    showRange     = false,  -- "Damage: 59-65 (avg 62)"
    showDPC       = false,  -- "Damage per cast: x"
    schoolTint    = false,  -- tint the damage lines by spell school
    showNextRank  = false,  -- next-rank damage or healing comparison
    shiftDetails  = true,   -- hold Shift while hovering for the full breakdown
    showMinimap   = true,   -- minimap button (addon compartment always available)
    showMana      = true,   -- mana cost line
    showDPMana    = false,  -- "Damage per mana: x" (opt-in)
    showManaSustain = false,
    showCasterStats = false,
    showPowerScaling = false,
    showExpectedThroughput = false,
    spellRules    = {},     -- per-spell overrides: spellID string -> "hide" | avg damage number
    healColor     = { 0.45, 0.85, 0.45 },
    showActionBar = true,   -- add lines to action bar tooltips
    showSpellbook = true,   -- add lines to spellbook tooltips
    includeDoT    = true,   -- count damage-over-time in the totals
    gcdFloor      = true,   -- never divide by less than the spell's GCD
    dpsDecimals   = 1,      -- 0, 1 or 2
    manaMode      = 1,      -- 1 = percent, 2 = amount, 3 = both
    thousands     = false,  -- 1,234 instead of 1234
    fontSize      = 12,
    fontOutline   = 1,      -- 1 = none, 2 = outline, 3 = thick outline
    damageColor   = { 1, 0.82, 0 },   -- gold
    manaColor     = { 0.4, 0.6, 1 },  -- blue
}
local BOOL_KEYS = { "showDPS", "showDPM", "showMana", "showDPMana", "showActionBar",
                    "showSpellbook", "includeDoT", "gcdFloor", "thousands",
                    "showHealing", "showRange", "showDPC", "schoolTint",
                    "showNextRank", "shiftDetails", "showMinimap",
                    "showManaSustain", "showCasterStats", "showPowerScaling",
                    "showExpectedThroughput" }
local ENUMS = { dpsDecimals = { 0, 1, 2 }, manaMode = { 1, 2, 3 }, fontOutline = { 1, 2, 3 } }
local COLOR_KEYS = { "damageColor", "healColor", "manaColor" }
local DEFAULT_MINIMAP_ANGLE = 215
local MAX_SPELL_ID = 4294967295

local PREFIX = "|cffffd100DamageTips|r: "
local function Print(msg) print(PREFIX .. msg) end

----------------------------------------------------------------------
-- Saved variables: validate everything, never trust the WTF contents
----------------------------------------------------------------------
local function FiniteNumber(value)
    if IsSecret(value) then return nil end
    local kind = type(value)
    if kind ~= "number" and kind ~= "string" then return nil end
    local n = tonumber(value)
    if n and n > -math.huge and n < math.huge then return n end
end

local function SpellIDKey(value)
    local id = FiniteNumber(value)
    if id and id > 0 and id <= MAX_SPELL_ID and id == math_floor(id) then
        return string_format("%.0f", id)
    end
end

local function ReadRuleValue(value)
    if IsSecret(value) then return nil end
    if value == "hide" then return value end
    local number = FiniteNumber(value)
    if number and number >= 0 then return number end
end

local function ReadEnum(value, allowed)
    local n = FiniteNumber(value)
    for _, option in ipairs(allowed) do
        if n == option then return n end
    end
end

local function NormalizeAngle(n)
    local angle = math.fmod(n, 360)
    if angle < 0 then angle = angle + 360 end
    return angle < 360 and angle or 0
end

local function SanitizeColor(c, default)
    if type(c) ~= "table" then c = {} end
    local color = {}
    for i = 1, 3 do
        local v = FiniteNumber(c[i])
        if not v then v = default[i] end
        color[i] = math_min(1, math_max(0, v))
    end
    return color
end

local function SanitizeRules(source)
    local rules, aliases = {}, {}
    if type(source) ~= "table" then return rules end
    for id, value in pairs(source) do
        local key, rule = SpellIDKey(id), ReadRuleValue(value)
        if key and rule ~= nil then
            if key == id then
                rules[key] = rule
            elseif not aliases[key] or tostring(id) < aliases[key].original then
                aliases[key] = { original = tostring(id), value = rule }
            end
        end
    end
    for key, alias in pairs(aliases) do
        if rules[key] == nil then rules[key] = alias.value end
    end
    return rules
end

local function InitDB()
    if type(DamageTipsDB) ~= "table" then DamageTipsDB = {} end
    local db = DamageTipsDB

    -- 1.2 -> 1.3: the single "showDamage" flag became separate DPS / DPM flags
    if type(db.showDamage) == "boolean" then
        if type(db.showDPS) ~= "boolean" then db.showDPS = db.showDamage end
        if type(db.showDPM) ~= "boolean" then db.showDPM = db.showDamage end
    end
    db.showDamage = nil

    for _, key in ipairs(BOOL_KEYS) do
        if type(db[key]) ~= "boolean" then db[key] = DEFAULTS[key] end
    end
    for key, allowed in pairs(ENUMS) do
        db[key] = ReadEnum(db[key], allowed) or DEFAULTS[key]
    end

    local size = FiniteNumber(db.fontSize) or DEFAULTS.fontSize
    db.fontSize = math_min(FONT_MAX, math_max(FONT_MIN, math_floor(size + 0.5)))

    for _, key in ipairs(COLOR_KEYS) do
        db[key] = SanitizeColor(db[key], DEFAULTS[key])
    end
    db.minimapAngle = NormalizeAngle(FiniteNumber(db.minimapAngle) or DEFAULT_MINIMAP_ANGLE)
    db.spellRules = SanitizeRules(db.spellRules)

    DB = db
end

----------------------------------------------------------------------
-- Bounded cache for public parsed spell text only
----------------------------------------------------------------------
local PARSE_CACHE_SIZE, MAX_CACHED_TEXT_BYTES = 64, 8192
local parseCache, parseSlots, nextParseSlot = {}, {}, 1
local PET_BOOK = 3

local function InvalidateCache()
    wipe(parseCache)
    wipe(parseSlots)
    nextParseSlot = 1
end

local function RemoveParseEntry(spellID, source)
    local entries = parseCache[source]
    if not entries then return end
    local entry = entries[spellID]
    if not entry then return end
    entries[spellID], parseSlots[entry.slot] = nil, nil
end

local function ParsePublicText(spellID, source, text, model, wantsExpected)
    if #text > MAX_CACHED_TEXT_BYTES then
        RemoveParseEntry(spellID, source)
        return Estimates.ParseComponents(text, model, wantsExpected)
    end
    local entries = parseCache[source]
    if not entries then entries = {}; parseCache[source] = entries end
    local entry = entries[spellID]
    -- Locale is fixed for the session, as it is in the parser. Model identity
    -- is resolved from the exact build separately on each relevant hover.
    if entry and entry.text == text and entry.model == model and entry.wantsExpected == wantsExpected then
        return entry.parsed
    end

    local parsed = Estimates.ParseComponents(text, model, wantsExpected)
    if not entry then
        local slot = nextParseSlot
        local old = parseSlots[slot]
        if old then RemoveParseEntry(old.spellID, old.source) end
        entry = { spellID = spellID, source = source, slot = slot }
        entries[spellID], parseSlots[slot] = entry, entry
        nextParseSlot = slot % PARSE_CACHE_SIZE + 1
    end
    entry.text, entry.model, entry.wantsExpected, entry.parsed = text, model, wantsExpected, parsed
    return parsed
end

local function CopyColor(dst, src)
    dst[1], dst[2], dst[3] = src[1], src[2], src[3]
end

local function SettingsChanged(minimapChanged)
    if minimapChanged then
        BuildMinimapButton()
    end
    if RefreshConfig then RefreshConfig() end
end

local function SetOption(key, value)
    DB[key] = value
    SettingsChanged(key == "showMinimap")
end

local function ResetDB()
    -- Spell rules and the minimap position are independent user customizations.
    for _, key in ipairs(BOOL_KEYS) do DB[key] = DEFAULTS[key] end
    for key in pairs(ENUMS) do DB[key] = DEFAULTS[key] end
    DB.fontSize = DEFAULTS.fontSize
    for _, key in ipairs(COLOR_KEYS) do CopyColor(DB[key], DEFAULTS[key]) end
    SettingsChanged(true)
end

----------------------------------------------------------------------
-- Line text (shared by the tooltip and the settings preview)
----------------------------------------------------------------------
local function Group(str) -- "1234567.5" -> "1,234,567.5"
    local int, rest = str:match("^(%d+)(.*)$")
    if not int then return str end
    int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return int .. rest
end

local function FormatNumber(str)
    if DB.thousands then return Group(str) end
    return str
end

local function ManaSustainLineText(casts, netCost)
    if casts == nil then return nil end
    if casts == 0 then return "Mana sustain: not enough mana for one cast" end
    if casts == false then return "Mana sustain: sustainable at this cadence" end
    return string_format("Mana sustain: ~%s %s (%s net mana per cycle)",
        FormatNumber(string_format("%.0f", casts)), casts == 1 and "cast" or "casts",
        FormatNumber(string_format("%.2f", netCost)))
end

local function OutputBeforeLowManaText(casts, average, label)
    if not casts or casts <= 0 or not average or average <= 0 then return nil end
    local total = casts * average
    if total >= math.huge then return nil end
    return string_format("Before low mana: ~%s %s", FormatNumber(string_format("%.0f", total)), label)
end

local function FormatPowerGain(coefficient)
    return (string_format("%.1f", coefficient * 100):gsub("%.0$", ""))
end

local function PowerScalingLineText(stat, coefficient, output, unit)
    local gain = FormatPowerGain(coefficient)
    return string_format("+100 %s: +%s %s / %s (nominal)", stat, gain, output, unit or "cast")
end

local function PeriodicScalingLineText(stat, effect, output)
    if effect.perRecipient then
        return string_format("+100 %s: +%s total %s per recipient (nominal)",
            stat, FormatPowerGain(effect.coefficient * effect.ticks), output)
    end
    return string_format("+100 %s: +%s %s / tick (+%s over %d ticks)",
        stat, FormatPowerGain(effect.coefficient), output,
        FormatPowerGain(effect.coefficient * effect.ticks), effect.ticks)
end

local function ExpectedLineText(kind, rate, hit, crit, effect, target, modifiers, baselineHealing)
    local value = FormatNumber(string_format(DPS_FORMATS[DB.dpsDecimals], rate))
    local context, resistText = "equal-level PvE", ""
    if target and kind == "spell" then
        local detail = target.resistance and "" or (modifiers and modifiers.targetAura and ", level + aura" or ", level only")
        context = string_format("target L%d%s", target.level, detail)
        if target.resistance then
            resistText = string_format(", %s resist %.4g", target.resistClass, target.resistance)
        end
    end
    if effect then
        local period = effect.channel and (effect.channel .. " channel") or "full effect"
        local critText = crit and string_format("%.1f%% crit", crit) or "no crit rolls"
        if kind == "healing" then
            if effect.perRecipient then period = "per recipient, " .. period end
            if modifiers and modifiers.tickCrit then
                critText = string_format("%.1f%% direct crit, %.1f%% tick crit", crit, modifiers.tickCrit)
            end
            return string_format("Expected HPS (%s): %s (%s)", period, value, critText)
        end
        local hitUnit = effect.hitMode == "tick" and "hit per missile" or "hit"
        return string_format("Expected DPS (%s, %s): %s (%.1f%% %s, %s%s)",
            period, context, value, hit, hitUnit, critText, resistText)
    end
    if kind == "healing" then
        if baselineHealing then
            return string_format("Expected HPS (baseline): %s (%.1f%% sheet crit)", value, crit)
        end
        return string_format("Expected HPS: %s (%.1f%% crit)", value, crit)
    elseif kind == "landed" then
        if target then
            return string_format("DPS on landed hits (target L%d, armor): %s (%.1f%% crit, %.1f%% armor reduction)",
                target.level, value, crit, target.armorReduction * 100)
        end
        return string_format("DPS on landed hits: %s (%.1f%% crit)", value, crit)
    end
    return string_format("Expected DPS (%s): %s (%.1f%% hit, %.1f%% crit%s)", context, value, hit, crit, resistText)
end

local function DamageLineText(dps)
    local a = DB.showDPS and ("DPS: " .. FormatNumber(string_format(DPS_FORMATS[DB.dpsDecimals], dps))) or nil
    local b = DB.showDPM and ("DPM: " .. FormatNumber(string_format("%.0f", dps * 60))) or nil
    if a and b then return a .. "   " .. b end
    return a or b or false
end

local function EfficiencyLineText(total, cost)
    if not DB.showDPMana or not cost or cost <= 0 or total <= 0 then return false end
    return "Damage per mana: " .. FormatNumber(string_format("%.2f", total / cost))
end

local function RangeLineText(lo, hi)
    if not DB.showRange or not lo or not hi or lo == hi then return false end
    return string_format("Damage: %s-%s (avg %s)",
        FormatNumber(string_format("%.0f", lo)),
        FormatNumber(string_format("%.0f", hi)),
        FormatNumber(string_format("%.0f", (lo + hi) / 2)))
end

local function DPCLineText(total)
    if not DB.showDPC or not total or total <= 0 then return false end
    return "Damage per cast: " .. FormatNumber(string_format("%.0f", total))
end

local function HealLineText(hps, perRecipient)
    if not DB.showHealing or not hps or hps <= 0 then return false end
    local a = "HPS: " .. FormatNumber(string_format(DPS_FORMATS[DB.dpsDecimals], hps))
    local b = "HPM: " .. FormatNumber(string_format("%.0f", hps * 60))
    return a .. "   " .. b .. (perRecipient and " (per recipient)" or "")
end

local function HealEffLineText(htotal, cost, perRecipient)
    if not DB.showDPMana or not DB.showHealing or not cost or cost <= 0 or not htotal or htotal <= 0 then
        return false
    end
    local label = perRecipient and "Healing per mana (per recipient): " or "Healing per mana: "
    return label .. FormatNumber(string_format("%.2f", htotal / cost))
end

local function AbsorbLineText(absorb)
    if not DB.showHealing or not absorb or absorb <= 0 then return false end
    return "Absorbs: " .. FormatNumber(string_format("%.0f", absorb))
end

local function NextRankLineText(dps, nextDPS)
    if not DB.showNextRank or not dps or dps <= 0 or not nextDPS then return false end
    return string_format("Next rank: DPS %s (%+.0f%%)",
        FormatNumber(string_format(DPS_FORMATS[DB.dpsDecimals], nextDPS)),
        (nextDPS - dps) / dps * 100)
end

local function NextRankHealingLineText(metric, current, nextValue, precision, perRecipient)
    if not FiniteNumber(current) or current <= 0 or not FiniteNumber(nextValue) or nextValue <= 0 then return end
    local delta = (nextValue - current) / current * 100
    if not FiniteNumber(delta) then return end
    local scope = perRecipient and " (per recipient)" or ""
    return string_format("Next rank: healing per %s%s %s (%+.0f%%)", metric, scope,
        FormatNumber(string_format(precision, nextValue)), delta)
end


-- Breakdown lines supplement output that is already visible in the tooltip.
local function BuildDetailLines(t, damage, healing, absorb)
    if not DB.shiftDetails or not (damage or healing or absorb) then return nil end
    local lines = {}
    local function add(line) lines[#lines + 1] = line end
    local function amount(value) return FormatNumber(string_format("%.0f", value)) end
    local function direct(label, low, high)
        if not low or low <= 0 and high <= 0 then return end
        if low == high then
            add(label .. ": " .. amount(low))
        else
            add(string_format("%s: %s-%s (avg %s)", label, amount(low), amount(high),
                amount(low + (high - low) / 2)))
        end
    end
    local function periodic(label, total, duration)
        if total and total > 0 then
            add(string_format("%s: %s over %s sec", label, amount(total), tostring(duration or "?")))
        end
    end
    if damage then
        direct("Direct damage", t.lo, t.hi)
        periodic("Damage over time", t.dot, t.dotDur)
        if t.time then add(string_format("Damage divisor: %.2f sec", t.time)) end
        if t.school then add("School: " .. t.school:sub(1, 1):upper() .. t.school:sub(2)) end
    end
    if healing then
        direct("Direct healing", t.hLo, t.hHi)
        periodic(t.healingPerRecipient and "Healing over time per recipient" or "Healing over time",
            t.hot, t.hotDur)
        if t.htime then add(string_format("Healing divisor: %.2f sec", t.htime)) end
    end
    if absorb then add("Absorb per cast: " .. amount(t.absorb)) end
    return #lines > 0 and lines or nil
end

local function ManaLineText(cost, maxMana)
    if not DB.showMana or not cost or cost <= 0 then return false end
    local amount = FormatNumber(string_format("%.0f", cost))
    local mode = DB.manaMode
    if mode == 2 then return "Mana cost: " .. amount end
    if not maxMana or maxMana <= 0 then
        return false
    end
    local pct = cost / maxMana * 100
    if mode == 3 then return string_format("Mana cost: %s (%.1f%%)", amount, pct) end
    return string_format("Mana cost: %.1f%% of max mana", pct)
end

----------------------------------------------------------------------
-- Spell data (Mainline API only; every value guarded against secrets)
----------------------------------------------------------------------

local function ReadMilliseconds(value)
    if IsSecret(value) or type(value) ~= "number" or value < 0 or value >= math.huge or value ~= value then
        return nil
    end
    return value / 1000
end

local function GetCastTime(spellID)
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
    if not ok or IsSecret(info) or type(info) ~= "table" then return nil end
    return ReadMilliseconds(info.castTime)
end

local function GetBaseTimings(spellID)
    if not GetSpellBaseCooldown then return nil end
    local ok, cdMS, gcdMS = pcall(GetSpellBaseCooldown, spellID)
    if not ok then return nil end
    return ReadMilliseconds(cdMS), ReadMilliseconds(gcdMS)
end

local function GetBaseCycle(spellID)
    local cd, gcd = GetBaseTimings(spellID)
    local cast = GetCastTime(spellID)
    if cd and gcd and cast then
        return math_max(cast, cd, DB.gcdFloor and gcd or 0)
    end
end

-- Use a public description, or the client's explicitly typed description
-- lines, before considering a load request. Never parse titles, cast/cost
-- lines, or FontString:GetText().
local SPELL_DESCRIPTION = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SpellDescription
local function GetSpellText(spellID, isPet)
    if C_Spell and C_Spell.GetSpellDescription then
        local ok, desc = pcall(C_Spell.GetSpellDescription, spellID)
        if ok then
            if IsSecret(desc) then return "", true, false end
            if type(desc) == "string" and desc:find("%S") then return desc, false, true end
        end
    end
    if not (SPELL_DESCRIPTION and C_TooltipInfo and C_TooltipInfo.GetSpellByID) then return "", false, false end
    local ok, data = pcall(C_TooltipInfo.GetSpellByID, spellID, isPet)
    if not ok then return "", false, false end
    if IsSecret(data) then return "", true, false end
    if type(data) ~= "table" then return "", false, false end

    local lines = data.lines
    if IsSecret(lines) then return "", true, false end
    if type(lines) ~= "table" then return "", false, false end
    local parts
    for i = 1, #lines do
        local line = lines[i]
        if IsSecret(line) then return "", true, false end
        if type(line) == "table" then
            local kind = line.type
            if IsSecret(kind) then return "", true, false end
            if kind == SPELL_DESCRIPTION then
                local value = line.leftText
                if IsSecret(value) then return "", true, false end
                if type(value) == "string" and value:find("%S") then
                    parts = parts or {}
                    parts[#parts + 1] = value
                end
            end
        end
    end
    if parts then return table_concat(parts, " "), false, true end
    return "", false, false
end

local function GetTooltipFontPath()
    return (GameTooltipText and GameTooltipText:GetFont()) or STANDARD_TEXT_FONT
end

local SCHOOL_COLORS = {
    frost = { 0.62, 0.8, 1 }, fire = { 1, 0.5, 0.25 }, shadow = { 0.6, 0.45, 0.9 },
    holy = { 1, 0.9, 0.5 }, nature = { 0.55, 0.9, 0.45 }, arcane = { 1, 0.55, 0.85 },
    physical = { 1, 1, 1 },
}

------------------------------------------------------------------------ Spell rank index (spellbook scan; rebuilt when the spellbook changes)
----------------------------------------------------------------------
local nextRanks, rankIndexDirty = {}, true

local function IsWholeNumber(value, minimum)
    return not IsSecret(value) and type(value) == "number" and value >= minimum
        and value < math.huge and value == math_floor(value)
end

local function RebuildRankIndex()
    local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    if not spellType or not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
        and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo) then return end

    local count = C_SpellBook.GetNumSpellBookSkillLines()
    if not IsWholeNumber(count, 0) then return end
    local matches, seen = {}, {}
    for line = 1, count do
        local skill = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if not IsSecret(skill) and type(skill) == "table" then
            local offset, size = skill.itemIndexOffset, skill.numSpellBookItems
            if IsWholeNumber(offset, 0) and IsWholeNumber(size, 0) then
                local names = {}
                for slot = offset + 1, offset + size do
                    local info = C_SpellBook.GetSpellBookItemInfo(slot, BANK_PLAYER)
                    if not IsSecret(info) and type(info) == "table" then
                        local kind, id, name, subName = info.itemType, info.spellID, info.name, info.subName
                        local offSpec, passive = info.isOffSpec, info.isPassive
                        if not IsSecret(kind) and kind == spellType
                            and not IsSecret(offSpec) and offSpec ~= true
                            and not IsSecret(passive) and passive ~= true
                            and not IsSecret(name) and type(name) == "string" and name ~= "" then
                            local group = names[name]
                            if not group then
                                group = { byRank = {}, byID = {} }
                                names[name] = group
                            end
                            local ranks, ids = group.byRank, group.byID
                            local rank = not IsSecret(subName) and type(subName) == "string"
                                and tonumber(subName:match("^Rank (%d+)$"))
                            if IsWholeNumber(rank, 1) and IsWholeNumber(id, 1) then
                                if ids[id] and ids[id] ~= rank then group.incomplete = true end
                                ids[id] = rank
                                if ranks[rank] == nil then ranks[rank] = id
                                elseif ranks[rank] ~= id then ranks[rank] = false end
                            else
                                -- An unreadable or unranked entry could belong to this group.
                                group.incomplete = true
                            end
                        end
                    end
                end
                for _, group in pairs(names) do
                    if not group.incomplete then
                        local ranks = group.byRank
                        for rank, id in pairs(ranks) do
                            if id then
                                -- Require the immediate next rank in the same skill line.
                                local nextID = ranks[rank + 1] or false
                                if seen[id] and matches[id] ~= nextID then nextID = false end
                                matches[id], seen[id] = nextID, true
                            end
                        end
                    end
                end
            end
        end
    end
    nextRanks, rankIndexDirty = matches, false
end

local function NextRankSpellID(spellID)
    if not IsWholeNumber(spellID, 1) then return nil end
    if rankIndexDirty then RebuildRankIndex() end
    if not rankIndexDirty then return nextRanks[spellID] or nil end
end

----------------------------------------------------------------------
-- Async spell data (SPELL_DATA_LOAD_RESULT)
----------------------------------------------------------------------
local cur = { generation = 0, added = false }
local AddSpellInfo, ResolveTooltipSpell -- defined in the hook section

local function ClearTooltipContext()
    cur.generation = cur.generation + 1
    cur.spellID, cur.owner, cur.kind, cur.slot, cur.arg, cur.source = nil, nil, nil, nil, nil, nil
    cur.nativeInfo, cur.queuedRefresh, cur.deferredRefresh = nil, nil, nil
    cur.added, cur.processed = false, false
end

local errorShown = false
local function RunTooltipHandler(handler, ...)
    local ok, err = pcall(handler, ...)
    if not ok and not errorShown then
        errorShown = true
        Print("error (shown once): " .. tostring(err))
    end
end

local REQUEST_TIMEOUT, MAX_REQUEST_ATTEMPTS = 5, 3
local requests = {} -- per-spell attempt budget and retry deadline
local pending = {}  -- exact attempt awaiting SPELL_DATA_LOAD_RESULT
local waiting = 0
local dataFrame = CreateFrame("Frame")

local function IsNativeRefreshBuild()
    if not GetBuildInfo then return false end
    local ok, version, build, _, interface = pcall(GetBuildInfo)
    return ok and not IsSecret(version) and not IsSecret(build) and not IsSecret(interface)
        and version == "1.60.1" and (build == "70938" or build == 70938) and interface == 16001
end

local function GetStockBookItem(owner)
    local mixin = _G.SpellBookItemMixin
    if not mixin or not owner.GetParent or (owner.IsForbidden and owner:IsForbidden()) then return end
    local item = owner:GetParent()
    if IsSecret(item) or not item or (item.IsForbidden and item:IsForbidden()) then return end
    local button, show, slot, bank = item.Button, item.ShowSpellBookTooltip, item.slotIndex, item.spellBank
    if not IsSecret(button) and button == owner and not IsSecret(show) and type(show) == "function"
        and show == mixin.ShowSpellBookTooltip and not IsSecret(slot) and slot == cur.slot
        and not IsSecret(bank) and bank == cur.arg then
        return item, show
    end
end

local function HasStockActionUpdater(owner)
    local mixin = _G.ActionBarActionButtonMixin
    if not mixin or (owner.IsForbidden and owner:IsForbidden()) then return false end
    local update, action = owner.UpdateTooltip, owner.action
    return not IsSecret(update) and type(update) == "function" and update == mixin.SetTooltip
        and not IsSecret(action) and action == cur.slot
end

local function RefreshTooltip(refresh)
    if refresh ~= cur.queuedRefresh then return end
    cur.queuedRefresh = nil
    if refresh.generation ~= cur.generation or not DB
        or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
    local shown = GameTooltip:IsShown()
    if IsSecret(shown) or not shown then return end
    local owner = GameTooltip:GetOwner()
    if IsSecret(owner) or owner ~= cur.owner then return end
    local currentID, source = ResolveTooltipSpell(cur.kind, cur.slot, cur.arg)
    if currentID ~= refresh.spellID or source ~= cur.source then return end

    if cur.nativeInfo then
        local info = GameTooltip:GetPrimaryTooltipInfo()
        if IsSecret(info) or info ~= cur.nativeInfo then return end
        if IsNativeRefreshBuild() then
            -- Blizzard's existing action-button updater already refreshes its tooltip.
            if cur.kind == ACTION and HasStockActionUpdater(owner) then return end
            if cur.kind == BOOK then
                local item, show = GetStockBookItem(owner)
                if item then
                    if not InCombatLockdown then return end
                    local locked = InCombatLockdown()
                    if IsSecret(locked) then return end
                    if locked then
                        cur.deferredRefresh = refresh
                        return
                    end
                    cur.deferredRefresh = nil
                    -- Preserve the spellbook's extra lines and gamepad anchoring.
                    show(item)
                    return
                end
            end
        end
    end

    -- No safe replay is available. Keep the existing load-result fallback for
    -- empty tooltips, but never append a second set of addon lines.
    if refresh.spellData and not cur.added then
        AddSpellInfo(GameTooltip, refresh.spellID, source)
    end
end

local function QueueTooltipRefresh(spellID, spellData)
    if not spellID or cur.spellID ~= spellID or (not spellData and (cur.kind ~= BOOK or not cur.nativeInfo))
        or not (C_Timer and C_Timer.After) then return end
    local queued = cur.queuedRefresh
    if queued then
        queued.spellData = queued.spellData or spellData
        return
    end
    local refresh = { generation = cur.generation, spellID = spellID, spellData = spellData }
    cur.queuedRefresh = refresh
    -- Spell events can fire synchronously from inside the tooltip's setter.
    C_Timer.After(0, function() RunTooltipHandler(RefreshTooltip, refresh) end)
end

local function InvalidateSpellText(spellID)
    rankIndexDirty = true
    if IsWholeNumber(spellID, 1) then
        RemoveParseEntry(spellID, ACTION)
        RemoveParseEntry(spellID, BOOK)
        RemoveParseEntry(spellID, PET_BOOK)
    else
        InvalidateCache()
    end
end

local function FinishSpellRequest(spellID, attempt, success)
    if pending[spellID] ~= attempt then return end
    pending[spellID] = nil
    waiting = waiting - 1
    if waiting == 0 then dataFrame:UnregisterEvent("SPELL_DATA_LOAD_RESULT") end
    attempt.retryAt = GetTime() + 2 ^ (attempt.count - 1)
    if success then
        InvalidateSpellText(spellID)
        QueueTooltipRefresh(spellID, true)
    end
end

-- Retries occur only on later hovers, with a bounded budget for each spell.
local function RequestSpellData(spellID)
    if not IsWholeNumber(spellID, 1) or not (C_Spell and C_Spell.RequestLoadSpellData
        and C_Timer and C_Timer.After) or pending[spellID] then return false end
    local last = requests[spellID]
    if last and (last.count >= MAX_REQUEST_ATTEMPTS or GetTime() < last.retryAt) then
        return false
    end
    local attempt = { count = last and last.count + 1 or 1 }
    requests[spellID], pending[spellID] = attempt, attempt
    waiting = waiting + 1
    if waiting == 1 then dataFrame:RegisterEvent("SPELL_DATA_LOAD_RESULT") end
    C_Timer.After(REQUEST_TIMEOUT, function() FinishSpellRequest(spellID, attempt, false) end)
    local ok, result = pcall(C_Spell.RequestLoadSpellData, spellID)
    if not ok or IsSecret(result) or result == false then FinishSpellRequest(spellID, attempt, false) end
    return true
end

dataFrame:RegisterEvent("SPELLS_CHANGED")
dataFrame:RegisterEvent("SPELL_TEXT_UPDATE")
dataFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
dataFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
dataFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
dataFrame:SetScript("OnEvent", function(_, event, spellID, success)
    if event == "SPELLS_CHANGED" then
        rankIndexDirty = true
        if DB then InvalidateCache() end
        QueueTooltipRefresh(cur.spellID)
    elseif event == "SPELL_TEXT_UPDATE" then
        InvalidateSpellText(spellID)
        if IsWholeNumber(spellID, 1) then QueueTooltipRefresh(spellID, true) end
    elseif event == "MODIFIER_STATE_CHANGED" then
        if DB and DB.shiftDetails and not IsSecret(spellID) and (spellID == "LSHIFT" or spellID == "RSHIFT") then
            QueueTooltipRefresh(cur.spellID)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if DB and DB.showExpectedThroughput then QueueTooltipRefresh(cur.spellID) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        local deferred = cur.deferredRefresh
        if deferred and deferred.generation == cur.generation then
            cur.deferredRefresh = nil
            QueueTooltipRefresh(deferred.spellID, deferred.spellData)
        end
    elseif event == "SPELL_DATA_LOAD_RESULT" and IsWholeNumber(spellID, 1) then
        local attempt = pending[spellID]
        if attempt then FinishSpellRequest(spellID, attempt, not IsSecret(success) and success == true) end
    end
end)

----------------------------------------------------------------------
-- Entry computation
----------------------------------------------------------------------
local function ActiveModeledEffect(parsed, model)
    if model and DB.includeDoT and parsed.effect then
        return parsed.effect, (parsed.damage or parsed.healing).periodic
    end
end

local function ResolveExpectedAmount(parsed, model, effect)
    local amount = Estimates.ResolveExpectedAmount(parsed, model)
    if amount == 0 and not effect then return nil end
    return amount
end

local function GetExpectedCycle(baseTime, effect)
    if not baseTime then return nil end
    local time = math_max(baseTime, effect and effect.duration or 0)
    if time > 0 then return time end
end

-- A comparison probe never chains ranks or calculates healing throughput.
-- Include healing totals only if the current tooltip needs that comparison.
local function Compute(spellID, light, estimate, powerModel, source, readNextHealing)
    local text, secret, loaded = GetSpellText(spellID, source == PET_BOOK)
    local t = {}
    if not loaded or secret then RemoveParseEntry(spellID, source) end
    if not loaded and not secret then
        RequestSpellData(spellID)
    end
    if DEBUG then Print("spell text: " .. (text ~= "" and text or "<none / secret>")) end

    local ruleID = SpellIDKey(spellID)
    local rule = ruleID and DB.spellRules[ruleID]
    if rule == "hide" then
        t.hidden = true
        return t
    end

    estimate = estimate and loaded and not secret
    local wantsSustain = estimate and DB.showManaSustain
    local wantsExpected = estimate and powerModel and powerModel.expected
        and DB.showExpectedThroughput and type(rule) ~= "number" or false
    t.powerModel = estimate and powerModel
    t.baselineDamage = DB.showDPS or DB.showDPM or DB.showDPC or DB.showRange or DB.showDPMana
    local parsed
    if loaded and not secret then
        parsed = ParsePublicText(spellID, source, text, powerModel, wantsExpected)
    else
        parsed = {}
    end
    local damage, healing = parsed.damage, parsed.healing
    t.healingPerRecipient = healing ~= nil and parsed.effect ~= nil and parsed.effect.perRecipient == true
    local needsRecipientScope = powerModel and powerModel.periodic and powerModel.periodic.perRecipient
    local readableHealingScope = not needsRecipientScope or t.healingPerRecipient
    if type(rule) == "number" then
        t.total, t.lo, t.hi = rule, rule, rule
    elseif damage and (t.baselineDamage or estimate) then
        t.dot, t.dotDur = DB.includeDoT and damage.periodic or 0, DB.includeDoT and damage.duration or nil
        t.total, t.lo, t.hi = damage.direct + t.dot, damage.low, damage.high
        t.school = damage.school
    end
    if readNextHealing or (not light and (DB.showHealing or estimate)) then
        t.absorb = parsed.absorb
        if healing then
            t.hot, t.hotDur = DB.includeDoT and healing.periodic or 0, DB.includeDoT and healing.duration or nil
            t.htotal, t.hLo, t.hHi = healing.direct + t.hot, healing.low, healing.high
        end
    end

    local compareHealing = not light and DB.showNextRank and DB.showHealing
        and (source == ACTION or source == BOOK)
    if (compareHealing or readNextHealing) and readableHealingScope and FiniteNumber(t.htotal) and t.htotal > 0 then
        t.comparableHealing = t.htotal
    end
    compareHealing = compareHealing and t.comparableHealing ~= nil
    local checkFixedMana = wantsSustain or t.comparableHealing ~= nil
    if DB.showMana or DB.showDPMana or checkFixedMana then
        t.cost, t.fixedManaCost = Estimates.GetManaCost(spellID, checkFixedMana)
    end

    local damageTiming = t.total and t.total > 0 and (t.baselineDamage or wantsSustain)
    local healingTiming = not light and t.htotal and t.htotal > 0 and (DB.showHealing or wantsSustain)
    local effect, tickTotal = ActiveModeledEffect(parsed, t.powerModel)
    t.tickTotal = tickTotal
    local expectedAmount = wantsExpected and ResolveExpectedAmount(parsed, t.powerModel, effect)

    if damageTiming or healingTiming or expectedAmount then
        local baseTime = GetBaseCycle(spellID)
        if baseTime then
            if damageTiming then
                local time = math_max(baseTime, t.dotDur or 0)
                if time > 0 then t.time, t.dps = time, t.total / time end
            end
            if healingTiming then
                local time = math_max(baseTime, t.hotDur or 0)
                if time > 0 then t.htime, t.hps = time, t.htotal / time end
            end
            if wantsSustain then t.sustainCycle = math_max(t.time or 0, t.htime or 0) end
            if expectedAmount then
                local time = GetExpectedCycle(baseTime, effect)
                if time then
                    t.expectedAmount, t.expectedCycle, t.expectedEffect = expectedAmount, time, effect
                end
            end
        end
    end

    local compareDamage = not light and DB.showNextRank and t.baselineDamage and t.dps and t.dps > 0
    if compareDamage or compareHealing then
        local nextID = NextRankSpellID(spellID)
        if nextID then
            local nextModel = compareHealing and Estimates.GetSpellModel(nextID)
            local nextHealingModel = nextModel and nextModel.expected == "healing" and nextModel or nil
            local nt = Compute(nextID, true, false, nextHealingModel, BOOK, compareHealing)
            if compareDamage then
                -- A modeled healing grammar can replace the generic parse.
                -- Keep the old damage comparison when both are requested.
                local damageRank = nextHealingModel and nextHealingModel.periodic
                    and Compute(nextID, true, false, nil, BOOK) or nt
                t.nextDPS = damageRank.dps
            end
            if compareHealing and nt.comparableHealing and t.healingPerRecipient == nt.healingPerRecipient then
                t.nextHealing, t.nextHealingManaCost = nt.comparableHealing, nt.fixedManaCost
            end
        end
    end

    return t, estimate
end

local function GetEntry(spellID, estimate, powerModel, source)
    local e = {}
    local t, readableEstimate = Compute(spellID, false, estimate, powerModel, source)

    if t.baselineDamage and t.total and t.total > 0 then
        if t.dps and (DB.showDPS or DB.showDPM) then e.dmgLine = DamageLineText(t.dps) end
        e.dpcLine = DPCLineText(t.total)
        e.rangeLine = RangeLineText(t.lo, t.hi)
        e.effLine = EfficiencyLineText(t.total, t.cost)
        e.nextLine = NextRankLineText(t.dps, t.nextDPS)
        if DB.schoolTint and t.school then e.schoolColor = SCHOOL_COLORS[t.school] end
    end

    if DB.showHealing and t.htotal and t.htotal > 0 then
        e.healLine = HealLineText(t.hps, t.healingPerRecipient)
        e.heffLine = HealEffLineText(t.htotal, t.cost, t.healingPerRecipient)
        if t.nextHealing then
            e.nextHealLine = NextRankHealingLineText("cast", t.htotal, t.nextHealing, "%.0f", t.healingPerRecipient)
            if t.fixedManaCost and t.nextHealingManaCost then
                e.nextHealManaLine = NextRankHealingLineText("mana", t.htotal / t.fixedManaCost,
                    t.nextHealing / t.nextHealingManaCost, "%.2f", t.healingPerRecipient)
            end
        end
    end
    e.absorbLine = AbsorbLineText(t.absorb)
    e.detailLines = BuildDetailLines(t, e.dmgLine or e.dpcLine or e.rangeLine or e.effLine or e.nextLine,
        e.healLine or e.heffLine or e.nextHealLine, e.absorbLine)

    if DB.showMana and t.cost and t.cost > 0 then
        local maxMana
        if DB.manaMode ~= 2 then
            maxMana = UnitPowerMax("player", MANA)
            if IsSecret(maxMana) then maxMana = nil end
        end
        e.manaLine = ManaLineText(t.cost, maxMana)
    end
    return e, readableEstimate and t
end

----------------------------------------------------------------------
-- Styled tooltip lines
----------------------------------------------------------------------
-- Tooltip lines are recycled by the game, so every line we restyle is put
-- back when the tooltip clears. Parallel arrays: no per-line tables.
local leftLines = {}
local styledLines, styledFonts, styledCount = {}, {}, 0

local function GetLeftLine(n)
    local line = leftLines[n]
    if not line then
        line = _G["GameTooltipTextLeft" .. n]
        leftLines[n] = line
    end
    return line
end

local function AddStyledLine(tooltip, text, color)
    tooltip:AddLine(text, color[1], color[2], color[3])
    local line = GetLeftLine(tooltip:NumLines())
    if line then
        styledCount = styledCount + 1
        styledLines[styledCount] = line
        styledFonts[styledCount] = line:GetFontObject()
        line:SetFont(GetTooltipFontPath(), DB.fontSize, OUTLINES[DB.fontOutline])
    end
end

GameTooltip:HookScript("OnTooltipCleared", function()
    for i = styledCount, 1, -1 do
        styledLines[i]:SetFontObject(styledFonts[i] or GameTooltipText)
        styledLines[i], styledFonts[i] = nil, nil
    end
    styledCount = 0
    ClearTooltipContext()
end)
GameTooltip:HookScript("OnHide", ClearTooltipContext)

local function AddPowerLines(tooltip, t, dmgColor)
    local model = t.powerModel
    if not model then return false end
    local added = false
    if DB.showPowerScaling then
        local effect = model.periodic
        local school = model.school and (model.school:sub(1, 1):upper() .. model.school:sub(2))
        if model.spellPower then
            AddStyledLine(tooltip, PowerScalingLineText(school .. " spell power", model.spellPower, "damage"), dmgColor)
            added = true
        end
        if model.healingPower then
            AddStyledLine(tooltip, PowerScalingLineText("healing power", model.healingPower, "healing"), DB.healColor)
            added = true
        end
        if model.attackPower then
            AddStyledLine(tooltip, PowerScalingLineText("attack power", model.attackPower, "damage"), dmgColor)
            added = true
        end
        if model.rangedPower then
            AddStyledLine(tooltip, PowerScalingLineText("ranged attack power", model.rangedPower, "damage", "shot"), dmgColor)
            added = true
        end
        if effect and t.tickTotal and effect.coefficient > 0 then
            local healing = model.expected == "healing"
            local stat = healing and "healing power" or (effect.ranged and "ranged attack power" or (school .. " spell power"))
            local color = healing and DB.healColor or dmgColor
            AddStyledLine(tooltip, PeriodicScalingLineText(stat, effect, healing and "healing" or "damage"), color)
            added = true
        end
    end
    if t.expectedAmount then
        local rate, hit, crit, target, modifiers = Estimates.GetExpectedRate(model.expected, t.expectedAmount, t.expectedCycle,
            t.expectedEffect, t.tickTotal, model)
        if rate then
            local color = model.expected == "healing" and DB.healColor or dmgColor
            AddStyledLine(tooltip, ExpectedLineText(model.expected, rate, hit, crit, t.expectedEffect, target,
                modifiers, model.baselineHealing), color)
            if modifiers then
                AddStyledLine(tooltip, "Modifiers: " .. table_concat(modifiers.labels, ", "), color)
            end
            added = true
        end
    end
    return added
end

local function AddEstimateLines(tooltip, t, dmgColor)
    local added = false
    if t.fixedManaCost and t.sustainCycle then
        local casts, netCost = Estimates.GetManaSustain(t.fixedManaCost, t.sustainCycle)
        local mana = ManaSustainLineText(casts, netCost)
        if mana then
            AddStyledLine(tooltip, mana, DB.manaColor)
            added = true
        end
        local damage = OutputBeforeLowManaText(casts, t.total, "damage")
        if damage then AddStyledLine(tooltip, damage, dmgColor) end
        local healing = OutputBeforeLowManaText(casts, t.htotal,
            t.healingPerRecipient and "healing per recipient" or "healing")
        if healing then AddStyledLine(tooltip, healing, DB.healColor) end
    end
    if DB.showCasterStats then
        local crit, power, healing = Estimates.GetCasterStats(t.school, t.htotal and t.htotal > 0)
        if crit then
            AddStyledLine(tooltip, string_format("Caster spell crit: %.1f%%", crit), dmgColor)
            added = true
        end
        if power then
            local school = t.school:sub(1, 1):upper() .. t.school:sub(2)
            AddStyledLine(tooltip, school .. " spell power: " .. FormatNumber(string_format("%.0f", power)), dmgColor)
            added = true
        end
        if healing then
            AddStyledLine(tooltip, "Bonus healing: " .. FormatNumber(string_format("%.0f", healing)), DB.healColor)
            added = true
        end
    end
    return AddPowerLines(tooltip, t, dmgColor) or added
end

AddSpellInfo = function(tooltip, spellID, source, nativeShow)
    if not DB or not spellID then return end
    local model = source and Estimates.GetSpellModel(spellID)
    local estimate = source and (DB.showManaSustain or DB.showCasterStats
        or (model and (DB.showPowerScaling or DB.showExpectedThroughput)))
        and Estimates.IsKnownPlayerSpell(spellID, source == ACTION)
    local e, estimateData = GetEntry(spellID, estimate, model, source or PET_BOOK)
    local added = false
    local dmgColor = e.schoolColor or DB.damageColor

    if e.dmgLine then AddStyledLine(tooltip, e.dmgLine, dmgColor) added = true end
    if e.dpcLine then AddStyledLine(tooltip, e.dpcLine, dmgColor) added = true end
    if e.rangeLine then AddStyledLine(tooltip, e.rangeLine, dmgColor) added = true end
    if e.effLine then AddStyledLine(tooltip, e.effLine, dmgColor) added = true end
    if e.nextLine then AddStyledLine(tooltip, e.nextLine, dmgColor) added = true end
    if e.healLine then AddStyledLine(tooltip, e.healLine, DB.healColor) added = true end
    if e.heffLine then AddStyledLine(tooltip, e.heffLine, DB.healColor) added = true end
    if e.nextHealLine then AddStyledLine(tooltip, e.nextHealLine, DB.healColor) added = true end
    if e.nextHealManaLine then AddStyledLine(tooltip, e.nextHealManaLine, DB.healColor) added = true end
    if e.absorbLine then AddStyledLine(tooltip, e.absorbLine, DB.healColor) added = true end
    if e.manaLine then AddStyledLine(tooltip, e.manaLine, DB.manaColor) added = true end
    if estimateData and AddEstimateLines(tooltip, estimateData, dmgColor) then added = true end

    if DB.shiftDetails and e.detailLines then
        local gray = { 0.65, 0.65, 0.65 }
        if IsShiftKeyDown and IsShiftKeyDown() then
            for i = 1, #e.detailLines do AddStyledLine(tooltip, e.detailLines[i], gray) end
            added = true
        elseif added then
            AddStyledLine(tooltip, "Hold Shift for the full breakdown", gray)
            added = true
        end
    end

    if added then
        cur.added = true
        if not nativeShow then tooltip:Show() end -- native processing calls Show after all post-calls
    end
end

----------------------------------------------------------------------
-- Hooks: action bar and spellbook
----------------------------------------------------------------------
local function ResolveActionSpell(slot)
    local actionType, id = GetActionInfo(slot)
    if IsSecret(actionType) or IsSecret(id) then return nil end
    if actionType == "spell" then
        return id
    elseif actionType == "macro" and GetMacroSpell then
        local spellID = GetMacroSpell(id)
        if IsSecret(spellID) then return nil end
        return spellID
    end
    return nil
end

local function ResolveBookSpell(slot, bank)
    if not (C_SpellBook and C_SpellBook.GetSpellBookItemInfo) then return nil end
    if IsSecret(bank) then return nil end
    if type(bank) == "string" then -- old-style "spell"/"pet" book type
        bank = (bank == "pet") and BANK_PET or BANK_PLAYER
    end
    bank = bank or BANK_PLAYER
    local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
    if IsSecret(info) or type(info) ~= "table" then return nil end
    local id = info.spellID
    if IsSecret(id) then return nil end
    return id, bank == BANK_PLAYER
end

ResolveTooltipSpell = function(kind, slot, arg)
    if not DB or not IsWholeNumber(slot, 1) or IsSecret(arg) then return nil end
    local spellID, source
    if kind == ACTION then
        if not DB.showActionBar then return end
        spellID = ResolveActionSpell(slot)
        source = ACTION
    else
        if not DB.showSpellbook then return end
        local isPlayerBook
        spellID, isPlayerBook = ResolveBookSpell(slot, arg)
        if isPlayerBook then source = BOOK end
    end
    if IsWholeNumber(spellID, 1) then return spellID, source end
end

local function IsMainTooltip(tooltip)
    return not IsSecret(tooltip) and tooltip == GameTooltip
        and not (tooltip.IsForbidden and tooltip:IsForbidden())
end

local function RenderTooltip(tooltip, kind, slot, arg, nativeInfo)
    local spellID, source = ResolveTooltipSpell(kind, slot, arg)
    if not spellID then return end
    local owner = tooltip:GetOwner()
    if not IsSecret(owner) and owner ~= nil then
        cur.spellID, cur.owner, cur.kind, cur.slot, cur.arg, cur.source = spellID, owner, kind, slot, arg, source
        cur.nativeInfo = nativeInfo
    end
    AddSpellInfo(tooltip, spellID, source, nativeInfo ~= nil)
end

local function OnTooltipHook(tooltip, kind, slot, arg)
    if not IsMainTooltip(tooltip) then return end
    ClearTooltipContext()
    RenderTooltip(tooltip, kind, slot, arg)
end

local function OnTooltipPostCall(tooltip, data)
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local info = tooltip:GetProcessingTooltipInfo()
    if IsSecret(info) or type(info) ~= "table" then return end
    local getter = info.getterName
    if IsSecret(getter) or (getter ~= "GetAction" and getter ~= "GetSpellBookItem") then return end
    local primary = tooltip:GetPrimaryTooltipInfo()
    if IsSecret(primary) or primary ~= info then return end
    local append, args = info.append, info.getterArgs
    if IsSecret(append) or append or IsSecret(args) or type(args) ~= "table" then return end
    local tooltipData = info.tooltipData
    if IsSecret(tooltipData) or IsSecret(data) or type(data) ~= "table" or tooltipData ~= data then return end
    -- A native reprocess calls ClearLines before this post-call, even when the
    -- new data uses the same instance ID. For this pass append at most once.
    cur.processed = true
    RenderTooltip(tooltip, getter == "GetAction" and ACTION or BOOK, args[1], args[2], info)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and TooltipDataProcessor.AllTypes
    and GameTooltip.GetProcessingTooltipInfo and GameTooltip.GetPrimaryTooltipInfo then
    -- GetAction/GetSpellBookItem do not promise a tooltip enum for every
    -- source (e.g. macros). Route on the exact native getter then resolve
    -- spell/macro identity, with no setter post-hooks in this mode.
    TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip, data)
        if DB and not cur.processed and not IsSecret(tooltip) and tooltip == GameTooltip then
            RunTooltipHandler(OnTooltipPostCall, tooltip, data)
        end
    end)
else
    if GameTooltip.SetAction then
        hooksecurefunc(GameTooltip, "SetAction", function(tooltip, slot)
            RunTooltipHandler(OnTooltipHook, tooltip, ACTION, slot)
        end)
    end
    if GameTooltip.SetSpellBookItem then
        hooksecurefunc(GameTooltip, "SetSpellBookItem", function(tooltip, slot, bank)
            RunTooltipHandler(OnTooltipHook, tooltip, BOOK, slot, bank)
        end)
    end
end

----------------------------------------------------------------------
-- Config window (tabs: Lines / Calculation / Format / Advanced)
----------------------------------------------------------------------
local config
local cfgTab = "lines"
local OnOptionChanged, OpenColorPicker -- defined below in this section
local ExportSettings, ImportSettings -- assigned in the sharing section further down

local function MakeHeader(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function MakeCheck(parent, label, x, y, key)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    text:SetText(label)
    cb:SetScript("OnClick", function(self)
        OnOptionChanged(key, self:GetChecked() and true or false)
    end)
    parent.checks[key] = cb
    return cb
end

-- Button that cycles through choices: left click forward, right click back.
local function MakeCycle(parent, label, x, y, key, choices)
    local lab = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lab:SetPoint("TOPLEFT", x, y - 4)
    lab:SetText(label)

    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(96, 22)
    btn:SetPoint("TOPLEFT", x + 170, y)
    btn:RegisterForClicks("AnyUp")
    btn.choices, btn.key = choices, key
    btn:SetScript("OnClick", function(self, mouse)
        local idx = 1
        for i = 1, #choices do
            if choices[i].value == DB[key] then idx = i end
        end
        if mouse == "RightButton" then
            idx = idx - 1
            if idx < 1 then idx = #choices end
        else
            idx = idx % #choices + 1
        end
        OnOptionChanged(key, choices[idx].value)
        self:SetText(choices[idx].label)
    end)
    parent.cycles[key] = btn
    return btn
end

local function MakeSwatch(parent, label, x, y, colorKey)
    local sw = CreateFrame("Button", nil, parent)
    sw:SetSize(22, 22)
    sw:SetPoint("TOPLEFT", x, y)

    local border = sw:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(1, 1, 1, 1)

    local fill = sw:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    sw.fill = fill

    local text = sw:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", sw, "RIGHT", 8, 0)
    text:SetText(label)

    sw:SetScript("OnClick", function()
        OpenColorPicker(DB[colorKey])
    end)
    return sw
end

-- Uses Blizzard's slider template when present, otherwise a minimal slider.
local function MakeSlider(parent)
    local name = "DamageTipsFontSlider"
    local ok, slider = pcall(CreateFrame, "Slider", name, parent, "OptionsSliderTemplate")
    if not ok or not slider then
        slider = CreateFrame("Slider", nil, parent)
        slider:SetOrientation("HORIZONTAL")
        slider:SetHeight(16)
        local bar = slider:CreateTexture(nil, "BACKGROUND")
        bar:SetColorTexture(0.25, 0.25, 0.25, 0.9)
        bar:SetPoint("LEFT")
        bar:SetPoint("RIGHT")
        bar:SetHeight(4)
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    end

    local text = slider.Text or _G[name .. "Text"]
    if not text then
        text = slider:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        text:SetPoint("BOTTOM", slider, "TOP", 0, 4)
    end
    local low = slider.Low or _G[name .. "Low"]
    local high = slider.High or _G[name .. "High"]
    if low then low:SetText(FONT_MIN) end
    if high then high:SetText(FONT_MAX) end

    slider:SetMinMaxValues(FONT_MIN, FONT_MAX)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    return slider, text
end

-- Sample numbers for the live preview
local SAMPLE_DPS, SAMPLE_TOTAL, SAMPLE_COST, SAMPLE_MAX = 123.4567, 592.59, 50, 500

local MANA_CHOICES = { { label = "Percent", value = 1 }, { label = "Amount", value = 2 }, { label = "Both", value = 3 } }
local DECIMAL_CHOICES = { { label = "0", value = 0 }, { label = "1", value = 1 }, { label = "2", value = 2 } }
local OUTLINE_CHOICES = { { label = "None", value = 1 }, { label = "Outline", value = 2 }, { label = "Thick", value = 3 } }

local function UpdateColors()
    local d, h, m = DB.damageColor, DB.healColor, DB.manaColor
    config.damageSwatch.fill:SetColorTexture(d[1], d[2], d[3], 1)
    config.healSwatch.fill:SetColorTexture(h[1], h[2], h[3], 1)
    config.manaSwatch.fill:SetColorTexture(m[1], m[2], m[3], 1)
    for _, fs in ipairs(config.dmgPreviews) do fs:SetTextColor(d[1], d[2], d[3]) end
    for _, fs in ipairs(config.healPreviews) do fs:SetTextColor(h[1], h[2], h[3]) end
    config.previewMana:SetTextColor(m[1], m[2], m[3])
    config.previewSustain:SetTextColor(m[1], m[2], m[3])
    config.previewCaster:SetTextColor(d[1], d[2], d[3])
    config.previewScaling:SetTextColor(d[1], d[2], d[3])
    config.previewExpected:SetTextColor(d[1], d[2], d[3])
end

local function ApplyPreview(fs, text, path, size, flags)
    if text then
        fs:SetText(text)
        fs:SetFont(path, size, flags)
        fs:Show()
    else
        fs:Hide()
    end
end

local function UpdatePreview()
    local path, size, flags = GetTooltipFontPath(), DB.fontSize, OUTLINES[DB.fontOutline]
    local dmg, heal = config.dmgPreviews, config.healPreviews
    ApplyPreview(dmg[1], DamageLineText(SAMPLE_DPS), path, size, flags)
    ApplyPreview(dmg[2], DPCLineText(SAMPLE_TOTAL), path, size, flags)
    ApplyPreview(dmg[3], RangeLineText(55, 65), path, size, flags)
    ApplyPreview(dmg[4], EfficiencyLineText(SAMPLE_TOTAL, SAMPLE_COST), path, size, flags)
    ApplyPreview(dmg[5], NextRankLineText(SAMPLE_DPS, SAMPLE_DPS * 1.18), path, size, flags)
    ApplyPreview(heal[1], HealLineText(80.5), path, size, flags)
    ApplyPreview(heal[2], HealEffLineText(402.5, SAMPLE_COST), path, size, flags)
    ApplyPreview(heal[3], AbsorbLineText(500), path, size, flags)
    ApplyPreview(config.previewMana, ManaLineText(SAMPLE_COST, SAMPLE_MAX), path, size, flags)
    ApplyPreview(config.previewSustain, DB.showManaSustain and ManaSustainLineText(8, 15), path, size, flags)
    ApplyPreview(config.previewCaster, DB.showCasterStats and "Caster spell crit: 12.5%", path, size, flags)
    ApplyPreview(config.previewScaling, DB.showPowerScaling and PowerScalingLineText("Fire spell power", 0.429, "damage"), path, size, flags)
    ApplyPreview(config.previewExpected, DB.showExpectedThroughput and ExpectedLineText("spell", 130, 98, 12.5), path, size, flags)
    config.sliderText:SetText("Font size: " .. DB.fontSize)
end

local function SyncCycle(btn)
    local choices, value = btn.choices, DB[btn.key]
    for i = 1, #choices do
        if choices[i].value == value then
            btn:SetText(choices[i].label)
            return
        end
    end
end

RefreshConfig = function()
    if not config or not DB then return end
    for key, cb in pairs(config.checks) do cb:SetChecked(DB[key]) end
    for _, btn in pairs(config.cycles) do SyncCycle(btn) end
    config.syncing = true
    config.slider:SetValue(DB.fontSize)
    config.syncing = false
    UpdateColors()
    UpdatePreview()
    -- Spell rules summary
    local hidden, pinned = 0, 0
    for _, v in pairs(DB.spellRules or {}) do
        if v == "hide" then hidden = hidden + 1 else pinned = pinned + 1 end
    end
    config.rulesText:SetText((hidden + pinned == 0)
        and "No spell rules. Use /damagetips hide <spell> or setdmg <spell> <avg>."
        or (hidden .. " spell(s) hidden, " .. pinned .. " with pinned damage."))
end

OnOptionChanged = function(key, value)
    SetOption(key, value)
end

-- Opens the colour picker for a { r, g, b } table
OpenColorPicker = function(colorTable)
    if not ColorPickerFrame then
        Print("colour picker unavailable on this client")
        return
    end
    local r, g, b = colorTable[1], colorTable[2], colorTable[3]
    local function apply()
        colorTable[1], colorTable[2], colorTable[3] = ColorPickerFrame:GetColorRGB()
        UpdateColors()
    end
    local function cancel()
        colorTable[1], colorTable[2], colorTable[3] = r, g, b
        UpdateColors()
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            hasOpacity = false,
            swatchFunc = function() -- fires continuously while dragging: update colours only
                apply()
            end,
            cancelFunc = cancel,
        })
    else
        -- Legacy picker API (older clients): plain fields instead of an info table
        ColorPickerFrame.func = apply       -- fires when the picker closes
        ColorPickerFrame.cancelFunc = cancel
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.previousValues = { r = r, g = g, b = b }
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

local function SelectTab(key)
    cfgTab = key
    for k, panel in pairs(config.panels) do panel:SetShown(k == key) end
    for k, btn in pairs(config.tabBtns) do
        if k == key then btn:LockHighlight() else btn:UnlockHighlight() end
    end
end

local function CreateConfig()
    local f = CreateFrame("Frame", "DamageTipsConfigFrame", UIParent, "BackdropTemplate")
    f.checks, f.cycles = {}, {}
    f:SetSize(620, 560)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    f:Hide()
    tinsert(UISpecialFrames, "DamageTipsConfigFrame") -- close with Escape

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("DamageTips")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    f.panels, f.tabBtns = {}, {}
    local tabDefs = {
        { "lines", "Lines" }, { "calc", "Calculation" },
        { "format", "Format" }, { "adv", "Advanced" },
    }
    for i, td in ipairs(tabDefs) do
        local key, label = td[1], td[2]
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetSize(100, 22)
        btn:SetText(label)
        btn:SetPoint("TOPLEFT", 24 + (i - 1) * 108, -44)
        btn:SetScript("OnClick", function() SelectTab(key); RefreshConfig() end)
        f.tabBtns[key] = btn
        local panel = CreateFrame("Frame", nil, f)
        panel.checks, panel.cycles = f.checks, f.cycles
        panel:SetPoint("TOPLEFT", 8, -72)
        panel:SetPoint("BOTTOMRIGHT", -8, 8)
        panel:Hide()
        f.panels[key] = panel
    end

    ------------------------------------------------------------------
    -- Tab: Lines
    ------------------------------------------------------------------
    local lines = f.panels.lines
    MakeHeader(lines, "Lines", 16, -8)
    MakeCheck(lines, "DPS (damage per second)", 16, -26, "showDPS")
    MakeCheck(lines, "DPM (damage per minute)", 16, -52, "showDPM")
    MakeCheck(lines, "Damage per cast", 16, -78, "showDPC")
    MakeCheck(lines, "Damage range (59-65)", 16, -104, "showRange")
    MakeCheck(lines, "Healing (HPS / HPM, absorbs)", 16, -130, "showHealing")
    MakeCheck(lines, "Damage & healing per mana", 16, -156, "showDPMana")
    MakeCheck(lines, "Mana cost", 16, -182, "showMana")
    MakeCheck(lines, "Tint damage lines by spell school", 16, -208, "schoolTint")
    MakeCheck(lines, "Hold Shift for the full breakdown", 16, -234, "shiftDetails")

    MakeHeader(lines, "Show on", 330, -8)
    MakeCheck(lines, "Action bars", 330, -26, "showActionBar")
    MakeCheck(lines, "Spellbook", 330, -52, "showSpellbook")
    MakeHeader(lines, "Spell estimates", 330, -92)
    MakeCheck(lines, "Mana sustain estimate", 330, -112, "showManaSustain")
    MakeCheck(lines, "Caster spell stats", 330, -138, "showCasterStats")
    MakeCheck(lines, "Spell and attack power scaling", 330, -164, "showPowerScaling")
    MakeCheck(lines, "Expected DPS and HPS", 330, -190, "showExpectedThroughput")

    ------------------------------------------------------------------
    -- Tab: Calculation
    ------------------------------------------------------------------
    local calc = f.panels.calc
    MakeHeader(calc, "Damage math", 16, -8)
    MakeCheck(calc, "Include periodic effects", 16, -26, "includeDoT")
    MakeCheck(calc, "Minimum time is the GCD", 16, -52, "gcdFloor")
    MakeCheck(calc, "Thousands separators", 16, -78, "thousands")
    MakeCheck(calc, "Show next rank comparison", 16, -104, "showNextRank")

    MakeHeader(calc, "Format", 330, -8)
    MakeCycle(calc, "DPS decimals", 330, -28, "dpsDecimals", DECIMAL_CHOICES)
    MakeCycle(calc, "Mana cost shown as", 330, -56, "manaMode", MANA_CHOICES)

    local calcHint = calc:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    calcHint:SetPoint("TOPLEFT", 16, -150)
    calcHint:SetWidth(560)
    calcHint:SetJustifyH("LEFT")
    calcHint:SetText("DPS divides average damage by the longest of cast time, the spell's " ..
        "cooldown, its global cooldown and any damage-over-time duration.")

    ------------------------------------------------------------------
    -- Tab: Format
    ------------------------------------------------------------------
    local fmt = f.panels.format
    MakeHeader(fmt, "Colours", 16, -8)
    f.damageSwatch = MakeSwatch(fmt, "Damage lines", 18, -28, "damageColor")
    f.healSwatch = MakeSwatch(fmt, "Healing lines", 18, -56, "healColor")
    f.manaSwatch = MakeSwatch(fmt, "Mana line", 18, -84, "manaColor")

    MakeHeader(fmt, "Text", 330, -8)
    MakeCycle(fmt, "Font outline", 330, -28, "fontOutline", OUTLINE_CHOICES)

    local slider, sliderText = MakeSlider(fmt)
    slider:SetPoint("TOPLEFT", 336, -72)
    slider:SetWidth(220)
    slider:SetScript("OnValueChanged", function(_, value)
        if f.syncing or not DB then return end
        value = math_floor(value + 0.5)
        if value == DB.fontSize then return end
        DB.fontSize = value
        UpdatePreview()
    end)
    f.slider, f.sliderText = slider, sliderText

    local previewLabel = fmt:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    previewLabel:SetPoint("TOPLEFT", 16, -122)
    previewLabel:SetText("Preview")

    f.dmgPreviews, f.healPreviews = {}, {}
    local function previewLine(tbl, y)
        local fs = fmt:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", 16, y)
        tbl[#tbl + 1] = fs
        return fs
    end
    for i = 1, 5 do previewLine(f.dmgPreviews, -140 - (i - 1) * 20) end
    for i = 1, 3 do previewLine(f.healPreviews, -140 - 5 * 20 - (i - 1) * 20) end
    f.previewMana = fmt:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.previewMana:SetPoint("TOPLEFT", 16, -140 - 8 * 20)
    f.previewSustain = fmt:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.previewSustain:SetPoint("TOPLEFT", 16, -140 - 9 * 20)
    f.previewCaster = fmt:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.previewCaster:SetPoint("TOPLEFT", 16, -140 - 10 * 20)
    f.previewScaling = fmt:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.previewScaling:SetPoint("TOPLEFT", 16, -140 - 11 * 20)
    f.previewExpected = fmt:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.previewExpected:SetPoint("TOPLEFT", 16, -140 - 12 * 20)

    ------------------------------------------------------------------
    -- Tab: Advanced
    ------------------------------------------------------------------
    local adv = f.panels.adv
    MakeHeader(adv, "Buttons", 16, -8)
    MakeCheck(adv, "Minimap button (drag it around the minimap)", 16, -26, "showMinimap")

    MakeHeader(adv, "Spell rules", 16, -66)
    f.rulesText = adv:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.rulesText:SetPoint("TOPLEFT", 20, -92)
    f.rulesText:SetWidth(560)
    f.rulesText:SetJustifyH("LEFT")
    local clearRules = CreateFrame("Button", nil, adv, "UIPanelButtonTemplate")
    clearRules:SetSize(160, 22)
    clearRules:SetPoint("TOPLEFT", 20, -112)
    clearRules:SetText("Clear all spell rules")
    clearRules:SetScript("OnClick", function()
        wipe(DB.spellRules)
        RefreshConfig()
        Print("spell rules cleared")
    end)
    local rulesHint = adv:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    rulesHint:SetPoint("TOPLEFT", 20, -140)
    rulesHint:SetWidth(560)
    rulesHint:SetJustifyH("LEFT")
    rulesHint:SetText("/damagetips hide <spell> skips a spell's lines; " ..
        "/damagetips setdmg <spell> <avg> pins its average damage for spells the text parser gets wrong.")

    MakeHeader(adv, "Settings sharing", 16, -186)
    local exportBtn = CreateFrame("Button", nil, adv, "UIPanelButtonTemplate")
    exportBtn:SetSize(190, 22)
    exportBtn:SetPoint("TOPLEFT", 20, -212)
    exportBtn:SetText("Print my settings string")
    exportBtn:SetScript("OnClick", function()
        Print("settings string (copy it, paste with /damagetips import):")
        print(ExportSettings())
    end)
    local importLabel = adv:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    importLabel:SetPoint("TOPLEFT", 20, -246)
    importLabel:SetText("Import a settings string (paste, then press Enter):")
    local importBox = CreateFrame("EditBox", nil, adv, "InputBoxTemplate")
    importBox:SetSize(560, 22)
    importBox:SetPoint("TOPLEFT", 20, -262)
    importBox:SetAutoFocus(false)
    importBox:SetScript("OnEnterPressed", function(self)
        local ok, err = ImportSettings(self:GetText())
        if ok then
            Print("settings imported")
            self:SetText("")
        else
            Print("import failed: " .. tostring(err))
        end
        self:ClearFocus()
    end)

    local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    reset:SetSize(214, 24)
    reset:SetPoint("BOTTOMRIGHT", -24, 16)
    reset:SetText("Reset options (keep spell rules)")
    reset:SetScript("OnClick", function()
        ResetDB()
        Print("options reset; spell rules and minimap position kept")
    end)

    config = f
    SelectTab("lines")
    f:Hide()
    return f
end

local function ToggleConfig()
    if not config then config = CreateConfig() end
    if config:IsShown() then
        config:Hide()
    else
        RefreshConfig()
        config:Show()
    end
end


----------------------------------------------------------------------
-- Addon compartment (minimap addon list) entry: see ## AddonCompartmentFunc in the TOC
function DamageTips_OnAddonCompartmentClick()
    if DB then ToggleConfig() end
end

----------------------------------------------------------------------
-- Minimap button
----------------------------------------------------------------------
local minimapBtn

local function PositionMinimapButton()
    if not minimapBtn then return end
    local angle = math.rad(DB.minimapAngle)
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end

RefreshMinimapButton = function()
    if not minimapBtn then return end
    if DB and DB.showMinimap then
        minimapBtn:Show()
        PositionMinimapButton()
    else
        minimapBtn:Hide()
    end
end

BuildMinimapButton = function()
    if minimapBtn then
        RefreshMinimapButton()
        return true
    end
    if not Minimap then return false end
    local b = CreateFrame("Button", "DamageTipsMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\AddOns\\DamageTips\\Media\\icon.tga")
    local border = b:CreateTexture(nil, "ARTWORK")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffffd100DamageTips|r")
        GameTooltip:AddLine("Click: open settings", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: move around the minimap", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function() if DB then ToggleConfig() end end)
    local function StopDragging(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
    end
    local function UpdateDrag(self)
        if not DB or not Minimap then
            StopDragging(self)
            return
        end
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = (Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()) or 1
        cx, cy = cx / scale, cy / scale
        local atan2 = math.atan2 or math.atan
        DB.minimapAngle = math.deg(atan2(cy - my, cx - mx)) % 360
        PositionMinimapButton()
    end
    b:SetScript("OnDragStart", function(self)
        if not DB or not Minimap then return end
        self.dragging = true
        self:SetScript("OnUpdate", UpdateDrag)
    end)
    b:SetScript("OnDragStop", StopDragging)
    b:SetScript("OnHide", StopDragging)
    minimapBtn = b
    RefreshMinimapButton()
    return true
end

----------------------------------------------------------------------
-- Settings export / import (plain "DT1;key=value;..." text, no code)
----------------------------------------------------------------------
local function ColorToHex(c)
    return string_format("%02x%02x%02x",
        math_floor(c[1] * 255 + 0.5), math_floor(c[2] * 255 + 0.5), math_floor(c[3] * 255 + 0.5))
end

local function HexToColor(s)
    if type(s) ~= "string" then return nil end
    local r, g, b = s:match("^(%x%x)(%x%x)(%x%x)$")
    if not r then return nil end
    return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end

ExportSettings = function()
    local out = { "DT1" }
    for _, k in ipairs(BOOL_KEYS) do out[#out + 1] = k .. "=" .. (DB[k] and "1" or "0") end
    for k in pairs(ENUMS) do out[#out + 1] = k .. "=" .. tostring(DB[k]) end
    out[#out + 1] = "fontSize=" .. tostring(DB.fontSize)
    out[#out + 1] = "minimapAngle=" .. tostring(DB.minimapAngle)
    out[#out + 1] = "damageColor=" .. ColorToHex(DB.damageColor)
    out[#out + 1] = "healColor=" .. ColorToHex(DB.healColor)
    out[#out + 1] = "manaColor=" .. ColorToHex(DB.manaColor)
    local rules = {}
    for id, v in pairs(DB.spellRules or {}) do rules[#rules + 1] = id .. ":" .. tostring(v) end
    table_sort(rules)
    out[#out + 1] = "spellRules=" .. table_concat(rules, ",")
    return table_concat(out, ";")
end


local function ParseFields(text, separator, pattern, canonicalKey)
    local fields = {}
    local start = 1
    while start <= #text do
        local stop = text:find(separator, start, true)
        local token = text:sub(start, stop and stop - 1 or #text)
        local key, value = token:match(pattern)
        if not key then return nil, "malformed field" end
        if canonicalKey then key = canonicalKey(key) end
        if not key then return nil, "invalid spell ID" end
        if fields[key] ~= nil then return nil, "duplicate field " .. key end
        fields[key] = value
        if not stop then break end
        if stop == #text and separator == "," then return nil, "empty spell rule" end
        start = stop + 1
    end
    return fields
end

-- Validate and decode the whole string before any changes to SavedVariables.
-- Syntactically valid fields from a newer exporter are ignored.
ImportSettings = function(str)
    if type(str) ~= "string" then return false, "not text" end
    str = str:match("^%s*(.-)%s*$")
    if str:sub(1, 4) ~= "DT1;" then return false, "not a DamageTips settings string" end
    if str:find("%c") then return false, "control characters in settings" end

    local vals, bad = ParseFields(str:sub(5), ";", "^([%a_][%w_]*)=(.*)$")
    if not vals then return false, bad end
    local changes = {}
    for _, key in ipairs(BOOL_KEYS) do
        local value = vals[key]
        if value ~= nil then
            if value ~= "0" and value ~= "1" then return false, "bad value for " .. key end
            changes[key] = value == "1"
        end
    end
    for key, allowed in pairs(ENUMS) do
        if vals[key] ~= nil then
            local number = ReadEnum(vals[key], allowed)
            if number == nil then return false, "bad value for " .. key end
            changes[key] = number
        end
    end
    if vals.fontSize ~= nil then
        local n = FiniteNumber(vals.fontSize)
        if not n or n < FONT_MIN or n > FONT_MAX then return false, "bad font size" end
        changes.fontSize = math_floor(n + 0.5)
    end
    if vals.minimapAngle ~= nil then
        local n = FiniteNumber(vals.minimapAngle)
        if not n then return false, "bad minimap angle" end
        changes.minimapAngle = NormalizeAngle(n)
    end
    local colors = {}
    for _, key in ipairs(COLOR_KEYS) do
        if vals[key] ~= nil then
            colors[key] = HexToColor(vals[key])
            if not colors[key] then return false, "bad colour for " .. key end
        end
    end
    if vals.spellRules ~= nil then
        local rules, err = ParseFields(vals.spellRules, ",", "^(%d+):(.+)$", SpellIDKey)
        if not rules then return false, err end
        for key, value in pairs(rules) do
            local rule = ReadRuleValue(value)
            if rule == nil then return false, "bad spell rule value for " .. key end
            rules[key] = rule
        end
        changes.spellRules = rules
    end

    for key, value in pairs(changes) do DB[key] = value end
    for key, color in pairs(colors) do CopyColor(DB[key], color) end
    SettingsChanged(changes.showMinimap ~= nil or changes.minimapAngle ~= nil)
    return true
end

-- Spell argument for /damagetips hide|show|setdmg: an ID or an exact name.
local function ResolveSpellArg(arg)
    arg = (arg or ""):match("^%s*(.-)%s*$")
    if arg == "" then return nil end
    if tonumber(arg) then return SpellIDKey(arg) end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, arg)
        if ok and not IsSecret(info) and type(info) == "table" then
            return SpellIDKey(info.spellID)
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
local function OnOff(v) return v and "|cff00ff00on|r" or "|cffff4040off|r" end

local function ShowStatus()
    local status, version, build, interface, verifiedCount = Estimates.GetModelBuildStatus()
    Print(string_format("Client: version %s, build %s, Interface %s.",
        version or "unavailable", build or "unavailable", interface and tostring(interface) or "unavailable"))
    if status == "verified" then
        Print(string_format("Spell models: enabled for %d verified spell IDs.", verifiedCount))
    elseif status == "unreadable" then
        Print("Spell models: disabled because client build information is unavailable.")
    else
        Print("Spell models: disabled on this unverified client build.")
    end
    Print("Settings: power scaling " .. OnOff(DB.showPowerScaling)
        .. ", expected DPS/HPS " .. OnOff(DB.showExpectedThroughput) .. ".")
end

local function ExplainExpected(spellID, ruleID, buildStatus)
    if not DB.showExpectedThroughput then
        return "Expected DPS and HPS is off.", "Enable it in Lines."
    end
    local rule = DB.spellRules[ruleID]
    if rule == "hide" then return "This rank is hidden.", "Use /dtips show " .. ruleID .. "." end
    if type(rule) == "number" then
        return "This rank uses pinned damage.", "Use /dtips show " .. ruleID .. " to restore normal parsing."
    end
    if not DB.showActionBar and not DB.showSpellbook then
        return "Action bar and spellbook tooltips are off.", "Enable a tooltip location in Lines."
    end
    if buildStatus == "unreadable" then return "Client build information is unavailable." end
    if buildStatus ~= "verified" then return "This client build is unverified." end
    local model = Estimates.GetSpellModel(spellID)
    if not model then return "This rank has no verified model on this build." end
    if not model.expected then return "This rank supports scaling only." end
    local fromAction = not DB.showSpellbook
    if not Estimates.IsKnownPlayerSpell(spellID, fromAction) then
        if fromAction then
            return "The action bar could not confirm an unambiguous player rank.",
                "Check the learned rank or enable spellbook tooltips."
        end
        return "The player spellbook could not confirm this rank.", "Use the ID of a learned rank."
    end
    if not Estimates.SupportsSpellTextLocale() then return "Estimates require English spell descriptions." end

    local text, secret, loaded = GetSpellText(spellID, false)
    if secret then return "The spell description is restricted." end
    if not loaded then
        return "The spell description is unavailable.", "Hover the spell in the spellbook and try again."
    end
    -- Parse directly so a report cannot replace a hover cache entry.
    local parsed = Estimates.ParseComponents(text, model, true)
    local effect, ticks = ActiveModeledEffect(parsed, model)
    if not DB.includeDoT and parsed.effect and parsed.expectedAmount == 0 then
        return "Periodic effects are off for this periodic-only rank.", "Enable Include Periodic Effects."
    end
    local amount = ResolveExpectedAmount(parsed, model, effect)
    if not amount then
        if parsed.attackPowerBase then return "Required combat stats are unavailable." end
        return "The spell description does not match the estimate model."
    end

    local cycle = GetExpectedCycle(GetBaseCycle(spellID), effect)
    if not cycle then return "Spell timing is unavailable." end
    if not Estimates.GetExpectedRate(model.expected, amount, cycle, effect, ticks, model) then
        return "Required combat stats are unavailable."
    end
    if model.expected == "healing" then return "Expected HPS is available." end
    if model.expected == "landed" then return "DPS on landed hits is available." end
    return "Expected DPS is available."
end

local REPORT_DIALOG = "DAMAGETIPS_ESTIMATE_REPORT"

local function SelectReport(dialog, report)
    if (dialog.IsForbidden and dialog:IsForbidden()) or not dialog.GetEditBox then return false end
    local edit = dialog:GetEditBox()
    if IsSecret(edit) or not edit or (edit.IsForbidden and edit:IsForbidden()) then return false end
    edit:SetText(report)
    edit:SetFocus()
    edit:HighlightText()
    return true
end

local function TryShowEstimateReport(report)
    if not (InCombatLockdown and StaticPopupDialogs and StaticPopup_Show) then return false end
    local checked, locked = pcall(InCombatLockdown)
    if not checked or IsSecret(locked) or locked ~= false then return false end
    if not StaticPopupDialogs[REPORT_DIALOG] then
        StaticPopupDialogs[REPORT_DIALOG] = {
            text = "DamageTips estimate report\nPress Ctrl+C to copy.",
            button1 = CLOSE or "Close",
            hasEditBox = true,
            maxLetters = 0,
            editBoxWidth = 320,
            timeout = 0,
            hideOnEscape = true,
            EditBoxOnEscapePressed = function(edit) edit:GetParent():Hide() end,
        }
    end
    local shown, dialog = pcall(StaticPopup_Show, REPORT_DIALOG)
    if not shown or IsSecret(dialog) or not dialog then return false end
    local ok, selected = pcall(SelectReport, dialog, report)
    if ok and selected then return true end
    if dialog.Hide then pcall(dialog.Hide, dialog) end
    return false
end

local function ShowEstimateReport(argument)
    local id = argument:match("^%d+$") and SpellIDKey(argument)
    if not id then Print("usage: /dtips why <spellID>") return end
    local status, _, build = Estimates.GetModelBuildStatus()
    local reason, action = ExplainExpected(tonumber(id), id, status)
    local report = string_format("DamageTips | Build %s | Spell ID %s | Reason: %s",
        build or "unavailable", id, reason)
    if action then report = report .. " | Action: " .. action end
    if not TryShowEstimateReport(report) then print(report) end
end

local function ShowHelp()
    Print("commands:")
    print("  |cffffd100/damagetips|r - open the settings window")
    print("  |cffffd100/dtips status|r - show client and spell model compatibility")
    print("  |cffffd100/dtips why <spellID>|r - explain expected DPS or HPS for a rank")
    print("  |cffffd100/damagetips dps|r - toggle DPS (" .. OnOff(DB.showDPS) .. ")")
    print("  |cffffd100/damagetips dpm|r - toggle DPM (" .. OnOff(DB.showDPM) .. ")")
    print("  |cffffd100/damagetips mana|r - toggle mana cost line (" .. OnOff(DB.showMana) .. ")")
    print("  |cffffd100/damagetips sustain|r - toggle mana sustain (" .. OnOff(DB.showManaSustain) .. ")")
    print("  |cffffd100/damagetips caster|r - toggle caster spell stats (" .. OnOff(DB.showCasterStats) .. ")")
    print("  |cffffd100/damagetips scaling|r - toggle power scaling (" .. OnOff(DB.showPowerScaling) .. ")")
    print("  |cffffd100/damagetips expected|r - toggle expected output (" .. OnOff(DB.showExpectedThroughput) .. ")")
    print("  |cffffd100/damagetips healing|r - toggle healing lines (" .. OnOff(DB.showHealing) .. ")")
    print("  |cffffd100/damagetips minimap|r - toggle the minimap button (" .. OnOff(DB.showMinimap) .. ")")
    print("  |cffffd100/damagetips debug|r - toggle debug output (" .. OnOff(DEBUG) .. ")")
    print("  |cffffd100/damagetips reset|r - reset options, keeping spell rules and minimap position")
    print("  |cffffd100/damagetips hide <spell>|show <spell>|r - hide or restore a spell's lines")
    print("  |cffffd100/damagetips setdmg <spell> <avg>|r - pin a spell's average damage")
    print("  |cffffd100/damagetips rules|r - list spell rules")
    print("  |cffffd100/damagetips export|r / |cffffd100import <string>|r - share settings")
end

local TOGGLES = {
    dps     = { key = "showDPS",     label = "DPS" },
    dpm     = { key = "showDPM",     label = "DPM" },
    mana    = { key = "showMana",    label = "mana cost line" },
    sustain = { key = "showManaSustain", label = "mana sustain estimate" },
    caster  = { key = "showCasterStats", label = "caster spell stats" },
    scaling = { key = "showPowerScaling", label = "spell and attack power scaling" },
    expected = { key = "showExpectedThroughput", label = "expected DPS and HPS" },
    healing = { key = "showHealing", label = "healing lines" },
}

SLASH_DAMAGETIPS1 = "/damagetips"
SLASH_DAMAGETIPS2 = "/dtips"
SlashCmdList["DAMAGETIPS"] = function(msg)
    if not DB then return end
    msg = msg or ""
    local cmd = msg:lower():match("^%s*(%S*)")
    local rest = msg:match("^%s*%S+%s*(.-)%s*$") or ""
    local toggle = TOGGLES[cmd]

    if cmd == "" or cmd == "config" or cmd == "options" then
        ToggleConfig()
    elseif cmd == "help" then
        ShowHelp()
    elseif cmd == "status" then
        ShowStatus()
    elseif cmd == "why" then
        ShowEstimateReport(rest)
    elseif toggle then
        SetOption(toggle.key, not DB[toggle.key])
        Print(toggle.label .. " " .. OnOff(DB[toggle.key]))
    elseif cmd == "debug" then
        DEBUG = not DEBUG
        Print("debug " .. OnOff(DEBUG))
        if DEBUG and GetBuildInfo then
            local version, build = GetBuildInfo()
            Print("client: " .. tostring(version) .. " build " .. tostring(build))
        end
    elseif cmd == "reset" then
        ResetDB()
        Print("options reset; spell rules and minimap position kept")
    elseif cmd == "minimap" then
        SetOption("showMinimap", not DB.showMinimap)
        Print("minimap button " .. OnOff(DB.showMinimap))
    elseif cmd == "hide" then
        local id = ResolveSpellArg(rest)
        if not id then Print("usage: /damagetips hide <spell name or ID>") return end
        DB.spellRules[id] = "hide"
        SettingsChanged(false)
        Print("hiding DamageTips lines for spell " .. id)
    elseif cmd == "show" then
        local id = ResolveSpellArg(rest)
        if not id then Print("usage: /damagetips show <spell name or ID>") return end
        DB.spellRules[id] = nil
        SettingsChanged(false)
        Print("spell " .. id .. " uses normal parsing again")
    elseif cmd == "setdmg" then
        local name, n = rest:match("^(.-)%s+(%S+)$")
        local id = name and ResolveSpellArg(name)
        local value = FiniteNumber(n)
        if not id or not value or value < 0 then Print("usage: /damagetips setdmg <spell name or ID> <average damage>") return end
        DB.spellRules[id] = value
        SettingsChanged(false)
        Print("spell " .. id .. " average damage pinned to " .. n)
    elseif cmd == "rules" then
        local any = false
        for id, v in pairs(DB.spellRules or {}) do
            any = true
            Print("  spell " .. id .. ": " .. (v == "hide" and "hidden" or ("damage pinned to " .. tostring(v))))
        end
        if not any then Print("no spell rules set") end
    elseif cmd == "export" then
        Print("settings string (copy it, paste with /damagetips import):")
        print(ExportSettings())
    elseif cmd == "import" then
        local ok, err = ImportSettings(rest)
        if ok then
            Print("settings imported")
        else
            Print("import failed: " .. tostring(err))
        end
    else
        ShowHelp()
    end
end

----------------------------------------------------------------------
-- Init (one-off event: unregistered as soon as it has fired)
----------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        InitDB()
        if not BuildMinimapButton() then self:RegisterEvent("PLAYER_LOGIN") end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        BuildMinimapButton()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
