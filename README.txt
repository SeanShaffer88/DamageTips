DamageTips
==========
Author:  Malikor
Licence: GNU General Public License v3.0 or later (see LICENSE.txt)

Modification notice (2026-11-12)
-------------------------------
This release modifies Malikor's DamageTips 1.4.0. It adds optional mana sustain,
caster stats, power scaling and expected output, and fixes the settings
window, hidden-spell mana line and Renew classification. See CHANGELOG.txt
for the full changes.

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
sustain estimates, caster spell stats, power scaling and expected output.

Time basis for DPS: the longest of cast time, the spell's global cooldown,
its base cooldown and any damage-over-time duration.

Built for World of Warcraft: Forever, Interface 16001. API signatures for
the estimates were checked against Blizzard's UI files for build
1.60.1.70888. Local Lua mock checks passed. During the live beta smoke check,
the tester reported that options persisted, expected values appeared on
druid healing spells, and no errors appeared. Live damage coverage and
taint behavior remain unverified.

Installation
------------
Before replacing an existing install, exit WoW and back up the DamageTips
folder and its SavedVariables to a location outside Interface/AddOns/.
Copy the DamageTips folder into _forever_/Interface/AddOns/ and restart
the game, or /reload.

Rollback to 1.4.0
-----------------
Exit WoW completely. Replace the current DamageTips folder in
_forever_/Interface/AddOns/ with your backed-up 1.4.0 DamageTips folder.
Keep your SavedVariables as they are unless you need to recover the old
settings. In that case, restore your backed-up DamageTips SavedVariables
before restarting WoW.

Settings
--------
/damagetips opens the tabbed settings window (also: /dtips, the addon list
entry next to the minimap, or the minimap button). Everything is saved
between sessions.

  Lines          DPS, DPM, damage per cast, damage range, healing lines,
                 per-mana lines, mana cost, school tint, Shift breakdown;
                 show on action bars / spellbook, mana sustain, caster stats,
                 spell and attack power scaling, expected DPS and HPS
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
/damagetips scaling Toggle spell and attack power scaling
/damagetips expected Toggle expected DPS and HPS
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
* Power scaling and expected output use an exact spell-rank list for WoW
  Forever 1.60.1.70888 (Interface 16001). Both options start off.
  On other builds, the scaling and expected lines are hidden. Base
  tooltip metrics can still appear when the client provides readable data.
  The scaling lines show nominal changes per +100 stat before any
  additional talent or low-rank modifiers.
* Supported caster families are Fire Blast, Lightning Bolt, Shadow Bolt,
  Wrath, Starfire, Flash Heal, Heal, Greater Heal, Healing Touch and
  Healing Wave. Frostbolt, Arcane Shot and the verified Hammer of Wrath
  variant (429151) show scaling only. Bloodthirst shows attack power
  scaling and a DPS estimate for landed hits.
* Expected output for direct spells uses the game's current tooltip amount
  and the spell's cast/cooldown/GCD cadence. The fallback equal-level spell
  hit model starts at 96% and adds sheet hit modifiers, bounded to 0–100%.
  Spell crit is modeled at 1.5x, melee crit at 2x, and direct heals are
  assumed to land. Expected HPS represents raw healing before overheal.
  These estimates start from sheet stats and standard crit bonuses.
  Bloodthirst derives its amount from the live AP formula.
* Supported spell-specific modifiers are Call of Thunder for Lightning
  Bolt (+5 percentage points to crit), Ruin for Shadow Bolt (up to 2x
  crit damage), Improved Regrowth for direct Regrowth healing (+10 points
  per rank), and active Combustion for Fire Blast (+10 points per stack).
  Regrowth tick crit keeps the sheet chance. The estimate uses readable
  committed talents and the current aura snapshot. Other talents, procs,
  auras, spell piercing and avoidance are outside this model.
* For eligible PvE spell DPS, the strongest readable Curse of the Elements
  rank adds 4–10% damage taken. Its resistance reduction is accounted for
  through the client effective-resistance value when available. The
  modifier line lists the effects used in the estimate.
* For damage spells, Expected DPS checks the current target during tooltip
  refresh. Target level adjusts spell hit for attackable, living PvE
  targets within three effective levels of the player. When school
  resistance is unavailable, restricted, zero, or outside the Holy
  damage model, the target label reads "level only" or "level + aura"
  if Curse of the Elements contributes. Ineligible targets and
  unsupported level differences use the equal-level estimate.
* Positive readable resistance uses the combat-log fitted mean
  R / (R + 8L + 19), where L is the player's effective level. Direct
  damage and channel ticks use the full mean. Ordinary periodic ticks use
  one tenth of it. Mind Flay uses this mean both to reduce the initial
  application chance before hit bonuses and for partial resistance on
  successful ticks. The fit is approximate and spell-specific server
  mechanics can differ. Bloodthirst uses the client armor reduction API
  when effective armor is readable and positive. Its rate is conditional
  on landed hits in either mode. Healing estimates are target-independent.
* Supported periodic families are Corruption, Shadow Word: Pain,
  Rejuvenation, Renew, Regrowth, Moonfire, Immolate, Holy Fire and Fireball.
  Arcane Missiles and Mind Flay use their full base channels. Serpent Sting
  shows ranged power scaling. Each estimate needs the recognized English
  description and the build's tick schedule. The scaling lines are nominal
  per-tick gains, with a full-effect total where the periodic coefficient
  is positive.
* Periodic rates assume all ticks finish and use the longest of the
  effect duration and the tooltip's normal casting cadence.
  A damage aura needs one successful application. Each Arcane Missiles
  missile rolls hit independently. The model applies 1.5x crit only to
  eligible components and assumes healing lands. Mind Flay represents
  the base channel before any talent ramp. Include damage over time also
  controls these periodic lines. Mixed spells can still show their direct
  power scaling with that option off.
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
* The basic DPS line requires a damage amount or range in the spell text.
* Spell data that the client has not loaded yet is requested once. The
  lines appear when the data arrives or on the next tooltip refresh.

More documents: CHANGELOG.txt, DESCRIPTION.txt, AUDIT.txt, CREDITS.txt
World of Warcraft is a trademark of Blizzard Entertainment. This addon is not
affiliated with or endorsed by Blizzard Entertainment.
