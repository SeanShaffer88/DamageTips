import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "validate_forever_combat_log.py"
HEADER = "COMBAT_LOG_VERSION,22,ADVANCED_LOG_ENABLED,1,BUILD_VERSION,1.60.1,PROJECT_ID,18"
CASTER = "Player-123-00000001"
RECIPIENT = "Player-123-00000002"
OTHER = "Player-123-00000003"
TIME = datetime(2026, 11, 14, 23, 59, 32)


def line(seconds, payload):
    stamp = TIME + timedelta(seconds=seconds)
    prefix = stamp.strftime("%m/%d/%Y %H:%M:%S.%f")[:-3]
    return f"{prefix}-5  {payload}\n"


def spell_event(event, spell, recipient):
    return f'{event},{CASTER},"Caster, the Tester",0x511,0x0,{recipient},"R",0x512,0x0,{spell},"A spell",0x8'


def heal(spell, recipient, raw, absorbs=0, critical=False):
    effective = 0 if critical else min(10, raw)
    tick = spell_event("SPELL_PERIODIC_HEAL", spell, recipient)
    return tick + ",0" * 19 + f",{effective},{raw},{raw - effective},{absorbs},{'1' if critical else 'nil'}"


def cast(start, spell, values, interval, *, crit=None, multiplier=1.5,
         recipient=RECIPIENT, removed=True, tick_offset=0, absorbs=0,
         duration=None, remove_before_last_tick=False):
    aura_in = spell_event("SPELL_AURA_APPLIED", spell, recipient) + ",BUFF"
    aura_out = spell_event("SPELL_AURA_REMOVED", spell, recipient) + ",BUFF"
    duration = duration if duration is not None else len(values) * interval
    output = line(start, aura_in)
    for index, value in enumerate(values, 1):
        critical = index == crit
        raw = round(value * multiplier) if critical else value
        if remove_before_last_tick and index == len(values):
            output += line(start + duration, aura_out)
        output += line(start + index * interval + tick_offset, heal(spell, recipient, raw, absorbs, critical))
    if removed and not remove_before_last_tick:
        output += line(start + duration, aura_out)
    return output


class ValidatorTest(unittest.TestCase):
    def run_case(self, spell, low, high, *, build="70938", header=HEADER,
                 high_power="200", same_path=False):
        with tempfile.TemporaryDirectory() as directory:
            low_log = Path(directory, "low.txt")
            high_log = low_log if same_path else Path(directory, "high.txt")
            low_log.write_text(line(0, HEADER) + low, encoding="utf-8")
            high_log.write_text(line(0, header) + high, encoding="utf-8")
            return subprocess.run(
                [sys.executable, "-B", str(SCRIPT), "--build", build, "--spell-id", str(spell),
                 "--caster-guid", CASTER, "--recipient-guid", RECIPIENT,
                 "--low-log", str(low_log), "--low-healing-power", "0",
                 "--high-log", str(high_log), "--high-healing-power", high_power],
                capture_output=True, text=True, check=False,
            )

    def test_wild_growth_uses_decay_order_raw_healing_and_one_recipient(self):
        low_values = [110, 100, 90, 80, 70, 60, 50]
        high_values = [123, 113, 103, 93, 83, 73, 63]
        for spell in (408120, 1238214, 1238215):
            with self.subTest(spell=spell):
                low = cast(1, spell, low_values, 1)
                low += cast(11, spell, low_values, 1, crit=2, remove_before_last_tick=True)
                low += cast(21, spell, [300] * 3, 1, recipient=OTHER)
                report = self.run_case(spell, low, cast(1, spell, high_values, 1))
                self.assertEqual(report.returncode, 0, report.stdout + report.stderr)
                self.assertIn("91", report.stdout)
                self.assertEqual(report.stdout.count("PASS"), 3)

    def test_riptide_checks_periodic_heal_only(self):
        for spell in (408521, 1239242, 1239243):
            with self.subTest(spell=spell):
                low = line(1, spell_event("SPELL_HEAL", spell, RECIPIENT))
                low += cast(1, spell, [120] * 5, 3)
                high = cast(1, spell, [140] * 5, 3)
                high += cast(20, spell, [140] * 5, 3, crit=4)
                report = self.run_case(spell, low, high)
                self.assertEqual(report.returncode, 0, report.stdout + report.stderr)
                self.assertIn("100", report.stdout)

    def test_tick_count_cadence_gain_and_crit_mismatch_fail(self):
        spell = 408521
        low = cast(1, spell, [120] * 5, 3)
        high = cast(1, spell, [140] * 5, 3)
        wrong_captures = (
            cast(20, spell, [140] * 4, 3, duration=15),
            cast(20, spell, [140] * 5, 2, duration=15),
            cast(20, spell, [120] * 5, 3),
            cast(20, spell, [140] * 5, 3, crit=2, multiplier=2),
        )
        for wrong in wrong_captures:
            with self.subTest(wrong=wrong):
                report = self.run_case(spell, low, high + wrong)
                self.assertEqual(report.returncode, 2, report.stdout + report.stderr)
                self.assertIn("FAIL", report.stdout)

    def test_missing_crit_truncated_and_absorbed_casts_are_inconclusive(self):
        spell = 408521
        low = cast(1, spell, [120] * 5, 3)
        high = cast(1, spell, [140] * 5, 3)
        high += cast(20, spell, [140] * 5, 3, crit=2, absorbs=10)
        high += cast(40, spell, [140] * 5, 3, crit=2, removed=False)
        report = self.run_case(spell, low, high)
        self.assertEqual(report.returncode, 3, report.stdout + report.stderr)
        self.assertIn("INCONCLUSIVE", report.stdout)

    def test_post_removal_ticks_are_counted_until_the_next_cast(self):
        spell = 408120
        low = cast(1, spell, [100] * 7, 1)
        high = cast(1, spell, [113] * 7, 1)
        high += line(8.001, heal(spell, RECIPIENT, 113))
        high += cast(10, spell, [113] * 7, 1, crit=3)
        report = self.run_case(spell, low, high)
        self.assertEqual(report.returncode, 2, report.stdout + report.stderr)
        self.assertIn("expected 7 ticks, observed 8", report.stdout)

    def test_near_removal_death_map_change_and_refresh_discard_casters_aura(self):
        spell = 408521
        low = cast(1, spell, [120] * 5, 3)
        high = cast(1, spell, [140] * 5, 3)
        high += cast(20, spell, [140] * 5, 3, crit=2)
        high += line(35.01, f"UNIT_DIED,0000000000000000,nil,0x0,0x0,{CASTER},nil,0x0,0x0")
        high += cast(40, spell, [140] * 2, 3, crit=2, removed=False)
        high += line(47, "MAP_CHANGE,1414,Kalimdor")
        high += cast(50, spell, [140] * 2, 3, crit=2, removed=False)
        high += line(57, spell_event("SPELL_AURA_REFRESH", spell, RECIPIENT) + ",BUFF")
        high += line(65, spell_event("SPELL_AURA_REMOVED", spell, RECIPIENT) + ",BUFF")
        report = self.run_case(spell, low, high)
        self.assertEqual(report.returncode, 3, report.stdout + report.stderr)
        self.assertIn("low 0, high 3", report.stdout)

    def test_zero_raw_healing_and_uninformative_crit_are_inconclusive(self):
        spell = 408521
        for base, expected in ((0, "INCONCLUSIVE Healing-power gain"), (2, "INCONCLUSIVE Periodic crit multiplier")):
            with self.subTest(base=base):
                low = cast(1, spell, [base] * 5, 3)
                low += cast(20, spell, [base] * 5, 3, crit=2, multiplier=1)
                high = cast(1, spell, [base + 20] * 5, 3)
                report = self.run_case(spell, low, high)
                self.assertEqual(report.returncode, 3, report.stdout + report.stderr)
                self.assertIn(expected, report.stdout)

    def test_unsupported_periodic_heal_layout_is_rejected(self):
        spell = 408521
        low = cast(1, spell, [120] * 5, 3)
        high = line(1, spell_event("SPELL_AURA_APPLIED", spell, RECIPIENT) + ",BUFF")
        high += line(4, spell_event("SPELL_PERIODIC_HEAL", spell, RECIPIENT) + ",140,0,0,nil")
        report = self.run_case(spell, low, high)
        self.assertEqual(report.returncode, 2)
        self.assertIn("unsupported advanced SPELL_PERIODIC_HEAL layout", report.stderr)

    def test_tiny_power_gap_or_same_file_is_rejected(self):
        for options in ({"high_power": "1"}, {"same_path": True}):
            with self.subTest(options=options):
                report = self.run_case(408521, "", "", **options)
                self.assertEqual(report.returncode, 2)

    def test_wrong_build_or_incompatible_header_is_rejected(self):
        cases = (
            {"build": "70888"},
            {"header": HEADER.replace("1.60.1", "1.60.1.70888")},
            {"header": HEADER.replace("ENABLED,1", "ENABLED,0")},
        )
        for options in cases:
            with self.subTest(options=options):
                report = self.run_case(408521, "", "", **options)
                self.assertEqual(report.returncode, 2)


if __name__ == "__main__":
    unittest.main()
