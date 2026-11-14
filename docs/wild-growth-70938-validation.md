# Wild Growth on Forever 70938

The candidate supports Wild Growth ranks 1–3 (`408120`, `1238214`, `1238215`)
on `1.60.1.70938`, Interface `16001`. The 70938 client exports record a
1,000 ms periodic heal, a 7,000 ms aura, and a nominal healing-power
coefficient of 0.066. The same effect rows have a 0.033 coefficient in
70888. Blizzard confirms the [coefficient change](https://us.forums.blizzard.com/en/wow/t/wow-forever-hotfixes-november-13-2026/2403040/10)
and [crit eligibility](https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-development-notes-%E2%80%93-updated-november-2/2360696/1).
The client spell text describes stronger early ticks. The model uses the
tooltip's full heal once and reports raw healing per recipient.

## Combat-log gate for 1.6.2

1. On 70938, record `/dtips status`, the spell rank, the tooltip's full heal,
   and the character's bonus healing. Turn on `/combatlog`.
2. Use one caster and follow one recipient. Keep their level, talents, forms,
   and buffs fixed. Record several casts at each of two clearly different
   bonus-healing values. Change only healing power. Let the aura expire
   naturally before recasting. Record the healing stat and tooltip total
   for both gear sets, then turn off `/combatlog`.
3. Match aura and periodic heal events by spell, caster, and recipient.
   Confirm seven full ticks with roughly one second between ticks. Compare
   raw heals before overheal. Compare the same tick number across casts at
   the same healing power to check that critical healing is about 1.5 times
   the noncritical heal, allowing for rounding.
4. Compare the full noncritical totals between gear sets. Check the raw
   totals against the two tooltips and check whether the gain is about
   `0.462 × change in bonus healing`, allowing for rounding across seven
   ticks. Review the tick-by-tick gain without assuming equal increments.

Keep this candidate out of 1.6.2 until these checks pass. If the log shows
a different schedule, multiplier, or aggregate gain, revise the model
and repeat the affected check.
