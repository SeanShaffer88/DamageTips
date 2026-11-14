-- DamageTips component-parser regressions. Run with the addon path as arg[1].
local addonPath = assert(arg[1], "provide addon directory")
local checks = 0
local function expect(condition, message)
    assert(condition, message)
    checks = checks + 1
end
local function loadModels(locale)
    GetLocale = function() return locale end
    local private = {}
    for _, file in ipairs({ "SpellPowerModels", "SpellModifiers", "SpellEstimates" }) do
        assert(loadfile(addonPath .. "/" .. file .. ".lua"))("DamageTips", private)
    end
    return private.SpellEstimates.ParseComponents, private.SpellPowerModels, private.SpellEstimates.ResolveExpectedAmount
end

local parse, models, resolveExpectedAmount = loadModels("enUS")
local t = parse("Heals a friendly target for 194–238.", models[2061], true)
expect(t.healing.direct == 216 and t.expectedAmount == 216 and not t.damage,
    "Flash Heal dashes and bare health amount produce the same base and model components")
t = parse("Heals a friendly target for 90—110 and another 110 over 21 sec.", models[8936], true)
expect(t.healing.direct == 100 and t.healing.low == 90 and t.healing.high == 110
    and t.healing.periodic == 110 and t.healing.duration == 21 and t.expectedAmount == 100,
    "Regrowth exposes independent direct and periodic healing with the correct units")
t = parse("Heals the target of 150 damage over 15 sec.", nil, false)
expect(t.healing.periodic == 150 and not t.damage, "Renew wording does not become damage on an unknown build")
t = parse("Draws on the soul of the party member to shield them, absorbing 174 damage. Lasts 30 sec.", nil, false)
expect(t.absorb == 174 and not t.damage, "stock shield wording does not become damage")
t = parse("Launches arcane missiles at the enemy, causing 30 Arcane damage each second for 3 sec.", models[5143], true)
expect(t.damage.direct == 0 and t.damage.periodic == 90 and t.damage.duration == 3
    and t.effect.ticks == 3 and t.expectedAmount == 0, "missile amount is per projectile and counted once per tick")
t = parse("Launches arcane missiles at the enemy, causing 30 Arcane damage every 2 sec for 4 sec.", models[5144], true)
expect(t.damage.periodic == 60 and not t.effect and not t.expectedAmount,
    "mismatched verified interval keeps independently readable baseline but suppresses the model")

for _, amount in ipairs({ "1,2", "12,34,567", "1.5", "20 to 10" }) do
    t = parse("Blasts the enemy for " .. amount .. " Fire damage.", models[2136], true)
    expect(not t.damage and not t.expectedAmount, "malformed amount must not leak a shorter numeric match: " .. amount)
end
t = parse("Causes 1,234 to 2,345 Arcane damage to the target.", models[2912], true)
expect(t.damage.low == 1234 and t.damage.high == 2345 and t.expectedAmount == 1789.5,
    "all valid groups survive without ambiguity")
t = parse("Heals the target for 100 health every 2 sec.", models[2061], true)
expect(not t.healing and not t.expectedAmount, "unresolved healing per tick must not be a direct heal")
t = parse("Blasts the enemy for 180 Fire damage every 2 sec.", models[2136], true)
expect(not t.damage and not t.expectedAmount, "unresolved damage per tick must not be a direct hit")
t = parse("Empowers an ally for 999 Fire damage on their next attack. Blasts for 180 Fire damage.", models[2136], true)
expect(not t.expectedAmount, "a recognized direct-model sentence cannot apply crit and hit to a different amount")
t = parse("Blasts the enemy for 999 Fire damage, then causes 180 Fire damage to the target.", models[2136], true)
expect(not t.expectedAmount, "mismatched direct-model sentence within one clause must fail closed")
t = parse("Blasts the enemy for 180 Fire damage. Heals the target for 1,2 over 12 sec.", models[2136], true)
expect(t.damage.direct == 180 and not t.expectedAmount,
    "malformed periodic clause still excludes a direct-only forecast")

local originalAttackPower = UnitAttackPower
local reads = 0
UnitAttackPower = function()
    reads = reads + 1
    return 500, 0, 0
end
local bloodthirst = "Instantly attack the target causing damage equal to 45% of your Attack Power plus 30."
t = parse(bloodthirst, models[23881], false)
expect(reads == 0 and not t.expectedAmount and not t.attackPowerBase, "baseline parsing does not query attack power")
t = parse(bloodthirst, models[23881], true)
expect(reads == 0 and t.attackPowerBase == 30 and not t.expectedAmount,
    "exact Bloodthirst AP formula parsing does not query attack power")
expect(resolveExpectedAmount(t, models[23881]) == 255 and reads == 1,
    "Bloodthirst applies live AP only when resolving the expected amount")
UnitAttackPower = originalAttackPower

local localized = loadModels("deDE")
t = localized("Blasts the enemy for 180 Fire damage.", models[2136], true)
expect(t.status == "unsupported" and not t.damage and not t.expectedAmount,
    "unsupported locales never reinterpret ambiguous translated descriptions")

print("DamageTips description component mocks passed (" .. checks .. " assertions).")
