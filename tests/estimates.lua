-- Focused Lua 5.1 mocks for the DamageTips WoW Forever addon entry points.
local addonPath = assert(arg[1], "provide addon directory")
local realPrint = print
local chat, events, tooltipLines = {}, {}, {}
local owner = {}
local now, mana, regen, crit, power, healing = 100, 175, 10, 12.5, 54, 82
local secret = setmetatable({}, { __index = function() error("secret table inspected") end })
local costs = { { type = 0, cost = 100, minCost = 100, costPerSec = 0, requiredAuraID = 0 } }
local castTime, cooldown, gcd = 2000, 0, 1500
local spellID, playerKnown, petKnown = 123, true, false
local buildVersion, buildNumber, buildInterface = "1.60.1", "70888", 16001
local hitRating, hitModifier, meleeCrit = 1, 1, 20
local apBase, apPositive, apNegative = 500, 20, -10
local damageText = "Blasts the target for 90 to 110 Fire damage."
local healText = "Restores 160 health."
local description, dataOverride = damageText, nil
local knownCalls, regenCalls, costCalls, critCalls, requests = 0, 0, 0, 0, 0
local assertions = 0
local shiftDown = false
local timers = {}
Enum = { TooltipDataLineType = { SpellDescription = 34 } }

C_Timer = {
    After = function(delay, callback)
        timers[#timers + 1] = { due = now + delay, callback = callback }
    end,
}

local function runReadyTimers()
    local queued = timers
    timers = {}
    for _, timer in ipairs(queued) do
        if timer.due <= now then timer.callback() else timers[#timers + 1] = timer end
    end
end

function print(message) chat[#chat + 1] = tostring(message) end
function issecretvalue(value) return rawequal(value, secret) end
function GetTime() return now end
function GetBuildInfo() return buildVersion, buildNumber, "Oct 2026", buildInterface end
function GetLocale() return "enUS" end
function GetActionInfo(slot)
    if slot == 2 then return "macro", 7 end
    if slot == 3 then return "item", 123 end
    return "spell", spellID
end
function GetMacroSpell(id) assert(id == 7); return spellID end
function GetSpellBaseCooldown(id) return cooldown, gcd end
function UnitPowerMax(unit, resource) return 1000 end
function UnitPower(unit, resource)
    assert(unit == "player" and resource == 0)
    return mana
end
function GetPowerRegenForPowerType(resource)
    assert(resource == 0)
    regenCalls = regenCalls + 1
    return 99, regen
end
function GetSpellCritChance(...)
    assert(select("#", ...) == 0)
    critCalls = critCalls + 1
    return crit
end
function GetSpellBonusDamage(school) assert(school == 3); return power end
function GetSpellBonusHealing() return healing end
CR_HIT_SPELL = 8
function GetCombatRatingBonus(index) assert(index == CR_HIT_SPELL); return hitRating end
function GetSpellHitModifier() return hitModifier end
function GetCritChance() return meleeCrit end
function UnitAttackPower(unit) assert(unit == "player"); return apBase, apPositive, apNegative end
function IsShiftKeyDown() return shiftDown end
function wipe(t) for k in pairs(t) do t[k] = nil end end
tinsert = table.insert
STANDARD_TEXT_FONT = "test-font"
SlashCmdList, UISpecialFrames, UIParent = {}, {}, {}
DamageTipsDB = { showDamage = true, showMinimap = false, manaMode = 3 }
DamageTipsDB.unrelatedLegacyValue = "keep me"
DamageTipsDB.spellRules = { ["234"] = 12, ["0234"] = "hide", [567] = 0, ["789"] = math.huge }
local savedDB = DamageTipsDB
C_Spell = {
    GetSpellInfo = function() return { castTime = castTime } end,
    GetSpellPowerCost = function()
        costCalls = costCalls + 1
        return costs
    end,
    GetSpellDescription = function() return description end,
    RequestLoadSpellData = function() requests = requests + 1 end,
}
C_SpellBook = {
    GetSpellBookItemInfo = function() return { spellID = spellID } end,
    IsSpellKnown = function(id, bank)
        assert(id == spellID)
        knownCalls = knownCalls + 1
        if bank == 0 then return playerKnown end
        assert(bank == 1)
        return petKnown
    end,
}
C_TooltipInfo = {
    GetSpellByID = function()
        if dataOverride then return dataOverride end
        return { lines = { { leftText = "Test Spell" }, { type = 34, leftText = description } } }
    end,
}

local widget = {}
widget.__index = widget
local function newWidget(parent)
    local frame = setmetatable({ scripts = {}, children = {} }, widget)
    if parent and parent.children then table.insert(parent.children, frame) end
    return frame
end
function widget:SetScript(name, fn) self.scripts[name] = fn end
function widget:RegisterEvent(name) events[name] = self end
function widget:UnregisterEvent(name) if events[name] == self then events[name] = nil end end
function widget:SetPoint(...) self.point = { ... } end
function widget:ClearAllPoints() self.point = nil end
function widget:SetSize(width, height) self.width, self.height = width, height end
function widget:SetText(value) self.text = value end
function widget:GetText() return self.text end
function widget:ClearFocus() self.focused = false end
function widget:SetChecked(value) self.checked = value end
function widget:GetChecked() return self.checked end
function widget:Hide() self.visible = false end
function widget:Show() self.visible = true end
function widget:SetShown(value) self.visible = value end
function widget:IsShown() return self.visible end
function widget:CreateFontString() return newWidget(self) end
function widget:CreateTexture() return newWidget(self) end
for _, method in ipairs({
    "EnableMouse", "RegisterForDrag", "SetFrameStrata", "SetMovable", "SetBackdrop",
    "RegisterForClicks", "SetAllPoints", "SetColorTexture", "SetMinMaxValues", "SetValueStep",
    "SetObeyStepOnDrag", "SetValue", "SetTextColor", "SetFont", "SetWidth", "SetJustifyH",
    "SetAutoFocus", "StartMoving", "StopMovingOrSizing", "LockHighlight", "UnlockHighlight",
    "SetFrameLevel", "SetHighlightTexture", "SetTexture",
}) do widget[method] = function() end end
function CreateFrame(kind, name, parent)
    local frame = newWidget(parent)
    frame.kind = kind
    if name then _G[name] = frame end
    return frame
end
Minimap = newWidget()

GameTooltip = { shown = true }
function GameTooltip:HookScript(event, fn)
    if event == "OnTooltipCleared" then self.onCleared = fn end
end
function GameTooltip:SetAction() tooltipLines = {}; self.onCleared() end
GameTooltip.SetSpellBookItem = GameTooltip.SetAction
function GameTooltip:AddLine(line) tooltipLines[#tooltipLines + 1] = line end
function GameTooltip:NumLines() return #tooltipLines end
function GameTooltip:GetOwner() return owner end
function GameTooltip:Show() self.shown = true end
function GameTooltip:IsShown() return self.shown end
function hooksecurefunc(obj, method, hook)
    local original = obj[method]
    obj[method] = function(self, ...)
        original(self, ...)
        hook(self, ...)
    end
end

local function fireEvent(name, ...)
    local frame = assert(events[name], name .. " was not registered")
    frame.scripts.OnEvent(frame, name, ...)
end
local function expect(ok, label)
    assert(ok, label .. "\nTooltip: " .. table.concat(tooltipLines, " | "))
    assertions = assertions + 1
end
local function has(text)
    for _, line in ipairs(tooltipLines) do if line:find(text, 1, true) then return true end end
    return false
end
local function chatContains(start, text)
    for i = start + 1, #chat do
        if chat[i]:find(text, 1, true) then return true end
    end
    return false
end
local function hasNoEstimates()
    return not (has("Mana sustain") or has("Before low mana") or has("Caster spell crit")
        or has("spell power:") or has("Bonus healing:"))
end
local function hover(slot) GameTooltip:SetAction(slot or 1) end
local function command(text) SlashCmdList.DAMAGETIPS(text) end

local namespace = {}
assert(loadfile(addonPath .. "/SpellPowerModels.lua"))("DamageTips", namespace)
assert(loadfile(addonPath .. "/SpellModifiers.lua"))("DamageTips", namespace)
assert(loadfile(addonPath .. "/SpellEstimates.lua"))("DamageTips", namespace)
assert(loadfile(addonPath .. "/DamageTips.lua"))("DamageTips", namespace)
fireEvent("ADDON_LOADED", "DamageTips")
local minimapButton = assert(DamageTipsMinimapButton)
expect(not minimapButton:IsShown(), "legacy minimap preference applies at startup")
expect(DamageTipsDB == savedDB and DamageTipsDB.unrelatedLegacyValue == "keep me"
    and DamageTipsDB.spellRules["234"] == 12 and DamageTipsDB.spellRules["567"] == 0
    and DamageTipsDB.spellRules["0234"] == nil and DamageTipsDB.spellRules["789"] == nil,
    "load keeps the account DB and canonical rules while sanitizing bad values")
command("import DT1;showMinimap=1;minimapAngle=-270;spellRules=234:12")
expect(minimapButton:IsShown() and DamageTipsDB.minimapAngle == 90
    and math.abs(minimapButton.point[4]) < 0.01 and minimapButton.point[5] > 79,
    "import updates visibility and position with no config frame")
command("import DT1;showMinimap=0")
expect(not minimapButton:IsShown(), "partial import hides minimap with no config frame")
command("reset")
expect(minimapButton:IsShown() and DamageTipsDB.minimapAngle == 90 and DamageTipsDB.spellRules["234"] == 12,
    "reset syncs minimap and retains angle and rules with no config frame")
command("import DT1;showMinimap=0;manaMode=3;spellRules=")
expect(not minimapButton:IsShown() and next(DamageTipsDB.spellRules) == nil,
    "empty rules field clears rules and partial import preserves other fields")
expect(DamageTipsDB.showManaSustain == false and DamageTipsDB.showCasterStats == false,
    "old SavedVariables default both estimates off")
hover()
expect(has("DPS: 50.0") and has("DPM: 3000") and has("Mana cost: 100 (10.0%)"),
    "baseline damage, DPM and mana match")
expect(hasNoEstimates() and knownCalls == 0 and regenCalls == 0 and critCalls == 0,
    "disabled options do not query new player APIs")
local baselineCostCalls = costCalls
hover()
expect(costCalls == baselineCostCalls + 1, "baseline hover rereads live mana cost")

command("")
local config = assert(DamageTipsConfigFrame)
local sustainBox, casterBox = config.checks.showManaSustain, config.checks.showCasterStats
expect(config:IsShown() and config.panels.lines:IsShown() and not config.panels.format:IsShown(),
    "Lines tab is shown by default")
expect(sustainBox:GetChecked() == false and casterBox:GetChecked() == false,
    "new checkboxes start unchecked")
expect(sustainBox.point[2] == 330 and sustainBox.point[3] == -112 and casterBox.point[3] == -138,
    "new checkboxes occupy the right column with separate rows")
expect(not config.previewSustain:IsShown() and not config.previewCaster:IsShown(),
    "preview examples are hidden by default")
sustainBox:SetChecked(true)
sustainBox.scripts.OnClick(sustainBox)
command("caster")
expect(config.previewSustain:IsShown() and config.previewCaster:IsShown()
    and config.previewSustain.text:find("~8 casts", 1, true)
    and config.previewCaster.text == "Caster spell crit: 12.5%",
    "both options update their sample previews")
expect(knownCalls == 0 and regenCalls == 0 and critCalls == 0,
    "sample previews do not read live stats")

local beforeSustain = costCalls
hover()
expect(has("~1 cast (80.00 net mana per cycle)") and has("~100 damage"),
    "175 mana buys one cast when each later cycle nets 80 mana")
expect(costCalls == beforeSustain + 1, "one combined mana cost query per eligible hover")
expect(has("Caster spell crit: 12.5%") and has("Fire spell power: 54") and has("DPS: 50.0"),
    "caster stats preserve baseline damage")
mana = 180
hover()
expect(has("~2 casts") and has("~200 damage"), "180 mana buys exactly two casts")
mana, regen = 200, 0
hover()
expect(has("~2 casts (100.00 net mana per cycle)"), "zero casting regen ignores resting regen")
mana, regen = 99, 50
hover()
expect(has("not enough mana for one cast") and not has("Before low mana"),
    "insufficient initial mana even at sustainable cadence")
mana = 100
hover()
expect(has("sustainable at this cadence") and not has("Before low mana"),
    "break-even casting regen is sustainable after an affordable first cast")

mana, regen, crit, power = secret, secret, secret, secret
hover()
expect(hasNoEstimates() and has("DPS: 50.0"), "same-second restricted stats never reuse public estimates")
mana, regen, crit, power = 180, 10, 15, 71
hover()
expect(has("~2 casts") and has("15.0%") and has("Fire spell power: 71"), "public inputs resume immediately")
description = secret
hover()
expect(hasNoEstimates() and not has("DPS"), "restricted description invalidates estimate in same second")
description, dataOverride = damageText, secret
hover()
expect(has("DPS: 50.0") and has("Caster spell crit"),
    "a public spell description does not need the restricted fallback")
dataOverride = nil
castTime = secret
hover()
expect(not has("Mana sustain") and has("Caster spell crit"), "restricted cast time suppresses sustain only")
castTime, gcd = 2000, secret
hover()
expect(not has("Mana sustain") and has("Caster spell crit"), "restricted GCD suppresses sustain only")
gcd = 1500

GameTooltip:SetSpellBookItem(1, 0)
expect(has("Mana sustain") and has("Caster spell crit"), "explicit player spellbook works")
GameTooltip:SetSpellBookItem(1, 1)
expect(hasNoEstimates() and has("DPS: 50.0"), "same spell ID from pet bank cannot reuse player estimates")
GameTooltip:SetSpellBookItem(1, "pet")
expect(hasNoEstimates(), "legacy pet-bank argument still suppresses player estimates")
petKnown = true
hover()
expect(hasNoEstimates() and has("DPS: 50.0"), "ambiguous action ID is suppressed")
GameTooltip:SetSpellBookItem(1, "spell")
expect(has("Mana sustain"), "explicit legacy player bank resolves shared ID")
petKnown, playerKnown = false, secret
hover()
expect(hasNoEstimates() and has("DPS: 50.0"), "unknown or restricted player ownership omits estimates")
playerKnown = true
hover(2)
expect(has("Mana sustain"), "spell macro resolves through the regular tooltip hook")
hover(3)
expect(#tooltipLines == 0, "non-spell action is ignored")

costs[1].costPerSec = 1
hover()
expect(not has("Mana sustain") and has("Mana cost: 100"), "recurring cost excluded")
costs[1].costPerSec, costs[1].requiredAuraID = 0, 22
hover()
expect(not has("Mana sustain") and has("Mana cost: 100"), "conditional cost excluded")
costs[1].requiredAuraID, costs[1].minCost = 0, 90
hover()
expect(not has("Mana sustain") and has("Mana cost: 100"), "optional cost excluded")
costs[1].minCost, costs[2] = 100, { type = 3, cost = 10 }
hover()
expect(not has("Mana sustain") and has("Mana cost: 100"), "additional resource cost excluded")
costs[2], costs[1].minCost = nil, secret
hover()
expect(not has("Mana sustain") and has("Mana cost: 100"), "restricted cost detail excluded")
costs[1].minCost = 100
local normalCosts = costs
costs = secret
hover()
expect(not has("Mana sustain") and not has("Mana cost") and has("DPS: 50.0"), "restricted cost table excluded")
costs = normalCosts

description = healText
hover()
expect(has("HPS: 80.0") and has("~320 healing") and has("Bonus healing: 82") and not has("Fire spell power"),
    "healing uses its parsed output and caster healing stat")
description, mana = damageText .. " Also inflicts 60 Fire damage over 6 seconds. " .. healText, 180
hover()
expect(has("~3 casts (40.00 net mana per cycle)") and has("~480 damage") and has("~480 healing"),
    "mixed spell models the longest enabled periodic duration")
command("import DT1;includeDoT=0")
hover()
expect(has("~2 casts (80.00 net mana per cycle)") and has("~200 damage") and has("~320 healing"),
    "periodic toggle affects cadence and output")

command("hide " .. spellID)
hover()
expect(#tooltipLines == 0, "hidden spell suppresses estimates and all legacy lines")
command("show " .. spellID)
command("export")
local exported = chat[#chat]
expect(exported:find("showManaSustain=1", 1, true) and exported:find("showCasterStats=1", 1, true),
    "new choices are exported")
command("reset")
expect(not DamageTipsDB.showManaSustain and not DamageTipsDB.showCasterStats
    and not config.previewSustain:IsShown() and not config.previewCaster:IsShown(), "reset clears new options")
command("import DT1;showDPS=0")
expect(not DamageTipsDB.showDPS and not DamageTipsDB.showManaSustain and not DamageTipsDB.showCasterStats,
    "old settings strings remain usable")
command("import " .. exported)
expect(DamageTipsDB.showDPS and DamageTipsDB.showManaSustain and DamageTipsDB.showCasterStats, "new choices round-trip")
command("import DT1;showManaSustain=0;showCasterStats=invalid")
expect(DamageTipsDB.showManaSustain and DamageTipsDB.showCasterStats, "malformed import has no partial writes")

local readRegen, readCrit, readPower = GetPowerRegenForPowerType, GetSpellCritChance, GetSpellBonusDamage
GetPowerRegenForPowerType, GetSpellCritChance, GetSpellBonusDamage = nil, nil, nil
description = damageText
hover()
expect(hasNoEstimates() and has("DPS: 50.0"), "missing optional getters preserve baseline")
GetPowerRegenForPowerType, GetSpellCritChance, GetSpellBonusDamage = readRegen, readCrit, readPower
local spellKnown = C_SpellBook.IsSpellKnown
C_SpellBook.IsSpellKnown = nil
hover()
expect(hasNoEstimates() and has("DPS: 50.0"), "missing ownership getter preserves baseline")
C_SpellBook.IsSpellKnown = spellKnown

command("import DT1;showDPS=0;showDPM=0;showHealing=0;showManaSustain=0")
castTime, cooldown = nil, nil
local spellInfo = C_Spell.GetSpellInfo
C_Spell.GetSpellInfo = function() error("caster stats should not need cast time") end
hover()
expect(has("Mana cost") and has("Caster spell crit") and not has("DPS") and not has("Mana sustain"),
    "caster-only path preserves existing mana and bypasses unavailable timing")
C_Spell.GetSpellInfo, castTime, cooldown = spellInfo, 2000, 0
command("import " .. exported)

command("import DT1;showMana=0")
spellID, description, mana = 999, nil, 180
hover()
expect(requests == 1 and hasNoEstimates(), "missing spell text requests data and skips estimates")
description = damageText
fireEvent("SPELL_DATA_LOAD_RESULT", spellID, true)
runReadyTimers()
expect(has("Mana sustain") and has("Caster spell crit"), "async loaded tooltip preserves player context")

for _, line in ipairs(chat) do expect(not line:find("error (shown once)", 1, true), "no guarded hook errors") end
local previousAssertions = assertions
local chatBeforePower = #chat

local function noPowerLines()
    return not (has("+100 ") or has("Expected DPS") or has("Expected HPS") or has("DPS on landed hits"))
end

local fireBlast = "Blasts the enemy for 90 to 110 Fire damage."
command("reset")
command("import DT1;showMinimap=0")
spellID, description, crit = 2136, fireBlast, 20
hover()
expect(noPowerLines() and not DamageTipsDB.showPowerScaling and not DamageTipsDB.showExpectedThroughput,
    "known supported spells default to legacy lines")
local scalingBox, expectedBox = config.checks.showPowerScaling, config.checks.showExpectedThroughput
expect(scalingBox.point[2] == 330 and scalingBox.point[3] == -164 and expectedBox.point[3] == -190
    and not config.previewScaling:IsShown() and not config.previewExpected:IsShown(),
    "two new controls have separate right-column rows and inactive previews")
scalingBox:SetChecked(true)
scalingBox.scripts.OnClick(scalingBox)
hover()
expect(has("+100 Fire spell power: +42.9 damage / cast (nominal)") and not has("Expected DPS"),
    "power scaling independently shows the selected rank")
command("expected")
hover()
expect(has("DPS: 50.0") and has("Expected DPS (equal-level PvE): 53.9 (98.0% hit, 20.0% crit)"),
    "expected damage uses live 100 average once rather than adding current power")
expect(config.previewScaling:IsShown() and config.previewExpected:IsShown(),
    "both new previews reflect saved choices")
command("scaling")
hover()
expect(not has("+100 Fire") and has("Expected DPS"), "expected throughput works with scaling off")
command("scaling")

spellID, description = 403, "Casts a bolt of lightning at the target for 16 Nature damage."
hover()
expect(has("+42.9 damage / cast") and has("Expected DPS"), "Lightning Bolt rank 1 exact coefficient")
spellID = 529
hover()
expect(has("+57.1 damage / cast") and has("Expected DPS"), "Lightning Bolt rank 2 differs from rank 1")
spellID = 548
hover()
expect(has("+71.4 damage / cast"), "Lightning Bolt rank 3 differs from rank 2")
spellID, description = 2912, "Causes 113 Arcane damage to the target."
hover()
expect(has("+100 Arcane spell power: +100 damage") and has("Expected DPS"), "Starfire flat known template and genuine 1.0 coefficient")
spellID, description = 686, "Sends a shadowy bolt at the enemy, causing 13 Shadow damage."
hover()
expect(has("+48.6 damage / cast") and has("Expected DPS"), "Shadow Bolt flat known template")
spellID, description = 116, "Launches a bolt of frost at the enemy, causing 19 to 24 Frost damage."
hover()
expect(has("+40.7 damage / cast") and not has("Expected DPS"), "binary Frostbolt scaling only")

spellID, description = 2136, fireBlast
hitRating, hitModifier, crit = 0, 0, 0
hover()
expect(has("48.0 (96.0% hit, 0.0% crit)"), "zero bonuses preserve the 96% base hit and zero crit")
hitRating, hitModifier, crit = 30, 60, 100
hover()
expect(has("75.0 (100.0% hit, 100.0% crit)"), "hit caps at 100 and full spell crit uses 1.5x")
hitRating, hitModifier = -300, 0
hover()
expect(has("0.0 (0.0% hit, 100.0% crit)"), "negative hit modifier floors hit at zero")
hitRating, hitModifier, crit = 1, 1, 20
hover()
expect(has("53.9"), "normal spell rating restored")
hitModifier = secret
hover()
expect(has("+100 Fire") and has("DPS: 50.0") and not has("Expected DPS"),
    "same-second restricted hit cannot reuse readable estimate")
hitModifier, hitRating = 1, secret
hover()
expect(not has("Expected DPS"), "restricted rating omits expected DPS")
hitRating, crit = 1, secret
hover()
expect(not has("Expected DPS"), "restricted crit omits expected DPS")
crit, castTime = 20, secret
hover()
expect(has("+100 Fire") and not has("Expected DPS"), "secret cast cadence omits expected DPS only")
castTime, cooldown = 2000, secret
hover()
expect(not has("Expected DPS"), "secret base cooldown omits expected DPS")
cooldown, gcd = 0, secret
hover()
expect(not has("Expected DPS"), "secret GCD omits expected DPS")
gcd = 1500
local originalHitModifier = GetSpellHitModifier
GetSpellHitModifier = function() error("mock API failure") end
hover()
expect(has("DPS: 50.0") and not has("Expected DPS"), "throwing chance preserves baseline")
GetSpellHitModifier = nil
hover()
expect(has("DPS: 50.0") and not has("Expected DPS"), "missing chance does not become zero")
GetSpellHitModifier = originalHitModifier

description = "Blasts the enemy for 180 Fire damage every 2 sec."
hover()
expect(not has("DPS:") and not has("Expected DPS"), "an isolated periodic tick with no total duration is not a direct hit")
description = fireBlast .. " Then burns for 60 Fire damage over 6 sec."
command("import DT1;includeDoT=0")
hover()
expect(has("DPS: 50.0") and not has("Expected DPS"), "periodic marker is respected even when baseline DoT is disabled")
description = fireBlast
command("setdmg 2136 180")
hover()
expect(has("DPS: 90.0") and has("+100 Fire") and not has("Expected DPS"),
    "numeric overrides preserve baseline values and suppress expected output")
command("show 2136")
command("hide 2136")
hover()
expect(#tooltipLines == 0, "hidden supported spells suppress all lines")
command("show 2136")
GameTooltip:SetSpellBookItem(1, 0)
expect(has("Expected DPS"), "supported player book spell is modeled")
GameTooltip:SetSpellBookItem(1, 1)
expect(noPowerLines() and has("DPS: 50.0"), "same-ID pet tooltip is unmodeled")
petKnown = true
hover()
expect(noPowerLines(), "ambiguous supported action ID is unmodeled")
petKnown, playerKnown = false, false
hover()
expect(noPowerLines(), "unknown player rank is unmodeled")
playerKnown = true
buildNumber = "70889"
hover()
expect(noPowerLines() and has("DPS: 50.0"), "adjacent build with same interface remains unmodeled")
buildNumber, buildInterface = "70888", 16002
hover()
expect(noPowerLines(), "matching build and wrong interface is unmodeled")
buildInterface, buildNumber = 16001, secret
hover()
expect(noPowerLines(), "restricted build value does not pass")
buildNumber = 70888
hover()
expect(has("Expected DPS"), "numeric exact build is accepted")
description = secret
hover()
expect(noPowerLines(), "restricted tooltip text suppresses all new lines immediately")
description, spellID = fireBlast, 400001
hover()
expect(noPowerLines() and has("DPS: 50.0"), "unlisted spell with same description never borrows scaling")

spellID, description = 2061, "Heals a friendly target for 194–238."
hitModifier = secret
hover()
expect(has("+100 healing power: +42.9 healing") and has("Expected HPS: 118.8 (20.0% crit)")
    and not has("hit,"), "direct heal fallback parses a dash range and needs only crit")
description = "Heals a friendly target for 194 to 238 health."
hover()
expect(has("HPS: 108.0") and has("Expected HPS: 118.8"), "existing healing line is unchanged")
description = "Heals a friendly target for 100 health every 2 sec."
hover()
expect(not has("Expected HPS"), "periodic heal cannot use direct-heal model")
description = "Heals a friendly target for 194 to 238. Restores 100 health over 5 sec."
hover()
expect(not has("Expected HPS"), "separate periodic heal sentence disqualifies direct model")
spellID, description = 2054, "Heal your target for 270."
hover()
expect(has("+85.7 healing") and has("Expected HPS"), "Heal exact client grammar")
spellID, description = 2060, "A slow casting spell that heals a single target for 844."
hover()
expect(has("Expected HPS"), "Greater Heal exact client grammar")
crit = secret
hover()
expect(not has("Expected HPS"), "heal also drops a secret sheet crit")
crit, hitModifier = 20, 1

spellID, description = 23881,
    "Instantly attack the target causing damage equal to 45% of your Attack Power plus 30 and increasing your movement speed by 10% for 4 sec."
hover()
expect(has("+100 attack power: +45 damage") and has("DPS on landed hits: 155.7 (20.0% crit)")
    and not has("Expected DPS"), "Bloodthirst uses signed AP parts and melee crit")
local bloodthirstText = description
description = description:gsub("45%%", "46%%")
hover()
expect(not has("DPS on landed hits") and has("+100 attack power"), "mismatched AP grammar leaves only nominal scaling")
description = "Instantly attacks the target for 259 Physical damage."
hover()
expect(not has("DPS on landed hits"), "fixed damage description is never fed AP again")
description, apNegative = bloodthirstText, secret
hover()
expect(not has("DPS on landed hits"), "any restricted AP component omits expected melee output")
apNegative, meleeCrit = -10, secret
hover()
expect(not has("DPS on landed hits"), "restricted melee crit omits expected melee output")
meleeCrit = 20
spellID, description = 429151, "Hurls a hammer that strikes an enemy for 300 to 330 Holy damage."
hover()
expect(has("+100 Holy spell power: +15 damage") and has("+100 attack power: +15 damage")
    and not has("Expected DPS"), "verified hybrid Hammer variant shows independent marginal stats")
spellID = 24275
hover()
expect(noPowerLines(), "normal Hammer rank does not borrow the hybrid coefficient")
spellID, description = 3044, "An instant shot that causes 25 Arcane damage."
hover()
expect(has("+100 ranged attack power: +15 damage / shot") and not has("Arcane spell power") and not has("Expected DPS"),
    "Arcane Shot uses the ranged coefficient and avoids the spell hit model")

command("export")
local powerExport = chat[#chat]
expect(powerExport:find("showPowerScaling=1", 1, true) and powerExport:find("showExpectedThroughput=1", 1, true),
    "power flags are present in DT1 export")
command("reset")
command("import DT1;showDPS=0")
expect(not DamageTipsDB.showPowerScaling and not DamageTipsDB.showExpectedThroughput and not DamageTipsDB.showDPS,
    "old DT1 settings import without enabling the new flags")
command("import " .. powerExport)
expect(DamageTipsDB.showPowerScaling and DamageTipsDB.showExpectedThroughput, "power flags survive DT1 round trip")
command("import DT1;showPowerScaling=0;showExpectedThroughput=bad")
expect(DamageTipsDB.showPowerScaling and DamageTipsDB.showExpectedThroughput,
    "invalid expected flag cannot partially apply scaling flag")
for i = chatBeforePower + 1, #chat do
    expect(not chat[i]:find("error (shown once)", 1, true), "new hook scenarios completed without caught errors")
end
local alpha2Assertions = assertions
local periodicChatStart = #chat
local function periodicHover(id, text)
    spellID, description = id, text
    hover()
end
local function lacksPeriodic()
    return not (has(" / tick (") or has("Expected DPS (full effect") or has("Expected HPS (full effect")
        or has("Expected DPS (full channel") or has("Expected DPS (base channel"))
end

command("import DT1;includeDoT=1;showPowerScaling=1;showExpectedThroughput=1")
buildNumber, buildInterface = "70888", 16001
hitRating, hitModifier, crit, cooldown, castTime, gcd = 1, 1, 20, 0, 2000, 1500
local corruption = "Corrupts the target, causing 120 Shadow damage over 12 sec."
periodicHover(172, corruption)
expect(has("+100 Shadow spell power: +20 damage / tick (+80 over 4 ticks)")
    and has("DPS: 10.0") and has("Expected DPS (full effect, equal-level PvE): 10.8 (98.0% hit, 20.0% crit)"),
    "Corruption consumes full tooltip total and one application hit")
periodicHover(6222, "Corrupts the target, causing 150 Shadow damage over 15 seconds.")
expect(has("+100 over 5 ticks") and has("PvE): 10.8"), "Corruption rank 2 schedule is five ticks")
periodicHover(6223, "Corrupts the target, causing 180 Shadow damage over 18 sec.")
expect(has("+120 over 6 ticks") and has("PvE): 10.8"), "Corruption rank 3 schedule is six ticks")
periodicHover(589, "A word of darkness that causes 180 Shadow damage over 18 sec.")
expect(has("+120 over 6 ticks") and has("PvE): 10.8"), "Shadow Word: Pain uses its own grammar")
periodicHover(172, "Corrupts the target, causing 1,200 Shadow damage over 12 sec.")
expect(has("PvE): 107.8"), "grouped four-digit total is read once")
periodicHover(172, "Corrupts the target, causing 1,2 Shadow damage over 12 sec.")
expect(lacksPeriodic(), "malformed digit grouping is rejected")
periodicHover(172, "Corrupts the target, causing 120 Shadow damage over 15 sec.")
expect(lacksPeriodic(), "duration mismatched to the chosen rank is rejected")
periodicHover(172, "Corrupts the target, causing 120 Shadow damage over 12 secret.")
expect(lacksPeriodic(), "unrecognized duration units are rejected")
periodicHover(172, "Corrupts the target, causing Shadow damage over 12 sec.")
expect(lacksPeriodic(), "missing periodic amount is rejected")
periodicHover(172, "Corrupts the target, causing 0 Shadow damage over 12 sec.")
expect(lacksPeriodic(), "zero periodic amount is rejected")

hitModifier = secret
periodicHover(774, "Heals the target for 120 over 12 sec.")
expect(has("+100 healing power: +20 healing / tick (+80 over 4 ticks)")
    and has("Expected HPS (full effect): 11.0 (20.0% crit)"), "Rejuvenation uses no spell hit")
periodicHover(139, "Heals the target of 150 damage over 15 sec.")
expect(has("HPS: 10.0") and not has("DPS") and has("+100 over 5 ticks")
    and has("Expected HPS (full effect): 11.0"), "Renew uses healing in both legacy and periodic outputs")
periodicHover(8936, "Heals a friendly target for 90 to 110 and another 110 over 21 sec.")
expect(has("+100 healing power: +28.6 healing / cast") and has("+7.1 healing / tick (+49.7 over 7 ticks)")
    and has("Expected HPS (full effect): 11.0"), "Regrowth sums its direct range average and total ticks")
periodicHover(8936, "Heals a friendly target for 90–110 and another 110 over 21 sec.")
expect(has("Expected HPS (full effect): 11.0"), "Regrowth direct dash range matches")
periodicHover(8936, "Heals a friendly target for 110 to 90 and another 110 over 21 sec.")
expect(lacksPeriodic(), "Regrowth rejects reversed direct ranges")

hitModifier = 1
local moonfire = "Burns the enemy for 100 Arcane damage and then an additional 80 Arcane damage over 9 sec."
periodicHover(8921, moonfire)
expect(has("+15 damage / cast") and has("+13 damage / tick (+39 over 3 ticks)")
    and has("PvE): 21.6"), "Moonfire shares one application hit between both components")
periodicHover(8924, moonfire:gsub("9 sec", "12 sec"))
expect(has("+52 over 4 ticks") and has("PvE): 16.2"), "Moonfire higher rank has a four-tick schedule")
periodicHover(348, "Burns the enemy for 50 Fire damage and then an additional 100 Fire damage over 15 sec.")
expect(has("+20 damage / cast") and has("+13 damage / tick (+65 over 5 ticks)")
    and has("PvE): 10.8"), "Immolate uses direct Fire and separate periodic Fire amounts")
local holyFire = "Consumes the enemy in holy flames that cause 100 to 140 Holy damage and an additional 80 Holy damage over 10 sec."
periodicHover(14914, holyFire)
expect(has("+75 damage / cast") and has("+5 damage / tick (+25 over 5 ticks)")
    and has("PvE): 21.6"), "Holy Fire has a two-second periodic interval")
cooldown = 12000
hover()
expect(has("PvE): 18.0"), "base cooldown longer than full effect controls expected cadence")
cooldown = 0
periodicHover(133, "Hurls a fiery ball that causes 100 Fire damage and an additional 20 Fire damage over 4 sec.")
expect(has("+42.9 damage / cast") and not has(" / tick (") and has("PvE): 32.3"),
    "Fireball includes zero-coefficient ticks in expected output only")

local shortMissiles = "Launches Arcane Missiles at the enemy, causing 30 Arcane damage each second for 3 sec."
periodicHover(5143, shortMissiles)
expect(has("+28.6 damage / tick (+85.8 over 3 ticks)")
    and has("Expected DPS (full channel, equal-level PvE): 32.3 (98.0% hit per missile, 20.0% crit)"),
    "Arcane Missiles uses per-missile damage and only one hit roll per missile")
periodicHover(5144, shortMissiles:gsub("3 sec", "4 sec"))
expect(has("+114.4 over 4 ticks") and has("PvE): 32.3"), "Arcane Missiles rank 2 has four missiles")
periodicHover(5145, shortMissiles:gsub("3 sec", "5 sec"))
expect(has("+143 over 5 ticks") and has("PvE): 32.3"), "Arcane Missiles higher ranks have five missiles")
periodicHover(5144, "Launches Arcane Missiles at the enemy, causing 30 Arcane damage every 1 second for 4 sec.")
expect(has("PvE): 32.3"), "explicit per-missile interval can be verified")
periodicHover(5144, "Launches Arcane Missiles at the enemy, causing 30 Arcane damage every 2 sec for 4 sec.")
expect(lacksPeriodic(), "mismatched per-missile interval suppresses the forecast and tick scaling")
periodicHover(5145, shortMissiles)
expect(lacksPeriodic(), "same tooltip duration cannot be used with a different channel rank")
periodicHover(7268, shortMissiles)
expect(lacksPeriodic(), "child spell ID is not a player tooltip model")
periodicHover(15407, "Assault the target's mind with Shadow energy, causing 90 Shadow damage over 3 sec  and slowing their movement speed by 50%.")
expect(has("+16.7 damage / tick (+50.1 over 3 ticks)")
    and has("Expected DPS (base channel, equal-level PvE): 32.3 (98.0% hit, 20.0% crit)"),
    "Mind Flay models its base full-channel total and one application hit")
periodicHover(1978, "Stings the target, causing 150 Nature damage over 15 sec. Only one Sting per Hunter can be active on any one target.")
expect(has("+100 ranged attack power: +5 damage / tick (+25 over 5 ticks)") and not has("Expected DPS"),
    "Serpent Sting exposes nominal ranged scaling without a magic hit forecast")

periodicHover(8921, moonfire)
command("import DT1;includeDoT=0")
hover()
expect(has("Expected DPS (equal-level PvE): 53.9") and not has(" / tick (")
    and has("+15 damage / cast") and has("DPS: 50.0"),
    "Include DoT off preserves direct damage, scaling and expected DPS")
periodicHover(8936, "Heals a friendly target for 90 to 110 and another 110 over 21 sec.")
expect(has("HPS: 50.0") and has("Expected HPS: 55.0")
    and has("+28.6 healing / cast") and not has(" / tick ("),
    "periodic off preserves the direct Regrowth heal, scaling and expected HPS")
periodicHover(172, corruption)
expect(lacksPeriodic() and not has("DPS"), "Include DoT off hides pure periodic lines")
command("import DT1;includeDoT=1")
periodicHover(172, corruption)
expect(has("Expected DPS"), "re-enabling Include DoT restores periodic output")
GameTooltip:SetSpellBookItem(1, 1)
expect(lacksPeriodic() and has("DPS: 10.0"), "same-ID pet tooltip gets no player-only periodic lines")
GameTooltip:SetSpellBookItem(1, 0)
expect(has("Expected DPS"), "known player spellbook periodic tooltip supported")
buildNumber = "70889"
hover()
expect(lacksPeriodic() and has("DPS: 10.0"), "periodic forecasts require exact build")
buildNumber = "70888"
description = secret
hover()
expect(lacksPeriodic(), "restricted current tooltip text suppresses prior same-second forecast")
description, crit = corruption, secret
hover()
expect(has("+80 over 4 ticks") and not has("Expected DPS"), "secret crit suppresses only live forecast")
crit, hitModifier = 20, secret
hover()
expect(has("+80 over 4 ticks") and not has("Expected DPS"), "secret hit suppresses periodic forecast")
hitModifier, castTime = 1, secret
hover()
expect(has("+80 over 4 ticks") and not has("Expected DPS"), "secret cadence suppresses periodic forecast")
castTime = 2000
command("hide 172")
hover()
expect(#tooltipLines == 0, "hidden rules suppress all periodic lines")
command("show 172")
command("setdmg 172 200")
hover()
expect(has("DPS: 100.0") and has("+80 over 4 ticks") and not has("Expected DPS"),
    "damage overrides remain baseline-only and suppress forecast")
command("show 172")
command("import DT1;showPowerScaling=0")
hover()
expect(not has(" / tick (") and has("Expected DPS"), "periodic forecast is independent of scaling")
command("import DT1;showPowerScaling=1;showExpectedThroughput=0")
hover()
expect(has(" / tick (") and not has("Expected DPS"), "periodic scaling is independent of forecast")

local getRate = namespace.SpellEstimates.GetExpectedRate
local beforeCrit = critCalls
crit = secret
local noncritRate, noncritHit, noncritCrit = getRate("spell", 20, 5, {
    hitMode = "application", directCrit = false, tickCrit = false,
}, 80)
expect(noncritRate == 19.6 and noncritHit == 98 and noncritCrit == nil and critCalls == beforeCrit,
    "wholly noncrit fixture neither reads nor assumes a crit stat")
crit = 100
local splitRate = getRate("healing", 20, 5, { hitMode = "none", directCrit = true, tickCrit = false }, 80)
expect(splitRate == 22, "only the crit-eligible direct component receives 1.5x")

for i = periodicChatStart + 1, #chat do
    expect(not chat[i]:find("error (shown once)", 1, true), "periodic hook scenarios completed without caught errors")
end
local alpha3Assertions = assertions
local targetChatStart = #chat
local targetExists, targetAttackable, targetIsPlayer, targetPlayerControlled, targetDead = true, true, false, false, false
local livePlayerLevel, liveTargetLevel, resist, effectiveArmor, armorEffect = 60, 62, 70, 1000, 0.25
local targetReads, resistReads, armorReads, fallbackLevels, armorEffectReads = 0, 0, 0, 0, 0
local lastSchool
Enum.Damageclass = { Fire = 41, Frost = 42, Nature = 43, Shadow = 44, Arcane = 45, Holy = 46 }

function UnitExists(unit)
    assert(unit == "target")
    targetReads = targetReads + 1
    return targetExists
end
function UnitCanAttack(player, target)
    assert(player == "player" and target == "target")
    targetReads = targetReads + 1
    return targetAttackable
end
function UnitIsPlayer(unit)
    assert(unit == "target")
    targetReads = targetReads + 1
    return targetIsPlayer
end
function UnitPlayerControlled(unit)
    assert(unit == "target")
    targetReads = targetReads + 1
    return targetPlayerControlled
end
function UnitIsDeadOrGhost(unit)
    assert(unit == "target")
    targetReads = targetReads + 1
    return targetDead
end
function UnitEffectiveLevel(unit)
    assert(unit == "player" or unit == "target")
    targetReads = targetReads + 1
    if unit == "player" then return livePlayerLevel end
    return liveTargetLevel
end
function UnitLevel(unit)
    assert(unit == "player" or unit == "target")
    fallbackLevels = fallbackLevels + 1
    if unit == "player" then return livePlayerLevel end
    return liveTargetLevel
end
function UnitResistance(unit, school)
    assert(unit == "target")
    resistReads = resistReads + 1
    lastSchool = school
    return 999, 555, resist, 777
end
function UnitArmor(unit)
    assert(unit == "target")
    armorReads = armorReads + 1
    return 9999, effectiveArmor, 8888, 7777
end
C_PaperDollInfo = {
    GetArmorEffectiveness = function(armor, attackerLevel)
        assert(armor == effectiveArmor and attackerLevel == livePlayerLevel)
        armorEffectReads = armorEffectReads + 1
        return armorEffect
    end,
}

command("import DT1;includeDoT=1;showPowerScaling=1;showExpectedThroughput=1")
crit, meleeCrit, hitRating, hitModifier = 20, 20, 1, 1
periodicHover(2136, fireBlast)
expect(has("DPS: 50.0") and has("Expected DPS (target L62): 46.3 (96.0% hit, 20.0% crit, Fire resist 70)")
    and lastSchool == Enum.Damageclass.Fire and armorReads == 0 and fallbackLevels == 0,
    "magic uses effective level and third resistance return without querying armor")

resist = 0
local expectedHit = { [57] = "100.0%", [58] = "100.0%", [59] = "99.0%", [60] = "98.0%",
    [61] = "97.0%", [62] = "96.0%", [63] = "85.0%" }
for level = 57, 63 do
    liveTargetLevel = level
    hover()
    expect(has("target L" .. level .. ", level only") and has(expectedHit[level] .. " hit"),
        "live level bracket " .. level .. " is applied without claiming zero resistance")
end
local beforeResist = resistReads
for _, level in ipairs({ 56, 64, -1, 0, 60.5, 256, math.huge, secret }) do
    liveTargetLevel = level
    hover()
    expect(has("Expected DPS (equal-level PvE): 53.9") and resistReads == beforeResist,
        "out-of-scope, skull or unusable level falls back before reading resistance")
end
liveTargetLevel = 62
livePlayerLevel = secret
hover()
expect(has("Expected DPS (equal-level PvE)") and resistReads == beforeResist,
    "restricted player effective level falls back without reading resistance")
livePlayerLevel = 60
local effectiveLevelGetter = UnitEffectiveLevel
UnitEffectiveLevel = nil
hover()
expect(has("target L62, level only") and fallbackLevels == 2,
    "UnitLevel fallback runs only if the effective-level API is absent")
UnitEffectiveLevel = function() error("mock effective level unavailable") end
hover()
expect(has("Expected DPS (equal-level PvE)") and fallbackLevels == 2,
    "throwing effective-level getter does not fall through to raw level")
UnitEffectiveLevel = effectiveLevelGetter

targetAttackable = false
hover()
expect(has("Expected DPS (equal-level PvE)"), "friendly target falls back")
targetAttackable, targetPlayerControlled = true, true
hover()
expect(has("Expected DPS (equal-level PvE)"), "player-controlled NPC/pet falls back")
targetPlayerControlled, targetIsPlayer = false, true
hover()
expect(has("Expected DPS (equal-level PvE)"), "player target falls back even if its controller flag disagrees")
targetIsPlayer, targetDead = false, true
hover()
expect(has("Expected DPS (equal-level PvE)"), "dead hostile NPC falls back")
targetDead, targetExists = false, secret
hover()
expect(has("Expected DPS (equal-level PvE)"), "protected existence flag falls back")
targetExists, targetPlayerControlled = true, nil
hover()
expect(has("Expected DPS (equal-level PvE)"), "unavailable player-control flag is not treated as NPC")
targetPlayerControlled = false
local canAttack = UnitCanAttack
UnitCanAttack = function() error("mock target attackability failure") end
hover()
expect(has("Expected DPS (equal-level PvE)"), "throwing eligibility check is guarded")
UnitCanAttack = canAttack

for _, value in ipairs({ secret, 0, -70, math.huge }) do
    resist = value
    hover()
    expect(has("Expected DPS (target L62, level only): 52.8") and not has("Fire resist"),
        "unreadable or nonpositive resistance leaves a level-only estimate")
end
local resistanceGetter = UnitResistance
UnitResistance = function() error("mock resistance unavailable") end
hover()
expect(has("target L62, level only"), "throwing resistance still preserves target level")
UnitResistance = resistanceGetter
resist = 70
hover()
expect(has("target L62): 46.3") and has("Fire resist 70"), "readable resistance is sampled again immediately")
liveTargetLevel, resist = 63, 105
hover()
expect(has("target L63") and has("85.0% hit") and has("Fire resist 105") and not has("Fire resist 70"),
    "same-clock target replacement cannot reuse level or resistance")
targetExists = false
hover()
expect(has("Expected DPS (equal-level PvE): 53.9") and not has("resist"),
    "clearing target on the same clock reverts to the exact fallback")
targetExists, liveTargetLevel, resist = true, 62, 70

periodicHover(172, corruption)
expect(has("Expected DPS (full effect, target L62): 10.4") and has("Shadow resist 70")
    and lastSchool == Enum.Damageclass.Shadow, "ordinary ticks use one tenth the fitted resistance mean")
periodicHover(348, "Burns the enemy for 50 Fire damage and then an additional 100 Fire damage over 15 sec.")
expect(has("Expected DPS (full effect, target L62): 10.0") and has("96.0% hit"),
    "mixed direct/tick spell has one shared hit and separate reductions")
periodicHover(5143, shortMissiles)
expect(has("Expected DPS (full channel, target L62): 27.8")
    and has("96.0% hit per missile") and has("Arcane resist 70"),
    "missiles use full partial mitigation and one per-missile hit chance")
periodicHover(15407, "Assault the target's mind with Shadow energy, causing 90 Shadow damage over 3 sec and slowing their movement speed by 50%.")
expect(has("Expected DPS (base channel, target L62): 24.4") and has("84.4% hit"),
    "Mind Flay binary application and full landed-tick partial mitigation both apply")
beforeResist = resistReads
periodicHover(14914, holyFire)
expect(has("Expected DPS (full effect, target L62, level only): 21.1") and resistReads == beforeResist,
    "Holy damage changes hit by level without reading resistance")

periodicHover(23881, bloodthirstText)
expect(has("DPS on landed hits (target L62, armor): 116.8 (20.0% crit, 25.0% armor reduction)")
    and armorReads == 1 and armorEffectReads == 1 and resistReads == beforeResist,
    "Bloodthirst uses effective armor, native fraction and no magic resistance or hit")
effectiveArmor = secret
hover()
expect(has("DPS on landed hits: 155.7") and armorEffectReads == 1, "restricted armor preserves the landed-only fallback")
effectiveArmor = 0
hover()
expect(has("DPS on landed hits: 155.7") and armorEffectReads == 1, "zero placeholder armor preserves the fallback")
effectiveArmor, armorEffect = 1000, 25
hover()
expect(has("DPS on landed hits: 155.7"), "percentage instead of native fraction is rejected")
armorEffect = secret
hover()
expect(has("DPS on landed hits: 155.7"), "restricted armor reduction is rejected")
armorEffect = 1
hover()
expect(has("DPS on landed hits (target L62, armor): 0.0"), "readable native full reduction can produce zero landed damage")

local readsBeforeExcluded = targetReads
periodicHover(2061, "Heals a friendly target for 194 to 238 health.")
expect(has("Expected HPS: 118.8") and targetReads == readsBeforeExcluded, "healing does not read target at all")
periodicHover(3044, "An instant shot that causes 25 Arcane damage.")
expect(has("+100 ranged attack power") and targetReads == readsBeforeExcluded, "scaling-only spell does not read target")
periodicHover(123, fireBlast)
expect(targetReads == readsBeforeExcluded, "unsupported spell does not read target")
command("import DT1;showExpectedThroughput=0")
periodicHover(2136, fireBlast)
expect(has("+100 Fire spell power") and targetReads == readsBeforeExcluded, "disabled expected output does not read target")
command("import DT1;showExpectedThroughput=1")
crit = secret
hover()
expect(not has("Expected DPS") and targetReads == readsBeforeExcluded, "unavailable core stats skip target reads")

for i = targetChatStart + 1, #chat do
    expect(not chat[i]:find("error (shown once)", 1, true), "target hook scenarios completed without caught errors")
end
local alpha4Assertions = assertions
local modifierChatStart = #chat
local activeConfig, stagedPurchases, stagedRefunds, stagedSwaps = 11, nil, nil, nil
local talentReads, playerAuraReads, targetAuraReads = 0, 0, 0
local traitNodes, curses = {}, {}
local combustion

local function committedNode(id, entry, rank)
    return { ID = id, activeRank = rank, currentRank = rank,
        activeEntry = { entryID = entry, rank = rank }, entryIDsWithCommittedRanks = { entry } }
end
C_ClassTalents = { GetActiveConfigID = function() talentReads = talentReads + 1; return activeConfig end }
C_Traits = {
    GetStagedChanges = function(config)
        assert(config == activeConfig)
        return stagedPurchases, stagedRefunds, stagedSwaps
    end,
    GetNodeInfo = function(config, node)
        assert(config == activeConfig)
        return traitNodes[node]
    end,
}
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id)
        assert(id == 28682)
        playerAuraReads = playerAuraReads + 1
        return combustion
    end,
    GetUnitAuraBySpellID = function(unit, id)
        assert(unit == "target" and (id == 440892 or id == 1311676 or id == 1311677 or id == 1311680))
        targetAuraReads = targetAuraReads + 1
        return curses[id]
    end,
}

targetExists, crit, hitRating, hitModifier = false, 20, 1, 1
command("import DT1;showExpectedThroughput=1;showPowerScaling=1")
local lightning = "Casts a bolt of lightning at the target for 100 Nature damage."
traitNodes[104760] = committedNode(104760, 129420, 1)
periodicHover(403, lightning)
expect(has("55.1 (98.0% hit, 25.0% crit)") and has("Modifiers: Call of Thunder") and has("DPS: 50.0"),
    "Call of Thunder contributes five points to Lightning Bolt without changing base output")
stagedPurchases, stagedRefunds, stagedSwaps = { 12345 }, {}, {}
hover()
expect(has("Call of Thunder"), "unrelated staged purchase preserves committed modifier")
stagedPurchases = { 104760 }
hover()
expect(has("53.9 (98.0% hit, 20.0% crit)") and not has("Modifiers:"), "relevant staged purchase fails closed")
stagedPurchases, stagedRefunds = {}, { 104760 }
hover()
expect(not has("Modifiers:"), "relevant staged refund fails closed")
stagedRefunds, stagedSwaps = {}, { 104760 }
hover()
expect(not has("Modifiers:"), "relevant staged selection swap fails closed")
stagedPurchases, stagedRefunds, stagedSwaps = { secret }, {}, {}
hover()
expect(not has("Modifiers:"), "restricted member in staged array fails closed")
stagedPurchases, stagedRefunds, stagedSwaps = {}, nil, {}
hover()
expect(not has("Modifiers:"), "partial staged response cannot certify committed state")
stagedPurchases, stagedRefunds, stagedSwaps = nil, nil, nil
local getStaged = C_Traits.GetStagedChanges
C_Traits.GetStagedChanges = function() error("staging unavailable") end
hover()
expect(not has("Modifiers:"), "throwing staged reader preserves base forecast")
C_Traits.GetStagedChanges = nil
hover()
expect(not has("Modifiers:"), "missing staged reader fails closed")
C_Traits.GetStagedChanges = getStaged
traitNodes[104760].entryIDsWithCommittedRanks = { 129372 }
hover()
expect(not has("Modifiers:"), "active but uncommitted entry is rejected")
traitNodes[104760] = committedNode(104760, 129420, 2)
hover()
expect(not has("Modifiers:"), "Call of Thunder rejects out-of-range rank")
traitNodes[104760].activeRank = secret
hover()
expect(not has("Modifiers:"), "restricted active rank is rejected")
traitNodes[104760], traitNodes[104712], activeConfig = nil, committedNode(104712, 129372, 1), 12
hover()
expect(has("Call of Thunder"), "alternate active config and verified node are read on the same clock")
activeConfig = secret
hover()
expect(not has("Modifiers:"), "restricted config ID is rejected")
activeConfig, crit = 12, 98
hover()
expect(has("100.0% crit") and has("Call of Thunder"), "spell-specific crit caps at 100")
crit = 100
hover()
expect(has("100.0% crit") and not has("Modifiers:"), "already capped crit adds no modifier label")
crit = 20

local beforeTalent = talentReads
periodicHover(5176, "Causes 100 Nature damage to the target.")
expect(not has("Modifiers:") and talentReads == beforeTalent, "unrelated Nature spell does not query traits")
traitNodes[104913] = committedNode(104913, 129573, 5)
local regrowthText = "Heals a friendly target for 90 to 110 and another 110 over 21 sec."
local beforeTargetAura = targetAuraReads
targetExists = true
periodicHover(8936, regrowthText)
expect(has("Expected HPS (full effect): 12.2 (70.0% direct crit, 20.0% tick crit)")
    and has("Modifiers: Improved Regrowth") and targetAuraReads == beforeTargetAura,
    "Improved Regrowth rank 5 changes direct crit only and never reads target aura")
traitNodes[104913] = committedNode(104913, 129573, 3)
hover()
expect(has("11.7 (50.0% direct crit, 20.0% tick crit)"), "Improved Regrowth rank 3 uses the exact curve point")
traitNodes[104913].activeEntry.rank = 4
hover()
expect(has("Expected HPS (full effect): 11.0 (20.0% crit)") and not has("Modifiers:"),
    "inconsistent active entry rank falls back")

targetExists = false
traitNodes[105883] = committedNode(105883, 130613, 5)
periodicHover(686, "Sends a shadowy bolt at the enemy, causing 100 Shadow damage.")
expect(has("58.8 (98.0% hit, 20.0% crit)") and has("Modifiers: Ruin"), "Ruin rank 5 doubles total crit damage")
traitNodes[105883] = committedNode(105883, 130613, 1)
hover()
expect(has("54.9 (98.0% hit, 20.0% crit)") and has("Modifiers: Ruin"), "Ruin rank 1 scales bonus only")

combustion = { spellId = 28682, isHelpful = true, duration = 0, expirationTime = 0, applications = 2 }
periodicHover(2136, fireBlast)
expect(has("58.8 (98.0% hit, 40.0% crit)") and has("Modifiers: Combustion x2"),
    "known indefinite Combustion aura uses its public zero-duration sentinel and two stacks")
combustion.applications = 10
hover()
expect(has("73.5 (98.0% hit, 100.0% crit)") and has("Combustion x10"), "ten stacks respect cap")
for _, stacks in ipairs({ 0, 11, 1.5, secret }) do
    combustion.applications = stacks
    hover()
    expect(has("53.9") and not has("Modifiers:"), "invalid or restricted stack leaves base estimate")
end
combustion.applications, combustion.duration = 2, secret
hover()
expect(not has("Modifiers:"), "indefinite sentinel requires readable duration")
combustion.duration, combustion.expirationTime = 5, now
hover()
expect(not has("Modifiers:"), "finite expired aura is rejected")
combustion.expirationTime, combustion.spellId = now + 5, 11129
hover()
expect(not has("Modifiers:"), "charge counter never masquerades as crit stack aura")
combustion.spellId, combustion.isHelpful = 28682, secret
hover()
expect(not has("Modifiers:"), "restricted aura type falls back")
combustion.isHelpful = true
hover()
expect(has("Combustion x2"), "readable active finite aura is accepted")
local beforePlayerAura = playerAuraReads
periodicHover(133, "Hurls a fiery ball that causes 100 Fire damage and an additional 20 Fire damage over 4 sec.")
expect(not has("Modifiers:") and playerAuraReads == beforePlayerAura, "other Fire spell does not query Combustion")
combustion = nil
periodicHover(2136, fireBlast)
expect(not has("Modifiers:"), "expired or removed aura has no stale stack state")

local function curseAura(id)
    return { spellId = id, isHarmful = true, expirationTime = now + 300, applications = 0 }
end
targetExists, liveTargetLevel, resist = true, 62, 70
curses[440892], curses[1311680] = curseAura(440892), curseAura(1311680)
hover()
expect(has("Expected DPS (target L62): 50.9") and has("Fire resist 70")
    and has("Modifiers: Curse of the Elements +10%") and not has("Elements +4%"),
    "strongest Curse adds damage taken once without subtracting resistance again")
curses[1311680] = secret
hover()
expect(has("48.2") and has("Elements +4%"), "strongest readable rank can be weaker than a protected aura")
curses[1311677] = curseAura(1311677)
resist = 0
hover()
expect(has("Expected DPS (target L62, level + aura): 57.0") and has("Elements +8%"),
    "resistance-unavailable target labels level plus active aura")
combustion = { spellId = 28682, isHelpful = true, duration = 0, expirationTime = 0, applications = 2 }
resist, curses[1311680] = 70, curseAura(1311680)
hover()
expect(has("Expected DPS (target L62): 55.6") and has("Modifiers: Combustion x2, Curse of the Elements +10%"),
    "crit chance and target damage-taken modifier combine once each")
curses[1311680].expirationTime, curses[1311677], curses[440892], combustion = 0, nil, nil, nil
hover()
expect(has("Expected DPS (target L62): 46.3") and not has("Modifiers:"), "Curse requires finite active expiry")
curses[1311680] = curseAura(1311680)
local beforeCurse = targetAuraReads
targetExists = false
hover()
expect(has("Expected DPS (equal-level PvE): 53.9") and targetAuraReads == beforeCurse and not has("Modifiers:"),
    "target clear cannot retain Curse and fallback never reads auras")
targetExists, liveTargetLevel = true, 64
hover()
expect(targetAuraReads == beforeCurse and not has("Modifiers:"), "unsupported level fallback skips target debuffs")
liveTargetLevel = 62
periodicHover(23881, bloodthirstText)
expect(targetAuraReads == beforeCurse and not has("Modifiers:"), "physical output never reads Curse")

local beforeDisabledTalent, beforeDisabledAura = talentReads, playerAuraReads
command("import DT1;showExpectedThroughput=0")
periodicHover(403, lightning)
periodicHover(2136, fireBlast)
expect(talentReads == beforeDisabledTalent and playerAuraReads == beforeDisabledAura and targetAuraReads == beforeCurse,
    "disabled expected output never reads talent or modifier auras")
for i = modifierChatStart + 1, #chat do
    expect(not chat[i]:find("error (shown once)", 1, true), "modifier hook scenarios completed without caught errors")
end

-- A deliberately small synthetic set exercises exclusions even when the
-- production evidence approves every model. Restore the production map
-- before testing the actual 70938 coverage.
local verified70938 = namespace.Verified70938
namespace.Verified70938 = { [2136] = true, [2061] = true, [172] = true, [116] = true, [686] = false, [123] = true }
local estimates = namespace.SpellEstimates
local directHealText = "Heals a friendly target for 194 to 238."
local corruptionText = "Corrupts the target, causing 120 Shadow damage over 12 sec."
local frostboltText = "Launches a bolt of frost at the enemy, causing 100 Frost damage."
local function check70938Output(id, text, scaling, expected)
    periodicHover(id, text)
    expect(has(scaling) and (not expected or has(expected)), "70938 shows the verified spell model for ID " .. id)
    if not expected then
        expect(not has("Expected DPS") and not has("Expected HPS"), "scaling-only spell does not get an expected rate")
    end
end
targetExists, buildNumber = false, "70938"
command("import DT1;showPowerScaling=1;showExpectedThroughput=1;includeDoT=1")
check70938Output(2136, fireBlast, "+100 Fire spell power", "Expected DPS")
check70938Output(2061, directHealText, "+100 healing power", "Expected HPS")
check70938Output(172, corruptionText, "/ tick", "Expected DPS (full effect")
check70938Output(116, frostboltText, "+100 Frost spell power")
expect(estimates.GetSpellModel(686) == nil, "70938 rejects an unapproved legacy model")
expect(estimates.GetSpellModel(123) == nil, "allowlist cannot create a spell model")
expect(estimates.GetSpellModel(secret) == nil and estimates.GetSpellModel(1.5) == nil,
    "model lookup rejects secret and fractional spell IDs")

command("export")
local exported = chat[#chat]
local statusStart = #chat
command("status")
expect(chatContains(statusStart, "version 1.60.1, build 70938, Interface 16001"), "status prints the exact build")
expect(chatContains(statusStart, "enabled for 7 verified spell IDs"),
    "status counts only enabled legacy IDs plus the three build-specific ranks")
expect(chatContains(statusStart, "power scaling |cff00ff00on|r, expected DPS/HPS |cff00ff00on|r"),
    "status reports saved option flags")
command("export")
expect(chat[#chat] == exported, "status does not change settings")

buildNumber = "70939"
periodicHover(2136, fireBlast)
expect(has("DPS:") and not has("+100") and not has("Expected DPS"), "unknown build preserves baseline only")
statusStart = #chat
command("status")
expect(chatContains(statusStart, "disabled on this unverified client build"), "status distinguishes unknown build")
buildNumber, buildInterface = 70938, 16002
expect(estimates.GetSpellModel(2136) == nil, "legacy numeric build with wrong interface is rejected")
buildVersion, buildInterface = "1.60.2", 16001
expect(estimates.GetSpellModel(2136) == nil, "matching build with wrong client version is rejected")
buildVersion, buildNumber = "1.60.1", secret
statusStart = #chat
command("status")
expect(chatContains(statusStart, "build unavailable") and chatContains(statusStart, "information is unavailable"),
    "status handles restricted build without formatting it")
local getBuild = GetBuildInfo
GetBuildInfo = function() error("test build reader fault") end
expect(estimates.GetSpellModel(2136) == nil, "build read error disables model")
GetBuildInfo = getBuild

namespace.Verified70938, buildNumber = verified70938, 70938
local productionStatus, _, _, _, productionCount = estimates.GetModelBuildStatus()
expect(productionStatus == "verified" and productionCount == 212,
    "70938 includes the 209 legacy ranks and three build-specific ranks")
check70938Output(2136, fireBlast, "+100 Fire spell power", "Expected DPS")
check70938Output(2061, directHealText, "+100 healing power", "Expected HPS")
check70938Output(172, corruptionText, "/ tick", "Expected DPS (full effect")
check70938Output(3044, "An instant shot that causes 100 Arcane damage.", "+100 ranged attack power")
for id, model in pairs(namespace.SpellPowerModels) do
    expect(estimates.GetSpellModel(id) == ((verified70938 and verified70938[id] == true) and model or nil),
        "production 70938 gate matches its explicit coverage for ID " .. id)
end
buildNumber = "70888"
for id, model in pairs(namespace.SpellPowerModels) do
    expect(estimates.GetSpellModel(id) == model, "70888 retains its original model for ID " .. id)
end

-- Only typed spell-description rows may stand in for an empty description.
spellID, description, dataOverride = 2136, "", { lines = {
    { type = 13, leftText = "Blasts the target for 999 Fire damage." },
    { type = 34, leftText = fireBlast },
} }
now = now + 2
hover()
expect(has("DPS: 50.0") and has("Expected DPS"), "typed fallback ignores title and reads spell description")
dataOverride = { lines = {
    { type = 13, leftText = "Blasts the target for 999 Fire damage." },
    { type = 0, leftText = "Instant cast and 100 Mana" },
} }
now = now + 2
hover()
expect(not has("DPS:") and not has("Expected DPS"), "name and cost rows are not spell descriptions")
dataOverride = { lines = {
    { type = 34, leftText = fireBlast },
    { type = 34, leftText = secret },
} }
now = now + 2
hover()
expect(not has("DPS:") and not has("Expected DPS"), "partly secret fallback does not parse a partial spell")

-- Invalid input must leave both the saved state and the visible button alone.
command("import DT1;showMinimap=1;minimapAngle=90;spellRules=234:1e-9;futureFlag=kept-by-newer-client")
expect(DamageTipsDB.spellRules["234"] == 1e-9 and minimapButton:IsShown(),
    "valid partial import preserves finite exponent values and ignores future keys")
command("export")
local settingsBefore = chat[#chat]
local priorAnchor = minimapButton.point
for _, bad in ipairs({
    "malformed;showMinimap=0", "showMinimap=0;showMinimap=1",
    "showMinimap=0;;showDPS=1", "minimapAngle=1e999;showMinimap=0",
    "minimapAngle=invalid;showMinimap=0", "fontSize=21;showMinimap=0",
    "damageColor=12345;showMinimap=0", "manaMode=9;showMinimap=0",
    "spellRules=234:1e999;showMinimap=0", "spellRules=234:-1;showMinimap=0",
    "spellRules=0:hide;showMinimap=0", "spellRules=234:hide,0234:12;showMinimap=0",
    "spellRules=234:hide,,567:0;showMinimap=0",
}) do
    command("import DT1;" .. bad)
    expect(chat[#chat]:find("import failed", 1, true), "invalid DT1 is rejected: " .. bad)
    command("export")
    expect(chat[#chat] == settingsBefore and minimapButton:IsShown() and minimapButton.point == priorAnchor,
        "failed import preserves settings and minimap anchor: " .. bad)
end
command("import " .. settingsBefore)
expect(DamageTipsDB.spellRules["234"] == 1e-9 and minimapButton:IsShown(), "full DT1 export re-imports")
command("import DT1;")
expect(chat[#chat]:find("settings imported", 1, true) and DamageTipsDB.spellRules["234"] == 1e-9,
    "legacy DT1 no-op remains compatible")

local importBox
for _, child in ipairs(config.panels.adv.children) do
    if child.kind == "EditBox" then importBox = child end
end
assert(importBox and importBox.scripts.OnEnterPressed)
local invalidPanelImport = "DT1;showMinimap=0;fontSize=bad"
importBox:SetText(invalidPanelImport)
importBox.scripts.OnEnterPressed(importBox)
expect(minimapButton:IsShown() and importBox:GetText() == invalidPanelImport,
    "failed panel import leaves settings and the typed input intact")
importBox:SetText("DT1;showMinimap=0;minimapAngle=180")
importBox.scripts.OnEnterPressed(importBox)
expect(not minimapButton:IsShown() and DamageTipsDB.minimapAngle == 180 and importBox:GetText() == "",
    "panel import uses the same validated commit")
local resetButton
for _, child in ipairs(config.children) do
    if child.kind == "Button" and child.text and child.text:find("Reset", 1, true) then resetButton = child end
end
assert(resetButton and resetButton.scripts.OnClick)
resetButton.scripts.OnClick(resetButton)
expect(minimapButton:IsShown() and minimapButton.point[4] < -79 and DamageTipsDB.spellRules["234"] == 1e-9,
    "panel reset also syncs the minimap and preserves spell rules")

local function countMatches(s)
    local count = 0
    for _, line in ipairs(tooltipLines) do
        if line:find(s, 1, true) then count = count + 1 end
    end
    return count
end
command("import DT1;showMana=0;showHealing=1;shiftDetails=1;includeDoT=1")
dataOverride, castTime, cooldown, gcd = nil, 2000, 0, 1500
spellID, description = 8936, "Heals a friendly target for 90 to 110 and another 110 over 21 sec."
hover()
expect(has("HPS:") and has("Hold Shift") and not has("Healing over time"), "healing-only tooltip offers Shift details")
shiftDown = true
hover()
expect(has("Direct healing:") and has("Healing over time: 110") and has("Healing divisor: 21.00") and not has("Hold Shift")
    and not has("Healing: 210"), "mixed healing details distinguish direct healing and HoT without repeating the total")
command("import DT1;includeDoT=0")
hover()
expect(has("HPS: 50.0") and not has("Healing over time") and has("Healing divisor: 2.00"),
    "Shift breakdown excludes disabled periodic healing")
command("import DT1;includeDoT=1")
spellID, description = 8921, "Burns the enemy for 100 Arcane damage and then an additional 80 Arcane damage over 9 sec."
hover()
expect(has("Direct damage: 100") and has("Damage over time: 80") and not has("Damage: 180"),
    "mixed damage details do not repeat the full spell total")
spellID, description = 17, "Draws on the soul of the party member to shield them, absorbing 174 damage. Lasts 30 sec."
hover()
expect(has("Absorbs: 174") and has("Absorb per cast: 174") and not has("DPS:"), "absorb-only tooltip has Shift details")
command("hide 17")
hover()
expect(#tooltipLines == 0, "hidden spell has no Shift details")
command("show 17")
command("import DT1;showHealing=0")
hover()
expect(#tooltipLines == 0, "disabled healing suppresses absorb details")
command("import DT1;showHealing=1;shiftDetails=0")
hover()
expect(has("Absorbs: 174") and countMatches("174") == 1, "disabled Shift details leave the standard absorb line")

realPrint(string.format("DamageTips Forever estimate mocks passed (%d assertions, including %d prior, %d alpha.3, %d alpha.2 and %d original).",
    assertions, alpha4Assertions, alpha3Assertions, alpha2Assertions, previousAssertions))
