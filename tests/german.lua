-- Original synthetic German fixtures; these are not captured client tooltips.
local root = assert(arg[1])
GetLocale = function() return "deDE" end
local private = {}
for _, name in ipairs({ "SpellPowerModels", "SpellModifiers", "SpellEstimates" }) do
    assert(loadfile(root .. "/" .. name .. ".lua"))("DamageTips", private)
end
local e, m = private.SpellEstimates, private.SpellPowerModels
local count = 0
local function check(value, message) assert(value, message); count = count + 1 end
local function parse(text, model) return e.ParseComponents(text, model, true) end
check(e.ReadSpellRank("Rang 12") == 12, "German rank")
check(e.ReadSpellRank("Rank 12") == nil and e.ReadSpellRank("Rang 2x") == nil, "rank fails closed")
local t = parse("Verursacht 1.234,5 bis 2.345,5 Feuerschaden.", m[2136])
check(t.damage.low == 1234.5 and t.damage.high == 2345.5 and t.expectedAmount == 1790, "German grouped decimal range")
t = parse("Heilt ein verbündetes Ziel um 90–110 Gesundheit.", m[2061])
check(t.healing.direct == 100 and t.expectedAmount == 100, "direct healing")
t = parse("Verursacht 1\194\160234 Feuerschaden.", m[2136])
check(t.damage.direct == 1234, "Unicode numeric grouping")
t = parse("Verursacht im Verlauf von 12 Sek. insgesamt 120 Schattenschaden.", m[172])
check(t.damage.periodic == 120 and t.effect.ticks == 4, "periodic schedule")
t = parse("Verursacht alle 1 Sek. 30 Arkanschaden. Hält 3 Sek. lang an.", m[5143])
check(t.damage.periodic == 90 and t.effect.ticks == 3, "channel amount counted once")
t = parse("Heilt ein verbündetes Ziel um 90 bis 110 Gesundheit und im Verlauf von 21 Sek. um weitere 140 Gesundheit.", m[8936])
check(t.healing.direct == 100 and t.healing.periodic == 140 and t.effect, "mixed heal")
t = parse("Verursacht 90 bis 110 Feuerschaden und im Verlauf von 4 Sek. zusätzlich 20 Feuerschaden.", m[133])
check(t.damage.direct == 100 and t.damage.periodic == 20 and t.effect, "mixed damage")
t = parse("Absorbiert 500 Schaden.")
check(t.absorb == 500 and not t.damage, "absorb")
for _, value in ipairs({ "12.34", "1,2,3", "20 bis 10", "-5", "1.0000" }) do
    check(parse("Verursacht " .. value .. " Feuerschaden.", m[2136]).status == "unsupported", "malformed amount " .. value)
end
check(parse("Verursacht 100 Feuerschaden. Unbekannte zusätzliche Wirkung.", m[2136]).status == "unsupported", "unknown clause")
t = parse("Verursacht im Verlauf von 9 Sek. insgesamt 120 Schattenschaden.", m[172])
check(t.damage and not t.effect and not t.expectedAmount, "schedule mismatch baseline only")
t = parse("Verursacht 100 Feuerschaden.")
check(t.damage and not t.expectedAmount, "unknown model baseline only")
check(parse("Deals 100 Fire damage.", m[2136]).status == "unsupported", "wrong grammar")
print("German parser: " .. count .. " assertions passed")
