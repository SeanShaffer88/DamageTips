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
    local model = MODELS[spellID]
    if not model then return nil end
    local modelBuild = ReadModelBuild()
    if IsModelVerified(modelBuild, spellID) then
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

local function ParseAmount(text, prefix, suffix)
    local low, high = text:match(prefix .. "(%d+)%s+to%s+(%d+)" .. suffix)
    if not low then low, high = text:match(prefix .. "(%d+)%s*%-%s*(%d+)" .. suffix) end
    if low then
        low, high = tonumber(low), tonumber(high)
        if low <= high then return low + (high - low) / 2 end
        return nil
    end
    return tonumber(text:match(prefix .. "(%d+)" .. suffix))
end

function Estimates.GetExpectedAmount(model, text)
    local kind = model.expected
    if not kind then return nil end
    text = text:lower():gsub("(%d),(%d)", "%1%2"):gsub("–", "-"):gsub("—", "-")
    if text:find("damage%s+every%s+%d") or text:find("health%s+every%s+%d") then return nil end
    if kind == "spell" then
        local suffix = "%s+" .. model.school .. "%s+damage"
        return ParseAmount(text, "for%s+", suffix .. "%.")
            or ParseAmount(text, "causing%s+", suffix .. "%.")
            or ParseAmount(text, "causes%s+", suffix .. "%s+to the target%.")
    elseif kind == "healing" then
        return ParseAmount(text, "heals a friendly target for%s+", "%.")
            or ParseAmount(text, "heals a friendly target for%s+", "%s+health%.")
            or ParseAmount(text, "heal your target for%s+", "%.")
            or ParseAmount(text, "heal your target for%s+", "%s+health%.")
            or ParseAmount(text, "heals a single target for%s+", "%.")
            or ParseAmount(text, "heals a single target for%s+", "%s+health%.")
    end

    -- Bloodthirst's live text expresses a formula, not a ready-scaled amount.
    local percent, flat = text:match("damage equal to (%d+)%% of your attack power plus (%d+) and increasing")
    if not percent then
        percent, flat = text:match("damage equal to (%d+)%% of your attack power plus (%d+)%.")
    end
    if tonumber(percent) ~= model.attackPower * 100 then return nil end
    local power = ReadAttackPower()
    if power then return tonumber(flat) + model.attackPower * power end
    return nil
end

local PERIODIC_AMOUNT = "([%d,]+)"
local DIRECT_AMOUNT = "([%d][%d, to%-]*)"
local DURATION = "(%d+) (sec%a*)"
local SECONDS = { sec = true, secs = true, second = true, seconds = true }
local TOTAL_GRAMMARS = {
    corruption = "corrupts the target, causing " .. PERIODIC_AMOUNT .. " shadow damage over ",
    pain = "a word of darkness that causes " .. PERIODIC_AMOUNT .. " shadow damage over ",
    rejuvenation = "heals the target for " .. PERIODIC_AMOUNT .. " over ",
    renew = "heals the target of " .. PERIODIC_AMOUNT .. " damage over ",
    serpentSting = "stings the target, causing " .. PERIODIC_AMOUNT .. " nature damage over ",
    mindFlay = "assault the target's mind with shadow energy, causing " .. PERIODIC_AMOUNT .. " shadow damage over ",
}
local MIXED_GRAMMARS = {
    regrowth = "heals a friendly target for " .. DIRECT_AMOUNT .. " and another " .. PERIODIC_AMOUNT .. " over ",
    burn = "burns the enemy for " .. DIRECT_AMOUNT .. " %s damage and then an additional "
        .. PERIODIC_AMOUNT .. " %s damage over ",
    holyFire = "consumes the enemy in holy flames that cause " .. DIRECT_AMOUNT .. " holy damage and an additional "
        .. PERIODIC_AMOUNT .. " holy damage over ",
    fireball = "hurls a fiery ball that causes " .. DIRECT_AMOUNT .. " fire damage and an additional "
        .. PERIODIC_AMOUNT .. " fire damage over ",
}

local function ReadTooltipInteger(value)
    if not value then return nil end
    if value:match("^%d+$") then return tonumber(value) end
    local leading, grouped = value:match("^(%d%d?%d?)(,%d.*)$")
    if leading and grouped:gsub(",%d%d%d", "") == "" then
        return tonumber((value:gsub(",", "")))
    end
    return nil
end

local function ReadTooltipAverage(value)
    local low, high = value:match("^([%d,]+) to ([%d,]+)$")
    if not low then low, high = value:match("^([%d,]+)%s*%-%s*([%d,]+)$") end
    if not low then return ReadTooltipInteger(value) end
    low, high = ReadTooltipInteger(low), ReadTooltipInteger(high)
    if IsNonnegative(low) and IsNonnegative(high) and low <= high then
        return low + (high - low) / 2
    end
    return nil
end

-- Tooltip amounts in the aura descriptions are full-effect totals. Missiles
-- are the exception: the tooltip references the triggered spell's per-hit amount.
function Estimates.GetPeriodicAmounts(model, text)
    local effect = model.periodic
    local grammar = effect.grammar
    local direct, amount, duration, unit
    text = text:lower():gsub("–", "-"):gsub("—", "-"):gsub("%s+", " ")
    if grammar == "missiles" then
        local prefix = "launches arcane missiles at the enemy, causing " .. PERIODIC_AMOUNT .. " arcane damage "
        amount, duration, unit = text:match(prefix .. "each second for " .. DURATION .. "%.")
        if not amount then
            local interval, intervalUnit
            amount, interval, intervalUnit, duration, unit =
                text:match(prefix .. "every " .. DURATION .. " for " .. DURATION .. "%.")
            if not SECONDS[intervalUnit] or tonumber(interval) ~= effect.interval then return nil end
        end
    elseif MIXED_GRAMMARS[grammar] then
        local pattern = MIXED_GRAMMARS[grammar]
        if grammar == "burn" then
            -- Insert the school using literal replacements so the captures
            -- in the Lua pattern keep their meaning.
            pattern = pattern:gsub(" %%s ", " " .. model.school .. " ")
        end
        direct, amount, duration, unit = text:match(pattern .. DURATION .. "%.")
        if not direct then return nil end
    elseif grammar == "mindFlay" then
        amount, duration, unit = text:match(TOTAL_GRAMMARS[grammar] .. DURATION .. " and slowing their movement speed by %d+%%%.")
    else
        amount, duration, unit = text:match(TOTAL_GRAMMARS[grammar] .. DURATION .. "%.")
    end
    if not SECONDS[unit] or tonumber(duration) ~= effect.duration then return nil end
    local total = ReadTooltipInteger(amount)
    if not IsNonnegative(total) or total == 0 then return nil end
    if grammar == "missiles" then total = total * effect.ticks end
    local directTotal = 0
    if direct then
        directTotal = ReadTooltipAverage(direct)
        if not IsNonnegative(directTotal) or directTotal == 0 then return nil end
    end
    if not IsNonnegative(total) then return nil end
    return directTotal, total
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
