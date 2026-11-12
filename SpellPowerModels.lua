-- DamageTips Forever spell data (GPL-3.0-or-later, see LICENSE.txt).
-- Nominal coefficients verified for 1.60.1.70888. See CREDITS.txt for sources.
local _, addon = ...
local models = {}
addon.SpellPowerModels = models

local function AddRanks(model, ...)
    for _, spellID in ipairs({ ... }) do
        models[spellID] = model
    end
end

local function Damage(school, coefficient, expected)
    return { school = school, spellPower = coefficient, expected = expected }
end

local function Healing(coefficient)
    return { healingPower = coefficient, expected = "healing" }
end

-- Fire Blast
AddRanks(Damage("fire", 0.429, "spell"), 2136, 2137, 2138, 8412, 8413, 10197, 10199)
-- Lightning Bolt
AddRanks(Damage("nature", 0.429, "spell"), 403)
AddRanks(Damage("nature", 0.571, "spell"), 529)
AddRanks(Damage("nature", 0.714, "spell"), 548, 915, 943, 6041, 10391, 10392, 15207, 15208)
-- Shadow Bolt
AddRanks(Damage("shadow", 0.486, "spell"), 686)
AddRanks(Damage("shadow", 0.629, "spell"), 695)
AddRanks(Damage("shadow", 0.800, "spell"), 705)
AddRanks(Damage("shadow", 0.857, "spell"), 1088, 1106, 7641, 11659, 11660, 11661, 25307)
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
