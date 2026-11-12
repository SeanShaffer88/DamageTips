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
local GCD_FALLBACK = 1.5 -- used only when the spell reports no GCD of its own
local CACHE_TTL = 1.0    -- seconds a computed result is reused while hovering
local FONT_MIN, FONT_MAX = 8, 20
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local BANK_PLAYER = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
local BANK_PET = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet) or 1
local ACTION, BOOK = 1, 2
local OUTLINES = { "", "OUTLINE", "THICKOUTLINE" }
local DPS_FORMATS = { [0] = "%.0f", [1] = "%.1f", [2] = "%.2f" }

local DEBUG = false
local DB

local DEFAULTS = {
    showDPS       = true,   -- "DPS: x"
    showDPM       = true,   -- "DPM: x" (damage per minute)
    showHealing   = true,   -- "HPS: x   HPM: y" and the absorb line on healing spells
    showRange     = false,  -- "Damage: 59-65 (avg 62)"
    showDPC       = false,  -- "Damage per cast: x"
    schoolTint    = false,  -- tint the damage lines by spell school
    showNextRank  = false,  -- "Next rank: DPS x (+y%)"
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

local PREFIX = "|cffffd100DamageTips|r: "
local function Print(msg) print(PREFIX .. msg) end

----------------------------------------------------------------------
-- Saved variables: validate everything, never trust the WTF contents
----------------------------------------------------------------------
local function SanitizeColor(c, default)
    if type(c) ~= "table" then c = {} end
    for i = 1, 3 do
        local v = tonumber(c[i])
        if not v then v = default[i] end
        c[i] = math_min(1, math_max(0, v))
    end
    return c
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
        local v, valid = tonumber(db[key]), false
        for _, a in ipairs(allowed) do
            if v == a then valid = true end
        end
        if valid then db[key] = v else db[key] = DEFAULTS[key] end
    end

    local size = tonumber(db.fontSize) or DEFAULTS.fontSize
    db.fontSize = math_min(FONT_MAX, math_max(FONT_MIN, math_floor(size + 0.5)))

    db.damageColor = SanitizeColor(db.damageColor, DEFAULTS.damageColor)
    db.manaColor = SanitizeColor(db.manaColor, DEFAULTS.manaColor)
    db.healColor = SanitizeColor(db.healColor, DEFAULTS.healColor)

    if type(db.minimapAngle) ~= "number" then db.minimapAngle = 215 end

    local rules = {}
    if type(db.spellRules) == "table" then
        for k, v in pairs(db.spellRules) do
            if type(k) == "string" and tonumber(k) then
                if v == "hide" then rules[k] = "hide"
                elseif type(v) == "number" and v >= 0 then rules[k] = v end
            end
        end
    end
    db.spellRules = rules

    DB = db
end

----------------------------------------------------------------------
-- Result cache (recycled entry tables, no per-hover allocations)
----------------------------------------------------------------------
-- Blizzard re-runs the tooltip setter periodically while the mouse rests on a
-- button, so the computed lines are reused for CACHE_TTL seconds per spell.
local cache = {}     -- [spellID] = entry
local entryPool = {} -- recycled entries

local function InvalidateCache()
    for id, e in pairs(cache) do
        entryPool[#entryPool + 1] = e
        cache[id] = nil
    end
end

-- Any option that changes the text of a line goes through here.
local function SetOption(key, value)
    DB[key] = value
    InvalidateCache()
end

local function CopyColor(dst, src)
    dst[1], dst[2], dst[3] = src[1], src[2], src[3]
end

local function ResetDB()
    for _, key in ipairs(BOOL_KEYS) do DB[key] = DEFAULTS[key] end
    for key in pairs(ENUMS) do DB[key] = DEFAULTS[key] end
    DB.fontSize = DEFAULTS.fontSize
    CopyColor(DB.damageColor, DEFAULTS.damageColor)
    CopyColor(DB.manaColor, DEFAULTS.manaColor)
    CopyColor(DB.healColor, DEFAULTS.healColor)
    InvalidateCache()
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
    return string_format("+100 %s: +%s %s / tick (+%s over %d ticks)",
        stat, FormatPowerGain(effect.coefficient), output,
        FormatPowerGain(effect.coefficient * effect.ticks), effect.ticks)
end

local function ExpectedLineText(kind, rate, hit, crit, effect, target, modifiers)
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

local function HealLineText(hps)
    if not DB.showHealing or not hps or hps <= 0 then return false end
    local a = "HPS: " .. FormatNumber(string_format(DPS_FORMATS[DB.dpsDecimals], hps))
    local b = "HPM: " .. FormatNumber(string_format("%.0f", hps * 60))
    return a .. "   " .. b
end

local function HealEffLineText(htotal, cost)
    if not DB.showDPMana or not DB.showHealing or not cost or cost <= 0 or not htotal or htotal <= 0 then
        return false
    end
    return "Healing per mana: " .. FormatNumber(string_format("%.2f", htotal / cost))
end

local function AbsorbLineText(absorb)
    if not DB.showHealing or not absorb or absorb <= 0 then return false end
    return "Absorbs: " .. FormatNumber(string_format("%.0f", absorb))
end

local function NextRankLineText(dps, nextDPS)
    if not DB.showNextRank or not dps or dps <= 0 or not nextDPS or nextDPS <= dps then return false end
    return string_format("Next rank: DPS %s (+%.0f%%)",
        FormatNumber(string_format(DPS_FORMATS[DB.dpsDecimals], nextDPS)),
        (nextDPS - dps) / dps * 100)
end

-- Breakdown lines shown while Shift is held (components already parsed).
local function BuildDetailLines(t)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    if t.lo and t.hi and t.lo ~= t.hi then
        add(string_format("Direct: %s-%s (avg %s)",
            FormatNumber(string_format("%.0f", t.lo)),
            FormatNumber(string_format("%.0f", t.hi)),
            FormatNumber(string_format("%.0f", (t.lo + t.hi) / 2))))
    elseif t.total and t.total > 0 then
        add("Damage: " .. FormatNumber(string_format("%.0f", t.total)))
    end
    if t.dot and t.dot > 0 then
        add(string_format("Damage over time: %s over %s sec",
            FormatNumber(string_format("%.0f", t.dot)), tostring(t.dotDur or "?")))
    end
    if t.time then add(string_format("Divisor: %.2f sec", t.time)) end
    if t.school then add("School: " .. t.school:sub(1, 1):upper() .. t.school:sub(2)) end
    if DB.showHealing and t.htotal and t.htotal > 0 then
        add("Healing: " .. FormatNumber(string_format("%.0f", t.htotal)))
        if t.hot and t.hot > 0 then
            add(string_format("Heal over time: %s over %s sec",
                FormatNumber(string_format("%.0f", t.hot)), tostring(t.hotDur or "?")))
        end
        if t.htime then add(string_format("Heal divisor: %.2f sec", t.htime)) end
    end
    if DB.showHealing and t.absorb and t.absorb > 0 then
        add("Absorb: " .. FormatNumber(string_format("%.0f", t.absorb)))
    end
    if #lines == 0 then return nil end
    return lines
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
local function GetCastTime(spellID)
    if not (C_Spell and C_Spell.GetSpellInfo) then return 0 end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
    if not ok or IsSecret(info) or type(info) ~= "table" then return 0 end
    local ms = info.castTime
    if IsSecret(ms) or type(ms) ~= "number" then return 0 end
    return ms / 1000, ms >= 0 and ms < math.huge
end

-- Returns base cooldown and the spell's own GCD, in seconds.
local function GetBaseTimings(spellID)
    if not GetSpellBaseCooldown then return 0, GCD_FALLBACK end
    local ok, cdMS, gcdMS = pcall(GetSpellBaseCooldown, spellID)
    if not ok then return 0, GCD_FALLBACK end
    local cd, gcd = 0, GCD_FALLBACK
    local cdReadable = not IsSecret(cdMS) and type(cdMS) == "number"
    local gcdReadable = not IsSecret(gcdMS) and type(gcdMS) == "number"
    if cdReadable then cd = cdMS / 1000 end
    if gcdReadable and gcdMS > 0 then gcd = gcdMS / 1000 end
    return cd, gcd, cdReadable and gcdReadable and cdMS >= 0 and cdMS < math.huge
        and gcdMS >= 0 and gcdMS < math.huge
end

-- Spell text comes from tooltip data, never from FontString:GetText()
-- (always secret). Returns text, wasSecret, descriptionLoaded.
-- descriptionLoaded is false when only the name line (or nothing) came back,
-- which means the client has not loaded the spell data yet.
local parts = {} -- scratch table, reused
local function GetSpellText(spellID)
    local n, secret = 0, false

    if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
        local data = C_TooltipInfo.GetSpellByID(spellID)
        if IsSecret(data) then
            secret = true
        elseif type(data) == "table" then
            local lines = data.lines
            if IsSecret(lines) then
                secret = true
            elseif type(lines) == "table" then
                for i = 1, #lines do
                    local line = lines[i]
                    if IsSecret(line) then
                        secret = true
                    elseif type(line) == "table" then
                        local t = line.leftText
                        if IsSecret(t) then
                            secret = true
                        elseif type(t) == "string" then
                            n = n + 1
                            parts[n] = t
                        end
                    end
                end
            end
        end
    end

    local loaded = n >= 2
    if not loaded and C_Spell and C_Spell.GetSpellDescription then
        local desc = C_Spell.GetSpellDescription(spellID)
        if IsSecret(desc) then
            secret = true
        elseif type(desc) == "string" and desc ~= "" then
            n = n + 1
            parts[n] = desc
            loaded = true
        end
    end

    local text = table_concat(parts, " ", 1, n)
    wipe(parts)
    return text, secret, loaded
end

local function GetTooltipFontPath()
    return (GameTooltipText and GameTooltipText:GetFont()) or STANDARD_TEXT_FONT
end

----------------------------------------------------------------------
-- Damage & healing parsing (English patterns shipped; see PATTERNS)
----------------------------------------------------------------------
-- Pattern sets keyed by client locale. A translation file can register its
-- own set before this file loads: DamageTipsPatterns["deDE"] = { ... }.
-- Only the active locale's set is used; unmatched locales fall back to enUS.
local PATTERNS = {
    enUS = {
        dot       = "(%d+) [%a ]-damage over (%d+) sec",
        range     = "(%d+) to (%d+) (%a[%a ]-)damage",
        flat      = "for (%d+) (%a[%a ]-)damage",
        absorb    = "absorbs? (%d+) damage",
        hot       = "(%d+) health over (%d+) sec",
        hotAlt    = "for (%d+) over (%d+) sec",
        renew     = "[Hh]eals the target of ([%d,]+) damage over (%d+) sec%a*%.",
        healRange = "(%d+) to (%d+) health",
        healFlat  = "for (%d+) health",
        healFlat2 = "restores (%d+) health",
    },
}
if type(_G.DamageTipsPatterns) == "table" then
    for loc, pack in pairs(_G.DamageTipsPatterns) do
        if type(pack) == "table" then PATTERNS[loc] = pack end
    end
end
local P = PATTERNS[(GetLocale and GetLocale()) or "enUS"] or PATTERNS.enUS

local SCHOOL_COLORS = {
    frost = { 0.62, 0.8, 1 }, fire = { 1, 0.5, 0.25 }, shadow = { 0.6, 0.45, 0.9 },
    holy = { 1, 0.9, 0.5 }, nature = { 0.55, 0.9, 0.45 }, arcane = { 1, 0.55, 0.85 },
    physical = { 1, 1, 1 },
}

local function CleanSchool(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("%s+", "")
    if SCHOOL_COLORS[s] then return s end
    return nil
end

-- Returns direct, dot, dotDuration, rangeLo, rangeHi, school.
local function ParseDamage(text)
    local direct, dot, dotDuration, lo, hi, school = 0, 0, nil, nil, nil, nil
    text = text:lower():gsub("(%d),(%d)", "%1%2") -- "1,234" -> "1234"

    local dotAmount, dur = text:match(P.dot)
    if dotAmount then
        dot, dotDuration = tonumber(dotAmount), tonumber(dur)
        text = text:gsub(P.dot, "")
    end

    local a, b, s = text:match(P.range)
    if a then
        lo, hi = tonumber(a), tonumber(b)
        direct = (lo + hi) / 2
        school = CleanSchool(s)
    else
        local flat, fs = text:match(P.flat)
        if flat then
            direct = tonumber(flat)
            lo, hi = direct, direct
            school = CleanSchool(fs)
        end
    end

    return direct, dot, dotDuration, lo, hi, school
end

-- Healing text; the caller removes the damage-over-time text first so a DoT
-- is never mistaken for a heal-over-time.
-- Returns hDirect(avg), hLo, hHi, hot, hotDuration, absorb.
local function ParseHealing(text)
    local hDirect, hLo, hHi, hot, hotDur, absorb = 0, nil, nil, 0, nil, nil
    text = text:lower():gsub("(%d),(%d)", "%1%2")

    local ab = text:match(P.absorb)
    if ab then
        absorb = tonumber(ab)
        text = text:gsub(P.absorb, "")
    end

    local hotAmount, hd = text:match(P.hot)
    if not hotAmount then hotAmount, hd = text:match(P.hotAlt) end
    if hotAmount then
        hot, hotDur = tonumber(hotAmount), tonumber(hd)
        text = text:gsub(P.hot, ""):gsub(P.hotAlt, "")
    end

    local a, b = text:match(P.healRange)
    if a then
        hLo, hHi = tonumber(a), tonumber(b)
        hDirect = (hLo + hHi) / 2
        text = text:gsub(P.healRange, "")
    else
        local flat = text:match(P.healFlat) or text:match(P.healFlat2)
        if flat then
            hDirect = tonumber(flat)
            hLo, hHi = hDirect, hDirect
        end
    end

    return hDirect, hLo, hHi, hot, hotDur, absorb
end

----------------------------------------------------------------------
-- Spell rank index (spellbook scan; rebuilt when the spellbook changes)
----------------------------------------------------------------------
local rankIndex, rankIndexDirty = {}, true

local function RebuildRankIndex()
    rankIndex, rankIndexDirty = {}, false
    if not (C_SpellBook and C_SpellBook.GetSpellBookItemInfo) then return end
    local trailing = 0
    for slot = 1, 2000 do
        local info = C_SpellBook.GetSpellBookItemInfo(slot, BANK_PLAYER)
        if info and type(info.name) == "string" and not IsSecret(info.name) then
            trailing = 0
            local r = type(info.subName) == "string" and info.subName:match("^Rank (%d+)$") or nil
            r = tonumber(r) or 0
            local list = rankIndex[info.name]
            if not list then list = {}; rankIndex[info.name] = list end
            local id = info.spellID or info.actionID
            if type(id) == "number" and not IsSecret(id) then
                list[#list + 1] = { rank = r, id = id }
            end
        else
            trailing = trailing + 1
            if trailing > 40 then break end
        end
    end
    for _, list in pairs(rankIndex) do
        table_sort(list, function(a, b) return a.rank < b.rank end)
    end
end

local function NextRankSpellID(spellID)
    if rankIndexDirty then RebuildRankIndex() end
    local name
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        name = info and info.name
    end
    if type(name) ~= "string" or IsSecret(name) then return nil end
    local list = rankIndex[name]
    if not list or #list < 2 then return nil end
    local myRank = -1
    for _, e in ipairs(list) do
        if e.id == spellID then myRank = e.rank break end
    end
    local best
    for _, e in ipairs(list) do
        if e.rank > myRank and (not best or e.rank < best.rank) then best = e end
    end
    return best and best.id or nil
end

----------------------------------------------------------------------
-- Async spell data (SPELL_DATA_LOAD_RESULT)
----------------------------------------------------------------------
local cur = { added = false } -- spell ID, owner and source of the active tooltip
local AddSpellInfo -- forward declaration

local requestedOnce = {} -- spells we already asked the server about
local pending = {}       -- requests awaiting SPELL_DATA_LOAD_RESULT
local waiting = 0
local dataFrame = CreateFrame("Frame")

-- Returns true if a new request was issued.
local function RequestSpellData(spellID)
    if requestedOnce[spellID] or not (C_Spell and C_Spell.RequestLoadSpellData) then return false end
    requestedOnce[spellID] = true
    pending[spellID] = true
    waiting = waiting + 1
    dataFrame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
    pcall(C_Spell.RequestLoadSpellData, spellID)
    return true
end

dataFrame:RegisterEvent("SPELLS_CHANGED") -- rank index + cache go stale
dataFrame:SetScript("OnEvent", function(self, event, spellID)
    if event == "SPELLS_CHANGED" then
        rankIndexDirty = true
        if DB then InvalidateCache() end
        return
    end
    if not pending[spellID] then return end
    pending[spellID] = nil
    waiting = waiting - 1
    if waiting <= 0 then
        waiting = 0
        self:UnregisterEvent("SPELL_DATA_LOAD_RESULT") -- nothing left to wait for
    end

    local e = cache[spellID]
    if e then e.stamp = 0 end -- force a recompute with the loaded data

    -- Tooltip still showing this spell without our lines: append them now.
    if cur.spellID == spellID and not cur.added
        and GameTooltip:IsShown() and GameTooltip:GetOwner() == cur.owner then
        pcall(AddSpellInfo, GameTooltip, spellID, cur.source)
    end
end)

----------------------------------------------------------------------
-- Entry computation
----------------------------------------------------------------------
-- Computes every number for a spell. `light` skips healing and next-rank
-- (used when computing the next rank itself, to avoid chaining).
local function Compute(spellID, light, estimate, powerModel)
    local text, secret, loaded = GetSpellText(spellID)
    local t = { secret = secret, loaded = loaded }
    if not loaded and not secret then
        t.requested = RequestSpellData(spellID)
    end
    if DEBUG then Print("spell text: " .. (text ~= "" and text or "<none / secret>")) end

    local rule = DB.spellRules and DB.spellRules[tostring(spellID)]
    if rule == "hide" then
        t.hidden = true
        return t
    end

    estimate = estimate and loaded and not secret
    local wantsSustain = estimate and DB.showManaSustain
    local wantsExpected = estimate and powerModel and powerModel.expected
        and DB.showExpectedThroughput and type(rule) ~= "number"
    local hasPeriodicOutput = false
    t.powerModel = estimate and powerModel
    local effect = t.powerModel and t.powerModel.periodic
    local legacyText = text
    if P.renew then
        legacyText = text:gsub(P.renew, "heals the target for %1 health over %2 sec.")
    end
    t.baselineDamage = DB.showDPS or DB.showDPM or DB.showDPC or DB.showRange or DB.showDPMana
    if DB.showMana or DB.showDPMana or wantsSustain then
        t.cost, t.fixedManaCost = Estimates.GetManaCost(spellID, wantsSustain)
    end

    if text ~= "" and (t.baselineDamage or estimate) then
        local direct, dot, dotDur, lo, hi, school
        if type(rule) == "number" then
            direct, lo, hi, school = rule, rule, rule, nil
            dot, dotDur = 0, nil
        else
            direct, dot, dotDur, lo, hi, school = ParseDamage(legacyText)
        end
        hasPeriodicOutput = dot > 0
        if not DB.includeDoT then dot, dotDur = 0, nil end
        local total = direct + dot
        t.total, t.lo, t.hi, t.dot, t.dotDur, t.school = total, lo, hi, dot, dotDur, school
    end

    if not light and (DB.showHealing or estimate) and text ~= "" then
        local noDot = legacyText:gsub(P.dot, "") -- never read a DoT as a heal-over-time
        local hDirect, hLo, hHi, hot, hotDur, absorb = ParseHealing(noDot)
        hasPeriodicOutput = hasPeriodicOutput or hot > 0
        if not DB.includeDoT then hot, hotDur = 0, nil end
        local htotal = hDirect + hot
        t.htotal, t.hLo, t.hHi, t.hot, t.hotDur, t.absorb = htotal, hLo, hHi, hot, hotDur, absorb
    end

    local damageTiming = t.total and t.total > 0 and (t.baselineDamage or wantsSustain)
    local healingTiming = t.htotal and t.htotal > 0 and (DB.showHealing or wantsSustain)
    local expectedAmount
    if effect then
        if DB.includeDoT and (DB.showPowerScaling or wantsExpected) then
            local direct, tickTotal = Estimates.GetPeriodicAmounts(powerModel, text)
            t.tickTotal = tickTotal
            if wantsExpected then expectedAmount = direct end
        end
    elseif wantsExpected and not hasPeriodicOutput then
        expectedAmount = Estimates.GetExpectedAmount(powerModel, text)
    end
    if damageTiming or healingTiming or expectedAmount then
        local cd, gcd, cooldownsReadable = GetBaseTimings(spellID)
        local cast, castReadable = GetCastTime(spellID)
        local baseTime = math_max(cast, cd)
        if DB.gcdFloor then baseTime = math_max(baseTime, gcd) end
        if damageTiming then
            local time = math_max(baseTime, t.dotDur or 0)
            t.time = time > 0 and time or gcd
            t.dps = t.total / t.time
        end
        if healingTiming then
            local time = math_max(baseTime, t.hotDur or 0)
            t.htime = time > 0 and time or gcd
            t.hps = t.htotal / t.htime
        end
        if wantsSustain and cooldownsReadable and castReadable then
            t.sustainCycle = math_max(t.time or 0, t.htime or 0)
        end
        if expectedAmount and cooldownsReadable and castReadable then
            t.expectedAmount = expectedAmount
            local time = math_max(baseTime, effect and effect.duration or 0)
            t.expectedCycle = time > 0 and time or gcd
        end
    end

    if not light and t.baselineDamage and DB.showNextRank and t.dps and t.dps > 0 then
        local nextID = NextRankSpellID(spellID)
        if nextID then
            local nt = Compute(nextID, true)
            if nt and nt.dps then t.nextDPS = nt.dps end
        end
    end

    return t, estimate
end

local function BuildEntry(e, spellID, now, estimate, powerModel)
    e.dmgLine, e.dpcLine, e.rangeLine, e.effLine = false, false, false, false
    e.healLine, e.heffLine, e.absorbLine, e.nextLine, e.manaLine = false, false, false, false, false
    e.detailLines, e.schoolColor = nil, nil
    e.stamp = now

    local t, readableEstimate = Compute(spellID, false, estimate, powerModel)
    if t.requested then
        e.stamp = 0 -- data not loaded yet: do not cache this result
    end

    if t.baselineDamage and t.total and t.total > 0 then
        if DB.showDPS or DB.showDPM then e.dmgLine = DamageLineText(t.dps) end
        e.dpcLine = DPCLineText(t.total)
        e.rangeLine = RangeLineText(t.lo, t.hi)
        e.effLine = EfficiencyLineText(t.total, t.cost)
        e.nextLine = NextRankLineText(t.dps, t.nextDPS)
        if DB.schoolTint and t.school then e.schoolColor = SCHOOL_COLORS[t.school] end
        e.detailLines = BuildDetailLines(t)
    end

    if DB.showHealing and t.htotal and t.htotal > 0 then
        e.healLine = HealLineText(t.hps)
        e.heffLine = HealEffLineText(t.htotal, t.cost)
    end
    e.absorbLine = AbsorbLineText(t.absorb)

    if DB.showMana and t.cost and t.cost > 0 then
        local maxMana
        if DB.manaMode ~= 2 then
            maxMana = UnitPowerMax("player", MANA)
            if IsSecret(maxMana) then maxMana = nil end
        end
        e.manaLine = ManaLineText(t.cost, maxMana)
    end
    if readableEstimate then return t end
end

local function GetEntry(spellID, estimate, powerModel)
    local now = GetTime()
    local e = cache[spellID]
    if not estimate and e and (now - e.stamp) < CACHE_TTL then return e end

    if not e then
        e = entryPool[#entryPool]
        if e then entryPool[#entryPool] = nil else e = {} end
        cache[spellID] = e
    end
    return e, BuildEntry(e, spellID, now, estimate, powerModel)
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
    cur.spellID, cur.owner, cur.source, cur.added = nil, nil, nil, false
end)

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
            model.periodic, t.tickTotal, model)
        if rate then
            local color = model.expected == "healing" and DB.healColor or dmgColor
            AddStyledLine(tooltip, ExpectedLineText(model.expected, rate, hit, crit, model.periodic, target, modifiers), color)
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
        local healing = OutputBeforeLowManaText(casts, t.htotal, "healing")
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

AddSpellInfo = function(tooltip, spellID, source)
    if not DB or not spellID then return end
    local model = source and (DB.showPowerScaling or DB.showExpectedThroughput)
        and Estimates.GetSpellModel(spellID)
    local estimate = source and (DB.showManaSustain or DB.showCasterStats or model)
        and Estimates.IsKnownPlayerSpell(spellID, source == ACTION)
    local e, estimateData = GetEntry(spellID, estimate, model)
    local added = false
    local dmgColor = e.schoolColor or DB.damageColor

    if e.dmgLine then AddStyledLine(tooltip, e.dmgLine, dmgColor) added = true end
    if e.dpcLine then AddStyledLine(tooltip, e.dpcLine, dmgColor) added = true end
    if e.rangeLine then AddStyledLine(tooltip, e.rangeLine, dmgColor) added = true end
    if e.effLine then AddStyledLine(tooltip, e.effLine, dmgColor) added = true end
    if e.nextLine then AddStyledLine(tooltip, e.nextLine, dmgColor) added = true end
    if e.healLine then AddStyledLine(tooltip, e.healLine, DB.healColor) added = true end
    if e.heffLine then AddStyledLine(tooltip, e.heffLine, DB.healColor) added = true end
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
        tooltip:Show() -- resize the tooltip to fit new lines
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

local function OnTooltipHook(tooltip, kind, slot, arg)
    if not DB or IsSecret(slot) then return end
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
    if not spellID then return end

    cur.spellID, cur.owner, cur.source, cur.added = spellID, tooltip:GetOwner(), source, false
    AddSpellInfo(tooltip, spellID, source)
end

local errorShown = false
local function Guarded(tooltip, kind, slot, arg)
    local ok, err = pcall(OnTooltipHook, tooltip, kind, slot, arg)
    if not ok and not errorShown then
        errorShown = true
        Print("error (shown once): " .. tostring(err))
    end
end

if GameTooltip.SetAction then
    hooksecurefunc(GameTooltip, "SetAction", function(tooltip, slot)
        Guarded(tooltip, ACTION, slot)
    end)
end

if GameTooltip.SetSpellBookItem then
    hooksecurefunc(GameTooltip, "SetSpellBookItem", function(tooltip, slot, bank)
        Guarded(tooltip, BOOK, slot, bank)
    end)
end

----------------------------------------------------------------------
-- Config window (tabs: Lines / Calculation / Format / Advanced)
----------------------------------------------------------------------
local config
local cfgTab = "lines"
local RefreshMinimapButton -- assigned in the minimap section further down
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
        if key == "showMinimap" and RefreshMinimapButton then RefreshMinimapButton() end
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

local function RefreshConfig()
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
    if config then UpdatePreview() end
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
    MakeCheck(calc, "Include damage over time", 16, -26, "includeDoT")
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
        InvalidateCache()
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
        RefreshConfig()
    end)

    local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    reset:SetSize(140, 24)
    reset:SetPoint("BOTTOMRIGHT", -24, 16)
    reset:SetText("Reset to defaults")
    reset:SetScript("OnClick", function()
        ResetDB()
        RefreshConfig()
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
    local angle = math.rad((DB and DB.minimapAngle) or 215)
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

local function BuildMinimapButton()
    if minimapBtn or not Minimap then return end
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
    b:SetScript("OnDragStart", function(self) self.dragging = true end)
    b:SetScript("OnDragStop", function(self) self.dragging = false end)
    b:SetScript("OnUpdate", function(self)
        if not self.dragging or not DB then return end
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = (Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()) or 1
        cx, cy = cx / scale, cy / scale
        local atan2 = math.atan2 or math.atan
        DB.minimapAngle = math.deg(atan2(cy - my, cx - mx)) % 360
        PositionMinimapButton()
    end)
    minimapBtn = b
    RefreshMinimapButton()
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
    out[#out + 1] = "minimapAngle=" .. tostring(DB.minimapAngle or 215)
    out[#out + 1] = "damageColor=" .. ColorToHex(DB.damageColor)
    out[#out + 1] = "healColor=" .. ColorToHex(DB.healColor)
    out[#out + 1] = "manaColor=" .. ColorToHex(DB.manaColor)
    local rules = {}
    for id, v in pairs(DB.spellRules or {}) do rules[#rules + 1] = id .. ":" .. tostring(v) end
    table_sort(rules)
    out[#out + 1] = "spellRules=" .. table_concat(rules, ",")
    return table_concat(out, ";")
end

-- Validates everything first; only touches the live DB if the whole string
-- is well-formed. Returns true, or false + reason.
ImportSettings = function(str)
    if type(str) ~= "string" then return false, "not text" end
    str = str:match("^%s*(.-)%s*$")
    if str:sub(1, 4) ~= "DT1;" then return false, "not a DamageTips settings string" end

    local vals = {}
    for pair in str:gmatch("[^;]+") do
        local k, v = pair:match("^([^=]+)=(.*)$")
        if k then vals[k] = v end
    end

    for _, k in ipairs(BOOL_KEYS) do
        local v = vals[k]
        if v ~= nil and v ~= "0" and v ~= "1" then return false, "bad value for " .. k end
    end
    for k, allowed in pairs(ENUMS) do
        local v = vals[k]
        if v ~= nil then
            local n, ok = tonumber(v), false
            for _, a in ipairs(allowed) do if n == a then ok = true end end
            if not ok then return false, "bad value for " .. k end
        end
    end
    if vals.fontSize ~= nil then
        local n = tonumber(vals.fontSize)
        if not n or n < FONT_MIN or n > FONT_MAX then return false, "bad font size" end
    end
    local colors = {}
    for _, k in ipairs({ "damageColor", "healColor", "manaColor" }) do
        if vals[k] ~= nil then
            colors[k] = HexToColor(vals[k])
            if not colors[k] then return false, "bad colour for " .. k end
        end
    end
    local rules
    if vals.spellRules ~= nil then
        rules = {}
        if vals.spellRules ~= "" then
            for item in vals.spellRules:gmatch("[^,]+") do
                local id, v = item:match("^(%d+):(.+)$")
                if not id then return false, "bad spell rule: " .. item end
                if v == "hide" then rules[id] = "hide"
                elseif tonumber(v) and tonumber(v) >= 0 then rules[id] = tonumber(v)
                else return false, "bad spell rule value: " .. item end
            end
        end
    end

    for _, k in ipairs(BOOL_KEYS) do
        if vals[k] ~= nil then SetOption(k, vals[k] == "1") end
    end
    for k in pairs(ENUMS) do
        if vals[k] ~= nil then SetOption(k, tonumber(vals[k])) end
    end
    if vals.fontSize ~= nil then DB.fontSize = math_floor(tonumber(vals.fontSize) + 0.5) end
    if vals.minimapAngle ~= nil then
        local n = tonumber(vals.minimapAngle)
        if n then DB.minimapAngle = n % 360 end
    end
    for k, c in pairs(colors) do CopyColor(DB[k], c) end
    if rules then DB.spellRules = rules end
    InvalidateCache()
    return true
end

-- Spell argument for /damagetips hide|show|setdmg: an ID or an exact name.
local function ResolveSpellArg(arg)
    arg = (arg or ""):match("^%s*(.-)%s*$")
    if arg == "" then return nil end
    local id = tonumber(arg)
    if id then return id end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(arg)
        local sid = info and info.spellID
        if type(sid) == "number" and not IsSecret(sid) then return sid end
    end
    return nil
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
local function OnOff(v) return v and "|cff00ff00on|r" or "|cffff4040off|r" end

local function ShowHelp()
    Print("commands:")
    print("  |cffffd100/damagetips|r - open the settings window")
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
    print("  |cffffd100/damagetips reset|r - restore default settings")
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
    elseif toggle then
        SetOption(toggle.key, not DB[toggle.key])
        RefreshConfig()
        Print(toggle.label .. " " .. OnOff(DB[toggle.key]))
    elseif cmd == "debug" then
        DEBUG = not DEBUG
        InvalidateCache() -- so the next hover prints the spell text
        Print("debug " .. OnOff(DEBUG))
        if DEBUG and GetBuildInfo then
            local version, build = GetBuildInfo()
            Print("client: " .. tostring(version) .. " build " .. tostring(build))
        end
    elseif cmd == "reset" then
        ResetDB()
        RefreshConfig()
        Print("settings reset to defaults")
    elseif cmd == "minimap" then
        SetOption("showMinimap", not DB.showMinimap)
        RefreshMinimapButton()
        RefreshConfig()
        Print("minimap button " .. OnOff(DB.showMinimap))
    elseif cmd == "hide" then
        local id = ResolveSpellArg(rest)
        if not id then Print("usage: /damagetips hide <spell name or ID>") return end
        DB.spellRules[tostring(id)] = "hide"
        InvalidateCache()
        Print("hiding DamageTips lines for spell " .. id)
    elseif cmd == "show" then
        local id = ResolveSpellArg(rest)
        if not id then Print("usage: /damagetips show <spell name or ID>") return end
        DB.spellRules[tostring(id)] = nil
        InvalidateCache()
        Print("spell " .. id .. " uses normal parsing again")
    elseif cmd == "setdmg" then
        local name, n = rest:match("^(.-)%s+(%d+%.?%d*)$")
        local id = name and ResolveSpellArg(name)
        if not id or not n then Print("usage: /damagetips setdmg <spell name or ID> <average damage>") return end
        DB.spellRules[tostring(id)] = tonumber(n)
        InvalidateCache()
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
            RefreshConfig()
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
    if name == ADDON_NAME then
        InitDB()
        BuildMinimapButton()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
