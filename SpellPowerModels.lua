-- DamageTips Forever spell data (GPL-3.0-or-later, see LICENSE.txt).
-- Nominal coefficients are based on 1.60.1.70888. The 70938 allowlist is verified separately.
local _, addon = ...
local models = {}
addon.SpellPowerModels = models

local function AddRanks(model, ...)
    for _, spellID in ipairs({ ... }) do
        models[spellID] = model
    end
end

local function Damage(school, coefficient, expected, modifier)
    return { school = school, spellPower = coefficient, expected = expected, critModifier = modifier }
end

local function Healing(coefficient)
    return { healingPower = coefficient, expected = "healing" }
end

-- Fire Blast
AddRanks(Damage("fire", 0.429, "spell", "combustion"), 2136, 2137, 2138, 8412, 8413, 10197, 10199)
-- Lightning Bolt
AddRanks(Damage("nature", 0.429, "spell", "callOfThunder"), 403)
AddRanks(Damage("nature", 0.571, "spell", "callOfThunder"), 529)
AddRanks(Damage("nature", 0.714, "spell", "callOfThunder"), 548, 915, 943, 6041, 10391, 10392, 15207, 15208)
-- Shadow Bolt
AddRanks(Damage("shadow", 0.486, "spell", "ruin"), 686)
AddRanks(Damage("shadow", 0.629, "spell", "ruin"), 695)
AddRanks(Damage("shadow", 0.800, "spell", "ruin"), 705)
AddRanks(Damage("shadow", 0.857, "spell", "ruin"), 1088, 1106, 7641, 11659, 11660, 11661, 25307)
-- Wrath and Starfire
AddRanks(Damage("nature", 0.429, "spell"), 5176)
AddRanks(Damage("nature", 0.486, "spell"), 5177)
AddRanks(Damage("nature", 0.571, "spell"), 5178, 5179, 5180, 6780, 8905, 9912)
AddRanks(Damage("arcane", 1, "spell"), 2912, 8949, 8950, 8951, 9875, 9876, 25298)
-- Frostbolt has a binary resist component. Only show scaling.
AddRanks(Damage("frost", 0.407), 116)
AddRanks(Damage("frost", 0.489), 205)
AddRanks(Damage("frost", 0.597), 837)
AddRanks(Damage("frost", 0.706), 7322)
AddRanks(Damage("frost", 0.814), 8406, 8407, 8408, 10179, 10180, 10181, 25304)
-- Flash Heal, Heal and Greater Heal
AddRanks(Healing(0.429), 2061, 9472, 9473, 9474, 10915, 10916, 10917)
AddRanks(Healing(0.857), 2054, 2055, 6063, 6064, 2060, 10963, 10964, 10965, 25314)
-- Healing Touch and Healing Wave
AddRanks(Healing(0.429), 5185, 331)
AddRanks(Healing(0.571), 5186, 332)
AddRanks(Healing(0.714), 5187, 547)
AddRanks(Healing(0.857), 5188, 913, 939, 959, 8005, 10395, 10396, 25357)
AddRanks(Healing(1), 5189, 6778, 8903, 9758, 9888, 9889, 25297)
-- Hammer of Wrath (this exact hybrid variant), Bloodthirst and Arcane Shot.
AddRanks({ school = "holy", spellPower = 0.150, attackPower = 0.150 }, 429151)
AddRanks({ attackPower = 0.450, expected = "landed" }, 23881, 23892, 23893, 23894)
AddRanks({ rangedPower = 0.150 }, 3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287)

local function Periodic(grammar, school, ticks, interval, coefficient, options)
    options = options or {}
    local healing = school == nil
    local model = {
        school = school,
        expected = healing and "healing" or "spell",
        critModifier = options.critModifier,
        periodic = {
            grammar = grammar, ticks = ticks, interval = interval, duration = ticks * interval,
            coefficient = coefficient, tickCrit = options.tickCrit ~= false,
            directCrit = options.directCrit == true,
            hitMode = options.hitMode or (healing and "none" or "application"),
            channel = options.channel, ranged = options.ranged,
            binaryApplication = options.binaryApplication, perRecipient = options.perRecipient,
        },
    }
    if healing then
        model.healingPower = options.directPower
    else
        model.spellPower = options.directPower
    end
    if options.ranged then model.expected = nil end
    return model
end

-- Standard ranked auras use their effect period and SpellDuration.
AddRanks(Periodic("corruption", "shadow", 4, 3, 0.200), 172)
AddRanks(Periodic("corruption", "shadow", 5, 3, 0.200), 6222)
AddRanks(Periodic("corruption", "shadow", 6, 3, 0.200), 6223, 7648, 11671, 11672, 25311)
AddRanks(Periodic("pain", "shadow", 6, 3, 0.200), 589, 594, 970, 992, 2767, 10892, 10893, 10894)
AddRanks(Periodic("rejuvenation", nil, 4, 3, 0.200), 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299)
AddRanks(Periodic("renew", nil, 5, 3, 0.200), 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315)
AddRanks(Periodic("regrowth", nil, 7, 3, 0.071, { directPower = 0.286, directCrit = true, critModifier = "regrowth" }),
    8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858)
local moonfire = { directPower = 0.150, directCrit = true }
AddRanks(Periodic("burn", "arcane", 3, 3, 0.130, moonfire), 8921)
AddRanks(Periodic("burn", "arcane", 4, 3, 0.130, moonfire), 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835)
AddRanks(Periodic("burn", "fire", 5, 3, 0.130, { directPower = 0.200, directCrit = true }),
    348, 707, 1094, 2941, 11665, 11667, 11668, 25309)
AddRanks(Periodic("holyFire", "holy", 5, 2, 0.050, { directPower = 0.750, directCrit = true }),
    14914, 15262, 15263, 15264, 15265, 15266, 15267, 15261)
AddRanks(Periodic("fireball", "fire", 2, 2, 0, { directPower = 0.429, directCrit = true }), 133)
AddRanks(Periodic("fireball", "fire", 3, 2, 0, { directPower = 0.571, directCrit = true }), 143)
AddRanks(Periodic("fireball", "fire", 3, 2, 0, { directPower = 0.714, directCrit = true }), 145)
AddRanks(Periodic("fireball", "fire", 4, 2, 0, { directPower = 0.857, directCrit = true }), 3140)
AddRanks(Periodic("fireball", "fire", 4, 2, 0, { directPower = 1, directCrit = true }),
    8400, 8401, 8402, 10148, 10149, 10150, 10151, 25306)
AddRanks(Periodic("serpentSting", "nature", 5, 3, 0.050, { ranged = true, hitMode = "ranged" }),
    1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295)

-- Arcane Missiles uses the triggered missile's coefficient and hit per missile.
local missiles = { channel = "full", hitMode = "tick" }
AddRanks(Periodic("missiles", "arcane", 3, 1, 0.286, missiles), 5143)
AddRanks(Periodic("missiles", "arcane", 4, 1, 0.286, missiles), 5144)
AddRanks(Periodic("missiles", "arcane", 5, 1, 0.286, missiles), 5145, 8416, 8417, 10211, 10212, 25345)
-- Mind Flay has one application hit. The base channel excludes talent ramp.
AddRanks(Periodic("mindFlay", "shadow", 3, 1, 0.167, { channel = "base", binaryApplication = true }),
    15407, 17311, 17312, 17313, 17314, 18807)

-- 70938 uses 6.6% healing power on the periodic effect; 70888 uses 3.3%.
-- Wild Growth is front-loaded, so only display nominal full-effect scaling.
local wildGrowth = Periodic("wildGrowth", nil, 7, 1, 0.066, { perRecipient = true })
-- The Chain Heal bonus is a separate effect and is not part of Riptide healing.
local riptide = Periodic("riptide", nil, 5, 3, 0.100, { tickCrit = true })
addon.SpellPowerModels70938 = {
    [408120] = wildGrowth, [1238214] = wildGrowth, [1238215] = wildGrowth,
    [408521] = riptide, [1239242] = riptide, [1239243] = riptide,
}

-- BEGIN GENERATED 70938 ALLOWLIST
-- Reproduce with tools/validate_forever_models.py. See docs/forever-70938-validation.md.
local verified70938 = {}
for _, spellID in ipairs({
    116, 133, 139, 143, 145, 172, 205, 331, 332, 348, 403, 529,
    547, 548, 589, 594, 686, 695, 705, 707, 774, 837, 913, 915,
    939, 943, 959, 970, 992, 1058, 1088, 1094, 1106, 1430, 1978, 2054,
    2055, 2060, 2061, 2090, 2091, 2136, 2137, 2138, 2767, 2912, 2941, 3044,
    3140, 3627, 5143, 5144, 5145, 5176, 5177, 5178, 5179, 5180, 5185, 5186,
    5187, 5188, 5189, 6041, 6063, 6064, 6074, 6075, 6076, 6077, 6078, 6222,
    6223, 6778, 6780, 7322, 7641, 7648, 8005, 8400, 8401, 8402, 8406, 8407,
    8408, 8412, 8413, 8416, 8417, 8903, 8905, 8910, 8921, 8924, 8925, 8926,
    8927, 8928, 8929, 8936, 8938, 8939, 8940, 8941, 8949, 8950, 8951, 9472,
    9473, 9474, 9750, 9758, 9833, 9834, 9835, 9839, 9840, 9841, 9856, 9857,
    9858, 9875, 9876, 9888, 9889, 9912, 10148, 10149, 10150, 10151, 10179, 10180,
    10181, 10197, 10199, 10211, 10212, 10391, 10392, 10395, 10396, 10892, 10893, 10894,
    10915, 10916, 10917, 10927, 10928, 10929, 10963, 10964, 10965, 11659, 11660, 11661,
    11665, 11667, 11668, 11671, 11672, 13549, 13550, 13551, 13552, 13553, 13554, 13555,
    14281, 14282, 14283, 14284, 14285, 14286, 14287, 14914, 15207, 15208, 15261, 15262,
    15263, 15264, 15265, 15266, 15267, 15407, 17311, 17312, 17313, 17314, 18807, 23881,
    23892, 23893, 23894, 25295, 25297, 25298, 25299, 25304, 25306, 25307, 25309, 25311,
    25314, 25315, 25345, 25357, 429151,
}) do
    verified70938[spellID] = true
end
addon.Verified70938 = verified70938
-- END GENERATED 70938 ALLOWLIST
