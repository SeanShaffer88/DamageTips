#!/usr/bin/env python3
"""Verify 70938 DamageTips model inputs against the approved 70888 exports.

Supply the same Wago Tools DB2 CSV tables for each exact build. This tool does
not download data or edit Lua. --emit-lua prints the reviewed allowlist block.
"""

import argparse
import csv
import hashlib
import re
import subprocess
from collections import defaultdict
from pathlib import Path

MODEL_PATH = Path(__file__).resolve().parents[1] / "SpellPowerModels.lua"
MARKER = "-- BEGIN GENERATED 70938 ALLOWLIST"
END_MARKER = "-- END GENERATED 70938 ALLOWLIST"
TABLE_KEYS = {
    "Spell": "ID",
    "SpellName": "ID",
    "SpellEffect": "SpellID",
    "SpellMisc": "SpellID",
    "SpellClassOptions": "SpellID",
    "SpellLevels": "SpellID",
    "SpellCategories": "SpellID",
    "SpellAuraOptions": "SpellID",
    "SpellCooldowns": "SpellID",
    "SpellPower": "SpellID",
    "SpellShapeshift": "SpellID",
    "SpellXSpellVisual": "SpellID",
    "SpellXDescriptionVariables": "SpellID",
    "SpellCastTimes": "ID",
    "SpellDuration": "ID",
    "SpellRange": "ID",
    "SpellDescriptionVariables": "ID",
    "TraitDefinition": "ID",
    "TraitDefinitionEffectPoints": "TraitDefinitionID",
    "TraitNode": "ID",
    "TraitNodeEntry": "ID",
    "TraitNodeXTraitNodeEntry": "TraitNodeID",
    "CurvePoint": "CurveID",
}
SPELL_TABLES = tuple(TABLE_KEYS)[:13]
REQUIRED_ROWS = ("Spell", "SpellName", "SpellEffect", "SpellMisc")
ARCANE_SHOT = {3044: 25, 14281: 35, 14282: 50, 14283: 80, 14284: 105, 14285: 135, 14286: 160, 14287: 190}
SERPENT_STING = {1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295}
BLOODTHIRST = {23881, 23892, 23893, 23894}
# These unused tooltip predicate IDs occur on both builds, with no spell records.
CONDITIONAL_ONLY_IDS = {12952, 12953}
CURSES = (440892, 1311676, 1311677, 1311680)
MODIFIER_SPELLS = {
    "callOfThunder": (16120,),
    "regrowth": (17074,),
    "ruin": (17959,),
    "combustion": (11129, 28682),
}
MODIFIER_TRAITS = {
    "callOfThunder": ((16120, 104760, 129420), (16120, 104712, 129372)),
    "regrowth": ((17074, 104913, 129573),),
    "ruin": ((17959, 105883, 130613),),
}
SCHOOL_MASKS = {"holy": 2, "fire": 4, "nature": 8, "frost": 16, "shadow": 32, "arcane": 64}
DESCRIPTION_REFERENCE = re.compile(r"\$(?:\?[as])?(\d{3,})(?=[A-Za-z]|\[)")

LUA_MODEL_PROBE = """
local addon = {}
assert(loadfile(arg[1]))("DamageTips", addon)
for id, model in pairs(addon.SpellPowerModels) do
    local tick = model.periodic or {}
    local fields = {id, model.expected or "",
        model.critModifier or "", model.school or "", model.spellPower or "", model.healingPower or "",
        model.attackPower or "", model.rangedPower or "", tick.grammar or "",
        tick.ticks or "", tick.interval or "", tick.coefficient or ""}
    for index = 1, #fields do fields[index] = tostring(fields[index]) end
    print(table.concat(fields, ","))
end
"""


def load_models(lua):
    result = subprocess.run(
        [lua, "-", str(MODEL_PATH)],
        input=LUA_MODEL_PROBE, text=True, capture_output=True, check=True,
    )
    columns = ("expected", "modifier", "school", "spell_power", "healing_power",
               "attack_power", "ranged_power", "grammar", "ticks", "interval", "tick_power")
    models = {}
    for line in result.stdout.splitlines():
        spell, *values = line.split(",")
        models[int(spell)] = dict(zip(columns, values, strict=True))
    if not models:
        raise ValueError("No DamageTips models were loaded")
    return models


class ClientData:
    def __init__(self, directory):
        self.rows = {}
        self.headers = {}
        self.hashes = {}
        for table, key in TABLE_KEYS.items():
            path = directory / f"{table}.csv"
            self.hashes[table] = hashlib.sha256(path.read_bytes()).hexdigest()
            index = defaultdict(dict)
            seen = set()
            with path.open(encoding="utf-8-sig", newline="") as source:
                reader = csv.DictReader(source)
                if not reader.fieldnames or not {key, "ID"} <= set(reader.fieldnames):
                    raise ValueError(f"{path}: missing {key} or ID column")
                self.headers[table] = set(reader.fieldnames)
                for row in reader:
                    row_id = int(row["ID"])
                    if row_id in seen:
                        raise ValueError(f"{path}: duplicate row ID {row_id}")
                    seen.add(row_id)
                    index[int(row[key])][row_id] = row
            if not index:
                raise ValueError(f"{path}: empty CSV")
            self.rows[table] = index

    def get(self, table, key):
        return self.rows[table].get(key, {})


def allow_arcane_shot_cost(spell, before, after):
    """Arcane Shot's approved 15% RAP line does not use the mana cost."""
    if spell not in ARCANE_SHOT or before.keys() != after.keys() or len(before) != 1:
        return False
    old, = before.values()
    new, = after.values()
    changed = {key for key in old if old[key] != new[key]}
    return (changed == {"ManaCost", "PowerCostPct"}
            and old["ManaCost"] == str(ARCANE_SHOT[spell]) and old["PowerCostPct"] == "0"
            and new["ManaCost"] == "0" and new["PowerCostPct"] == "11")


def validate_model(data, spell, model):
    """Independently check the hardcoded coefficient and schedule inputs."""
    effects = [row for row in data.get("SpellEffect", spell).values() if row["DifficultyID"] == "0"]
    metadata = [row for row in data.get("SpellMisc", spell).values() if row["DifficultyID"] == "0"]
    if len(metadata) != 1:
        return "missing or ambiguous base SpellMisc row"
    metadata, = metadata
    if model["school"] and SCHOOL_MASKS[model["school"]] != int(metadata["SchoolMask"]):
        return "damage school differs from model"
    direct = [row for row in effects if row["Effect"] in {"2", "10"}]
    for coefficient, kind, column in (
        (model["spell_power"], "2", "EffectBonusCoefficient"),
        (model["healing_power"], "10", "EffectBonusCoefficient"),
        (model["attack_power"], "2", "BonusCoefficientFromAP"),
    ):
        if not coefficient:
            continue
        matching = [row for row in direct if row["Effect"] == kind]
        if len(matching) != 1:
            return f"missing or ambiguous direct effect {kind}"
        effect, = matching
        if spell in BLOODTHIRST:
            formula = data.get("Spell", spell)[spell]["Description_lang"]
            if (int(effect["EffectIndex"]) != 0 or "damage equal to $s2% of your Attack Power plus $s1" not in formula
                    or not any(row["EffectIndex"] == "1" and float(row["EffectBasePointsF"]) == float(coefficient) * 100
                               for row in effects)):
                return "Bloodthirst tooltip AP formula differs from model"
        elif round(float(effect[column]), 3) != float(coefficient):
            return f"{column} differs from model"
    if model["ranged_power"] and (spell not in ARCANE_SHOT or float(model["ranged_power"]) != 0.150):
        return "ranged coefficient lacks documented external source"
    if model["ticks"]:
        grammar = model["grammar"]
        aura = "23" if grammar == "missiles" else "8" if model["expected"] == "healing" else "3"
        ticks = [row for row in effects if row["Effect"] == "6" and row["EffectAura"] == aura]
        intervals = int(model["interval"]) * 1000
        durations = data.get("SpellDuration", int(metadata["DurationIndex"]))
        if len(ticks) != 1 or len(durations) != 1:
            return "missing or ambiguous periodic or duration row"
        tick, = ticks
        duration, = durations.values()
        total = int(model["ticks"]) * intervals
        if (int(tick["EffectAuraPeriod"]) != intervals or int(duration["Duration"]) != total
                or int(duration["MaxDuration"]) != total or duration["DurationPerLevel"] != "0"
                or duration["DurationPerResource"] != "0"):
            return "tick interval/count or duration differs from model"
        if grammar == "missiles":
            child = int(tick["EffectTriggerSpell"])
            child_effects = list(data.get("SpellEffect", child).values())
            description = data.get("Spell", spell)[spell]["Description_lang"]
            if len(child_effects) != 1 or child_effects[0]["Effect"] != "2" or f"{child}s1" not in description:
                return "triggered missile and tooltip references differ from model"
            tick = child_effects[0]
        if spell in SERPENT_STING:
            if float(model["tick_power"]) != 0.050 or model["expected"]:
                return "Serpent Sting coefficient/rate differs from documented scaling-only model"
        elif round(float(tick["EffectBonusCoefficient"]), 3) != float(model["tick_power"]):
            return "periodic coefficient differs from model"
    return None


def validate(baseline, live, models):
    if baseline.headers != live.headers:
        raise ValueError("CSV schemas differ between 70888 and 70938; review columns before approval")
    if not all(allow_arcane_shot_cost(spell, baseline.get("SpellPower", spell), live.get("SpellPower", spell))
               for spell in ARCANE_SHOT):
        raise ValueError("Input build fingerprint mismatch: expected all eight 70888-to-70938 Arcane Shot mana transitions")
    verified = []
    rejected = {}
    details = {}
    for spell, model in sorted(models.items()):
        changes = set()
        seen = set()
        tolerated_cost = set()
        pending = set()

        def compare(table, key, required=False, allow_cost=False):
            rows = baseline.get(table, key)
            after = live.get(table, key)
            if required and (not rows or not after):
                changes.add(f"{table}:{key} missing")
            if rows != after:
                if allow_cost and allow_arcane_shot_cost(key, rows, after):
                    tolerated_cost.add(key)
                else:
                    changes.add(f"{table}:{key} differs")
            return rows, after

        def add_text_references(row, fields):
            for field in fields:
                pending.update(map(int, DESCRIPTION_REFERENCE.findall(row[field])))

        modifier = model["modifier"]
        roots = {spell, *MODIFIER_SPELLS.get(modifier, ())}
        if model["expected"] == "spell":
            roots.update(CURSES)
        pending.update(roots)
        while pending:
            current = min(pending)
            pending.remove(current)
            if current in seen:
                continue
            seen.add(current)
            requires_spell_records = current in roots or current not in CONDITIONAL_ONLY_IDS
            for table in SPELL_TABLES:
                row_sets = compare(table, current, table in REQUIRED_ROWS and requires_spell_records,
                                   allow_cost=(table == "SpellPower" and current == spell
                                               and not model["expected"] and model["ranged_power"] == "0.15"))
                for row_set in row_sets:
                    for row in row_set.values():
                        if table == "Spell":
                            add_text_references(row, ("Description_lang", "AuraDescription_lang"))
                        elif table == "SpellEffect" and int(row["EffectTriggerSpell"]):
                            pending.add(int(row["EffectTriggerSpell"]))
                        elif table == "SpellMisc":
                            for field, name in (("CastingTimeIndex", "SpellCastTimes"), ("DurationIndex", "SpellDuration"),
                                                ("PvPDurationIndex", "SpellDuration"), ("RangeIndex", "SpellRange")):
                                if int(row[field]):
                                    compare(name, int(row[field]), required=True)
                        elif table == "SpellXDescriptionVariables":
                            for variables in compare("SpellDescriptionVariables", int(row["SpellDescriptionVariablesID"]), True):
                                for definition in variables.values():
                                    add_text_references(definition, ("Variables",))

        for trait_spell, node_id, entry_id in MODIFIER_TRAITS.get(modifier, ()):
            compare("TraitNode", node_id, True)
            for links in compare("TraitNodeXTraitNodeEntry", node_id, True):
                if sum(int(row["TraitNodeEntryID"]) == entry_id for row in links.values()) != 1:
                    changes.add(f"TraitNodeXTraitNodeEntry:{node_id} missing entry {entry_id}")
            for entries in compare("TraitNodeEntry", entry_id, True):
                for entry in entries.values():
                    definition_id = int(entry["TraitDefinitionID"])
                    for definitions in compare("TraitDefinition", definition_id, True):
                        if not any(int(row["SpellID"]) == trait_spell for row in definitions.values()):
                            changes.add(f"TraitDefinition:{definition_id} missing spell {trait_spell}")
                    for effects in compare("TraitDefinitionEffectPoints", definition_id, modifier in {"regrowth", "ruin"}):
                        for effect in effects.values():
                            if int(effect["CurveID"]):
                                compare("CurvePoint", int(effect["CurveID"]), True)

        if not changes:
            reason = validate_model(live, spell, model)
            if reason:
                changes.add(reason)
        details[spell] = (seen - {spell}, tolerated_cost)
        if changes:
            rejected[spell] = sorted(changes)
        else:
            verified.append(spell)
    return verified, rejected, details


def lua_allowlist(verified):
    lines = [MARKER, "-- Reproduce with tools/validate_forever_models.py. See docs/forever-70938-validation.md.",
             "local verified70938 = {}", "for _, spellID in ipairs({"]
    for start in range(0, len(verified), 12):
        lines.append("    " + ", ".join(map(str, verified[start:start + 12])) + ",")
    lines.extend(["}) do", "    verified70938[spellID] = true", "end",
                  "addon.Verified70938 = verified70938", END_MARKER])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", required=True, help="Installed Lua 5.1 executable")
    parser.add_argument("--baseline", required=True, type=Path, help="70888 Wago export directory")
    parser.add_argument("--live", required=True, type=Path, help="70938 Wago export directory")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--emit-lua", action="store_true", help="Print only the generated allowlist block")
    mode.add_argument("--check", action="store_true", help="Verify the generated allowlist already in Lua")
    args = parser.parse_args()
    models = load_models(args.lua)
    baseline = ClientData(args.baseline)
    live = ClientData(args.live)
    verified, rejected, details = validate(baseline, live, models)
    if args.emit_lua:
        print(lua_allowlist(verified))
        return
    for name in TABLE_KEYS:
        print(f"{name:30} {baseline.hashes[name]} {live.hashes[name]}")
    for spell, reasons in rejected.items():
        print(f"WITHHELD {spell} [{next(iter(live.get('SpellName', spell).values()), {}).get('Name_lang', '?')}]: {'; '.join(reasons)}")
    expected = sum(bool(models[spell]["expected"]) for spell in verified)
    dependencies = set().union(*(details[spell][0] for spell in verified)) - set(models)
    tolerated = set().union(*(details[spell][1] for spell in verified))
    print(f"MODELS {len(verified)}/{len(models)} verified; {expected} expected, {len(verified) - expected} scaling-only")
    print(f"DEPENDENCIES {len(dependencies)} non-model spell IDs: {', '.join(map(str, sorted(dependencies)))}")
    print(f"MANA-ONLY CHANGE {len(tolerated)} Arcane Shot ranks: {', '.join(map(str, sorted(tolerated)))}")
    if args.check:
        source = MODEL_PATH.read_text(encoding="utf-8")
        if lua_allowlist(verified) not in source or source.count(MARKER) != 1 or source.count(END_MARKER) != 1:
            parser.exit(1, "Lua 70938 allowlist does not match the validated spell IDs\n")
        print("Lua 70938 allowlist matches the verified IDs.")


if __name__ == "__main__":
    main()
