-- Inert regression cases for the 70938 spellbook and spell-data event contracts.
local path = assert(arg[1], "provide addon directory")
local now, currentID = 100, 1001
local records, petRecords, skills, descriptions, slots, events, timers = {}, {}, {}, {}, {}, {}, {}
local tooltipLines, owner, requestCounts = {}, {}, {}
local mode, assertions, errors = "async", 0, {}
local secret = setmetatable({}, { __index = function() error("secret record inspected") end })
local output = print

function print(line)
    if line:find("error (shown once)", 1, true) then errors[#errors + 1] = line end
end
function issecretvalue(value) return rawequal(value, secret) end
function GetTime() return now end
function GetLocale() return "enUS" end
function GetBuildInfo() return "1.60.1", "70938", "Nov 2026", 16001 end
function GetActionInfo() return "spell", currentID end
function GetSpellBaseCooldown() return 0, 1500 end
function UnitPowerMax() return 1000 end
function wipe(tbl) for key in pairs(tbl) do tbl[key] = nil end end
tinsert = table.insert
SlashCmdList = {}
DamageTipsDB = { showMinimap = false, showMana = false, showNextRank = true, shiftDetails = false }
Enum = { SpellBookItemType = { Spell = 1, FutureSpell = 2, Flyout = 4 } }

local function fire(name, ...)
    local frame = assert(events[name], "unexpected event: " .. name)
    frame.onEvent(frame, name, ...)
end

C_Timer = {
    After = function(delay, callback) timers[#timers + 1] = { at = now + delay, run = callback } end,
}
local function advance(seconds)
    now = now + seconds
    local previous = timers
    timers = {}
    for _, timer in ipairs(previous) do
        if timer.at <= now then timer.run()
        else timers[#timers + 1] = timer end
    end
end

C_Spell = {
    GetSpellInfo = function() return { castTime = 2000 } end,
    GetSpellDescription = function(id) return descriptions[id] end,
    GetSpellPowerCost = function() return { { type = 0, cost = 100 } } end,
    RequestLoadSpellData = function(id)
        requestCounts[id] = (requestCounts[id] or 0) + 1
        if mode == "throw" then error("request rejected") end
        if mode == "false" then return false end
        if mode == "sync" then
            descriptions[id] = "Deals 200 Fire damage."
            fire("SPELL_DATA_LOAD_RESULT", id, true)
        end
    end,
}
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return #skills end,
    GetSpellBookSkillLineInfo = function(line) return skills[line] end,
    GetSpellBookItemInfo = function(slot, bank)
        if bank == 1 then return petRecords[slot] end
        assert(bank == 0)
        slots[#slots + 1] = slot
        return records[slot]
    end,
}
C_TooltipInfo = {
    GetSpellByID = function(id)
        if descriptions[id] then
            return { lines = { { leftText = "Tooltip name" }, { leftText = descriptions[id] } } }
        end
        return { lines = { { leftText = "Tooltip name" } } }
    end,
}
function CreateFrame()
    return {
        RegisterEvent = function(self, name) events[name] = self end,
        UnregisterEvent = function(_, name) events[name] = nil end,
        SetScript = function(self, _, callback) self.onEvent = callback end,
    }
end
GameTooltip = {}
function GameTooltip:IsShown() return true end
function GameTooltip:GetOwner() return owner end
function GameTooltip:HookScript(event, callback)
    if event == "OnTooltipCleared" then self.onClear = callback end
end
function GameTooltip:SetAction() tooltipLines = {}; self.onClear() end
GameTooltip.SetSpellBookItem = GameTooltip.SetAction
function GameTooltip:AddLine(line) tooltipLines[#tooltipLines + 1] = line end
function GameTooltip:NumLines() return #tooltipLines end
function GameTooltip:Show() end
function hooksecurefunc(object, method, callback)
    local previous = object[method]
    object[method] = function(self, ...)
        previous(self, ...)
        callback(self, ...)
    end
end

local function expect(value, label)
    assert(value, label .. "\nTooltip: " .. table.concat(tooltipLines, " | "))
    assertions = assertions + 1
end

local function count(wanted)
    local matches = 0
    for _, line in ipairs(tooltipLines) do
        if line:find(wanted, 1, true) then matches = matches + 1 end
    end
    return matches
end

local function hover(id)
    currentID = id
    GameTooltip:SetAction(1)
end

local function row(name, rank, id, kind)
    return { itemType = kind or 1, spellID = id, name = name, subName = rank }
end

local ns = {}
for _, module in ipairs({ "SpellPowerModels", "SpellModifiers", "SpellEstimates", "DamageTips" }) do
    assert(loadfile(path .. "/" .. module .. ".lua"))("DamageTips", ns)
end
fire("ADDON_LOADED", "DamageTips")

skills = { { itemIndexOffset = 100, numSpellBookItems = 6 }, { itemIndexOffset = 300, numSpellBookItems = 1 } }
records[101] = row("Test Fire", "Rank 1", 1001)
records[102] = row("Test Fire", "Rank 2", 1002)
records[103] = row("Test Fire", "Rank 2", 1002) -- duplicate ID does not create ambiguity
records[104] = row("Test Fire", "Rank 2", 2000, 4) -- flyout cannot enter the map
records[105] = row("Test Fire", "Rank 2", 2001, 2) -- future ranks are not known player spells
records[106] = secret
records[301] = row("Test Fire", "Rank 2", 2002) -- different skill line
descriptions[1001] = "Blasts the target for 200 Fire damage."
descriptions[1002] = "Blasts the target for 180 Fire damage."
descriptions[2001] = descriptions[1001]
descriptions[2002] = descriptions[1001]
descriptions[3000] = descriptions[1001]
hover(1001)
expect(table.concat(slots, ",") == "101,102,103,104,105,106,301", "enumerate only reported spellbook ranges")
expect(count("Next rank: DPS 90.0 (-10%)") == 1, "show signed comparison for immediate same-line rank")
hover(3000)
expect(count("Next rank") == 0, "an unknown source ID cannot select an unrelated rank")
records[102].subName, records[103].subName = secret, ""
fire("SPELL_TEXT_UPDATE", 1002)
hover(1001)
expect(count("Next rank") == 0, "rank groups with unreadable or incomplete text are skipped")
records[102].subName, records[103].subName = "Rank 2", "Rank 2"
fire("SPELL_TEXT_UPDATE", 1002)
hover(1001)
expect(count("Next rank: DPS 90.0") == 1, "spell text availability invalidates the earlier rank entry")
records[103] = row("Test Fire", "Rank 2", 3000)
fire("SPELLS_CHANGED")
hover(1001)
expect(count("Next rank") == 0, "two unequal IDs claiming the immediate next rank are ambiguous")
records[103] = row("Test Fire", "Rank 3", 1002)
fire("SPELLS_CHANGED")
hover(1001)
expect(count("Next rank") == 0, "one ID claiming different ranks invalidates the group for other ranks")
hover(1002)
expect(count("Next rank") == 0, "the ambiguous ID cannot compare against itself")
records[103].isOffSpec = true
fire("SPELLS_CHANGED")
hover(1001)
expect(count("Next rank: DPS 90.0") == 1, "off-spec spells do not interfere with active rank lookup")
records[103].isOffSpec, records[103].isPassive = false, true
fire("SPELLS_CHANGED")
hover(1001)
expect(count("Next rank: DPS 90.0") == 1, "passive spells do not interfere with active rank lookup")

DamageTipsDB.showNextRank = false
mode = "throw"
hover(4001)
expect(requestCounts[4001] == 1 and not events.SPELL_DATA_LOAD_RESULT, "a thrown API call finalizes registration")
hover(4001)
expect(requestCounts[4001] == 1, "a failed request does not retry immediately")
mode = "false"
advance(1)
hover(4001)
expect(requestCounts[4001] == 2 and not events.SPELL_DATA_LOAD_RESULT, "explicit false finalizes a retry")
mode = "async"
advance(2)
hover(4001)
expect(requestCounts[4001] == 3 and events.SPELL_DATA_LOAD_RESULT, "third attempt is pending")
advance(5)
expect(not events.SPELL_DATA_LOAD_RESULT, "missing completion times out and unregisters the event")
advance(30)
hover(4001)
expect(requestCounts[4001] == 3, "failed retries have a bounded budget")

hover(4002)
fire("SPELL_DATA_LOAD_RESULT", 4002, false)
expect(not events.SPELL_DATA_LOAD_RESULT and count("DPS") == 0, "failed payload does not append")
hover(4003)
hover(4004)
descriptions[4003] = descriptions[1001]
fire("SPELL_DATA_LOAD_RESULT", 4003, true)
advance(0)
expect(count("DPS") == 0 and events.SPELL_DATA_LOAD_RESULT, "wrong tooltip generation and concurrent request are preserved")
descriptions[4004] = descriptions[1001]
fire("SPELL_DATA_LOAD_RESULT", 4004, true)
fire("SPELL_TEXT_UPDATE", 4004)
advance(0)
expect(count("DPS: 100.0") == 1 and not events.SPELL_DATA_LOAD_RESULT, "coalesced completion and text events append once")

mode = "sync"
hover(4005)
expect(not events.SPELL_DATA_LOAD_RESULT and count("DPS") == 0, "synchronous event resolves without reentrant decoration")
advance(0)
expect(count("DPS: 100.0") == 1, "deferred eligible decoration after synchronous completion")

mode = "async"
hover(4006)
descriptions[4006] = descriptions[1001]
fire("SPELL_DATA_LOAD_RESULT", 4006, true)
currentID = 4007 -- action slot changed without a new tooltip setter call
advance(0)
expect(count("DPS") == 0, "reassigned action slot invalidates deferred decoration")
hover(4008)
descriptions[4008] = descriptions[1001]
fire("SPELL_DATA_LOAD_RESULT", 4008, true)
owner = {}
advance(0)
expect(count("DPS") == 0, "changed tooltip owner invalidates deferred decoration")

petRecords[45] = row("Pet Fire", "Rank 1", 4010)
GameTooltip:SetSpellBookItem(45, "pet")
expect(requestCounts[4010] == 1, "pet tooltip resolves its own spell bank")
descriptions[4010] = descriptions[1001]
fire("SPELL_DATA_LOAD_RESULT", 4010, true)
petRecords[45].spellID = 4011
advance(0)
expect(count("DPS") == 0, "a changed spellbook bank slot invalidates deferred decoration")

local savedTimer = C_Timer
C_Timer = nil
hover(4012)
expect(not requestCounts[4012] and not events.SPELL_DATA_LOAD_RESULT, "no timer API leaves no unbounded request")
C_Timer = savedTimer

DamageTipsDB.showMana = true
hover(4009)
expect(count("Mana cost") == 1 and count("DPS") == 0, "pending tooltip may already have a mana line")
descriptions[4009] = descriptions[1001]
fire("SPELL_DATA_LOAD_RESULT", 4009, true)
advance(0)
expect(count("Mana cost") == 1 and count("DPS") == 0, "decorated tooltip avoids duplicate async appends")
hover(4009)
expect(count("Mana cost") == 1 and count("DPS: 100.0") == 1, "native refresh sees valid data without duplicates")
expect(#errors == 0, errors[1] or "no guarded tooltip errors")
output("DamageTips rank/load regressions passed (" .. assertions .. " assertions).")
