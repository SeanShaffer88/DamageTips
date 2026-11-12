-- DamageTips spell estimates (GPL-3.0-or-later, see LICENSE.txt).
local _, addon = ...

local Estimates = {}
addon.SpellEstimates = Estimates

local IsSecret = issecretvalue or function() return false end
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local BANK_PLAYER = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
local BANK_PET = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet) or 1
local SCHOOL_INDEX = { holy = 2, fire = 3, nature = 4, frost = 5, shadow = 6, arcane = 7 }

local function IsNonnegative(value)
    return not IsSecret(value) and type(value) == "number" and value >= 0 and value < math.huge
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
    if ok and IsNonnegative(value) then return value end
    return nil
end

function Estimates.GetCasterStats(school, hasHealing)
    local index = SCHOOL_INDEX[school]
    if not index and not hasHealing then return nil end
    local crit = ReadStat(GetSpellCritChance)
    if crit and crit > 100 then crit = nil end
    local power = index and ReadStat(GetSpellBonusDamage, index)
    local healing = hasHealing and ReadStat(GetSpellBonusHealing)
    return crit, power, healing
end
