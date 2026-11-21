-- Isolated 70938 tooltip processor fixture. The client owns all tooltip info
-- tables, clears on a native primary rebuild, and shows after the post-call.
local path = assert(arg[1], "provide addon directory")
local output = print
local events, scripts, timers, lines, errors = {}, {}, {}, {}, {}
local owner, activeID, activeType = {}, 1001, "spell"
local primary, processing
local post, posts, setterHooks, addCount, showCount, sourceReads = nil, 0, 0, 0, 0, 0
local now, isShown, forbidden = 100, true, false
local maximumMana = 1000
local shiftDown, target, combat = false, false, false
local bookSpellID = 1001
local build = "70938"
local descriptions = {
    [1001] = "Blasts the enemy for 100 Fire damage.",
    [1002] = "Heals a friendly target for 200 health.",
}
local secret = setmetatable({}, { __index = function() error("secret inspected") end })
local checks = 0

function issecretvalue(value) return rawequal(value, secret) end
function print(message) errors[#errors + 1] = message end
function GetTime() return now end
function GetLocale() return "enUS" end
function GetBuildInfo() return "1.60.1", build, "Nov 2026", 16001 end
function IsShiftKeyDown() return shiftDown end
function InCombatLockdown() return combat end
function UnitPowerMax() return maximumMana end
function UnitExists() return target end
function UnitCanAttack() return target end
function UnitIsPlayer() return false end
function UnitPlayerControlled() return false end
function UnitIsDeadOrGhost() return false end
function UnitEffectiveLevel(unit) return unit == "player" and 60 or 63 end
function GetSpellCritChance() return 0 end
function GetCombatRatingBonus() return 0 end
function GetSpellHitModifier() return 0 end
CR_HIT_SPELL = 8
function GetActionInfo(slot)
    assert(slot == 1)
    sourceReads = sourceReads + 1
    return activeType, activeID
end
function GetMacroSpell(id) return id == activeID and 1001 or nil end
function GetSpellBaseCooldown() return 0, 1500 end
function wipe(self) for key in pairs(self) do self[key] = nil end end
tinsert = table.insert
SlashCmdList = {}
local function fire(name, ...)
    local callback = assert(events[name], "event not registered: " .. name)
    callback.run(callback, name, ...)
end
local function nextFrame()
    local previous = timers
    timers = {}
    for _, timer in ipairs(previous) do
        if timer.at <= now then timer.callback()
        else timers[#timers + 1] = timer end
    end
end
C_Timer = { After = function(delay, callback) timers[#timers + 1] = { at = now + delay, callback = callback } end }
C_Spell = {
    GetSpellInfo = function() return { castTime = 2000 } end,
    GetSpellDescription = function(id) return descriptions[id] end,
    RequestLoadSpellData = function() end,
    GetSpellPowerCost = function() return { { type = 0, cost = 100 } } end,
}
C_SpellBook = {
    GetSpellBookItemInfo = function(slot, bank)
        assert(slot == 1)
        sourceReads = sourceReads + 1
        return { spellID = bank == 1 and 1002 or bookSpellID }
    end,
    IsSpellKnown = function(_, bank) return bank == 0 end,
}
function CreateFrame()
    return {
        RegisterEvent = function(self, name) events[name] = self end,
        UnregisterEvent = function(_, name) events[name] = nil end,
        SetScript = function(self, _, callback) self.run = callback end,
    }
end
function hooksecurefunc() setterHooks = setterHooks + 1 end
TooltipDataProcessor = {
    AllTypes = "ALL",
    AddTooltipPostCall = function(kind, callback)
        assert(kind == "ALL")
        post, posts = callback, posts + 1
    end,
}
DamageTipsDB = { showMinimap = false, showMana = false, shiftDetails = false }
GameTooltip = { SetAction = function() end, SetSpellBookItem = function() end }
function GameTooltip:HookScript(name, callback) scripts[name] = callback end
function GameTooltip:IsShown() return isShown end
function GameTooltip:IsForbidden() return forbidden end
function GameTooltip:GetOwner() return owner end
function GameTooltip:GetPrimaryTooltipInfo() return primary end
function GameTooltip:GetProcessingTooltipInfo() return processing end
function GameTooltip:AddLine(line)
    lines[#lines + 1] = line
    addCount = addCount + 1
end
function GameTooltip:NumLines() return #lines end
function GameTooltip:Show() showCount = showCount + 1 end

local function expect(value, label)
    assert(value, label .. "\nTooltip: " .. table.concat(lines, " | "))
    checks = checks + 1
end
local function count(text)
    local matches = 0
    for _, line in ipairs(lines) do
        if line:find(text, 1, true) then matches = matches + 1 end
    end
    return matches
end
local function has(text)
    return count(text) > 0
end
local function clear()
    lines = {}
    scripts.OnTooltipCleared(GameTooltip)
end
local function info(getter, args, data, append)
    local fields = { getterName = getter, getterArgs = args, tooltipData = data, append = append }
    return setmetatable({}, { __index = fields, __newindex = function() error("client info mutated") end })
end
local function native(getter, args, data)
    clear()
    primary = info(getter, args, data)
    processing = primary
    post(GameTooltip, data)
    GameTooltip:Show() -- client, not the addon
end
local bookRebuilds = 0
local bookData = { type = 1, dataInstanceID = 30 }
SpellBookItemMixin = {
    ShowSpellBookTooltip = function(self)
        assert(not combat, "addon forced a spellbook refresh in combat")
        assert(owner == self.Button, "addon replaced tooltip owner")
        bookRebuilds = bookRebuilds + 1
        native("GetSpellBookItem", { self.slotIndex, self.spellBank }, bookData)
        -- Blizzard adds these after SetSpellBookItem in the stock spellbook.
        GameTooltip:AddLine("Native spellbook action-bar status")
        GameTooltip:AddLine("Native assisted-combat text")
        GameTooltip:Show()
    end,
}
local stockBookItem = { Button = {}, slotIndex = 1, spellBank = 0,
    ShowSpellBookTooltip = SpellBookItemMixin.ShowSpellBookTooltip }
function stockBookItem.Button:GetParent() return stockBookItem end
function GameTooltip:RefreshDataNextUpdate()
    error("addon changed the native tooltip update schedule")
end
ActionBarActionButtonMixin = {
    SetTooltip = function() native("GetAction", { 1 }, bookData) end,
}
local stockAction = { action = 1, UpdateTooltip = ActionBarActionButtonMixin.SetTooltip }
local ns = {}
for _, module in ipairs({ "SpellPowerModels", "SpellModifiers", "SpellEstimates", "DamageTips" }) do
    assert(loadfile(path .. "/" .. module .. ".lua"))("DamageTips", ns)
end
fire("ADDON_LOADED", "DamageTips")
expect(posts == 1 and setterHooks == 0, "native postprocessor alone owns spell rendering")

local data = { type = 1, dataInstanceID = 20 }
native("GetAction", { 1 }, data)
expect(has("DPS: 50.0") and #lines == 1 and showCount == 1, "native render appends once and does not call Show")
post(GameTooltip, data)
expect(#lines == 1 and showCount == 1, "duplicate invocation is ignored within the same clear generation")
native("GetAction", { 1 }, { type = 1, dataInstanceID = 20 })
expect(has("DPS: 50.0") and #lines == 1 and showCount == 2, "native rebuild with same instance ID restores lines")

clear()
primary = info("GetSpellByID", { 1001 }, data)
processing = info("GetAction", { 1 }, data, true)
local reads = sourceReads
post(GameTooltip, data)
expect(#lines == 0 and reads == sourceReads, "appended action data cannot hijack another tooltip")
processing = primary
post(GameTooltip, data)
expect(#lines == 0 and reads == sourceReads, "direct spell links are outside the supported sources")
post({}, data)
post(secret, data)
expect(#lines == 0 and reads == sourceReads, "foreign and secret tooltips are skipped without resolving a source")

clear()
primary = info("GetAction", nil, data)
processing = primary
local reads = sourceReads
post(GameTooltip, data)
expect(#lines == 0 and sourceReads == reads, "missing getter arguments are ignored")
clear()
primary = info("GetAction", {}, data)
processing = primary
post(GameTooltip, data)
expect(#lines == 0 and sourceReads == reads, "missing action slot is ignored")
clear()
primary = info("GetAction", { 1 }, data)
processing = primary
post(GameTooltip, { type = 1, dataInstanceID = 21 })
expect(#lines == 0 and sourceReads == reads, "post-call data must match the primary tooltip data")

processing, primary = secret, secret
post(GameTooltip, data)
expect(#lines == 0, "secret info objects are skipped unopened")
primary = info(secret, { 1 }, data)
processing = primary
post(GameTooltip, data)
expect(#lines == 0, "secret getter is skipped")
primary = info("GetAction", secret, data)
processing = primary
post(GameTooltip, data)
expect(#lines == 0, "secret getter argument container is skipped")
primary = info("GetAction", { secret }, data)
processing = primary
post(GameTooltip, data)
expect(#lines == 0, "secret slot is never resolved")

forbidden = true
native("GetAction", { 1 }, data)
expect(#lines == 0, "forbidden main tooltip is skipped")
forbidden = false
activeType = "item"
native("GetAction", { 1 }, data)
expect(#lines == 0, "item action is skipped even under a native action getter")
activeType = "macro"
native("GetAction", { 1 }, { type = 25 })
expect(has("DPS: 50.0"), "macro routing does not depend on a Spell type result")
activeType = "spell"
native("GetSpellBookItem", { 1, 1 }, data)
expect(has("HPS: 100.0") and not has("DPS:"), "native spellbook route preserves the pet bank")
SlashCmdList.DAMAGETIPS("import DT1;showSpellbook=0;showActionBar=0")
native("GetSpellBookItem", { 1, 0 }, data)
expect(#lines == 0, "disabled spellbook source is skipped")
native("GetAction", { 1 }, data)
expect(#lines == 0, "disabled action source is skipped")
SlashCmdList.DAMAGETIPS("import DT1;showActionBar=1")

activeID = 1010
native("GetAction", { 1 }, data)
local shownBefore = showCount
descriptions[1010] = "Blasts the enemy for 200 Fire damage."
fire("SPELL_DATA_LOAD_RESULT", 1010, true)
nextFrame()
expect(has("DPS: 100.0") and #lines == 1 and showCount == shownBefore + 1,
    "deferred spell load appends to the matching displayed tooltip and resizes after the native render")
local addedBefore = addCount
fire("SPELL_TEXT_UPDATE", 1010)
nextFrame()
expect(addCount == addedBefore, "repeated text update cannot duplicate existing lines")
activeID = 1011
native("GetAction", { 1 }, data)
descriptions[1011] = "Blasts the enemy for 200 Fire damage."
fire("SPELL_DATA_LOAD_RESULT", 1011, true)
scripts.OnHide(GameTooltip)
nextFrame()
expect(#lines == 0, "hide invalidates deferred context even if visibility changes again")
expect(#errors == 2 and errors[1]:find("settings imported", 1, true) and errors[2]:find("settings imported", 1, true),
    "no forbidden data, mutation, or guarded hook errors")

DamageTipsDB.showSpellbook = true
DamageTipsDB.shiftDetails = true
DamageTipsDB.showExpectedThroughput = true
DamageTipsDB.showMana = true
bookSpellID, owner = 2136, stockBookItem.Button
descriptions[2136] = "Blasts the enemy for 90 to 110 Fire damage."
stockBookItem:ShowSpellBookTooltip()
expect(count("DPS: 50.0") == 1 and count("Expected DPS (equal-level PvE): 48.0") == 1
    and count("Hold Shift") == 1, "open book starts with equal-level estimate and Shift hint")
local rebuilds = bookRebuilds
local adds = addCount
fire("MODIFIER_STATE_CHANGED", "LCTRL", 1)
nextFrame()
expect(bookRebuilds == rebuilds and addCount == adds, "unrelated modifiers do not refresh the tooltip")

target, shiftDown = true, true
fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
fire("MODIFIER_STATE_CHANGED", "RSHIFT", 1)
fire("PLAYER_TARGET_CHANGED")
expect(bookRebuilds == rebuilds and addCount == adds, "event burst leaves rendering to the next frame")
nextFrame()
expect(bookRebuilds == rebuilds + 1 and count("Expected DPS (target L63, level only): 41.5") == 1
    and count("Direct damage:") == 1 and count("Hold Shift") == 0 and count("Mana cost") == 1,
    "Shift and target-change events rebuild the still-hovered book entry exactly once")
expect(count("Native spellbook action-bar status") == 1 and count("Native assisted-combat text") == 1,
    "stock spellbook rebuild preserves native lines appended after the post-call")

shiftDown = false
fire("MODIFIER_STATE_CHANGED", "RSHIFT", 0)
nextFrame()
expect(count("Hold Shift") == 1 and count("Direct damage:") == 0,
    "releasing Shift removes the breakdown from the open spellbook tooltip")

rebuilds, adds = bookRebuilds, addCount
fire("SPELL_TEXT_UPDATE", 1001)
nextFrame()
expect(bookRebuilds == rebuilds and addCount == adds, "unrelated spell text cannot refresh the open tooltip")
descriptions[2136] = "Blasts the enemy for 200 Fire damage."
fire("SPELL_TEXT_UPDATE", 2136)
nextFrame()
expect(bookRebuilds == rebuilds + 1 and count("DPS: 100.0") == 1 and count("DPS: 50.0") == 0,
    "matching spell text replaces the old rendered estimate")

bookSpellID = 1012
stockBookItem:ShowSpellBookTooltip()
expect(count("Mana cost") == 1 and count("DPS:") == 0, "a spell with pending description can render a mana line")
rebuilds = bookRebuilds
descriptions[1012] = "Blasts the enemy for 200 Fire damage."
fire("SPELL_DATA_LOAD_RESULT", 1012, true)
fire("SPELL_TEXT_UPDATE", 1012)
nextFrame()
expect(bookRebuilds == rebuilds + 1 and count("DPS: 100.0") == 1 and count("Mana cost") == 1,
    "coalesced data completion replaces a partially decorated tooltip without duplicating mana")

rebuilds, adds = bookRebuilds, addCount
descriptions[1012] = "Blasts the enemy for 300 Fire damage."
fire("SPELL_TEXT_UPDATE", 1012)
bookSpellID = 2136
nextFrame()
expect(bookRebuilds == rebuilds and addCount == adds, "changed slot contents invalidate a queued refresh")
bookSpellID = 1012
fire("SPELL_TEXT_UPDATE", 1012)
owner = {}
nextFrame()
expect(bookRebuilds == rebuilds and addCount == adds, "changed owner invalidates an otherwise matching queued refresh")
owner = stockBookItem.Button
fire("SPELL_TEXT_UPDATE", 1012)
scripts.OnHide(GameTooltip)
nextFrame()
expect(bookRebuilds == rebuilds and addCount == adds, "a hidden generation cannot force a stock-owner refresh")

bookSpellID = 2136
stockBookItem:ShowSpellBookTooltip()
rebuilds, adds = bookRebuilds, addCount
target = false
fire("PLAYER_TARGET_CHANGED")
combat = true -- lockdown begins between scheduling and the timer callback
nextFrame()
shiftDown = true
fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
fire("SPELL_TEXT_UPDATE", 2136)
nextFrame()
expect(bookRebuilds == rebuilds and addCount == adds, "lockdown prevents both queued and new forced rebuilds")
combat = false
fire("PLAYER_REGEN_ENABLED")
nextFrame()
expect(bookRebuilds == rebuilds + 1 and count("Expected DPS (equal-level PvE): 96.0") == 1
    and count("Direct damage:") == 1 and count("Mana cost") == 1,
    "ending lockdown refreshes the same visible tooltip once with current data")

rebuilds, adds = bookRebuilds, addCount
fire("SPELL_TEXT_UPDATE", 2136)
stockBookItem.slotIndex = 2
nextFrame()
expect(bookRebuilds == rebuilds and addCount == adds, "a recycled stock spellbook item cannot be replayed")
stockBookItem.slotIndex = 1
local stockShow = stockBookItem.ShowSpellBookTooltip
stockBookItem.ShowSpellBookTooltip = function() error("addon invoked non-stock callback") end
fire("PLAYER_TARGET_CHANGED")
nextFrame()
expect(bookRebuilds == rebuilds and addCount == adds and #errors == 2,
    "addon never invokes a replaced owner callback")
stockBookItem.ShowSpellBookTooltip = stockShow
build = "70939"
fire("SPELL_TEXT_UPDATE", 2136)
nextFrame()
expect(bookRebuilds == rebuilds and addCount == adds, "a newer build does not use the 70938-only native replay")
build = "70938"

owner, activeID = stockAction, 2136
native("GetAction", { 1 }, data)
adds = addCount
target = true
combat = true
fire("PLAYER_TARGET_CHANGED")
fire("SPELL_TEXT_UPDATE", 2136)
nextFrame()
expect(addCount == adds, "addon does not force an action tooltip refresh during lockdown")
stockAction:UpdateTooltip() -- Blizzard's periodic action-tooltip update
expect(count("Expected DPS (target L63, level only): 83.0") == 1 and count("Mana cost") == 1,
    "Blizzard's native action refresh works in lockdown with one current estimate and mana line")
expect(#errors == 2, "refreshing stock tooltips produced no guarded Lua errors")

combat, owner, bookSpellID = false, stockBookItem.Button, 2136
stockBookItem:ShowSpellBookTooltip()
rebuilds = bookRebuilds
maximumMana = 2000
fire("UNIT_POWER_UPDATE", "player", "MANA")
fire("UNIT_MAXPOWER", "player", "MANA")
fire("UNIT_STATS", "player")
fire("SPELL_POWER_CHANGED")
fire("COMBAT_RATING_UPDATE")
fire("PLAYER_EQUIPMENT_CHANGED", 16, true)
fire("PLAYER_TALENT_UPDATE")
fire("UNIT_AURA", "player", secret)
fire("UNIT_AURA", "target", secret)
expect(bookRebuilds == rebuilds, "input events never rebuild synchronously")
nextFrame()
expect(bookRebuilds == rebuilds + 1 and count("5.0%") == 1,
    "stat, mana, talent and aura bursts refresh current inputs once")
rebuilds = bookRebuilds
fire("UNIT_STATS", "party1")
fire("UNIT_POWER_UPDATE", "player", "RAGE")
fire("UNIT_MAXPOWER", secret, "MANA")
fire("UNIT_AURA", "party1", secret)
nextFrame()
expect(bookRebuilds == rebuilds, "unrelated and secret input scopes are ignored")
combat = true
fire("UNIT_AURA", "player", secret)
nextFrame()
expect(bookRebuilds == rebuilds, "input-driven native setters defer in combat")
combat = false
fire("PLAYER_REGEN_ENABLED")
nextFrame()
expect(bookRebuilds == rebuilds + 1, "input-driven refresh resumes once after combat")
rebuilds = bookRebuilds
fire("UNIT_STATS", "player")
scripts.OnHide(GameTooltip)
nextFrame()
expect(bookRebuilds == rebuilds and #errors == 2, "hidden input refresh is discarded without errors")

output("DamageTips tooltip refresh regressions passed (" .. checks .. " assertions).")
