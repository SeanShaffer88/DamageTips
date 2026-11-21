# German parser scope

`deDE` accepts bounded complete sentences for direct damage/healing, whole periodic damage/healing, mixed direct/periodic effects, channels and absorbs. It accepts German decimal commas, validated thousands groups, Unicode grouping spaces and `Rang N` spellbook subnames. Addon output remains English. Unsupported wording and malformed amounts fail closed; an independently readable baseline can survive a model schedule mismatch.

`tests/german.lua` contains original synthetic fixtures, not captured or verified German client descriptions. Periodic forecasts are limited to matching covered schedules and grammar shapes; Wild Growth/Riptide special wording and Bloodthirst AP wording have no German forecast grammar. Locale support does not expand the exact-build coefficient allowlist. Real German client capture remains separate evidence.
