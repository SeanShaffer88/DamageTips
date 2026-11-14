# Forever 1.60.1.70938 model validation

Scope: DamageTips' existing Forever model catalog, Interface 16001. Baseline
1.60.1.70888; candidate 1.60.1.70938. Reviewed 2026-11-14.

## Result

All 209 spell IDs in the existing model catalog passed. 180 preserve both their
scaling and expected output models, with Bloodthirst retaining landed-hit DPS.
The remaining 29 retain scaling only: Frostbolt (11), Arcane Shot (8), Serpent
Sting (9), and the modeled Hammer of Wrath variant (1). Unknown build tuples
and unlisted 70938 spell IDs remain disabled for modeled output.

All eight Arcane Shot entries changed from a flat mana cost to 11% base mana.
Only ManaCost and PowerCostPct changed in their SpellPower rows. Scaling uses
the existing 15% ranged attack power coefficient from Blizzard's November 2
notes. The tooltip still reads mana cost from the live API. The Arcane Shot
exception requires the eight precisely observed old and new mana rows, and
permits no other changed fields.

## Evidence and reproduction

The data source is Blizzard client DB2 exported as CSV by [Wago Tools](https://wago.tools/db2).
For each table listed below, save the two downloads as TableName.csv in matching
build directories. The endpoint is
https://wago.tools/db2/TableName/csv?build=1.60.1.70888 or
https://wago.tools/db2/TableName/csv?build=1.60.1.70938.
Use the filenames and SHA-256 hashes here to verify the historical source inputs.

From the DamageTips checkout, run the validator with Python 3.10+ and an
installed Lua 5.1 interpreter:

    python tools/validate_forever_models.py --lua "<lua.exe>" --baseline "<70888 directory>" --live "<70938 directory>" --check

The validator loads the actual Lua spell-model table and compares rows by
relationship key and row ID rather than CSV order. It compares root and
transitively observed spell-effect triggers, spell tooltip references and
description variables, base and PvP duration, cast time, ranges, school,
attributes, cooldowns, power costs, class masks, and related talent entries,
effect points, curves, spell modifiers and Curse of the Elements auras. It
checks modeled nominal direct and periodic coefficients and schedules against
70938 data. The documented ranged coefficients for Arcane Shot and Serpent
Sting come from the [November 2 blue notes](https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-development-notes-%E2%80%93-updated-november-2/2360696).
Bloodthirst uses the description's AP formula and corresponding effect
values. Missing records are rejected except for two unchanged Frostbolt
conditional predicate
IDs in Frostbolt's description variables that have no spell rows in either
export. The command also checks the generated block in SpellPowerModels.lua.
An Arcane Shot transition check rejects swapped or duplicate build inputs.
To print a candidate replacement block without editing source, use
--emit-lua in place of --check.

The [Blizzard 70938 UI export](https://github.com/Gethe/wow-ui-source/commit/bebcb6bf309cf41b41bd74f8ca651e6a105b2676)
identifies the candidate build. [Blizzard's hotfix notes through November 13](https://worldofwarcraft.blizzard.com/en-gb/news/24315281/wow-forever-hotfixes-november-9-2026)
were reviewed for modeled spell changes. The Arcane Shot mana change is
handled above. Wild Growth is outside the catalog. Lightning Overload proc
damage, Arcane Concentration activation, and accelerated Corruption ticks
during Wrack are outside the existing standalone spell model. The documented
creature Fireball change does not establish a change to the modeled player
spell. The validator establishes client-data compatibility, not unchanged
undocumented server mechanics, live output, modifier stacking, or taint.

## SHA-256 fingerprints and validator output

Columns: table, 70888 SHA-256, 70938 SHA-256.

    Spell                          3f4c3e7ca6f6c58b32c3865b8ceb6eec9bcff8e8d9facea62880f22def927bce d81a61397d9ecbc467a77767c4a3c231e9041ed08005c1716cdba6d3fe320ab5
    SpellName                      4358b3d1a2a859284b2f46cf614e6a1f85320be342acc1c4b68b625f30cf47a5 bd8dc963dd691c69aff531464636e7b5a944efeedb773895e7b2c4a0fb7c38b4
    SpellEffect                    da2fb074eedb51bd1246ef53666044c0b757bdb67340c3969b712caa8481ac2b f419db3f95ef93b2cf052d9c3996ec355df60846f1fa24c671822aacfa8f59a3
    SpellMisc                      4b3d573dae575c2051e71d524dc73ac3590c56aa102b69770675c0eb10508f85 4500fb0dae7f8f14d1db826801ab7e1ea4af33c5dd0ba6505f4012030bcff376
    SpellClassOptions              e91c48005fae22c0904144655623d33662db3b50afede67ae69c1931420b1c92 cfb30a095a14699ea4ea508cd87c870d5fc21a6cbcaea2d43125ce30e6e664e6
    SpellLevels                    c9ef7708478aaff1b5e488c58356df443ee7d6c08a53017819f9af37cd5bef5a 8bb6142b47be66c5110c7f64e53bbc27223a1d2bde739dafde1eec5c92a42649
    SpellCategories                86a4b4624b3335277e832a16813705231ad8840aadc1ede2844213522dfe7620 0ecd2ea2c3a0073ca9bf4c7703bac4ac9ecd184b7a2463b41d77acdd648b9b7c
    SpellAuraOptions               03a5d023510ebb6e97c60c3d64dbd3879fb9f32ae59d8a21d676e17e29475b56 12b6f72942f6dadc164eb775feeee5cab9bd3156f9d1cb82e3c865e984c7a28a
    SpellCooldowns                 f5b361c78849f57e8905ad168b7d770f44ab71f81cf19cc206130a4155afdf24 3bf0324f17269592c1771ca2927ccc5bd414ee381d98e80e67156a4c54cb0613
    SpellPower                     bdbd6ba6b4d5236d23c9348fcb383c2e81bbc724279b22b3e2cbd0a8c5954a65 bf1b66970d98f2c722b3081544cce9ded0f9c8db29177c971e5d867f1949eee7
    SpellShapeshift                563fce3bf8cfdff32c0df7cb55687dd7354f57d45b5ce9b207ce5d8b969cadd9 6b46968da8803591844ac10b10a2c9fa3fb4a0b2ba47d96786fdc361bba6c0fa
    SpellXSpellVisual              ea4759be552a3fa30efd75d342318364151fe868d8c36c45e983d6a0a21f22c7 4bc5687791e623b063f20c95224962a7cc60361bdbfa371597c6d0af37e4cae2
    SpellXDescriptionVariables     107b3d23691955ed29b9f7a51705423b88e91a6672d1579ca53b8db59c3ddef3 107b3d23691955ed29b9f7a51705423b88e91a6672d1579ca53b8db59c3ddef3
    SpellCastTimes                 f94e1e3a3495d11af875fd7b007124fdd660a19ba626bc1de00a609da81f25d8 f94e1e3a3495d11af875fd7b007124fdd660a19ba626bc1de00a609da81f25d8
    SpellDuration                  4787f303fe8487cd67e5f9e8574fdc6fa2a03516dcfaabba23d9944f937223f5 4787f303fe8487cd67e5f9e8574fdc6fa2a03516dcfaabba23d9944f937223f5
    SpellRange                     30734ead3acfb44c57737ed7c9f8ff2feafda2fbffa291711d4c4afef989b1b3 30734ead3acfb44c57737ed7c9f8ff2feafda2fbffa291711d4c4afef989b1b3
    SpellDescriptionVariables      20529a59a5c632572bca119b7a320f7e9200b2b6c4c70867e347f1c96cb73a0e 20529a59a5c632572bca119b7a320f7e9200b2b6c4c70867e347f1c96cb73a0e
    TraitDefinition                4c29bf0710067d94d87051dfa216ac1dbc96b7651043ce171d787012d92daea7 4c29bf0710067d94d87051dfa216ac1dbc96b7651043ce171d787012d92daea7
    TraitDefinitionEffectPoints    82ff4026089957611a31e82af8a7a257de4679c3d0637d13e37a381196cd4157 82ff4026089957611a31e82af8a7a257de4679c3d0637d13e37a381196cd4157
    TraitNode                      f7f37eead7e7641cdbecdb1c548276ae1e5c1776eb5ad0539b88770a78979d44 f7f37eead7e7641cdbecdb1c548276ae1e5c1776eb5ad0539b88770a78979d44
    TraitNodeEntry                 dccff303039c45dc3355d8d525a664db2a87de9a17bbec133f5859755e9152b0 dccff303039c45dc3355d8d525a664db2a87de9a17bbec133f5859755e9152b0
    TraitNodeXTraitNodeEntry       7e9fb84e1256434748b1763365ea7498e0d6dd4871f789ad2a1c39925c071492 7e9fb84e1256434748b1763365ea7498e0d6dd4871f789ad2a1c39925c071492
    CurvePoint                     914ea504c1e1cb83c38ff6920bb672a02a561ef98041c208849a0a29de202c81 7e0bcdd70c3867b1379a5dbc0466d99969e219ad6aa35be935182e467d7a6154
    MODELS 209/209 verified; 180 expected, 29 scaling-only
    DEPENDENCIES 25 non-model spell IDs: 7268, 7269, 7270, 8418, 8419, 10273, 10274, 11129, 11151, 12952, 12953, 16120, 17074, 17815, 17833, 17834, 17835, 17836, 17959, 25346, 28682, 440892, 1311676, 1311677, 1311680
    MANA-ONLY CHANGE 8 Arcane Shot ranks: 3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287
    Lua 70938 allowlist matches the verified IDs.
