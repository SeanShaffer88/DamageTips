# Validate Forever 70938 healing from combat logs

The validator reads two local advanced combat logs and checks the periodic
effects of one spell rank on one recipient. Run it from the DamageTips
checkout with Python 3.10 or later. It prints a report and requires no
additional packages.

| Spell | Rank 1 | Rank 2 | Rank 3 | Periodic model per recipient |
| --- | ---: | ---: | ---: | --- |
| Wild Growth | 408120 | 1238214 | 1238215 | 7 ticks, 1 second apart, 0.462 total healing-power coefficient |
| Riptide | 408521 | 1239242 | 1239243 | 5 ticks, 3 seconds apart, 0.500 total healing-power coefficient |

Both models expect periodic crits to heal for 1.5 times the matching noncrit.
The validator checks healing from `SPELL_PERIODIC_HEAL` events.

## Capture and compare

1. Confirm build 70938 in `/dtips status`. Use Advanced Combat Logging, then
   start and stop each saved capture with `/combatlog`. Keep two separate
   files and record the caster's displayed healing power for each.
2. Use the same caster, recipient, rank, level, talents, and healing modifiers
   in both captures. Change healing power by at least 50 using gear that
   leaves haste, crit multiplier, and healing modifiers the same. Keep healing
   power constant within each capture. Start with an unapplied aura and let
   each cast run to expiry before recasting or stopping the log.
3. Collect at least one complete noncritical, unabsorbed cast at each healing
   power. Keep recording until at least one unabsorbed periodic crit can be
   compared with a noncrit at the same tick number and healing power.
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
present, must match 70938.

## Read the result

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

Exit code **0** means all checks passed. Exit code **2** means at least one
model check failed or a capture could not be read using the supported schema.
Exit code **3** means additional complete or comparable observations are
needed. A passing report applies to the supplied capture conditions and
declared build. The fixtures in this repository are synthetic.

The parser follows the timestamp and header observed by the
[Forever data parser](https://github.com/tzcnt/forever-data/blob/main/analysis/analyze.py)
and the 36-field advanced healing row documented by the
[WowCoach parser reference](https://wowcoach.gg/docs/combat-log/damage-and-healing).
