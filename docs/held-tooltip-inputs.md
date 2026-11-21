# Held tooltip input refresh

Input events invalidate public description caches and reuse the existing single queued tooltip refresh. Player stats, attack power, ranged power, haste, mana, maximum mana, talents, equipment, combat ratings, spell power, and player/target aura changes are relevant. Unrelated unit and power tokens are filtered before work. Aura payloads are never inspected.

Contracts were checked against Blizzard's UI export for Forever 1.60.1 build 70938, commit `bebcb6bf309cf41b41bd74f8ca651e6a105b2676`.

- [Unit events](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua) define `UNIT_STATS`, `UNIT_ATTACK_POWER`, `UNIT_RANGED_ATTACK_POWER`, `UNIT_SPELL_HASTE`, `UNIT_POWER_UPDATE` and `UNIT_MAXPOWER`. Power events carry unit and power-type tokens.
- [Paper doll events](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/PaperDollInfoDocumentation.lua) define `SPELL_POWER_CHANGED`, `COMBAT_RATING_UPDATE` and `PLAYER_EQUIPMENT_CHANGED`.
- [Specialization events](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpecializationInfoDocumentation.lua) define `PLAYER_TALENT_UPDATE`.
- [Aura events](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua) define `UNIT_AURA` and its potentially restricted update payload.

Only the already validated 70938 stock spellbook setter is replayed, with the original owner, slot, bank, primary tooltip identity and generation rechecked. Combat defers that setter until combat ends. Stock action buttons retain Blizzard's updater and see invalidated input on their next native update. Other owners keep existing output until a safe native update or new hover. Hide, clear, source changes and owner changes discard queued work. No polling callback is introduced.

`tests/tooltip_refresh.lua` provides offline native-owner fixtures, including event bursts and restricted data. These checks do not reproduce engine taint or establish live tooltip rendering. In-game validation is assumed at the user's direction.
