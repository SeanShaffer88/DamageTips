-- DamageTips exact-build expected-output modifiers (GPL-3.0-or-later).
local _, addon = ...
local Modifiers = {}
addon.SpellModifiers = Modifiers

local IsSecret = issecretvalue or function() return false end
local TALENTS = {
    callOfThunder = { maxRank = 1, { 104760, 129420 }, { 104712, 129372 } },
    regrowth = { maxRank = 5, { 104913, 129573 } },
    ruin = { maxRank = 5, { 105883, 130613 } },
}
local CURSE_RANKS = { { 1311680, 10 }, { 1311677, 8 }, { 1311676, 6 }, { 440892, 4 } }

local function IsFinite(value)
    return not IsSecret(value) and type(value) == "number" and value > -math.huge and value < math.huge
end

local function IsPositiveInteger(value)
    return IsFinite(value) and value > 0 and value == math.floor(value)
end

local function AddIDs(ids, set)
    if IsSecret(ids) or type(ids) ~= "table" then return false end
    local count = 0
    for index, id in pairs(ids) do
        if not IsPositiveInteger(index) or index > #ids or not IsPositiveInteger(id) then return false end
        set[id] = true
        count = count + 1
    end
    return count == #ids
end

local function ReadStagedNodes(configID)
    local ok, purchases, refunds, swaps = pcall(C_Traits.GetStagedChanges, configID)
    if not ok or IsSecret(purchases) or IsSecret(refunds) or IsSecret(swaps) then return nil end
    local staged = {}
    if purchases == nil and refunds == nil and swaps == nil then return staged end
    if AddIDs(purchases, staged) and AddIDs(refunds, staged) and AddIDs(swaps, staged) then return staged end
    return nil
end

local function ReadCommittedRank(configID, nodeID, entryID, maxRank)
    local ok, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
    if not ok or IsSecret(node) or type(node) ~= "table" then return nil end
    local id, rank, current = node.ID, node.activeRank, node.currentRank
    if not IsPositiveInteger(id) or id ~= nodeID or not IsPositiveInteger(rank) or rank > maxRank
        or not IsPositiveInteger(current) or current ~= rank then return nil end
    local ids, committed = node.entryIDsWithCommittedRanks, {}
    if not AddIDs(ids, committed) or not committed[entryID] then return nil end
    local entry = node.activeEntry
    if IsSecret(entry) then return nil end
    if entry == nil then
        -- Some single-entry nodes have no explicit selection record.
        if #ids == 1 then return rank end
        return nil
    end
    if type(entry) ~= "table" or not IsPositiveInteger(entry.entryID) or entry.entryID ~= entryID
        or not IsPositiveInteger(entry.rank) or entry.rank ~= rank then return nil end
    return rank
end

local function ReadTalentRank(talent)
    local getConfig = C_ClassTalents and C_ClassTalents.GetActiveConfigID
    if not getConfig or not (C_Traits and C_Traits.GetStagedChanges and C_Traits.GetNodeInfo) then return nil end
    local ok, configID = pcall(getConfig)
    if not ok or not IsPositiveInteger(configID) then return nil end
    local staged = ReadStagedNodes(configID)
    if not staged then return nil end
    for _, candidate in ipairs(talent) do
        if staged[candidate[1]] then return nil end
    end
    for _, candidate in ipairs(talent) do
        local rank = ReadCommittedRank(configID, candidate[1], candidate[2], talent.maxRank)
        if rank then return rank end
    end
    return nil
end

local function ReadAura(spellID, typeField, getter, ...)
    if not getter then return nil end
    local ok, aura = pcall(getter, ...)
    if not ok or IsSecret(aura) or type(aura) ~= "table" then return nil end
    local id, flag, expires = aura.spellId, aura[typeField], aura.expirationTime
    if not IsPositiveInteger(id) or id ~= spellID or IsSecret(flag) or flag ~= true or not IsFinite(expires) then return nil end
    if spellID == 28682 and expires == 0 then
        -- Combustion's crit aura lasts until its charges are spent.
        local duration = aura.duration
        if IsFinite(duration) and duration == 0 then return aura end
        return nil
    end
    if not GetTime then return nil end
    local clockOK, now = pcall(GetTime)
    if not clockOK or not IsFinite(now) or now < 0 or expires <= now then return nil end
    return aura
end

local function ReadCombustionStacks()
    local getter = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    local aura = ReadAura(28682, "isHelpful", getter, 28682)
    if not aura then return nil end
    local stacks = aura.applications
    if IsPositiveInteger(stacks) and stacks <= 10 then return stacks end
    return nil
end

local function ReadCurseBonus()
    local getter = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    if not getter then return nil end
    for _, rank in ipairs(CURSE_RANKS) do
        if ReadAura(rank[1], "isHarmful", getter, "target", rank[1]) then return rank[2] end
    end
    return nil
end

function Modifiers.Get(model, crit, bonus, hasDirectCrit, eligibleTarget)
    local chance, critBonus, damageTaken = crit, bonus, 1
    local labels
    local modifier = model.critModifier
    if hasDirectCrit and crit then
        local talent = TALENTS[modifier]
        local rank = talent and ReadTalentRank(talent)
        if modifier == "ruin" and rank and crit > 0 then
            critBonus = bonus * (1 + 0.2 * rank)
            labels = { "Ruin" }
        elseif crit < 100 then
            if modifier == "callOfThunder" and rank then
                chance = math.min(100, crit + 5)
                labels = { "Call of Thunder" }
            elseif modifier == "regrowth" and rank then
                chance = math.min(100, crit + 10 * rank)
                labels = { "Improved Regrowth" }
            elseif modifier == "combustion" then
                local stacks = ReadCombustionStacks()
                if stacks then
                    chance = math.min(100, crit + 10 * stacks)
                    labels = { "Combustion x" .. stacks }
                end
            end
        end
    end
    if eligibleTarget then
        local taken = ReadCurseBonus()
        if taken then
            damageTaken = 1 + taken / 100
            labels = labels or {}
            labels[#labels + 1] = "Curse of the Elements +" .. taken .. "%"
        end
    end
    return chance, critBonus, damageTaken, labels
end
