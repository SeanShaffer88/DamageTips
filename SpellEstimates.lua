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

local function IsFinite(value)
    return not IsSecret(value) and type(value) == "number" and value > -math.huge and value < math.huge
end

local function IsNonnegative(value)
    return IsFinite(value) and value >= 0
end

function Estimates.GetSpellModel(spellID)
    if not IsNonnegative(spellID) or spellID == 0 then return nil end
    local model = MODELS[spellID]
    if not model or not GetBuildInfo then return nil end
    local ok, version, build, _, interface = pcall(GetBuildInfo)
    if not ok or IsSecret(version) or IsSecret(build) or IsSecret(interface) then return nil end
    if version == "1.60.1" and (build == "70888" or build == 70888) and interface == 16001 then
        return model
    end
    return nil
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

-- Equal-level PvE spell hit approximation. Healing is assumed to land.
-- Melee uses sheet crit on landed hits, with no avoidance model.
function Estimates.GetExpectedRate(kind, amount, cycle)
    if not IsNonnegative(amount) or amount == 0 or not IsNonnegative(cycle) or cycle == 0 then return nil end
    local crit, hit, bonus
    if kind == "landed" then
        crit, hit, bonus = ReadStat(GetCritChance), 100, 1
    elseif kind == "healing" then
        crit, hit, bonus = ReadStat(GetSpellCritChance), 100, 0.5
    elseif kind == "spell" then
        if not IsNonnegative(CR_HIT_SPELL) then return nil end
        local rating = ReadStat(GetCombatRatingBonus, CR_HIT_SPELL)
        local modifier = ReadStat(GetSpellHitModifier)
        if not rating or not modifier or not IsFinite(rating + modifier) then return nil end
        hit = math.min(100, math.max(0, 96 + rating + modifier))
        crit, bonus = ReadStat(GetSpellCritChance), 0.5
    else
        return nil
    end
    if not IsNonnegative(crit) or crit > 100 then return nil end
    local rate = (amount / cycle) * (hit / 100) * (1 + bonus * crit / 100)
    if IsNonnegative(rate) then return rate, hit, crit end
    return nil
end
