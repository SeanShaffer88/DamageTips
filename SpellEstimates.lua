-- DamageTips spell estimates (GPL-3.0-or-later, see LICENSE.txt).
local _, addon = ...

local Estimates = {}
addon.SpellEstimates = Estimates

local IsSecret = issecretvalue or function() return false end
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local BANK_PLAYER = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
local BANK_PET = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet) or 1
local SCHOOL_INDEX = { holy = 2, fire = 3, nature = 4, frost = 5, shadow = 6, arcane = 7 }
local MODELS = addon.SpellPowerModels
local MODELS_70938 = addon.SpellPowerModels70938
local Modifiers = addon.SpellModifiers

local function IsFinite(value)
    return not IsSecret(value) and type(value) == "number" and value > -math.huge and value < math.huge
end

local function IsNonnegative(value)
    return IsFinite(value) and value >= 0
end

local function ReadModelBuild()
    if not GetBuildInfo then return end
    local ok, version, build, _, interface = pcall(GetBuildInfo)
    if not ok then return end
    if IsSecret(version) or type(version) ~= "string" or not version:match("^%d+%.%d+%.%d+$") then
        version = nil
    end
    -- GetBuildInfo normally returns a string build number.
    if IsFinite(build) and build > 0 and build == math.floor(build) then
        build = tostring(build)
    elseif IsSecret(build) or type(build) ~= "string" or not build:match("^%d+$") then
        build = nil
    end
    if not IsFinite(interface) or interface <= 0 or interface ~= math.floor(interface) then
        interface = nil
    end
    local modelBuild
    if version == "1.60.1" and interface == 16001 and (build == "70888" or build == "70938") then
        modelBuild = build
    end
    return modelBuild, version, build, interface
end

local function IsModelVerified(modelBuild, spellID)
    return modelBuild == "70888" or (modelBuild == "70938"
        and addon.Verified70938 and addon.Verified70938[spellID] == true)
end

function Estimates.GetSpellModel(spellID)
    if not IsFinite(spellID) or spellID <= 0 or spellID ~= math.floor(spellID) then return nil end
    local model, buildOnlyModel = MODELS[spellID], MODELS_70938[spellID]
    if not model and not buildOnlyModel then return nil end
    local modelBuild = ReadModelBuild()
    if modelBuild == "70938" and buildOnlyModel then
        return buildOnlyModel
    end
    if model and IsModelVerified(modelBuild, spellID) then
        return model
    end
    return nil
end

function Estimates.GetModelBuildStatus()
    local modelBuild, version, build, interface = ReadModelBuild()
    local status, verifiedCount = "unverified", 0
    if not (version and build and interface) then
        status = "unreadable"
    elseif modelBuild then
        for spellID in pairs(MODELS) do
            if IsModelVerified(modelBuild, spellID) then
                verifiedCount = verifiedCount + 1
            end
        end
        if modelBuild == "70938" then
            for _ in pairs(MODELS_70938) do verifiedCount = verifiedCount + 1 end
        end
        if verifiedCount > 0 then status = "verified" end
    end
    return status, version, build, interface, verifiedCount
end

function Estimates.IsKnownPlayerSpell(spellID, fromAction)
    local isKnown = C_SpellBook and C_SpellBook.IsSpellKnown
    if not isKnown or not IsNonnegative(spellID) or spellID == 0 then return false end
    local ok, player = pcall(isKnown, spellID, BANK_PLAYER)
    if not ok or IsSecret(player) or player ~= true then return false end
    if not fromAction then return true end

    -- An action or macro has no explicit spellbook bank. Skip ambiguous IDs.
    local petOK, pet = pcall(isKnown, spellID, BANK_PET)
    return petOK and not IsSecret(pet) and pet == false
end

-- The first result preserves the existing mana display's first-mana-entry
-- behavior. The second requires a single unconditional, up-front mana cost.
function Estimates.GetManaCost(spellID, checkFixed)
    local getCost = C_Spell and C_Spell.GetSpellPowerCost
    if not getCost then return nil end
    local ok, costs = pcall(getCost, spellID)
    if not ok or IsSecret(costs) or type(costs) ~= "table" then return nil end
    for i = 1, #costs do
        local entry = costs[i]
        if not IsSecret(entry) and type(entry) == "table" then
            local powerType = entry.type
            if not IsSecret(powerType) and powerType == MANA then
                local cost = entry.cost
                if IsSecret(cost) or type(cost) ~= "number" then return nil end
                if checkFixed and #costs == 1 and IsNonnegative(cost) and cost > 0 then
                    local minimum, periodic, aura = entry.minCost, entry.costPerSec, entry.requiredAuraID
                    if not IsSecret(minimum) and minimum == cost
                        and not IsSecret(periodic) and periodic == 0
                        and not IsSecret(aura) and aura == 0 then
                        return cost, cost
                    end
                end
                return cost
            end
        end
    end
    return nil
end

-- nil is unavailable, false is sustainable at the modeled cadence, and a
-- number is the count of affordable casts before the next one fails.
function Estimates.GetManaSustain(cost, cycle)
    if not IsNonnegative(cost) or cost == 0 or not IsNonnegative(cycle) or cycle == 0
        or not UnitPower or not GetPowerRegenForPowerType then return nil end
    local manaOK, mana = pcall(UnitPower, "player", MANA)
    local regenOK, _, regen = pcall(GetPowerRegenForPowerType, MANA)
    if not manaOK or not regenOK or not IsNonnegative(mana) or not IsNonnegative(regen) then return nil end
    local recovered = regen * cycle
    if not IsNonnegative(recovered) then return nil end
    local netCost = cost - recovered
    if mana < cost then return 0, netCost end
    if netCost <= 0 then return false, netCost end

    local casts = 1 + math.floor((mana - cost) / netCost)
    if IsNonnegative(casts) then return casts, netCost end
    return nil
end

local function ReadStat(getter, ...)
    if not getter then return nil end
    local ok, value = pcall(getter, ...)
    if ok and IsFinite(value) then return value end
    return nil
end

function Estimates.GetCasterStats(school, hasHealing)
    local index = SCHOOL_INDEX[school]
    if not index and not hasHealing then return nil end
    local crit = ReadStat(GetSpellCritChance)
    if crit and (crit < 0 or crit > 100) then crit = nil end
    local power = index and ReadStat(GetSpellBonusDamage, index)
    local healing = hasHealing and ReadStat(GetSpellBonusHealing)
    return crit, IsNonnegative(power) and power, IsNonnegative(healing) and healing
end

local function ReadAttackPower()
    if not UnitAttackPower then return nil end
    local ok, base, positive, negative = pcall(UnitAttackPower, "player")
    if not ok or not IsFinite(base) or not IsFinite(positive) or not IsFinite(negative) then return nil end
    local total = base + positive + negative
    if IsFinite(total) then return math.max(0, total) end
    return nil
end


local AMOUNT = "([%d,%.][%d,%. to%-]*)"
local INTEGER = "([%d,%.]+)"
local DURATION = "(%d+) (sec%a*)"
local SECONDS = { sec = true, secs = true, second = true, seconds = true }

local function ReadInteger(value)
    if not value then return nil end
    if not value:match("^%d+$") then
        local _, grouped = value:match("^(%d%d?%d?)(,%d.*)$")
        if not grouped or grouped:gsub(",%d%d%d", "") ~= "" then return nil end
        value = value:gsub(",", "")
    end
    local number = tonumber(value)
    return IsNonnegative(number) and number or nil
end

local function ReadRange(value)
    local low, high = value:match("^([%d,]+) to ([%d,]+)$")
    if not low then low, high = value:match("^([%d,]+) *%- *([%d,]+)$") end
    if not low then
        local single = ReadInteger(value)
        return single, single
    end
    low, high = ReadInteger(low), ReadInteger(high)
    if low and high and low <= high then return low, high end
end

local function ReadDuration(value, unit)
    local duration = SECONDS[unit] and ReadInteger(value)
    return duration and duration > 0 and duration or nil
end

local function Components(low, high, periodic, duration, school)
    local direct = low and low + (high - low) / 2 or 0
    return { direct = direct, low = low, high = high, periodic = periodic or 0,
        duration = duration, school = school }
end

local MISSILES_PREFIX = "launches arcane missiles at the enemy, causing " .. INTEGER .. " arcane damage "
local TOTAL_GRAMMARS = {
    corruption = "corrupts the target, causing " .. INTEGER .. " shadow damage over ",
    pain = "a word of darkness that causes " .. INTEGER .. " shadow damage over ",
    rejuvenation = "heals the target for " .. INTEGER .. " over ",
    wildGrowth = "^heals the target and their party for " .. INTEGER .. " over ",
    riptide = "^heals a friendly target for " .. INTEGER .. " over ",
    renew = "heals the target of " .. INTEGER .. " damage over ",
    serpentSting = "stings the target, causing " .. INTEGER .. " nature damage over ",
    mindFlay = "assault the target's mind with shadow energy, causing " .. INTEGER .. " shadow damage over ",
}
local TOTAL_SUFFIXES = {
    mindFlay = " and slowing their movement speed by %d+%%%.",
    riptide = ", and increases the effectiveness of your chain heal casts directly on that target by %d+%%%.%s*$",
}
local MIXED_GRAMMARS = {
    regrowth = "heals a friendly target for " .. AMOUNT .. " and another " .. INTEGER .. " over ",
    burn = "burns the enemy for " .. AMOUNT .. " %s damage and then an additional "
        .. INTEGER .. " %s damage over ",
    holyFire = "consumes the enemy in holy flames that cause " .. AMOUNT .. " holy damage and an additional "
        .. INTEGER .. " holy damage over ",
    fireball = "hurls a fiery ball that causes " .. AMOUNT .. " fire damage and an additional "
        .. INTEGER .. " fire damage over ",
}

local function ReadMissiles(text)
    local amount, duration, unit = text:match(MISSILES_PREFIX .. "each second for " .. DURATION .. "%.")
    if amount then return ReadInteger(amount), ReadDuration(duration, unit), 1 end
    local interval, intervalUnit
    amount, interval, intervalUnit, duration, unit =
        text:match(MISSILES_PREFIX .. "every " .. DURATION .. " for " .. DURATION .. "%.")
    return ReadInteger(amount), ReadDuration(duration, unit), ReadDuration(interval, intervalUnit)
end

local function ReadModeledPeriodic(text, model)
    local effect = model.periodic
    local grammar = effect.grammar
    local amount, duration, low, high
    if grammar == "missiles" then
        local interval
        amount, duration, interval = ReadMissiles(text)
        if not amount or interval ~= effect.interval then return nil end
        amount = amount * effect.ticks
    else
        local direct, unit
        local pattern = MIXED_GRAMMARS[grammar] or TOTAL_GRAMMARS[grammar]
        if not pattern then return nil end
        if grammar == "burn" then
            pattern = pattern:gsub(" %%s ", " " .. model.school .. " ")
        end
        if MIXED_GRAMMARS[grammar] then
            direct, amount, duration, unit = text:match(pattern .. DURATION .. "%.")
            if not direct then return nil end
            low, high = ReadRange(direct)
            if not low or low + (high - low) / 2 <= 0 then return nil end
        else
            local suffix = TOTAL_SUFFIXES[grammar] or "%."
            amount, duration, unit = text:match(pattern .. DURATION .. suffix)
        end
        amount, duration = ReadInteger(amount), ReadDuration(duration, unit)
    end
    if not IsNonnegative(amount) or amount == 0 or duration ~= effect.duration then return nil end
    return Components(low, high, amount, duration, model.school)
end

local function ReadHealRange(text)
    local amount = text:match("heals? a friendly target for " .. AMOUNT .. " health%.")
        or text:match("heals? a friendly target for " .. AMOUNT .. "%.")
        or text:match("heal your target for " .. AMOUNT .. " health%.")
        or text:match("heal your target for " .. AMOUNT .. "%.")
        or text:match("heals? a single target for " .. AMOUNT .. " health%.")
        or text:match("heals? a single target for " .. AMOUNT .. "%.")
    if amount then return ReadRange(amount) end
end

local function ReadDamageRange(text, school)
    local suffix = " " .. school .. " damage"
    local amount = text:match("for " .. AMOUNT .. suffix .. "%.")
        or text:match("causing " .. AMOUNT .. suffix .. "%.")
        or text:match("causes " .. AMOUNT .. suffix .. " to the target%.")
    if amount then return ReadRange(amount) end
end

local function ReadBloodthirst(text, model)
    local percent, flat = text:match("damage equal to (%d+)%% of your attack power plus " .. INTEGER .. " and increasing")
    if not percent then
        -- A period at the end belongs to the sentence, not the amount.
        local prefix = "damage equal to (%d+)%% of your attack power plus ([%d,]+)%."
        percent, flat = text:match(prefix .. "$")
        if not percent then percent, flat = text:match(prefix .. " ") end
    end
    if tonumber(percent) ~= model.attackPower * 100 then return nil end
    return ReadInteger(flat)
end

local SCHOOL = { physical = true, holy = true, fire = true, nature = true, frost = true, shadow = true, arcane = true }
local locale = GetLocale and GetLocale() or "enUS"

function Estimates.SupportsSpellTextLocale()
    return locale == "enUS" or locale == "enGB" or locale == "deDE"
end

function Estimates.ReadSpellRank(text)
    if IsSecret(text) or type(text) ~= "string" then return nil end
    if locale == "deDE" then return tonumber(text:match("^Rang (%d+)$")) end
    if locale == "enUS" or locale == "enGB" then return tonumber(text:match("^Rank (%d+)$")) end
end

-- Original deDE fixtures describe this deliberately bounded grammar. It does
-- not translate arbitrary text or expand exact-build coefficient coverage.
local ReadGerman
do
    local amount = "([%d%., ]+)"
    local seconds = "([%d,]+) (sek%a*%.?)"
    local schools = { feuer = "fire", frost = "frost", schatten = "shadow", natur = "nature",
        arkan = "arcane", heilig = "holy", ["körperlichen"] = "physical" }
    local units = { sek = true, ["sek."] = true, sekunde = true, sekunden = true }
    local function number(text)
        if not text then return nil end
        text = text:gsub("^ +", ""):gsub(" +$", "")
        if text:find(" ", 1, true) and text:find(".", 1, true) then return nil end
        text = text:gsub(" ", ".")
        local whole, decimal = text:match("^(.-),(%d+)$")
        whole = whole or text
        if whole:find(".", 1, true) then
            local head, groups = whole:match("^(%d%d?%d?)(%..+)$")
            if not head or groups:gsub("%.%d%d%d", "") ~= "" then return nil end
            whole = whole:gsub("%.", "")
        elseif not whole:match("^%d+$") then return nil end
        local value = tonumber(whole .. (decimal and "." .. decimal or ""))
        return IsNonnegative(value) and value or nil
    end
    local function range(text)
        if not text then return nil end
        local lo, hi = text:match("^(.-) bis (.-)$")
        if not lo then lo, hi = text:match("^(.-) *%- *(.-)$") end
        if not lo then local value = number(text); return value, value end
        lo, hi = number(lo), number(hi)
        if lo and hi and lo <= hi then return lo, hi end
    end
    local function duration(text, unit)
        local value = units[unit] and number(text)
        return value and value > 0 and value or nil
    end
    local rangeAmount = "([%d%., bis%-]+)"
    function ReadGerman(text, model, wantsExpected)
        local result = { status = "unsupported" }
        text = text:gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü"):lower()
            :gsub("\194\160", " "):gsub("\226\128\175", " "):gsub("–", "-"):gsub("—", "-")
            :gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
            :gsub("körperlichen schaden", "körperlichenschaden")
        local value, school, low, high, total, span, unit, interval, intervalUnit
        local heal = text:match("^heilt ein verbündetes ziel um " .. rangeAmount .. " gesundheit%.$")
            or text:match("^heilt ein befreundetes ziel um " .. rangeAmount .. " gesundheit%.$")
            or text:match("^stellt beim ziel " .. rangeAmount .. " gesundheit wieder her%.$")
        if heal then
            low, high = range(heal)
            if low then result.healing = Components(low, high) end
        else
            value, school = text:match("^verursacht " .. rangeAmount .. " ([^ ]+)schaden%.$")
            if not value then value, school = text:match("^fügt dem ziel " .. rangeAmount .. " ([^ ]+)schaden zu%.$") end
            low, high = range(value)
            if low and schools[school] then result.damage = Components(low, high, nil, nil, schools[school]) end
        end
        value = text:match("^absorbiert " .. amount .. " schaden%.$")
            or text:match("^absorbiert " .. amount .. " schaden%. hält " .. "[%d,]+ sek%. lang an%.$")
        if value then result.absorb = number(value) end
        span, unit, total = text:match("^heilt das ziel im verlauf von " .. seconds .. " um insgesamt " .. amount .. " gesundheit%.$")
        if total then
            total, span = number(total), duration(span, unit)
            if total and span then result.healing = Components(nil, nil, total, span) end
        end
        span, unit, total, school = text:match("^verursacht im verlauf von " .. seconds .. " insgesamt " .. amount .. " ([^ ]+)schaden%.$")
        if total then
            total, span = number(total), duration(span, unit)
            if total and span and schools[school] then result.damage = Components(nil, nil, total, span, schools[school]) end
        end
        value, span, unit, total = text:match("^heilt ein verbündetes ziel um " .. rangeAmount
            .. " gesundheit und im verlauf von " .. seconds .. " um weitere " .. amount .. " gesundheit%.$")
        if value then
            low, high = range(value)
            total, span = number(total), duration(span, unit)
            if low and total and span then result.healing = Components(low, high, total, span) end
        end
        value, school, span, unit, total = text:match("^verursacht " .. rangeAmount
            .. " ([^ ]+)schaden und im verlauf von " .. seconds .. " zusätzlich " .. amount .. " %2schaden%.$")
        if value then
            low, high = range(value)
            total, span = number(total), duration(span, unit)
            if low and total and span and schools[school] then result.damage = Components(low, high, total, span, schools[school]) end
        end
        interval, intervalUnit, value, school, span, unit = text:match("^verursacht alle " .. seconds .. " " .. amount
            .. " ([^ ]+)schaden%. hält " .. seconds .. " lang an%.$")
        if value then
            interval, span, value = duration(interval, intervalUnit), duration(span, unit), number(value)
            if value and interval and span and span % interval == 0 and schools[school] then
                result.damage = Components(nil, nil, value * span / interval, span, schools[school])
            end
        end
        local parts = result.healing or result.damage
        if parts and (not IsNonnegative(parts.direct) or not IsNonnegative(parts.periodic)) then return { status = "unsupported" } end
        if parts then
            local effect = model and model.periodic
            local mixed = effect and ({ burn = true, holyFire = true, fireball = true, regrowth = true })[effect.grammar]
            local whole = effect and ({ corruption = true, pain = true, rejuvenation = true, renew = true, serpentSting = true, mindFlay = true })[effect.grammar]
            if effect and ((mixed and parts.low ~= nil) or (whole and parts.low == nil) or (effect.grammar == "missiles" and interval))
                and parts.duration == effect.duration and parts.periodic > 0
                and (not model.school or model.school == parts.school)
                and ((model.expected == "healing") == (result.healing ~= nil))
                and (effect.grammar ~= "missiles" or interval == effect.interval) then
                result.effect, result.expectedAmount = effect, wantsExpected and parts.direct
            elseif wantsExpected and model and not effect and parts.duration == nil
                and ((model.expected == "healing" and result.healing) or (model.expected == "spell" and result.damage and parts.school == model.school)) then
                result.expectedAmount = parts.direct
            end
        end
        if parts or result.absorb then result.status = "parsed" end
        return result
    end
end

local function RemoveMatched(text, first, last)
    return first and (text:sub(1, first - 1) .. " " .. text:sub(last + 1)) or text
end

local function ReadUnmodeled(text)
    local amount, interval, duration, unit
    local first, last, absorbText = text:find("absorbs? " .. INTEGER .. " damage%f[^%a]")
    if not first then first, last, absorbText = text:find("absorbing " .. INTEGER .. " damage%f[^%a]") end
    local absorb = ReadInteger(absorbText)
    text = RemoveMatched(text, first, last)

    local damage, heal
    local isPeriodic = text:find("damage every ", 1, true) ~= nil or text:find("health every ", 1, true) ~= nil
    amount, duration, interval = ReadMissiles(text)
    if amount and interval and duration and duration % interval == 0 then
        isPeriodic = true
        local total = amount * (duration / interval)
        if IsNonnegative(total) then damage = Components(nil, nil, total, duration, "arcane") end
    end

    -- Handle full-effect heals before damage: Renew describes its healing as
    -- "heals the target of ... damage over ...".
    local direct
    first, last, direct, amount, duration, unit =
        text:find("heals a friendly target for " .. AMOUNT .. " and another " .. INTEGER .. " over " .. DURATION)
    if not first then
        first, last, amount, duration, unit = text:find("heals the target of " .. INTEGER .. " damage over " .. DURATION)
    end
    if not first then
        first, last, amount, duration, unit = text:find("%f[%d,%.]" .. INTEGER .. " health over " .. DURATION)
    end
    if not first then
        first, last, amount, duration, unit = text:find("heals the target for " .. INTEGER .. " over " .. DURATION)
    end
    if first then
        isPeriodic = true
        local low, high
        if direct then low, high = ReadRange(direct) end
        local total, seconds = ReadInteger(amount), ReadDuration(duration, unit)
        if low or (total and seconds) then
            heal = Components(low, high, seconds and total, total and seconds)
        end
        text = RemoveMatched(text, first, last)
    end

    local durationAmount, school
    first, last, amount, school, durationAmount, unit =
        text:find("%f[%d,%.]" .. INTEGER .. " (%a[%a ]-)damage over " .. DURATION)
    if not first then
        first, last, amount, durationAmount, unit = text:find("%f[%d,%.]" .. INTEGER .. " damage over " .. DURATION)
    end
    if first then
        isPeriodic = true
        school = school and school:match("^(%a+) $")
        local total, seconds = ReadInteger(amount), ReadDuration(durationAmount, unit)
        if total and seconds then damage = Components(nil, nil, total, seconds, SCHOOL[school] and school) end
        text = RemoveMatched(text, first, last)
    end

    -- An explicit per-tick amount without a verified interval and duration
    -- cannot be treated as a hit or a full effect.
    text = text:gsub("%f[%d,%.]" .. INTEGER .. " [%a ]-damage every ", "")
        :gsub("%f[%d,%.]" .. INTEGER .. " health every ", "")
        :gsub(MISSILES_PREFIX .. "each second for " .. DURATION .. "%.", "")
        :gsub(MISSILES_PREFIX .. "every " .. DURATION .. " for " .. DURATION .. "%.", "")

    local lo, hi = ReadHealRange(text)
    if not lo then
        amount = text:match("for " .. AMOUNT .. " health%f[^%a]")
            or text:match("restores " .. AMOUNT .. " health%f[^%a]")
            or text:match("%f[%d,%.]" .. AMOUNT .. " health%f[^%a]")
        if amount then lo, hi = ReadRange(amount) end
    end
    if lo then heal = Components(lo, hi, heal and heal.periodic, heal and heal.duration) end

    amount, school = text:match("for " .. AMOUNT .. " (%a+) damage%f[^%a]")
    if not amount then amount, school = text:match("causing " .. AMOUNT .. " (%a+) damage%f[^%a]") end
    if not amount then amount, school = text:match("causes? " .. AMOUNT .. " (%a+) damage%f[^%a]") end
    if not amount then amount, school = text:match("inflicts? " .. AMOUNT .. " (%a+) damage%f[^%a]") end
    if not amount then amount, school = text:match("deals? " .. AMOUNT .. " (%a+) damage%f[^%a]") end
    if amount and SCHOOL[school] then
        lo, hi = ReadRange(amount)
        if lo then damage = Components(lo, hi, damage and damage.periodic, damage and damage.duration, school) end
    end
    return damage, heal, absorb, isPeriodic
end

local function ReadExpectedDirect(kind, text, model, damage, healing)
    local component, low, high
    if kind == "healing" then
        component = healing
        low, high = ReadHealRange(text)
    elseif kind == "spell" and damage and damage.school == model.school then
        component = damage
        low, high = ReadDamageRange(text, model.school)
    end
    if component and low and low == component.low and high == component.high then
        return component.direct
    end
end

-- Parse one public description into direct and periodic components. Verified
-- grammar supplies shared amounts, and generic text never borrows a schedule.
function Estimates.ParseComponents(text, model, wantsExpected)
    local result = { status = "unsupported" }
    if not Estimates.SupportsSpellTextLocale() then return result end
    if IsSecret(text) or type(text) ~= "string" or text == "" then return result end
    if locale == "deDE" then return ReadGerman(text, model, wantsExpected) end
    text = text:lower():gsub("–", "-"):gsub("—", "-"):gsub("%s+", " ")
    local kind = model and model.expected
    if model and model.periodic then
        local parts = ReadModeledPeriodic(text, model)
        if parts then
            if kind == "healing" then result.healing = parts else result.damage = parts end
            result.effect, result.expectedAmount, result.status = model.periodic, wantsExpected and parts.direct, "parsed"
            return result
        end
    end

    local damage, heal, absorb, hasPeriodic = ReadUnmodeled(text)
    result.damage, result.healing, result.absorb = damage, heal, absorb
    if wantsExpected and kind and not model.periodic and not hasPeriodic then
        if kind == "landed" then
            result.attackPowerBase = ReadBloodthirst(text, model)
        else
            result.expectedAmount = ReadExpectedDirect(kind, text, model, damage, heal)
        end
    end
    if damage or heal or absorb or result.expectedAmount or result.attackPowerBase then result.status = "parsed" end
    return result
end

function Estimates.ResolveExpectedAmount(parsed, model)
    if parsed.attackPowerBase then
        local power = ReadAttackPower()
        if power then return parsed.attackPowerBase + model.attackPower * power end
    else
        return parsed.expectedAmount
    end
end

local LEVEL_MISS = { [-3] = 1, [-2] = 2, [-1] = 3, [0] = 4, [1] = 5, [2] = 6, [3] = 17 }
local RESISTANCE_CLASS = { fire = "Fire", frost = "Frost", nature = "Nature", shadow = "Shadow", arcane = "Arcane" }

local function CheckUnitFlag(getter, required, ...)
    if not getter then return false end
    local ok, flag = pcall(getter, ...)
    return ok and not IsSecret(flag) and flag == required
end

local function ReadTargetLevels()
    if not CheckUnitFlag(UnitExists, true, "target")
        or not CheckUnitFlag(UnitCanAttack, true, "player", "target")
        or not CheckUnitFlag(UnitIsPlayer, false, "target")
        or not CheckUnitFlag(UnitPlayerControlled, false, "target")
        or not CheckUnitFlag(UnitIsDeadOrGhost, false, "target") then return nil end
    local getter = UnitEffectiveLevel
    if getter == nil then getter = UnitLevel end
    local player = ReadStat(getter, "player")
    local target = ReadStat(getter, "target")
    if not player or player < 1 or player > 255 or player ~= math.floor(player)
        or not target or target < 1 or target > 255 or target ~= math.floor(target) then return nil end
    return player, target
end

local function ReadDamageTarget(kind, model)
    local playerLevel, targetLevel = ReadTargetLevels()
    if not targetLevel then return nil end
    if kind == "landed" then
        local getReduction = C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectiveness
        if not UnitArmor or not getReduction then return nil end
        local ok, _, armor = pcall(UnitArmor, "target")
        if not ok or not IsNonnegative(armor) or armor == 0 then return nil end
        local reduction = ReadStat(getReduction, armor, playerLevel)
        if not IsNonnegative(reduction) or reduction > 1 then return nil end
        return { level = targetLevel, armorReduction = reduction }
    end

    local miss = LEVEL_MISS[targetLevel - playerLevel]
    if not miss then return nil end
    local target = { level = targetLevel, baseHit = 100 - miss }
    local class = RESISTANCE_CLASS[model.school]
    local classes = Enum and Enum.Damageclass
    local index = class and classes and classes[class]
    if not UnitResistance or not IsNonnegative(index) then return target end
    local ok, _, _, resistance = pcall(UnitResistance, "target", index)
    if not ok or not IsNonnegative(resistance) or resistance == 0 then return target end
    target.resistClass = class
    target.resistance = resistance
    target.resistMean = resistance / (resistance + 8 * playerLevel + 19)
    return target
end

-- PvE spell hit uses live eligible target levels when available. Healing is
-- assumed to land. Melee uses sheet crit on landed hits, without avoidance.
function Estimates.GetExpectedRate(kind, amount, cycle, effect, tickTotal, model)
    if not IsNonnegative(amount) or not IsNonnegative(cycle) or cycle == 0 then return nil end
    if effect then
        if not IsNonnegative(tickTotal) or tickTotal == 0 then return nil end
    elseif amount == 0 then
        return nil
    end
    local directCrit = not effect or effect.directCrit
    local tickCrit = effect and effect.tickCrit
    local needsCrit = (directCrit and amount > 0) or tickCrit
    local crit, hit, bonus, hitBonus
    if kind == "landed" then
        hit, bonus = 100, 1
    elseif kind == "healing" then
        if effect and effect.hitMode ~= "none" then return nil end
        hit, bonus = 100, 0.5
    elseif kind == "spell" then
        if effect and effect.hitMode ~= "application" and effect.hitMode ~= "tick" then return nil end
        if not IsNonnegative(CR_HIT_SPELL) then return nil end
        local rating = ReadStat(GetCombatRatingBonus, CR_HIT_SPELL)
        local modifier = ReadStat(GetSpellHitModifier)
        if not rating or not modifier or not IsFinite(rating + modifier) then return nil end
        hitBonus = rating + modifier
        bonus = 0.5
    else
        return nil
    end
    if needsCrit then
        if kind == "landed" then
            crit = ReadStat(GetCritChance)
        else
            crit = ReadStat(GetSpellCritChance)
        end
        if not IsNonnegative(crit) or crit > 100 then return nil end
    end
    local target = model and kind ~= "healing" and ReadDamageTarget(kind, model)
    if hitBonus then
        local baseHit = target and target.baseHit or 96
        if effect and effect.binaryApplication and target and target.resistMean then
            baseHit = baseHit * (1 - target.resistMean)
        end
        hit = math.min(100, math.max(0, baseHit + hitBonus))
    end
    local directChance, directBonus, damageTaken, labels = crit, bonus, 1, nil
    if model then
        directChance, directBonus, damageTaken, labels = Modifiers.Get(model, crit, bonus,
            directCrit and amount > 0 and hit > 0, kind == "spell" and hit > 0 and target)
    end
    local directFactor = 1 + directBonus * (directChance or 0) / 100
    local tickFactor = 1 + bonus * (crit or 0) / 100
    local direct = amount * (directCrit and directFactor or 1)
    local ticks = (tickTotal or 0) * (tickCrit and tickFactor or 1)
    if target then
        if target.armorReduction then
            direct = direct * (1 - target.armorReduction)
        elseif target.resistMean then
            local tickReduction = effect and effect.channel and target.resistMean or target.resistMean / 10
            direct = direct * (1 - target.resistMean)
            ticks = ticks * (1 - tickReduction)
        end
    end
    -- An aura's application hit gates all damage. Independent missile hit
    -- rolls have the same aggregate expectation and no additional parent roll.
    local rate = ((direct + ticks) / cycle) * (hit / 100) * damageTaken
    if IsNonnegative(rate) then
        local modifiers = labels and {
            labels = labels,
            tickCrit = tickCrit and directChance ~= crit and crit or nil,
            targetAura = damageTaken > 1,
        }
        return rate, hit, directChance, target, modifiers
    end
    return nil
end
