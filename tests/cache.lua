-- Exercise the public tooltip boundary with counted reads and parses.
local root = assert(arg[1], "provide addon directory")
local spell, text, cost, maximum = 2136, nil, 100, 1000
local hoverText = "Blasts the enemy for 90 to 110 Fire damage."
local build, ap, target = "70938", 500, false
local public, restricted = hoverText, {}
local reads, parses, checks = 0, 0, 0
local owner, events, lines = {}, {}, {}

function GetTime() return 100 end
function GetLocale() return "enUS" end
function GetBuildInfo() return "1.60.1", build, "", 16001 end
function issecretvalue(value) return rawequal(value, restricted) end
function wipe(tbl) for key in pairs(tbl) do tbl[key] = nil end end
tinsert = table.insert
function GetActionInfo() return "spell", spell end
function GetSpellBaseCooldown() return 0, 1500 end
function UnitPowerMax() return maximum end
function UnitAttackPower() return ap, 0, 0 end
function GetCritChance() return 0 end
function GetSpellCritChance() return 0 end
function GetSpellHitModifier() return 0 end
function GetCombatRatingBonus() return 0 end
function UnitExists() return target end
function UnitCanAttack() return target end
function UnitIsPlayer() return false end
function UnitPlayerControlled() return false end
function UnitIsDeadOrGhost() return false end
function UnitEffectiveLevel(unit) return unit == "player" and 60 or 63 end
CR_HIT_SPELL = 8
SlashCmdList = {}
DamageTipsDB = { showMinimap = false, showExpectedThroughput = true, shiftDetails = false }
C_Spell = {
    GetSpellDescription = function()
        reads = reads + 1
        if text == "throw" then error("test description failure") end
        return text
    end,
    GetSpellInfo = function() return { castTime = 2000 } end,
    GetSpellPowerCost = function() return { { type = 0, cost = cost } } end,
}
C_SpellBook = {
    GetSpellBookItemInfo = function() return { spellID = spell } end,
    IsSpellKnown = function(_, bank) return bank == 0 end,
}
function CreateFrame()
    return {
        RegisterEvent = function(self, name) events[name] = self end,
        UnregisterEvent = function(_, name) events[name] = nil end,
        SetScript = function(self, _, callback) self.onEvent = callback end,
    }
end
GameTooltip = {}
function GameTooltip:HookScript(event, callback)
    if event == "OnTooltipCleared" then self.onClear = callback end
end
function GameTooltip:SetAction() lines = {}; self.onClear() end
GameTooltip.SetSpellBookItem = GameTooltip.SetAction
function GameTooltip:GetOwner() return owner end
function GameTooltip:AddLine(line) lines[#lines + 1] = line end
function GameTooltip:NumLines() return #lines end
function GameTooltip:Show() end
function hooksecurefunc(object, method, callback)
    local original = object[method]
    object[method] = function(self, ...)
        original(self, ...)
        callback(self, ...)
    end
end

local function fire(event, ...)
    local frame = assert(events[event], event)
    frame.onEvent(frame, event, ...)
end

local function has(wanted)
    for _, line in ipairs(lines) do if line:find(wanted, 1, true) then return true end end
    return false
end

local function expect(condition, message)
    assert(condition, message .. "\n" .. table.concat(lines, " | "))
    checks = checks + 1
end

local private = {}
for _, file in ipairs({ "SpellPowerModels", "SpellModifiers", "SpellEstimates" }) do
    assert(loadfile(root .. "/" .. file .. ".lua"))("DamageTips", private)
end
local parse = private.SpellEstimates.ParseComponents
private.SpellEstimates.ParseComponents = function(...)
    parses = parses + 1
    return parse(...)
end
assert(loadfile(root .. "/DamageTips.lua"))("DamageTips", private)
fire("ADDON_LOADED", "DamageTips")

text = public
for _ = 1, 100 do GameTooltip:SetAction(1) end
expect(reads == 100 and parses == 1 and has("48.0 (96.0% hit"), "100 public description reads yield one parse")
target, cost, maximum = true, 200, 2000
GameTooltip:SetAction(1)
expect(parses == 1 and has("target L63") and has("41.5 (83.0% hit")
    and has("10.0% of max mana"), "target and mana remain live across parse hits")
maximum = 1000
GameTooltip:SetAction(1)
expect(parses == 1 and has("20.0% of max mana"), "mana value updates on the next hover")
GameTooltip:SetSpellBookItem(1, 0)
GameTooltip:SetSpellBookItem(1, "pet")
expect(parses == 3, "action, player book and pet book use separate cache entries")
GameTooltip:SetAction(1)
expect(parses == 3, "returning to action source reuses its own entry")

fire("SPELL_TEXT_UPDATE", spell)
GameTooltip:SetAction(1)
expect(parses == 4, "SPELL_TEXT_UPDATE invalidates the relevant parsed data")
fire("SPELLS_CHANGED")
GameTooltip:SetAction(1)
expect(parses == 5, "SPELLS_CHANGED invalidates parse memo")
build = "70939"
GameTooltip:SetAction(1)
expect(parses == 6 and not has("Expected DPS"), "model change invalidates cache despite identical description")
build = "70938"
GameTooltip:SetAction(1)
expect(parses == 7 and has("Expected DPS"), "verified model resumes after a build change")
text = "Blasts the enemy for 50 Fire damage."
GameTooltip:SetAction(1)
expect(parses == 8 and has("DPS: 25.0"), "changed public body does not reuse old parse")
text = restricted
GameTooltip:SetAction(1)
expect(parses == 8 and not has("DPS"), "restricted description neither parses nor replays prior output")
text = "throw"
GameTooltip:SetAction(1)
expect(parses == 8 and not has("DPS"), "failed description does not replay prior output")
text = "Blasts the enemy for 50 Fire damage."
GameTooltip:SetAction(1)
expect(parses == 9 and has("DPS: 25.0"), "a readable description is parsed after restriction")

spell, text, target = 23881, "Deals damage equal to 45% of your Attack Power plus 30.", false
GameTooltip:SetAction(1)
expect(parses == 10 and has("DPS on landed hits: 127.5"), "Bloodthirst resolves initially from live AP")
ap = 700
GameTooltip:SetAction(1)
expect(parses == 10 and has("DPS on landed hits: 172.5"), "AP can change without reparsing formula")
ap = restricted
GameTooltip:SetAction(1)
expect(parses == 10 and not has("DPS on landed hits"), "restricted AP is not replayed")
text = public
fire("SPELLS_CHANGED")
for id = 1, 65 do
    spell = 800000 + id
    GameTooltip:SetAction(1)
end
local before = parses
spell = 800065
GameTooltip:SetAction(1)
expect(parses == before, "most recent slot remains present")
spell = 800001
GameTooltip:SetAction(1)
expect(parses == before + 1, "ring evicts the oldest entry at the capacity bound")
text = public .. string.rep(" ", 8193)
GameTooltip:SetAction(1)
GameTooltip:SetAction(1)
expect(parses == before + 3, "oversize description bypasses memoization")
print("DamageTips public parse cache mocks passed (" .. checks .. " assertions).")
