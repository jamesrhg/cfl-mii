# CFL / Miiverse icon comparison

## Evidence and recovered function mappings

This pass compared existing local Ghidra pseudocode with the debug-symbol CFL
reference. These are structural identifications, not newly recovered symbols
from the stripped Miiverse binary. No claim of a complete CFL decompilation.

| Miiverse `olvctrdec/static.crs.c` | Named `cfl-test/cfldecomp/niconico_develop.axf.c` counterpart | Matching evidence |
| --- | --- | --- |
| `FUN_00187458`, line 130184 | `CFLi_InitResCharModel` | model flags at +0x68c, hair type +0x570, same mesh IDs/indices and texture load sequence |
| `FUN_00174584`, line 115286 | `CFLi_GetIconMtx` | 43.2/500 field-of-view calculation; 3.5 and 1750 depth terms; eye (0,34.5,600), target (0,34.5,0) |
| `FUN_00164e78`, line 101097 | `CFL_CommandMakeModelIcon` | background modes, local model copy, expression switch, icon camera, callback, cached draw lists at +0x698/+0x6b4 |
| `FUN_001938a8` | `CFLi_InitShapeRes` | same arguments and section IDs at every model-part construction call |

The symbolic reference's command-list construction around lines 156900..157054
starts with `s_StartDrawOpaCmd`. Its first list includes textured face and cap
parts; the second list follows separately. The old reimplementation instead
split by `hasTexture`, which put textured solid surfaces into the same pass
as overlays. `CFL_DrawIconHead` now groups by `depthWrite`: solid surfaces
first, then mask/noseline/glasses. ChatNow's body icon baker already calls
this shared renderer, so it receives the correction too.

## Hat mode

Both binaries compute `mode = modelFlags & 3`, then
`meshIndex = hairType * 2 + (mode == 1)`. Mode 2 omits CAP, HAIR and FOREHEAD
together. Cap texture selection remains the original hair type (not doubled).

`CFL_InitCharModelWithHairMode(..., CFL_HAIR_HAT)` exposes the odd-index mesh
variant; NORMAL (0) and HIDDEN (2) are also available. Existing callers of
`CFL_InitCharModel` retain NORMAL. These enum/API names are reimplementation
extensions, not claimed SDK symbol names. Hat mode prepares hair beneath an
application-supplied hat; it does not manufacture a hat mesh. ChatNow has no
hat asset or user hat selection, so ordinary chat icons keep normal hair.

## Rendering and allocation hardening

- Untextured solid parts explicitly produce alpha 1 instead of depending on
  lighting-output alpha. Source-over coverage from the earlier fix remains.
- The standalone icon command rebinds its shader, disables inherited alpha
  testing, and resets unused TEV stages. Failed frame acquisition releases
  the target and texture instead of proceeding inside another frame.
- Vertex and index allocation failures unwind partially constructed parts;
  decal buffers are checked before copying. A model whose face could not be
  allocated is not reported valid. Invalid Mii pointers, hair modes, unused
  expression bits and unsupported icon sizes are handled defensively.

These are code-level corrections, not hardware-verified pixel equality with
Miiverse. Lighting, material approximation and transparent edge compositing
still need console comparisons. No new per-frame allocations were introduced;
hair-mode selection happens during model construction only.
