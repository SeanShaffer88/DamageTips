# Validate Forever 70938 healing from combat logs

The validator reads two local advanced combat logs and checks one spell
rank on one recipient. Run it from the DamageTips checkout with Python 3.10
or later. It prints a report and requires no additional packages.

| Spell | Rank 1 | Rank 2 | Rank 3 | Periodic model per recipient |
| --- | ---: | ---: | ---: | --- |
| Wild Growth | 408120 | 1238214 | 1238215 | 7 ticks, 1 second apart, 0.462 total healing-power coefficient |
| Riptide | 408521 | 1239242 | 1239243 | 5 ticks, 3 seconds apart, 0.500 total healing-power coefficient |

| Direct spell | Spell IDs in rank order | Healing-power coefficient |
| --- | --- | ---: |
| Holy Light | 635, 639, 647, 1026, 1042, 3472, 10328, 10329, 25292 | 0.714 |
| Flash of Light | 19750, 19939, 19940, 19941, 19942, 19943 | 0.429 |
| Lesser Healing Wave | 8004, 8008, 8010, 10466, 10467, 10468 | 0.429 |

The build 70938 `SpellEffect` table records the direct coefficients along
with base healing roll variance and level terms. [70938 client data provenance](forever-70938-validation.md).

Both periodic models expect crits to heal for 1.5 times the matching noncrit.
The validator checks periodic healing from `SPELL_PERIODIC_HEAL` events.
Blizzard removed Riptide's initial heal. On build 70938, the first effect
of all three ranks is a dummy effect (`Effect=3`, `EffectBasePointsF=0` in
`SpellEffect` rows `1072707`, `1236793`, and `1236796`). The spell tooltip
references the periodic effect, duration, and Chain Heal bonus.
[Blizzard's November 2 notes](https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-development-notes-%E2%80%93-updated-november-2/2360696/1)
and [70938 client data provenance](forever-70938-validation.md).

## Capture and compare

1. Confirm build 70938 in `/dtips status`. Use Advanced Combat Logging, then
   start and stop each saved capture with `/combatlog`. Keep two separate
   files and record the caster's displayed healing power for each.
2. Use the same caster, recipient, rank, level, talents, and healing modifiers
   in both captures. Change healing power by at least 50 using gear that
   leaves haste, crit multiplier, and healing modifiers the same. Keep healing
   power constant within each capture. Avoid healing modifiers outside the
   baseline model, such as Paladin Oath of Light on the recipient or the Holy
   Power talent's bonus to holy critical healing.
3. For a periodic spell, start with an unapplied aura and let each cast run
   to expiry. Collect at least one complete noncritical, unabsorbed cast at
   each healing power and an unabsorbed periodic crit to compare at the same
   tick number and power. For a direct spell, collect at least 10 qualifying
   noncrit heals per power and 10 qualifying crits at one or both powers.
   Direct counts include fully overhealed casts with positive raw healing.
4. Copy the source and destination GUIDs from matching log entries. Use only
   one recipient GUID for Wild Growth even if the same cast hit others.

```powershell
python tools/validate_forever_combat_log.py --build 70938 --spell-id 408120 `
  --caster-guid Player-123-00000001 --recipient-guid Player-123-00000002 `
  --low-log "wild-growth-low.txt" --low-healing-power 20 `
  --high-log "wild-growth-high.txt" --high-healing-power 220
```

Use the timestamped Forever advanced v22, project 18 format. The usual
`BUILD_VERSION,1.60.1` header has no numeric build, so `--build` records the
build you confirmed for both captures. An explicit build suffix, when
present, must match 70938. Use `--spell-id 635` for Holy Light rank 1.

## Read the result

### Periodic spells

- **Tick count and timing** require aura applications with observed removals.
  The check allows 250 ms of timing jitter relative to application and
  expiry. An early removal, refresh, or incomplete capture cannot establish
  a full tick schedule. A pattern with a natural-length duration and too few
  or too many ticks fails.
- **Healing-power gain** compares the sum of periodic healing across full
  noncritical, unabsorbed casts with positive raw healing on every tick.
  All low-to-high gains must fall within one point per tick of the model's
  predicted total. Healing includes overheal.
- **Periodic crit multiplier** compares critical ticks against noncritical
  ticks at the same ordinal position and healing power. Each match allows
  one point of rounding and needs a noncrit above two raw healing points.
  Wild Growth ticks decay over time, so comparing different positions can
  give a misleading multiplier.
- **Initial heal absence** applies to Riptide. A positive raw `SPELL_HEAL`
  matching the selected rank, caster, and recipient fails the check, including
  fully overhealed or absorbed healing. With no positive rows, the check
  needs a complete, correctly timed aura at each healing-power value to pass.
  Initial healing-power gain and crit multiplier display as **N/A** because
  build 70938 has no initial heal.

### Direct spells

The direct checks read `SPELL_HEAL` for the selected rank, caster, and
recipient. They use positive raw healing including overheal and skip
absorbed samples. Identical rows at the same timestamp count once. Base
healing varies by cast, so the checks compare means.

- **Direct healing-power gain** compares the high-power and low-power
  noncrit means against the modeled gain. The tolerance is the larger of
  one healing point or 10% of the modeled gain.
- **Direct crit multiplier** reports the observed mean crit-to-noncrit
  ratio and sample counts at each power. At an eligible power, it tests the
  mean crit amount minus 1.5 times the mean noncrit amount. The tolerance is
  the larger of one healing point or 5% of that power's noncrit mean.
  At least one power needs both sample classes and a noncrit mean above two
  healing points to resolve the multiplier. When both qualify, both must
  pass, and either can fail the multiplier check.

For both direct checks, the validator uses an approximate 95% interval
of 2.262 standard errors on either side of the mean difference. The
tolerances account for rounding and calibrate the validator. A check
passes when the interval lies entirely within tolerance, fails when the
interval lies entirely outside tolerance, and stays inconclusive if it
overlaps a tolerance boundary or samples are insufficient. Collect more
comparable rolls to narrow an interval or use a wider healing-power gap to
improve resolution on gain.

Exit code **0** means all checks passed. Exit code **2** means at least one
model check failed or a capture could not be read using the supported schema.
Exit code **3** means additional complete or comparable observations are
needed. A passing report applies to the supplied capture conditions and
declared build. The fixtures in this repository are synthetic.

The parser follows the timestamp and header observed by the
[Forever data parser](https://github.com/tzcnt/forever-data/blob/main/analysis/analyze.py)
and the 36-field advanced healing row documented by the
[WowCoach parser reference](https://wowcoach.gg/docs/combat-log/damage-and-healing).
