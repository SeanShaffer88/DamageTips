-- Build gate and tooltip integration for Wild Growth. Game inputs are mocks.
local root = assert(arg[1], "provide addon directory")
local spell, build, version, interface = 408120, "70938", "1.60.1", 16001
local text, crit = "", 20
local restricted, events, lines = {}, {}, {}
local checks = 0
local powerReads, hitReads = 0, 0

function GetLocale() return "enUS" end
function GetBuildInfo() return version, build, "", interface end
function issecretvalue(value) return rawequal(value, restricted) end
function GetActionInfo() return "spell", spell end
function GetSpellBaseCooldown() return 6000, 1500 end
function GetSpellCritChance() return crit end
function GetSpellBonusHealing() powerReads = powerReads + 1; return 500 end
function GetSpellHitModifier() hitReads = hitReads + 1; return 10 end
function IsShiftKeyDown() return true end
tinsert = table.insert
SlashCmdList = {}
DamageTipsDB = {
    showMinimap = false, showMana = false, showPowerScaling = true,
    showExpectedThroughput = true, shiftDetails = true,
}
C_Spell = {
    GetSpellDescription = function() return text end,
    GetSpellInfo = function() return { castTime = 3000 } end,
}
C_SpellBook = {
    GetSpellBookItemInfo = function() return { spellID = spell } end,
    IsSpellKnown = function(_, bank) return bank == 0 end,
}
function CreateFrame()
    return {
        RegisterEvent = function(self, event) events[event] = self end,
        UnregisterEvent = function(_, event) events[event] = nil end,
        SetScript = function(self, _, callback) self.onEvent = callback end,
    }
end
GameTooltip = {}
function GameTooltip:HookScript(event, callback)
    if event == "OnTooltipCleared" then self.onClear = callback end
end
function GameTooltip:SetAction() lines = {}; self.onClear() end
GameTooltip.SetSpellBookItem = GameTooltip.SetAction
function GameTooltip:AddLine(line) lines[#lines + 1] = line end
function GameTooltip:NumLines() return #lines end
function GameTooltip:GetOwner() return self end
function GameTooltip:Show() end
function hooksecurefunc(object, method, callback)
    local original = object[method]
    object[method] = function(self, ...)
        original(self, ...)
        callback(self, ...)
    end
end

local function has(wanted)
    for _, line in ipairs(lines) do
        if line:find(wanted, 1, true) then return true end
    end
    return false
end

local function expect(condition, message)
    assert(condition, message .. "\n" .. table.concat(lines, " | "))
    checks = checks + 1
end

local addon = {}
for _, module in ipairs({ "SpellPowerModels", "SpellModifiers", "SpellEstimates", "DamageTips" }) do
    assert(loadfile(root .. "/" .. module .. ".lua"))("DamageTips", addon)
end
local loader = assert(events.ADDON_LOADED)
loader.onEvent(loader, "ADDON_LOADED", "DamageTips")
local estimates = addon.SpellEstimates
local ranks = { 408120, 1238214, 1238215 }
for _, id in ipairs(ranks) do
    local model = estimates.GetSpellModel(id)
    expect(model and model.expected == "healing" and model.periodic.ticks == 7
        and model.periodic.interval == 1 and model.periodic.duration == 7
        and model.periodic.coefficient == 0.066 and model.periodic.tickCrit
        and not model.periodic.directCrit and model.periodic.hitMode == "none"
        and model.periodic.perRecipient, "70938 supports this exact Wild Growth rank")
end
expect(not estimates.GetSpellModel(409810), "the spell that teaches Wild Growth has no model")
local _, _, _, _, count = estimates.GetModelBuildStatus()
expect(count == 233, "70938 includes Wild Growth and the 21 additional direct heal ranks")
for _, unsupported in ipairs({ "70888", "70939" }) do
    build = unsupported
    for _, id in ipairs(ranks) do
        expect(not estimates.GetSpellModel(id), "Wild Growth model is strictly 70938-only")
    end
end
build, interface = "70938", 16002
expect(not estimates.GetSpellModel(spell), "wrong Interface does not qualify")
version, interface = "1.60.2", 16001
expect(not estimates.GetSpellModel(spell), "wrong client version does not qualify")
version = "1.60.1"

local suffix = " Party members must be within 15 yds of target. The amount healed is applied quickly at first, and slows down as Wild Growth reaches its full duration."
local function hover(amount, duration)
    text = "Heals the target and their party for " .. amount .. " over " .. duration .. " sec." .. suffix
    GameTooltip:SetAction(1)
end
hover("280", 7)
expect(has("Expected HPS (per recipient, full effect): 44.0 (20.0% crit)"),
    "uses the full tooltip total once and crit, without spell hit or a party multiplier")
expect(powerReads == 0 and hitReads == 0, "expected healing does not read power or hit")
expect(has("+100 healing power: +46.2 total healing per recipient (nominal)")
    and not has("/ tick"), "reports a nominal full-effect gain without equal tick claims")
expect(has("HPS: 40.0   HPM: 2400 (per recipient)")
    and has("Healing over time per recipient: 280 over 7 sec"), "baseline and Shift breakdown are per recipient")

crit = 0
GameTooltip:SetSpellBookItem(1, 0)
expect(has("Expected HPS (per recipient, full effect): 40.0 (0.0% crit)"),
    "the spellbook uses the same model and fresh crit")
crit = restricted
GameTooltip:SetSpellBookItem(1, 0)
expect(not has("Expected HPS") and has("+100 healing power"),
    "unreadable crit suppresses expected output without hiding nominal scaling")
crit = 20
DamageTipsDB.includeDoT = false
hover("280", 7)
expect(not has("Expected HPS") and not has("+100") and not has("HPS:"),
    "disabling periodic effects hides healing, scaling and expected output")
DamageTipsDB.includeDoT = true
hover("280", 8)
expect(not has("Expected HPS") and not has("+100"), "changed spell duration suppresses modeled lines")
hover("2,80", 7)
expect(not has("Expected HPS") and not has("+100"), "malformed amounts fail closed")
text = restricted
GameTooltip:SetAction(1)
expect(not has("Expected HPS") and not has("+100"), "restricted descriptions fail closed")

print("DamageTips Wild Growth mocks passed (" .. checks .. " assertions).")
