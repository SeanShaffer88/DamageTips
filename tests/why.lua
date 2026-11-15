-- Exercise the slash command and the report's UI boundary.
local root = assert(arg[1], "provide addon directory")
local checks, reads, requests, popupCalls, tooltipCalls = 0, 0, 0, 0, 0
local events, messages = {}, {}
local build, locale, inCombat, known = "70938", "enUS", false, true
local petKnown = false
local restricted = {}
local description = "Blasts the enemy for 90 to 110 Fire damage."
local castTime, crit = 2000, 0
local realPrint = print

function print(message) messages[#messages + 1] = message end
function GetLocale() return locale end
function GetBuildInfo() return "1.60.1", build, "", 16001 end
function issecretvalue(value) return rawequal(value, restricted) end
function wipe(tbl) for key in pairs(tbl) do tbl[key] = nil end end
function InCombatLockdown() return inCombat end
function GetSpellBaseCooldown() return 0, 1500 end
function GetSpellCritChance() return crit end
function GetSpellHitModifier() return 0 end
function GetCombatRatingBonus() return 0 end
function SendChatMessage() error("only local chat output is allowed") end
function hooksecurefunc() end
tinsert = table.insert
CR_HIT_SPELL = 8
SlashCmdList = {}
StaticPopupDialogs = {}
DamageTipsDB = { showMinimap = false, showExpectedThroughput = true }
C_Spell = {
    GetSpellInfo = function() return { castTime = castTime } end,
    GetSpellDescription = function() reads = reads + 1; return description end,
    RequestLoadSpellData = function() requests = requests + 1 end,
}
C_SpellBook = { IsSpellKnown = function(_, bank)
    if bank == 0 then return known end
    return petKnown
end }

function CreateFrame()
    return {
        RegisterEvent = function(self, name) events[name] = self end,
        UnregisterEvent = function(_, name) events[name] = nil end,
        SetScript = function(self, _, callback) self.onEvent = callback end,
    }
end

GameTooltip = setmetatable({ HookScript = function() end }, {
    __index = function() return function() tooltipCalls = tooltipCalls + 1 end end,
})

local edit = {
    SetText = function(self, text) self.text = text end,
    SetFocus = function(self) self.focused = true end,
    HighlightText = function(self) self.selected = true end,
}
local showPopup, dialogHidden
function StaticPopup_Show(key)
    popupCalls = popupCalls + 1
    local template = assert(StaticPopupDialogs[key])
    assert(template.hasEditBox and template.hideOnEscape and template.button1
        and template.maxLetters == 0 and template.EditBoxOnEscapePressed)
    edit.escape = template.EditBoxOnEscapePressed
    if showPopup then return { GetEditBox = function() return edit end } end
end

local function loadAddon()
    local private = {}
    for _, file in ipairs({ "SpellPowerModels", "SpellModifiers", "SpellEstimates", "DamageTips" }) do
        assert(loadfile(root .. "/" .. file .. ".lua"))("DamageTips", private)
    end
    local loader = assert(events.ADDON_LOADED)
    loader.onEvent(loader, "ADDON_LOADED", "DamageTips")
end

local function expect(condition, message)
    checks = checks + 1
    assert(condition, message .. "\n" .. table.concat(messages, " | "))
end

local function run(command, wanted)
    messages = {}
    SlashCmdList.DAMAGETIPS(command)
    local output = table.concat(messages, "\n")
    expect(output:find(wanted, 1, true), command .. " should report " .. wanted)
    return output
end

loadAddon()
inCombat = true
for _, value in ipairs({ "", "-2136", "+2136", "2.136e3", "0x858", "0", "4294967296", "2136 another" }) do
    run("why " .. value, "/dtips why <spellID>")
end
expect(reads == 0 and popupCalls == 0, "invalid command avoids reads and popups")

DamageTipsDB.showExpectedThroughput = false
run("why 2136", "Expected DPS and HPS is off")
DamageTipsDB.showExpectedThroughput = true
DamageTipsDB.spellRules["2136"] = "hide"
run("why 2136", "This rank is hidden")
DamageTipsDB.spellRules["2136"] = 25
run("why 2136", "pinned damage")
DamageTipsDB.spellRules["2136"] = nil
DamageTipsDB.showSpellbook, DamageTipsDB.showActionBar = false, false
run("why 2136", "Action bar and spellbook tooltips are off")
DamageTipsDB.showSpellbook, DamageTipsDB.showActionBar = true, true
build = restricted
run("why 2136", "Build unavailable")
build = "70939"
run("why 2136", "client build is unverified")
build = "70938"
run("why 999999", "no verified model")
run("why 116", "scaling only")
known = false
run("why 2136", "could not confirm this rank")
known = true

description = restricted
run("why 2136", "description is restricted")
description = nil
run("why 2136", "description is unavailable")
description = "PRIVATE SENTINEL"
local output = run("why 2136", "description does not match")
expect(not output:find(description, 1, true), "raw spell text never appears in a report")
description = "Blasts the enemy for 90 to 110 Fire damage."
castTime = restricted
run("why 2136", "Spell timing is unavailable")
castTime, crit = 2000, restricted
run("why 2136", "Required combat stats are unavailable")
crit = 0
run("why 2136", "Expected DPS is available")
DamageTipsDB.showSpellbook, petKnown = false, true
run("why 2136", "The action bar could not confirm an unambiguous player rank")
petKnown = restricted
run("why 2136", "The action bar could not confirm an unambiguous player rank")
petKnown = false
run("why 2136", "Expected DPS is available")
DamageTipsDB.showSpellbook, petKnown = true, true
run("why 2136", "Expected DPS is available")
petKnown = false
DamageTipsDB.includeDoT = false
description = "Heals the target and their party for 280 over 7 sec."
run("why 408120", "Periodic effects are off for this periodic-only rank")
DamageTipsDB.includeDoT = true
run("why 408120", "Expected HPS is available")
DamageTipsDB.includeDoT = false
description = "Burns the enemy for 100 Arcane damage and then an additional 80 Arcane damage over 9 sec."
run("why 8921", "Expected DPS is available")
DamageTipsDB.includeDoT = true
description = "Blasts the enemy for 90 to 110 Fire damage."
expect(popupCalls == 0, "combat uses chat without opening a popup")

inCombat, showPopup = false, true
messages = {}
SlashCmdList.DAMAGETIPS("why 002136")
expect(popupCalls == 1 and edit.focused and edit.selected, "stock edit box focuses and selects the report")
expect(edit.text:find("DamageTips | Build 70938 | Spell ID 2136", 1, true)
    and edit.text:find("Expected DPS is available", 1, true), "report identifies the exact build, rank and result")
expect(not edit.text:find("|c", 1, true) and #messages == 0, "popup text is plain and avoids duplicate chat")
edit.GetParent = function() return { Hide = function() dialogHidden = true end } end
edit.escape(edit)
expect(dialogHidden, "Escape closes the popup with focus in the edit box")
showPopup = false
run("why 2136", "Expected DPS is available")
inCombat = restricted
local before = popupCalls
run("why 2136", "Expected DPS is available")
expect(popupCalls == before, "unreadable combat state only reports in chat")
expect(requests == 0 and tooltipCalls == 0 and DamageTipsDB.showExpectedThroughput,
    "diagnostic does not request data, change settings or touch GameTooltip")

locale = "deDE"
loadAddon()
run("why 2136", "English spell descriptions")
realPrint("DamageTips estimate explanation mocks passed (" .. checks .. " assertions).")
