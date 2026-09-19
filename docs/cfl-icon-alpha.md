# CFL icon background bleed

## Finding

The head renderer and ChatNow's texture-copy helper used SRC_ALPHA for
both RGB and alpha source factors. Their output alpha was therefore
`srcA * srcA + dstA * (1 - srcA)`. A mask texel with alpha 0.5 over an
opaque face reduced coverage to 0.75. Later icon compositing then exposed
the screen background through an already rendered face.

Use ONE as the alpha source factor, retaining the RGB factors:
`outA = srcA + dstA * (1 - srcA)`. This keeps opaque destinations opaque
while preserving transparency where there is no opaque surface underneath.

## Decompiled reference

Reference: `C:/Users/Lenovo/Downloads/cfl-test/cfldecomp/niconico_develop.axf.c`,
around line 160988. The face decal pass calls
`DirectSetColorDepthStatus(1,0,0,1,0x10760000)`.
The packed factors are RGB SRC_ALPHA / ONE_MINUS_SRC_ALPHA and alpha
ZERO / ONE: this pass preserves destination alpha. Its skin-colored
face target starts opaque. The existing reimplementation's face-texture
builder uses source-over alpha, which also preserves an opaque target;
the bug fixed here was in subsequent head drawing and texture copying.
This is not a claim that the SDK uses the same blend state in every pass.

The specialized face-mask construction passes are unchanged. Their
destination-alpha blending has a different purpose from head rendering.

## Library integration

`libraries/libCFL` builds the shared head renderer into `lib/libCFL.a`.
`CFL_DrawIconHead` is an explicitly documented reimplementation extension,
used by both `CFL_CommandMakeModelIcon` and ChatNow's custom body/icon bake.
ChatNow retains its body, camera, cache and UI texture-copy code.

The library Makefile now always enters its inner dependency check; previously
changes to C source could leave the archive stale. The inner make still avoids
recompiling unchanged objects.

## Validation limits

The alpha equation was checked for all 256 source-alpha levels over an opaque
destination. Visual confirmation on a console remains necessary, especially
for translucent silhouette edges; this change does not redesign the full
pipeline's straight-versus-premultiplied RGB representation.
