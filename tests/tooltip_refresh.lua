-- Isolated 70938 tooltip processor fixture. The client owns all tooltip info
-- tables, clears on a native primary rebuild, and shows after the post-call.
local path = assert(arg[1], "provide addon directory")
local output = print
local events, scripts, timers, lines, errors = {}, {}, {}, {}, {}
local owner, activeID, activeType = {}, 1001, "spell"
local primary, processing
local post, posts, setterHooks, addCount, showCount, sourceReads = nil, 0, 0, 0, 0, 0
local now, isShown, forbidden = 100, true, false
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
function GetBuildInfo() return "1.60.1", "70938", "Nov 2026", 16001 end
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
}
C_SpellBook = {
    GetSpellBookItemInfo = function(slot, bank)
        assert(slot == 1)
        sourceReads = sourceReads + 1
        return { spellID = bank == 1 and 1002 or 1001 }
    end,
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
local function has(text)
    for _, line in ipairs(lines) do
        if line:find(text, 1, true) then return true end
    end
    return false
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
output("DamageTips tooltip refresh regressions passed (" .. checks .. " assertions).")
