DamageTips
==========
Author:  Malikor
Licence: GNU General Public License v3.0 or later (see LICENSE.txt)

Adds extra lines to spell tooltips on your action bars and in the spellbook:

  * DPS               average damage per second
  * DPM               damage per minute (DPS x 60)
  * HPS / HPM         healing per second / per minute on healing spells
  * Damage per mana   total damage / mana cost (off by default)
  * Healing per mana  total healing / mana cost (with the per-mana option)
  * Absorbs           shield size on absorb spells
  * Mana cost         as % of your max mana, as an amount, or both

Optional lines: damage per cast, damage range, next-rank comparison,
school-tinted damage lines, a hold-Shift breakdown of the maths, mana
sustain estimates, and caster spell stats.

Time basis for DPS: the longest of cast time, the spell's global cooldown,
its base cooldown and any damage-over-time duration.

Built for World of Warcraft: Forever, Interface 16001. API signatures for
the estimates were checked against Blizzard's UI files for build
1.60.1.70888. The alpha was verified with Lua mocks.

Installation
------------
Copy the DamageTips folder into _forever_/Interface/AddOns/ and restart
the game, or /reload.

Settings
--------
/damagetips opens the tabbed settings window (also: /dtips, the addon list
entry next to the minimap, or the minimap button). Everything is saved
between sessions.

  Lines          DPS, DPM, damage per cast, damage range, healing lines,
                 per-mana lines, mana cost, school tint, Shift breakdown;
                 show on action bars / spellbook, mana sustain, caster stats
  Calculation    Include damage over time, GCD minimum, thousands separators,
                 next-rank comparison, DPS decimals, mana cost format
  Format         Colours (damage / healing / mana), font outline, font size,
                 live preview of every line
  Advanced       Minimap button, spell rules summary, settings export/import,
                 reset to defaults

Commands
--------
/damagetips         Open the settings window
/damagetips help    Show the command list
/damagetips dps     Toggle DPS
/damagetips dpm     Toggle DPM
/damagetips mana    Toggle the mana cost line
/damagetips sustain Toggle the mana sustain estimate
/damagetips caster  Toggle caster spell stats
/damagetips healing Toggle the healing lines
/damagetips minimap Toggle the minimap button
/damagetips debug   Print the spell text the addon read (for troubleshooting)
/damagetips reset   Restore default settings
/damagetips hide <spell>     Hide one spell's lines
/damagetips show <spell>     Remove a spell rule
/damagetips setdmg <spell> <avg>  Pin a spell's average damage
/damagetips rules   List spell rules
/damagetips export  Print a settings string to share
/damagetips import <string>   Apply a settings string

Notes
-----
* Mana sustain uses current mana, the spell's up-front cost, and casting
  mana regeneration. It pays the first cast from your current pool and
  applies steady regeneration between casts. Cadence follows the tooltip's
  DPS/HPS timing settings and allows full enabled periodic effects to run.
  Damage and healing estimates use the tooltip's average amounts. Actual
  results vary with casting cadence, mana procs, refunds, and regen ticks.
  The estimate needs readable data for a known player spell with one
  unconditional mana cost and no optional or recurring cost.
* Caster spell stats show character spell crit, spell power for a recognized
  damage school, and bonus healing for a healing spell when available. They
  describe the caster and leave the tooltip's damage and healing math intact.
* Forever follows Midnight's "secret value" rules. DamageTips reads spell text
  from the game's tooltip data and skips anything the game marks as secret, so
  a spell may occasionally show no damage line while data is restricted.
* Damage values are read from the spell's description text, so this currently
  works on English clients only.
* Spells without a flat damage number in their description (many weapon
  abilities) will not show damage lines.
* Spell data that the client has not loaded yet is requested once. The
  lines appear when the data arrives or on the next tooltip refresh.

More documents: CHANGELOG.txt, DESCRIPTION.txt, AUDIT.txt, CREDITS.txt
World of Warcraft is a trademark of Blizzard Entertainment. This addon is not
affiliated with or endorsed by Blizzard Entertainment.
