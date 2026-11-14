# Spell parsing, load and rank regression checks

This change targets Lua 5.1 and WoW Forever Interface 16001. It preserves the
exact-build model allowlist from PR 1. On other builds, public spell descriptions
can still supply basic tooltip output.

From the repository root, use Lua 5.1 to run the three harnesses with the
checkout path as their first argument:

    lua tests/estimates.lua .
    lua tests/parsing.lua .
    lua tests/rank_and_load.lua .

The mocks use Blizzard's 70938 client contract for description lines,
`SPELL_DATA_LOAD_RESULT(spellID, success)`, `SPELL_TEXT_UPDATE(spellID)` and
spellbook slot ranges. They do not exercise protected UI, taint, or server
combat calculations. Perform live verification before calling the candidate
stable.

Sources:

- https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua
- https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua
- https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/TooltipInfoSharedDocumentation.lua
