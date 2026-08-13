# cfl-mii

A reimplementation of Nintendo's CFL Mii-rendering library for 3DS
homebrew, built on top of libctru/citro3d.

It opens the console's system `CFL_Res.dat` Mii resource archive,
parses it, and builds a fully-shaded, textured 3D character model
(head, hair, face, eyes, eyebrows, mouth, nose, glasses, facial hair)
from a `MiiData` struct - the same data libctru's Mii Selector applet
hands you. It can also search/read the console's real Mii database
(`CFL_DB.dat`), encode/decode the standard `CFLStoreData` exchange
format, and optionally attach a full-body model - loaded from a real,
standard **IQM** file, not a project-specific format - to a
`CFLCharModel` so both the real-time draw path and the icon renderer
show head-on-body without any extra API surface - see
[Body models](#body-models-optional) below. A loaded body model can
also be re-posed from your own application-supplied skeletal animation
data (`CFL_PoseBodyModel`), correctly re-applying the same per-Mii
build/height body scale to the animated pose - see
[Animation playback](#animation-playback) below.

Reverse-engineered from a retail 3DS title binary's debug info and
cross-referenced against the real, compiled RFL (Wii) and FFL (Wii U)
Mii libraries - real function/type/constant names throughout, not
invented ones, wherever the decompile could confirm them.

## Building

This is a source library, not a standalone app - it has no `main()`.
Add `source/` to a devkitARM 3DS project's `SOURCES`/`INCLUDES` and
link against `citro3d`/`ctru`.

## Design

- **Instance-based.** `CFLCharModel` is a plain, caller-owned struct
  (`CFLCharModel model = {0};` on the stack, in an array, wherever) -
  this library never allocates one itself, only fills in one you
  already own. Hold as many as you want at once.
- **Data only, not drawing.** `CFL_InitCharModel` builds vertex/index
  buffers and baked textures; it never issues a draw call. Real CFL
  doesn't either (confirmed via the decompile) - rendering (camera,
  blend/depth state, draw order, lighting) is entirely your own job.
  `CFL_GetPartCount`/`CFL_GetPart` hand you the built data; an optional
  default shader (`CFL_BindDefaultShader`/`CFL_SetDefaultMaterial`) is
  there if you don't want to write your own. The one deliberate
  exception is `CFL_CommandMakeModelIcon`, which really does render (a
  real function whose whole job is producing a picture).
- **`bool`, not `CFLResult`.** Real CFL returns a `CFLResult` enum this
  project never captured the exact values of; every function here
  returns `bool` instead (`true` = success) to avoid guessing at
  error-code semantics on top of everything else.
- **Standard formats, not invented ones, wherever a real standard
  applies.** Mii data itself is the real 3DS `MiiData` layout
  (libctru's own struct); Mii exchange data is the real `CFLStoreData`
  wrapper; body models are real, standard IQM files, openable and
  editable by any IQM-aware tool (Blender's own importer/exporter,
  other game engines) - not a bespoke binary format only this project
  understands.

## API reference

### Lifecycle

```c
bool CFL_Initialize(void);
void CFL_Finalize(void);
bool CFL_IsAvailable(void);
void CFL_EnableSDDebug(bool enable);
```

- **`CFL_Initialize()`** - call once, after `C3D_Init()`. Opens the
  system `CFL_Res.dat` archive, sets up the shared shader/vertex
  attributes every `CFL_InitCharModel` call needs, and caches the
  console's real Mii database (`CFL_DB.dat`) if one exists. Returns
  `false` if the archive can't be opened - almost always means the app
  wasn't launched with full ARM11 filesystem permissions (launch via
  Luma3DS/Rosalina's homebrew launcher, not a plain 3dsx loader).
- **`CFL_Finalize()`** - call once, after destroying every
  `CFLCharModel`, before `C3D_Fini()`. Frees the shader program and
  the archive buffer.
- **`CFL_IsAvailable()`** - `true` once `CFL_Initialize` has succeeded
  and `CFL_Finalize` hasn't been called since. Cheap to check anywhere.
- **`CFL_EnableSDDebug(true/false)`** - opens/closes this library's own
  `sdmc:/3ds/cfl_test.txt` diagnostic log (off by default). Useful
  while developing - every archive-parse and model-build step logs
  what it's doing and why a part was skipped, if one was.

### Character models

```c
typedef struct {
    CFLPart parts[CFL_MAX_PARTS];
    int partCount;
    MiiData mii;
    bool valid;
    const CFLBodyModel* attachedBody; // NULL by default - see CFL_AttachBody below
    // ...
} CFLCharModel;

bool CFL_InitCharModel(CFLCharModel* model, const MiiData* mii,
                        CFLResolution resolution, CFLExpressionFlag expressionFlags);
void CFL_DeleteModel(CFLCharModel* model);
bool CFL_HasCharModel(const CFLCharModel* model);
```

- **`CFL_InitCharModel(model, mii, resolution, expressionFlags)`** -
  builds a full character model (face, mask, hair, cap, goatee, nose,
  glasses - everything this library knows how to render) from a real
  `MiiData` (the same struct libctru's Mii Selector applet returns).
  `model` must be zero-initialized before its *first* use (`= {0}`,
  `memset`, or plain static/global storage) - every call after that is
  always safe, since `CFL_InitCharModel` tears down whatever `model`
  previously held before rebuilding it, so calling it again on the
  same instance with a different Mii is the normal way to "change"
  a model.
  `resolution` is one of the `CFL_RESOLUTION_*` constants below and
  controls only the eye/eyebrow/mouth/mustache/mole decal canvas -
  `expressionFlags` (`CFL_EXPRESSION_FLAG(e)` OR'd together, or
  `CFL_EXPRESSION_FLAG_ALL`) declares up front which facial
  expressions this model will ever need; one texture is pre-baked per
  requested expression, so switching later is instant. **Real memory
  cost to plan around**: each baked expression texture is
  `resolution * resolution * 4` bytes - requesting every expression at
  a high resolution for several simultaneous models is a real way to
  exhaust VRAM on original-model 3DS hardware. Request only what you
  need. Returns `false` only if the face itself couldn't be built (or
  `CFL_Initialize` was never called); every other part is optional and
  silently skipped on failure (check the SD log via
  `CFL_EnableSDDebug(true)` if a Mii is missing a part you expected).
  **Real side effect, matching real CFL exactly**: a successful build
  also adds the Mii to the console's real "recently seen" Mii list
  (skipped automatically if it's already in your saved collection) -
  this is what real `CFL_InitCharModel` does too, not something this
  library adds on top.
- **`CFL_DeleteModel(model)`** - frees every part and every pre-baked
  expression texture `model` owns. Safe on a zeroed or already-deleted
  instance. `CFL_InitCharModel` already calls this internally before
  rebuilding, so you only need to call it yourself for explicit
  cleanup (e.g. before the instance's own storage - a stack frame, a
  freed array slot - goes away).
- **`CFL_HasCharModel(model)`** - `true` once `CFL_InitCharModel` has
  successfully built at least the face.

```c
typedef int CFLResolution;
#define CFL_RESOLUTION_64   64
#define CFL_RESOLUTION_128  128
#define CFL_RESOLUTION_256  256
#define CFL_RESOLUTION_512  512
#define CFL_RESOLUTION_1024 1024
```

### Expressions

```c
typedef enum {
    CFL_EXPRESSION_NORMAL = 0, CFL_EXPRESSION_SMILE, CFL_EXPRESSION_ANGER,
    CFL_EXPRESSION_SORROW, CFL_EXPRESSION_SURPRISE, CFL_EXPRESSION_BLINK,
    CFL_EXPRESSION_OPENMOUTH, CFL_EXPRESSION_SMILE_OM, CFL_EXPRESSION_ANGER_OM,
    CFL_EXPRESSION_SORROW_OM, CFL_EXPRESSION_SURPRISE_OM, CFL_EXPRESSION_BLINK_OM,
    CFL_EXPRESSION_WINK_L, CFL_EXPRESSION_WINK_R, CFL_EXPRESSION_WINK_L_OM,
    CFL_EXPRESSION_WINK_R_OM, CFL_EXPRESSION_LIKE_WINK_L, CFL_EXPRESSION_LIKE_WINK_R,
    CFL_EXPRESSION_FRUSTRATED, CFL_EXPRESSION_COUNT
} CFLExpression;

#define CFL_EXPRESSION_FLAG(e) (1u << (u32)(e))
#define CFL_EXPRESSION_FLAG_ALL ((1u << CFL_EXPRESSION_COUNT) - 1u)

bool CFL_SetExpression(CFLCharModel* model, CFLExpression expression);
CFLExpression CFL_GetExpression(const CFLCharModel* model);
const char* CFL_GetExpressionName(CFLExpression expression);
bool CFL_IsAvailableExpression(const CFLCharModel* model, CFLExpression expression);
```

- **`CFL_SetExpression(model, expr)`** - switches the model's bound
  MASK texture. `expr` must have been included in `expressionFlags` at
  `CFL_InitCharModel` time *and* have baked successfully - check
  `CFL_IsAvailableExpression` first if you're not sure (see
  [Validation](#validation-checklist) below). Instant - no GPU work
  beyond a texture rebind, no rebuild.
- **`CFL_GetExpression(model)`** - the currently-bound expression.
- **`CFL_GetExpressionName(expr)`** - a plain C string (`"Normal"`,
  `"Smile"`, ...), handy for debug overlays.
- **`CFL_IsAvailableExpression(model, expr)`** - `true` if `expr` can
  be switched to *right now* (requested **and** successfully baked -
  a request can still fail per-expression under VRAM pressure).

### Render data

```c
typedef struct {
    void* vbo; void* ibo;
    u32 vertexCount, indexCount;
    bool useIndices;
    float color[3];
    bool hasTexture;
    C3D_Tex tex;
    bool needsTint;      // true: multiply `color` in. false: texture RGB is already correct.
    bool isAlphaOnly;    // true: REPLACE with `color` for RGB. false: MODULATE by texture RGB.
    bool depthWrite;     // false for decal overlays (MASK, nose canvas) sitting on another part.
    bool noSpecular;     // true for flat 2D overlays that read wrong with a specular highlight.
    bool capBlend;       // true only for CAP - see its own note below.
} CFLPart;

int CFL_GetPartCount(const CFLCharModel* model);
const CFLPart* CFL_GetPart(const CFLCharModel* model, int index);

typedef struct { int projection; int modelView; } CFLShaderLocations;
CFLShaderLocations CFL_GetShaderLocations(void);
void CFL_RebindShader(void);
```

- **`CFL_GetPartCount`/`CFL_GetPart`** - the built model as a plain
  array of draw-ready parts. Loop over them and draw however you like
  (see the rendering example below for the exact TEV/blend setup this
  library's own parts expect - `needsTint`/`isAlphaOnly`/`capBlend`
  specifically matter, getting them backwards silently discards real
  texture detail, tints the wrong thing, or colors a hat's own
  underside pitch black instead of the real half-brightness favorite
  color real CFL shows there).
- **`part->capBlend`** - `true` only for the CAP part. Real CFL's own
  cap-tint formula isn't a plain modulate the way every other tinted
  part is - it's `favoriteColor * (texColor + 1) / 2`, so the
  texture's own real intensity only ever chooses between half- and
  full-brightness favorite color, never all the way down to black.
  `color` is already pre-halved by this library for a `capBlend` part,
  so a plain `texture * color` modulate (stage 0) gets you halfway
  there - drawing a `capBlend` part needs one extra TEV stage,
  `PREVIOUS + color` (additive), bracketed around *just that part's*
  own draw call (see the example below). Every other part is unaffected
  either way.
- **`CFL_GetShaderLocations()`** - the shared vertex shader's
  `projection`/`modelView` uniform locations, so you can upload your
  own camera matrices each frame. This library has no opinion on
  lighting or camera - those are entirely your choice, same as real
  CFL (confirmed via RFL's own real source: each game supplies its own
  light values, the library never fixes one).
- **`CFL_RebindShader()`** - **call this once per frame, before
  drawing any `CFLPart`, if you also use citro2d (or anything else
  that touches the active shader/attribute state) anywhere in the same
  frame.** citro2d's own `C2D_Prepare()`/text calls silently rebind
  their own default shader; without re-binding this library's own
  shader afterward, every subsequent `CFLPart` draw call breaks. Not
  needed in a citro3d-only app (the binding sticks for the whole
  program).

### Default shader (optional)

```c
void CFL_BindDefaultShader(void);
void CFL_SetDefaultMaterial(const float color[3], bool noSpecular);
```

A ready-made shading implementation you can use instead of writing
your own `C3D_LightEnv`/material setup - matching real FFL's own
`FFLDefaultShader` role (a convenience the library provides, never
forced). `CFL_BindDefaultShader()` once per frame before drawing any
part with it; `CFL_SetDefaultMaterial(part->color, part->noSpecular)`
once per part, right before its draw call. Nothing else in this
library depends on either being called - build your own lighting from
scratch if you want different shading.

### Body models (optional)

```c
typedef struct {
    void* vbo;
    void* ibo;
    u32 vertexCount, indexCount;
    float color[3]; // baked in at CFL_LoadBodyModel time - favoriteColor for the
                     // body part, gray/gold pants for the pants part
} CFLBodyPart;

#define CFL_BODY_MAX_PARTS 2

#define CFL_BODY_MAX_BONES 18 // a real body skeleton this library ships has
                               // 16 bones - a small margin above that

typedef struct {
    CFLBodyPart parts[CFL_BODY_MAX_PARTS]; // body, pants
    int partCount;
    bool hasHeadBone;
    float headBoneWorldMatrix[12]; // 3 rows of 4 (row_i = [Ai0,Ai1,Ai2,ti]) -
                                    // the real world transform of the body's
                                    // own "head" joint's own attach point
    float bodyScale[3]; // real nn::mii::detail::GetBodyScale(build,height) -
                         // how much THIS Mii's own build/height stretches
                         // the body model from its neutral pose
    void* rig; // opaque - real skeleton + raw per-vertex skin data this
               // body's own CFL_PoseBodyModel calls need, retained for the
               // model's whole lifetime. Never touch this directly - it's
               // NULL if CFL_LoadBodyModel couldn't retain it (still a
               // successfully loaded, drawable body - just not animatable).
} CFLBodyModel;

// One bone's real LOCAL (parent-relative) pose - the same shape real IQM
// itself stores per joint per frame.
typedef struct {
    float translate[3];
    float rotate[4]; // quaternion x,y,z,w
    float scale[3];
} CFLBoneLocalPose;

bool CFL_LoadBodyModel(const u8* bodyData, u32 bodySize, const MiiData* mii, CFLBodyModel* outBody);
void CFL_DeleteBodyModel(CFLBodyModel* body);
void CFL_AttachBody(CFLCharModel* model, const CFLBodyModel* body);

u32 CFL_GetBodyBoneCount(const CFLBodyModel* body);
const char* CFL_GetBodyBoneName(const CFLBodyModel* body, u32 boneIndex);
bool CFL_GetBodyBoneBindLocalPose(const CFLBodyModel* body, u32 boneIndex, CFLBoneLocalPose* outPose);
bool CFL_PoseBodyModel(CFLBodyModel* body, const CFLBoneLocalPose* poses, u32 boneCount);

#define CFL_HEAD_TO_BODY_SCALE (10.0f / 7.0f)
```

Real Nintendo body-model support - **not part of real CFL at all**
(confirmed via the decompile: `CFLIconSetting`'s real struct has no
body field, and nothing in CFL's own real API takes one either).
Attaching a head to a body is an application-level concern in real Mii
software too (this mirrors `ariankordi/FFL.js`'s own real
`attachHeadToBody`), which is why it's opt-in and additive rather than
baked into `CFL_InitCharModel` itself.

- **`CFL_LoadBodyModel(bodyData, bodySize, mii, &body)`** - parses a
  real, standard **IQM** file's raw bytes and colors the result for
  `mii` (body = favorite color, pants = gold/gray depending on the
  Mii's own ID) and scales it per that Mii's own real build/height.
  Returns `false` (leaving `*outBody` zeroed) on any parse failure -
  including a well-formed IQM file whose joint/mesh naming this
  library simply doesn't recognize (see
  [The IQM format, in detail](#the-iqm-format-in-detail) below for
  exactly what's required and why a mismatch is a hard failure, not a
  best-effort guess).
- **`CFL_DeleteBodyModel(body)`** - frees every part's vbo/ibo. Safe on
  an already-empty or partially-loaded `CFLBodyModel`.
- **`CFL_AttachBody(model, body)`** - sets (or clears, `body = NULL`)
  which `CFLBodyModel` this `CFLCharModel`'s icon renders should show
  alongside its head (see `CFL_CommandMakeModelIcon` below - there's no
  separate "with body" icon function, `model->attachedBody` is what
  decides). Does **not** take ownership of `body` - you still manage
  its real lifetime with `CFL_LoadBodyModel`/`CFL_DeleteBodyModel`
  yourself, same as every other pointer this library hands back rather
  than owns. A plain field assignment, safe to call any time.
- **`CFL_HEAD_TO_BODY_SCALE`** - the real head-to-body size ratio
  (`10/7`), matching `ariankordi/FFL.js`'s own `attachHeadToBody`
  exactly (its own real `headToBodyScale` constant) - use this when
  drawing a body in your own real-time scene (see the example below);
  `CFL_CommandMakeModelIcon`'s own internal drawing does **not** use
  it (see the note in [Icon rendering](#icon-rendering) below for why).
- **`CFL_GetBodyBoneCount(body)`** / **`CFL_GetBodyBoneName(body, i)`** -
  how many real bones `body` has, and each one's real name (from the
  original `.iqm`'s own text section). This is the authoritative bone
  ORDER `CFL_PoseBodyModel`'s own `poses` array must use - don't assume
  it matches the source file's own joint array order without checking,
  even though in practice it always will (this library never reorders
  or filters joints). Returns `0`/`NULL` if `body` wasn't loaded
  successfully or has no retained rig data (see `CFLBodyModel.rig`
  above). Names are stable pointers into the *original* `bodyData`
  buffer `CFL_LoadBodyModel` was given - valid for as long as that
  buffer is (true for a real embedded, permanently-resident asset, the
  normal case on 3DS).
- **`CFL_GetBodyBoneBindLocalPose(body, i, &outPose)`** - hands back
  bone `i`'s own real REST (bind) local pose. Useful when your own
  loaded animation doesn't cover every bone `body` has - fill in the
  gaps with this instead of leaving a bone at an all-zero pose (which
  would collapse it onto its parent). Returns `false` (leaving
  `*outPose` untouched) if `body`/`i` is invalid.
- **`CFL_PoseBodyModel(body, poses, boneCount)`** - re-poses and
  re-skins `body` from an app-supplied per-bone LOCAL pose array
  (`boneCount` must equal `CFL_GetBodyBoneCount(body)`), or resets back
  to the file's own real bind pose if `poses`/`boneCount` is
  `NULL`/`0`. Safe to call every frame - see
  [Animation playback](#animation-playback) below for the full
  derivation and an [example](#animating-a-body-model). Genuinely does
  real per-vertex CPU work each call (re-skins every vertex of every
  part and re-uploads each part's `vbo`/`ibo`) - cheap for this
  library's own small body assets (~360 vertices across 2 parts), but
  not free, and not yet measured against a real frame budget on real
  hardware.

#### The IQM format, in detail

Body models load from real [IQM (Inter-Quake
Model)](http://sauerbraten.org/iqm/) files - the same open, documented
binary format Blender's own IQM importer/exporter, several other game
engines, and tools like `fte-team/fteqw` already support. This library
does **not** implement or require a project-specific format for body
assets at all; any IQM file that follows the conventions below will
load.

**What this library reads from a real IQM file:**

- **Text section** - used for two things: each joint's own real name,
  and each mesh's own real `material` name (see "Mesh material
  identity" below).
- **Joints** (`iqmjoint`) - real, standard IQM joint records: a parent
  index (strictly before the joint itself in the array - a normal IQM
  export convention, not a project-specific requirement) and a real
  LOCAL (parent-relative) `translate`/`rotate`(quaternion, XYZW)/`scale`.
  This library composes the real joint hierarchy itself, on-device,
  the general/correct way to consume this data - it does **not**
  expect a pre-baked world transform (real IQM has no such field
  anyway).
- **Vertex arrays** - four are *required*: `POSITION` and `NORMAL`
  (both `FLOAT`, 3 components) and `BLENDINDEXES`/`BLENDWEIGHTS` (both
  `UBYTE`, 4 components - real linear-blend-skinning data, weights
  0-255 summing to 255 per vertex). Any *other* vertex array a real
  exporter also writes (texcoords, tangents, vertex colors, ...) is
  simply ignored, not an error. A file missing any of the four
  required arrays fails to load.
- **Meshes and triangles** - each mesh's own vertex/triangle range,
  read directly; each mesh capped at 256 vertices (this library's own
  parts use `u8` indices) - a bigger single mesh needs splitting into
  more than one mesh at export time.
- **Poses/anims/frames** - read and bounds-validated if present (so a
  malformed animation section in a *body* `.iqm` is still caught, not
  silently ignored), but this library still has no code that samples
  these sections itself - `CFL_LoadBodyModel` only ever loads a body's
  bind pose. Real animation *data* (a separate `.iqm` file containing
  these same sections but no mesh at all) is entirely your own
  application's job to read and sample - see
  [Animation playback](#animation-playback) below for what this
  library gives you to actually *apply* a sampled pose once you have
  one.

**Mesh material identity - read the name, never the mesh's array
position.** Each mesh's own real, standard `material` text field must
be exactly `mt_body` or `mt_pants` - this is how `CFL_LoadBodyModel`
tells the body mesh apart from the pants mesh (and, for a
single-mesh body like a small icon-sized asset, `mt_body` is simply
the only mesh present). This is deliberately **not** inferred from
which mesh comes first in the file: real body/pants export order can
genuinely differ between two otherwise-equivalent source assets (a
male and female body rig exported from the same tool, for example, can
end up with their meshes in opposite order) - trusting array position
instead of the mesh's own declared identity is exactly the kind of bug
that silently swaps which part gets which color. An unrecognized or
missing material name is a hard parse failure, by design, rather than
a guess.

**Bone-scale category, resolved by joint name.** This library applies
a real, per-Mii, non-uniform stretch (`bodyScale`, above) to different
regions of the body differently - torso/hips/legs get the full
build/height vector, arms get two axes swapped, wrists/ankles get a
single uniform scalar, and the neck/head joint is clamped so it never
gets *shorter* than its rest length (matching `ariankordi/FFL.js`'s
own real `editorBodyScaleDesc` table). Real IQM has no field for this
project-specific concept, so it's resolved by matching each joint's
own real name (`skl_root`, `chest`, `arm_l1`, `arm_l2`, `wrist_l`,
`arm_r1`, `arm_r2`, `wrist_r`, `head`, `hip`, `foot_l1`, `foot_l2`,
`ankle_l`, `foot_r1`, `foot_r2`, `ankle_r`) against a small internal
table, defaulting to the full non-uniform vector for any joint name it
doesn't recognize. The joint literally named `head` is also where
`headBoneWorldMatrix` comes from.

**Real linear-blend skinning, not hardcoded rigid.** Every vertex is
transformed by a real weighted blend across up to 4 bone influences
(`blendindexes`/`blendweights`), summed and re-normalized, exactly
like any other real IQM consumer would. A rigid single-influence
asset (every real body model this project ships is exactly that -
100% weight on one bone, 0 on the rest) is simply the degenerate case
of the same general formula, not a separate code path.

**Producing your own body `.iqm` files.** This library doesn't ship or
require any particular export pipeline - any tool that writes a
spec-compliant IQM file with the vertex arrays and mesh material names
above will work (Blender's own IQM exporter is a reasonable starting
point: rig a mesh, weight-paint it, name your two material slots
`mt_body`/`mt_pants`, export as IQM). If you're generating IQM files
programmatically instead (e.g. from another 3D format, or procedurally),
remember: joints must be written parent-before-child, `BLENDWEIGHTS`
must sum to 255 per vertex, and quaternions are XYZW.

#### Animation playback

`CFL_LoadBodyModel` still only ever loads a body's real bind pose - it
composes final world-space vertex positions once, at load time, and
bakes the result into `vbo`/`ibo`. What changed is `CFL_PoseBodyModel`
(above): call it with a per-bone pose and it re-derives a full,
correctly-Mii-scaled skinned mesh from that pose instead, safe to call
every frame. This library still has **no code anywhere that reads an
`.iqm` animation's own `iqmpose`/`iqmanim`/frame sections** - sampling
real animation data and deciding when/how fast to play it is entirely
your own application's job, matching how this library has always kept
drawing/timing decisions out of its own scope (see
[Design](#design) above). `CFL_PoseBodyModel` is the one thing this
library needed to add to make that possible at all: before it existed,
`CFL_LoadBodyModel` threw away the real skeleton and per-vertex bone
weights right after the one bind-pose bake, so there was nothing left
for an app-side player to re-pose even in principle.

**What `CFL_PoseBodyModel` actually does, given a pose:**

1. Composes the given per-bone `CFLBoneLocalPose` array into WORLD
   transforms via a real parent-chain FK solve (quaternion → 3×3
   rotation matrix, then walking bones parent-before-child, composing
   each one's local transform against its already-computed parent) -
   the exact same composition `CFL_LoadBodyModel` itself already used
   for the bind pose, just handed a different (and, unlike the bind
   pose, generally non-identity-rotation) pose this time.
2. Re-applies this SAME body's own real per-Mii build/height bone-scale
   category stretch on top of that ANIMATED pose - the identical
   pipeline `CFL_LoadBodyModel` used for the bind pose (see
   [Bone-scale category](#the-iqm-format-in-detail) above), just
   driven by the animated world positions instead of the file's static
   ones. This is the part that actually matters for correctness: a
   tall/short or wide/narrow Mii's own real proportions carry through
   into the animated pose exactly as they already do for the static
   one, rather than an animation just being blended on top of an
   already-scaled bind pose (which would *not* respect per-Mii scale
   correctly).
3. Re-skins every vertex of every part (the same real weighted
   linear-blend formula across up to 4 bone influences described
   above, now genuinely applying each bone's own rotation too - the
   original bind-pose-only formula could skip rotation entirely, since
   a bind pose's real rotation is always identity) and re-uploads each
   part's `vbo`/`ibo`. Also updates `headBoneWorldMatrix` from the
   real animated+scaled head bone.

`poses`/`boneCount` = `NULL`/`0` resets back to the real bind pose
(far cheaper than a fresh `CFL_LoadBodyModel` call). A bone your own
loaded animation doesn't cover should be filled with
`CFL_GetBodyBoneBindLocalPose` rather than left zeroed - see the
example below.

**Sampling a pose from `iqmanim`/`iqmpose`/frame data yourself.** Real
IQM's own encoding: an `iqmanim` names a contiguous range of frames
(with a framerate) inside the file's own global frame list; each
`iqmpose` describes one joint's own 10 channels (3 translate + 4
rotate + 3 scale) via a `channeloffset`/`channelscale` pair per
channel plus a bitmask of which channels actually vary frame-to-frame
(a channel that's constant for the whole animation isn't stored
per-frame at all); each frame itself is a flat array of packed `u16`
values, one per *animated* channel across every joint, in order -
decoding one frame means walking each joint's own pose channel mask
and either reading+dequantizing the next `u16`
(`channeloffset + rawValue * channelscale`) or just using
`channeloffset` directly for a channel the mask says is constant. See
[Animating a body model](#animating-a-body-model) below for a real,
complete reader.

**Matching an animation's own joints to a body's own bones, by name.**
A real anim-only `.iqm` (no mesh at all - just joints/poses/anims/
frames, the shape you get from a tool that exports "just the
animation") isn't guaranteed to store its joints in the same array
order as the body file it was authored against, even when both
describe the same real skeleton - match by `CFL_GetBodyBoneName`
against the animation's own joint names instead of assuming array
order lines up.

### Icon rendering

```c
typedef enum {
    CFL_ICON_BG_FAVORITE = 0,  // fill with the Mii's own favorite color
    CFL_ICON_BG_DIRECT = 1,    // fill with setting->bgColor
    CFL_ICON_BG_NO_CLEAR = 2,  // don't clear the canvas at all
} CFLIconBGType;

typedef void (*CFLIconCustomCallback)(void* customArgument, const CFLPart* part,
                                       const C3D_Mtx* projection, const C3D_Mtx* modelView);

typedef struct {
    CFLIconBGType bgType;
    float bgColor[4];                     // used when bgType == CFL_ICON_BG_DIRECT
    CFLIconCustomCallback customCallback;  // NULL = use this library's own default shading
    void* customArgument;
} CFLIconSetting;

bool CFL_CommandMakeModelIcon(CFLCharModel* model, CFLExpression expression,
                               int iconSize, const CFLIconSetting* setting, C3D_Tex* outIcon);
```

Real CFL function (`CFL_CommandMakeModelIcon`, DWARF-confirmed), and
the one real exception to "CFL doesn't draw" - its whole job is
producing a rendered square texture, using real CFL's own fixed icon
camera (not customizable). `expression` must be one of the bits
declared at `CFL_InitCharModel` time; if it wasn't successfully baked,
the icon falls back to whichever expression is currently bound rather
than failing (this function never mutates `model`). `setting` may be
`NULL` for plain defaults.

**Body support**: if `model->attachedBody` is set (via
`CFL_AttachBody`), the body draws alongside the head automatically -
there's no separate "make icon with body" function, matching real
`ariankordi/FFL.js`'s own architecture of attaching a head once and
reusing one generic render path either way. The head itself is drawn
completely unchanged (same fixed position/size as the bodyless case) -
the *body* is what gets positioned, shifted so its own real neck-bone
world position lands under the head, rather than the head moving to
meet the body. `CFL_HEAD_TO_BODY_SCALE` is **not** applied here (the
head is never rescaled for the icon) - real hardware testing found
the simplest, most direct result (an unscaled head, a repositioned
body) looked correct, after several attempts at an explicit size ratio
either over- or under-shot.

**Ownership**: `CFL_CommandMakeModelIcon` creates a fresh render
target, draws into it, and tears the render target back down again -
all within the one call. `*outIcon` is a completely ordinary
`C3D_Tex`; you own it exactly the way you'd own any other texture this
library hands back (e.g. `CFLPart.tex`) and free it with a plain
`C3D_TexDelete(&icon)` when you're done. Calling
`CFL_CommandMakeModelIcon` again on the *same* `C3D_Tex` (e.g. to
render a new expression, or to toggle `attachedBody` on and off) is
always safe without freeing it yourself first - this function frees any
previous render already on that struct automatically before making a
new one, so repeated calls on one persistent `C3D_Tex` never leak.

### Mii database access

```c
bool CFL_SearchOfficialData(const MiiData* mii, u16* outIndex);
bool CFL_IsAvailableOfficialData(u16 index);
bool CFL_GetOfficialData(u16 index, MiiData* outMii);
int  CFL_GetAvailableOfficialDataNum(void);
bool CFL_GetMyMiiIndex(u16* outIndex);
```

Real, read-only access to the console's own Mii database
(`CFL_DB.dat`, the same 100-slot store Mii Maker/the Mii Selector use)
- cached once at `CFL_Initialize` time, matching real CFL's own real
init order. **All of these can legitimately fail** if the console has
never had Mii Maker opened (no database file exists yet) - always
check the return value, don't assume the database is there.

- **`CFL_SearchOfficialData(mii, &index)`** - find a specific Mii's
  real slot (0-99) by identity (Mii ID + creator MAC, not by name).
  This is the real mechanism games use to make the Mii Selector applet
  reopen on the Mii it last showed (`miiSelectorSetInitialIndex`).
- **`CFL_IsAvailableOfficialData(index)`** - does this raw slot
  (0-99) hold a Mii at all?
- **`CFL_GetOfficialData(index, &mii)`** - fetch the actual `MiiData`
  at a slot.
- **`CFL_GetAvailableOfficialDataNum()`** - how many of the 100 slots
  are occupied. Returns `-1` if the database isn't available at all
  (distinct from a real `0`, which means "database exists, but
  empty").
- **`CFL_GetMyMiiIndex(&index)`** - the console owner's own Mii index.
  Returns `false` (with `*outIndex` still set to `0`) if unavailable -
  a caller that doesn't check the return sees the same "default to 0"
  behavior real CFL's own callers would, but checking it tells you
  whether that `0` is real.

### Store data (export/import)

```c
bool CFL_MakeStoreData(const MiiData* mii, CFLStoreData* out);
bool CFL_IsStoreDataValid(const CFLStoreData* storeData);
```

`CFLStoreData` (libctru's own real struct, `<3ds/mii.h>`) is the
standard checksummed wrapper Miis are exchanged in (QR codes,
StreetPass, NFC) - `{ MiiData miiData; u8 pad[2]; u16 crc16; }`.
`CFL_MakeStoreData` computes the real CRC16-CCITT self-check (zero the
checksum field, CRC the whole 96-byte structure including the zeroed
field, write the result back) and fills `out`. `CFL_IsStoreDataValid`
re-runs that same check and confirms it comes out to `0` - use this on
any `CFLStoreData` you didn't just create yourself (e.g. one decoded
from a QR code or received over StreetPass) before trusting its
`miiData` field.

### Utility

```c
const float* CFL_GetFavoriteColor(u8 index);
int CFL_GetWorkSize(bool hdModeEnabled);
void dbglog(const char* fmt, ...);
void dbglogErr(const char* fmt, ...);
void dbglogVramStats(const char* context, bool onScreen);
```

- **`CFL_GetFavoriteColor(index)`** - the real 12-entry favorite-color
  table as an `{r,g,b}` float triple. Out-of-range indices clamp to
  the last entry (11/black), matching real CFL's own real behavior -
  not a fallback to index 0.
- **`CFL_GetWorkSize(hdModeEnabled)`** - informational only (this
  library manages its own citro3d allocations, it never takes real
  CFL's memory-arena parameters) - shows what real CFL's own work
  buffer would have needed for the same operation.
- **`dbglog`/`dbglogErr`/`dbglogVramStats`** - printf-style logging
  into the log `CFL_EnableSDDebug` opens - `dbglogErr` also prints to
  the bottom-screen console, for genuine failures worth surfacing
  immediately.

## Validation checklist

Real, easy-to-hit failure cases this library reports rather than
crashing on - check these rather than assuming success:

- **`CFL_Initialize()` can fail** - almost always missing ARM11 FS
  permissions. Don't call anything else in this library if it returns
  `false`.
- **`CFL_InitCharModel` can partially fail** - it only returns `false`
  if the face itself couldn't be built; every other part (hair, cap,
  goatee, nose, glasses, and each individual pre-baked expression) can
  silently fail on its own (most commonly VRAM exhaustion from
  requesting too many expressions/too high a resolution across too
  many simultaneous models). Check `CFL_HasCharModel` for the
  minimum-viable case, and the SD log (`CFL_EnableSDDebug(true)`) for
  exactly what got skipped.
- **`CFL_SetExpression` fails silently on an unavailable expression**
  (wrong flag, or that one failed to bake) - it leaves the current
  expression alone rather than doing anything destructive, but check
  `CFL_IsAvailableExpression` first if your UI needs to know in
  advance whether a switch will work.
- **`CFL_LoadBodyModel` fails on a malformed or unrecognized IQM file**
  - a real, well-formed IQM file that's simply missing one of the four
  required vertex arrays, or whose mesh material names aren't
  `mt_body`/`mt_pants`, is a hard failure by design (see
  [The IQM format, in detail](#the-iqm-format-in-detail) above) rather
  than a best-effort partial load - check the return value before
  using `*outBody`.
- **Every `CFL_*OfficialData` function can fail if Mii Maker has never
  been opened on this console** - there's no `CFL_DB.dat` to read yet.
  This is a normal, expected state (common on a fresh console/emulator
  profile), not an error to alarm the user over.
- **`CFL_IsStoreDataValid` before trusting any `CFLStoreData` you
  didn't create yourself** - a corrupted or malformed QR code/NFC tag
  should never be fed straight into `CFL_InitCharModel` unchecked.
- **`CFLCharModel` must be zero-initialized before its first use** -
  static/global storage already gets this for free from C; a stack
  variable needs `= {0}` explicitly.
- **`CFL_PoseBodyModel` fails (leaving `body` unchanged) if `body` has
  no retained rig data, or `boneCount` doesn't match
  `CFL_GetBodyBoneCount(body)`** - check `CFL_GetBodyBoneCount(body) >
  0` once after `CFL_LoadBodyModel` before ever building a `poses`
  array sized for it, and always pass the CURRENT `CFL_GetBodyBoneCount`
  result as `boneCount`, not a value cached from an earlier body.

## Examples

All of these compile and link as-is against nothing but this library,
libctru, and citro3d - no other project files needed. The "body model"
example reuses `drawModelPartsAt` from the first example below it
rather than duplicating the per-part draw loop - copy both if you want
that one standalone.

### Rendering a CharModel with the default shader

```c
#include <3ds.h>
#include <citro3d.h>
#include "cfl_mii.h"

typedef struct { float position[3]; float normal[3]; float texcoord[2]; } Vertex;

#define DISPLAY_TRANSFER_FLAGS \
	(GX_TRANSFER_FLIP_VERT(0) | GX_TRANSFER_OUT_TILED(0) | GX_TRANSFER_RAW_COPY(0) | \
	GX_TRANSFER_IN_FORMAT(GX_TRANSFER_FMT_RGBA8) | GX_TRANSFER_OUT_FORMAT(GX_TRANSFER_FMT_RGB8) | \
	GX_TRANSFER_SCALING(GX_TRANSFER_SCALE_NO))

// The actual per-part draw loop, taking an explicit modelView - factored
// out this way (rather than building a fixed modelView internally) so
// the "body model" example further down can reuse this unchanged and
// just hand it a DIFFERENT modelView (the head repositioned to a body's
// own neck bone) instead of duplicating this whole loop.
static void drawModelPartsAt(const CFLCharModel* model, const C3D_Mtx* projection, const C3D_Mtx* modelView)
{
	CFLShaderLocations loc = CFL_GetShaderLocations();
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, loc.projection, projection);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, loc.modelView, modelView);

	CFL_BindDefaultShader();

	// Stage 1 adds the default shader's specular term on top of stage
	// 0's diffuse+ambient result - required for CFL_SetDefaultMaterial's
	// specular to actually show up.
	C3D_TexEnv* env1 = C3D_GetTexEnv(1);
	C3D_TexEnvInit(env1);
	C3D_TexEnvSrc(env1, C3D_RGB, GPU_PREVIOUS, GPU_FRAGMENT_SECONDARY_COLOR, 0);
	C3D_TexEnvFunc(env1, C3D_RGB, GPU_ADD);
	C3D_TexEnvSrc(env1, C3D_Alpha, GPU_PREVIOUS, 0, 0);
	C3D_TexEnvFunc(env1, C3D_Alpha, GPU_REPLACE);
	C3D_DirtyTexEnv(env1);

	int partCount = CFL_GetPartCount(model);
	for (int pass = 0; pass < 2; pass++) {
		bool texturedPass = (pass == 1);
		C3D_AlphaBlend(GPU_BLEND_ADD, GPU_BLEND_ADD, GPU_SRC_ALPHA, GPU_ONE_MINUS_SRC_ALPHA, GPU_SRC_ALPHA, GPU_ONE_MINUS_SRC_ALPHA);

		for (int i = 0; i < partCount; i++) {
			const CFLPart* part = CFL_GetPart(model, i);
			if (part->hasTexture != texturedPass) continue;

			C3D_DepthTest(true, GPU_GEQUAL, part->depthWrite ? GPU_WRITE_ALL : GPU_WRITE_COLOR);

			C3D_BufInfo* bufInfo = C3D_GetBufInfo();
			BufInfo_Init(bufInfo);
			BufInfo_Add(bufInfo, part->vbo, sizeof(Vertex), 3, 0x210);

			CFL_SetDefaultMaterial(part->color, part->noSpecular);

			C3D_TexEnv* env0 = C3D_GetTexEnv(0);
			if (part->hasTexture) {
				C3D_TexBind(0, (C3D_Tex*)&part->tex);
				C3D_TexEnvInit(env0);
				// Alpha-only formats (A4/A8) have undocumented RGB output
				// on real hardware - REPLACE with the tint directly.
				// Luminance formats (I4/I8/IA4/IA8) carry real per-pixel
				// pattern data - MODULATE preserves it.
				if (part->isAlphaOnly) {
					C3D_TexEnvSrc(env0, C3D_RGB, GPU_FRAGMENT_PRIMARY_COLOR, 0, 0);
					C3D_TexEnvFunc(env0, C3D_RGB, GPU_REPLACE);
				} else {
					C3D_TexEnvSrc(env0, C3D_RGB, GPU_TEXTURE0, GPU_FRAGMENT_PRIMARY_COLOR, 0);
					C3D_TexEnvFunc(env0, C3D_RGB, GPU_MODULATE);
				}
				C3D_TexEnvSrc(env0, C3D_Alpha, GPU_TEXTURE0, 0, 0);
				C3D_TexEnvFunc(env0, C3D_Alpha, GPU_REPLACE);
			} else {
				C3D_TexEnvInit(env0);
				C3D_TexEnvSrc(env0, C3D_Both, GPU_FRAGMENT_PRIMARY_COLOR, 0, 0);
				C3D_TexEnvFunc(env0, C3D_Both, GPU_REPLACE);
			}

			// CAP's own real tint formula needs one extra additive stage -
			// see CFLPart.capBlend's own note above. Bracketed around just
			// this one part's own draw call, nothing else.
			if (part->capBlend) {
				C3D_TexEnv* env2 = C3D_GetTexEnv(2);
				C3D_TexEnvInit(env2);
				C3D_TexEnvSrc(env2, C3D_RGB, GPU_PREVIOUS, GPU_FRAGMENT_PRIMARY_COLOR, 0);
				C3D_TexEnvFunc(env2, C3D_RGB, GPU_ADD);
				C3D_TexEnvSrc(env2, C3D_Alpha, GPU_PREVIOUS, 0, 0);
				C3D_TexEnvFunc(env2, C3D_Alpha, GPU_REPLACE);
				C3D_DirtyTexEnv(env2);
			}

			if (part->useIndices)
				C3D_DrawElements(GPU_TRIANGLES, part->indexCount, C3D_UNSIGNED_BYTE, part->ibo);
			else
				C3D_DrawArrays(GPU_TRIANGLES, 0, part->vertexCount);

			if (part->capBlend) {
				C3D_TexEnv* env2 = C3D_GetTexEnv(2);
				C3D_TexEnvInit(env2);
				C3D_DirtyTexEnv(env2);
			}
		}
	}
}

static void drawModel(const CFLCharModel* model, const C3D_Mtx* projection)
{
	C3D_Mtx modelView;
	Mtx_Identity(&modelView);
	Mtx_Translate(&modelView, 0.0f, 0.0f, -2.0f, true);
	Mtx_Scale(&modelView, 0.032f, 0.032f, 0.032f);
	drawModelPartsAt(model, projection, &modelView);
}

int main(void)
{
	gfxInitDefault();
	C3D_Init(C3D_DEFAULT_CMDBUF_SIZE);

	C3D_RenderTarget* target = C3D_RenderTargetCreate(240, 400, GPU_RB_RGBA8, GPU_RB_DEPTH24_STENCIL8);
	C3D_RenderTargetSetOutput(target, GFX_TOP, GFX_LEFT, DISPLAY_TRANSFER_FLAGS);

	if (!CFL_Initialize()) {
		gfxExit();
		return 1;
	}

	// Real Mii data from the system Mii Selector applet - CFL only
	// builds a model from MiiData you hand it, it has no opinion on how
	// you got it.
	MiiSelectorConf conf;
	MiiSelectorReturn ret;
	miiSelectorInit(&conf);
	miiSelectorLaunch(&conf, &ret);

	CFLCharModel model = {0}; // must be zero-initialized before first use
	if (!CFL_InitCharModel(&model, &ret.mii, CFL_RESOLUTION_256, CFL_EXPRESSION_FLAG(CFL_EXPRESSION_NORMAL))) {
		// Face itself failed to build - CFL_Initialize probably didn't
		// succeed, or the archive is missing/corrupt. Bail out rather
		// than drawing a model with no parts.
		CFL_Finalize();
		C3D_Fini();
		gfxExit();
		return 1;
	}

	C3D_Mtx projection;
	Mtx_PerspTilt(&projection, C3D_AngleFromDegrees(50.0f), C3D_AspectRatioTop, 0.01f, 1000.0f, false);

	CFL_RebindShader();

	while (aptMainLoop()) {
		hidScanInput();
		if (hidKeysDown() & KEY_START) break;

		C3D_FrameBegin(C3D_FRAME_SYNCDRAW);
			C3D_RenderTargetClear(target, C3D_CLEAR_ALL, 0x404040FF, 0);
			C3D_FrameDrawOn(target);
			drawModel(&model, &projection);
		C3D_FrameEnd(0);
	}

	CFL_DeleteModel(&model);
	CFL_Finalize();
	C3D_Fini();
	gfxExit();
	return 0;
}
```

### Multiple simultaneous models

`CFLCharModel` is a plain caller-owned struct, so holding several at
once is just an array - no special API needed:

```c
#define MAX_MII 4
static CFLCharModel models[MAX_MII] = {0}; // zero-initialized: static storage
static int modelCount = 0;

static bool addMii(const MiiData* mii)
{
	if (modelCount >= MAX_MII) return false;
	// A lower resolution and a smaller expression set here keeps VRAM
	// usage sane across several simultaneous models - see the
	// CFL_InitCharModel docs above for the real per-expression cost.
	if (!CFL_InitCharModel(&models[modelCount], mii, CFL_RESOLUTION_64,
	                        CFL_EXPRESSION_FLAG(CFL_EXPRESSION_NORMAL))) {
		return false;
	}
	modelCount++;
	return true;
}

// ...later, in your draw loop: just loop over models[0..modelCount) and
// draw each with drawModel() from the example above, at a different
// world-space offset per model.
```

### Switching expressions

```c
// Requested up front at CFL_InitCharModel time:
CFL_InitCharModel(&model, &mii, CFL_RESOLUTION_128,
                   CFL_EXPRESSION_FLAG(CFL_EXPRESSION_NORMAL) |
                   CFL_EXPRESSION_FLAG(CFL_EXPRESSION_SMILE)  |
                   CFL_EXPRESSION_FLAG(CFL_EXPRESSION_SURPRISE));

// ...later, an instant switch - no rebuild:
if (CFL_IsAvailableExpression(&model, CFL_EXPRESSION_SMILE)) {
	CFL_SetExpression(&model, CFL_EXPRESSION_SMILE);
} else {
	// Wasn't requested above, or failed to bake (VRAM pressure) -
	// CFL_GetExpression(&model) still reflects whatever's actually shown.
}
```

### Listing every Mii saved on the console

```c
int total = CFL_GetAvailableOfficialDataNum();
if (total < 0) {
	// No CFL_DB.dat at all - Mii Maker has never been opened on this
	// console. A real, normal state to handle, not necessarily an error.
} else {
	for (u16 i = 0; i < 100; i++) {
		if (!CFL_IsAvailableOfficialData(i)) continue;
		MiiData mii;
		if (CFL_GetOfficialData(i, &mii)) {
			// mii is a real, valid MiiData from slot i.
		}
	}
}
```

### Re-opening the Mii Selector on the last-picked Mii

```c
static MiiData lastPicked;
static bool haveLastPicked = false;

static void pickMii(void)
{
	MiiSelectorConf conf;
	miiSelectorInit(&conf);

	u16 initialIndex;
	if (haveLastPicked && CFL_SearchOfficialData(&lastPicked, &initialIndex)) {
		miiSelectorSetInitialIndex(&conf, initialIndex);
	}

	MiiSelectorReturn ret;
	miiSelectorLaunch(&conf, &ret);
	lastPicked = ret.mii;
	haveLastPicked = true;
}
```

### Exporting and validating `CFLStoreData`

```c
// Export: real Mii -> the standard checksummed exchange format.
CFLStoreData store;
if (CFL_MakeStoreData(&mii, &store)) {
	// store is now ready to write into a QR code, send over StreetPass, etc.
}

// Import: never trust a CFLStoreData you didn't just create yourself.
CFLStoreData received = /* decoded from a QR code, NFC tag, etc. */;
if (CFL_IsStoreDataValid(&received)) {
	CFL_InitCharModel(&model, &received.miiData, CFL_RESOLUTION_128,
	                   CFL_EXPRESSION_FLAG(CFL_EXPRESSION_NORMAL));
} else {
	// Checksum failed - corrupted or malformed data, don't use it.
}
```

### Creating a transparent icon

```c
#include <3ds.h>
#include <citro3d.h>
#include "cfl_mii.h"

int main(void)
{
	gfxInitDefault();
	C3D_Init(C3D_DEFAULT_CMDBUF_SIZE);

	if (!CFL_Initialize()) {
		gfxExit();
		return 1;
	}

	MiiSelectorConf conf;
	MiiSelectorReturn ret;
	miiSelectorInit(&conf);
	miiSelectorLaunch(&conf, &ret);

	CFLCharModel model = {0};
	CFL_InitCharModel(&model, &ret.mii, CFL_RESOLUTION_256, CFL_EXPRESSION_FLAG(CFL_EXPRESSION_NORMAL));

	// Transparent background instead of the library's own default
	// (CFL_ICON_BG_FAVORITE) - alpha=0 clears to fully transparent.
	CFLIconSetting setting = { CFL_ICON_BG_DIRECT, { 0.0f, 0.0f, 0.0f, 0.0f }, NULL, NULL };

	C3D_Tex icon = {0};
	if (CFL_CommandMakeModelIcon(&model, CFL_EXPRESSION_NORMAL, 256, &setting, &icon)) {
		// `icon` is a normal C3D_Tex with real per-pixel alpha - draw it
		// as an alpha-blended textured quad, same as any other
		// transparent texture. Release with a plain C3D_TexDelete when done.
		C3D_TexDelete(&icon);
	}

	CFL_DeleteModel(&model);
	CFL_Finalize();
	C3D_Fini();
	gfxExit();
	return 0;
}
```

### Rendering a body model in real time

`CFLBodyPart` is drawn exactly like an untextured `CFLPart` (same
vbo/ibo/color shape, same default shader) - the only new step is
positioning the head at the body's own real neck-bone world position
instead of a fixed offset. This example assumes a real, standard IQM
body asset has already been embedded and exported as
`body_iqm`/`body_iqm_size` (the usual devkitPro `bin2s` convention -
see [cfl-tool](https://github.com/jamesrhg/cfl-tool)'s own `data/`
directory and `Makefile` for real, ready-to-use `.iqm` files and how
they're embedded):

```c
#include <3ds.h>
#include <citro3d.h>
#include "cfl_mii.h"
#include "body_iqm.h" // extern const u8 body_iqm[]; extern const u32 body_iqm_size;

typedef struct { float position[3]; float normal[3]; float texcoord[2]; } Vertex;

// Draws a CFLBodyModel's own parts (body, pants) - same TEV/blend setup
// as a plain untextured CFLPart, just looping CFLBodyPart instead.
static void drawBody(const CFLBodyModel* body, const C3D_Mtx* projection, const C3D_Mtx* modelView)
{
	CFLShaderLocations loc = CFL_GetShaderLocations();
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, loc.projection, projection);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, loc.modelView, modelView);
	CFL_BindDefaultShader();

	C3D_TexEnv* env1 = C3D_GetTexEnv(1);
	C3D_TexEnvInit(env1);
	C3D_TexEnvSrc(env1, C3D_RGB, GPU_PREVIOUS, GPU_FRAGMENT_SECONDARY_COLOR, 0);
	C3D_TexEnvFunc(env1, C3D_RGB, GPU_ADD);
	C3D_TexEnvSrc(env1, C3D_Alpha, GPU_PREVIOUS, 0, 0);
	C3D_TexEnvFunc(env1, C3D_Alpha, GPU_REPLACE);
	C3D_DirtyTexEnv(env1);

	C3D_AlphaBlend(GPU_BLEND_ADD, GPU_BLEND_ADD, GPU_SRC_ALPHA, GPU_ONE_MINUS_SRC_ALPHA, GPU_SRC_ALPHA, GPU_ONE_MINUS_SRC_ALPHA);

	for (int i = 0; i < body->partCount; i++) {
		const CFLBodyPart* part = &body->parts[i];
		C3D_DepthTest(true, GPU_GEQUAL, GPU_WRITE_ALL);

		C3D_BufInfo* bufInfo = C3D_GetBufInfo();
		BufInfo_Init(bufInfo);
		BufInfo_Add(bufInfo, part->vbo, sizeof(Vertex), 3, 0x210);

		CFL_SetDefaultMaterial(part->color, false);

		C3D_TexEnv* env0 = C3D_GetTexEnv(0);
		C3D_TexEnvInit(env0);
		C3D_TexEnvSrc(env0, C3D_Both, GPU_FRAGMENT_PRIMARY_COLOR, 0, 0);
		C3D_TexEnvFunc(env0, C3D_Both, GPU_REPLACE);

		C3D_DrawElements(GPU_TRIANGLES, part->indexCount, C3D_UNSIGNED_BYTE, part->ibo);
	}
}

// Draws body, then the head repositioned to the body's own real neck-bone
// world position (scaled per-Mii via CFLBodyModel.bodyScale, already baked
// in by CFL_LoadBodyModel) - CFL_HEAD_TO_BODY_SCALE reconciles the two
// independently-authored coordinate spaces.
static void drawModelWithBody(const CFLCharModel* model, const CFLBodyModel* body,
                               const C3D_Mtx* projection, float scale)
{
	C3D_Mtx cameraView;
	Mtx_Identity(&cameraView);
	Mtx_Translate(&cameraView, 0.0f, -1.5f, -6.0f, true);

	if (body && body->partCount > 0) {
		C3D_Mtx bodyView = cameraView;
		Mtx_Scale(&bodyView, scale, scale, scale);
		drawBody(body, projection, &bodyView);
	}

	C3D_Mtx headView = cameraView;
	if (body && body->hasHeadBone) {
		const float* m = body->headBoneWorldMatrix; // 3 rows of 4: row_i = [Ai0,Ai1,Ai2,ti]
		Mtx_Translate(&headView, m[3] * scale, m[7] * scale, m[11] * scale, true);
		Mtx_Scale(&headView, scale * CFL_HEAD_TO_BODY_SCALE, scale * CFL_HEAD_TO_BODY_SCALE, scale * CFL_HEAD_TO_BODY_SCALE);
	} else {
		Mtx_Scale(&headView, scale, scale, scale);
	}
	// The same per-part draw loop as "Rendering a CharModel with the
	// default shader" above, just handed this explicit headView instead
	// of building its own fixed modelView - see that example for the
	// full loop body (CFL_GetPartCount/CFL_GetPart, the two-pass
	// untextured/textured TEV setup, the capBlend bracket, etc).
	drawModelPartsAt(model, projection, &headView);
}

int main(void)
{
	gfxInitDefault();
	C3D_Init(C3D_DEFAULT_CMDBUF_SIZE);

	C3D_RenderTarget* target = C3D_RenderTargetCreate(240, 400, GPU_RB_RGBA8, GPU_RB_DEPTH24_STENCIL8);
	C3D_RenderTargetSetOutput(target, GFX_TOP, GFX_LEFT, DISPLAY_TRANSFER_FLAGS);

	if (!CFL_Initialize()) { gfxExit(); return 1; }

	MiiSelectorConf conf;
	MiiSelectorReturn ret;
	miiSelectorInit(&conf);
	miiSelectorLaunch(&conf, &ret);

	CFLCharModel model = {0};
	CFL_InitCharModel(&model, &ret.mii, CFL_RESOLUTION_128, CFL_EXPRESSION_FLAG(CFL_EXPRESSION_NORMAL));

	CFLBodyModel body = {0};
	bool hasBody = CFL_LoadBodyModel(body_iqm, body_iqm_size, &ret.mii, &body);
	// Body load failure is deliberately non-fatal - fall back to
	// head-only (drawModelWithBody already handles body == NULL).

	C3D_Mtx projection;
	Mtx_PerspTilt(&projection, C3D_AngleFromDegrees(50.0f), C3D_AspectRatioTop, 0.01f, 1000.0f, false);

	CFL_RebindShader();

	while (aptMainLoop()) {
		hidScanInput();
		if (hidKeysDown() & KEY_START) break;

		C3D_FrameBegin(C3D_FRAME_SYNCDRAW);
			C3D_RenderTargetClear(target, C3D_CLEAR_ALL, 0x404040FF, 0);
			C3D_FrameDrawOn(target);
			drawModelWithBody(&model, hasBody ? &body : NULL, &projection, 0.032f);
		C3D_FrameEnd(0);
	}

	if (hasBody) CFL_DeleteBodyModel(&body);
	CFL_DeleteModel(&model);
	CFL_Finalize();
	C3D_Fini();
	gfxExit();
	return 0;
}
```

### Animating a body model

This library has no code that reads an animation `.iqm`'s own
`iqmpose`/`iqmanim`/frame sections itself (see
[Animation playback](#animation-playback) above) - that part is
genuinely your own application's job. This example is a real,
self-contained reader for exactly the shape a real *anim-only* `.iqm`
has (joints/poses/anims/frames, no mesh at all - the kind of file you
get from a tool whose job is "export just the animation"), plus the
bone-name matching and per-frame sampling that feeds `CFL_PoseBodyModel`.
Builds on the previous example - assumes `body`/`model`/`drawModelWithBody`
already exist, and a separate `walk_iqm`/`walk_iqm_size` (a real
anim-only export) is embedded the same way `body_iqm` was:

```c
#include <3ds.h>
#include <string.h>
#include <math.h>
#include "cfl_mii.h"
#include "walk_iqm.h" // extern const u8 walk_iqm[]; extern const u32 walk_iqm_size;

#define ANIM_MAX_JOINTS 18 // matches CFL_BODY_MAX_BONES

typedef struct {
    u32 jointCount;
    char jointNames[ANIM_MAX_JOINTS][32];
    u32 frameCount;
    float framerate;
    CFLBoneLocalPose* framePoses; // malloc'd: frameCount*jointCount, [frame*jointCount+joint]
} BodyAnimClip;

// Real IQM struct layouts this reader needs - deliberately independent of
// anything cfl_mii.h exposes (a real anim-only file has no mesh data at
// all, a simpler shape than what CFL_LoadBodyModel is built to read).
typedef struct {
    char magic[16]; u32 version, filesize, flags;
    u32 num_text, ofs_text;
    u32 num_meshes, ofs_meshes;
    u32 num_vertexarrays, num_vertexes, ofs_vertexarrays;
    u32 num_triangles, ofs_triangles, ofs_adjacency;
    u32 num_joints, ofs_joints;
    u32 num_poses, ofs_poses;
    u32 num_anims, ofs_anims;
    u32 num_frames, num_framechannels, ofs_frames, ofs_bounds;
    u32 num_comment, ofs_comment;
    u32 num_extensions, ofs_extensions;
} IqmHeader;
typedef struct { u32 name; s32 parent; float translate[3], rotate[4], scale[3]; } IqmJoint;
typedef struct { s32 parent; u32 mask; float channeloffset[10], channelscale[10]; } IqmPose;
typedef struct { u32 name, first_frame, num_frames; float framerate; u32 flags; } IqmAnim;

static void quatNormalize(float q[4]) {
    float len = sqrtf(q[0]*q[0]+q[1]*q[1]+q[2]*q[2]+q[3]*q[3]);
    if (len > 1e-8f) { q[0]/=len; q[1]/=len; q[2]/=len; q[3]/=len; }
    else { q[0]=0; q[1]=0; q[2]=0; q[3]=1; }
}

// Bounds-checks every section it reads, including a real per-read cursor
// check while decoding the flat frame-channel stream (not just an
// up-front total-size check) - a malformed file fails loudly, not
// silently. Decodes the whole clip into a dense [frame][joint] array once.
static bool loadAnimClip(const u8* data, u32 size, BodyAnimClip* out) {
    memset(out, 0, sizeof(*out));
    if (size < sizeof(IqmHeader)) return false;
    IqmHeader hdr; memcpy(&hdr, data, sizeof(hdr));
    if (memcmp(hdr.magic, "INTERQUAKEMODEL\0", 16) != 0) return false;
    if (hdr.version != 2 || hdr.filesize > size) return false;

    #define FITS(ofs, count, itemSize) ((u64)(ofs) + (u64)(count) * (u64)(itemSize) <= size)

    const char* text = NULL;
    if (hdr.num_text) {
        if (!FITS(hdr.ofs_text, hdr.num_text, 1)) return false;
        text = (const char*)(data + hdr.ofs_text);
    }
    if (hdr.num_joints == 0 || hdr.num_joints > ANIM_MAX_JOINTS) return false;
    if (!FITS(hdr.ofs_joints, hdr.num_joints, sizeof(IqmJoint))) return false;
    out->jointCount = hdr.num_joints;
    for (u32 i = 0; i < hdr.num_joints; i++) {
        IqmJoint j; memcpy(&j, data + hdr.ofs_joints + (size_t)i * sizeof(j), sizeof(j));
        const char* name = (text && j.name < hdr.num_text) ? (text + j.name) : "";
        strncpy(out->jointNames[i], name, sizeof(out->jointNames[i]) - 1);
    }

    if (hdr.num_poses != hdr.num_joints || hdr.num_frames == 0) return false;
    if (!FITS(hdr.ofs_poses, hdr.num_poses, sizeof(IqmPose))) return false;
    IqmPose poses[ANIM_MAX_JOINTS];
    memcpy(poses, data + hdr.ofs_poses, (size_t)hdr.num_poses * sizeof(IqmPose));
    if (!FITS(hdr.ofs_frames, (u64)hdr.num_frames * hdr.num_framechannels, sizeof(u16))) return false;

    out->frameCount = hdr.num_frames;
    out->framerate = 30.0f;
    if (hdr.num_anims > 0 && FITS(hdr.ofs_anims, 1, sizeof(IqmAnim))) {
        IqmAnim a; memcpy(&a, data + hdr.ofs_anims, sizeof(a));
        if (a.framerate > 0.0f) out->framerate = a.framerate;
    }

    out->framePoses = malloc(sizeof(CFLBoneLocalPose) * (size_t)out->frameCount * out->jointCount);
    if (!out->framePoses) { memset(out, 0, sizeof(*out)); return false; }

    const u16* cursor = (const u16*)(data + hdr.ofs_frames);
    const u16* cursorEnd = cursor + (size_t)hdr.num_frames * hdr.num_framechannels;
    for (u32 f = 0; f < hdr.num_frames; f++) {
        for (u32 j = 0; j < hdr.num_joints; j++) {
            const IqmPose* pose = &poses[j];
            float vals[10];
            for (int c = 0; c < 10; c++) {
                if (pose->mask & (1u << c)) {
                    if (cursor >= cursorEnd) { free(out->framePoses); memset(out, 0, sizeof(*out)); return false; }
                    vals[c] = pose->channeloffset[c] + (*cursor) * pose->channelscale[c];
                    cursor++;
                } else vals[c] = pose->channeloffset[c];
            }
            CFLBoneLocalPose* p = &out->framePoses[f * out->jointCount + j];
            p->translate[0]=vals[0]; p->translate[1]=vals[1]; p->translate[2]=vals[2];
            p->rotate[0]=vals[3]; p->rotate[1]=vals[4]; p->rotate[2]=vals[5]; p->rotate[3]=vals[6];
            quatNormalize(p->rotate);
            p->scale[0]=vals[7]; p->scale[1]=vals[8]; p->scale[2]=vals[9];
        }
    }
    #undef FITS
    return true;
}

// Samples `clip` at a (possibly fractional) frame, looping, into
// `outPoses` (indexed by the CLIP's own joint order) - linear for
// translate/scale, nlerp (normalized lerp with the standard shortest-arc
// sign fix) for rotation, a cheap and visually-indistinguishable-from-slerp
// approximation for adjacent source frames.
static void sampleAnimClip(const BodyAnimClip* clip, float frame, CFLBoneLocalPose* outPoses) {
    if (clip->frameCount == 0) return;
    float wrapped = fmodf(frame, (float)clip->frameCount);
    if (wrapped < 0.0f) wrapped += (float)clip->frameCount;
    u32 f0 = (u32)wrapped, f1 = (f0 + 1) % clip->frameCount;
    float t = wrapped - (float)f0;
    for (u32 j = 0; j < clip->jointCount; j++) {
        const CFLBoneLocalPose* a = &clip->framePoses[(size_t)f0 * clip->jointCount + j];
        const CFLBoneLocalPose* b = &clip->framePoses[(size_t)f1 * clip->jointCount + j];
        CFLBoneLocalPose* out = &outPoses[j];
        for (int c = 0; c < 3; c++) out->translate[c] = a->translate[c] + (b->translate[c]-a->translate[c])*t;
        for (int c = 0; c < 3; c++) out->scale[c] = a->scale[c] + (b->scale[c]-a->scale[c])*t;
        float dot = a->rotate[0]*b->rotate[0]+a->rotate[1]*b->rotate[1]+a->rotate[2]*b->rotate[2]+a->rotate[3]*b->rotate[3];
        float bs = dot < 0.0f ? -1.0f : 1.0f;
        for (int c = 0; c < 4; c++) out->rotate[c] = a->rotate[c] + (bs*b->rotate[c]-a->rotate[c])*t;
        quatNormalize(out->rotate);
    }
}

int main(void) {
    // ... gfxInitDefault/C3D_Init/CFL_Initialize/CFL_InitCharModel/
    // CFL_LoadBodyModel exactly as the previous example ...

    BodyAnimClip clip;
    bool hasClip = loadAnimClip(walk_iqm, walk_iqm_size, &clip);

    // Match the clip's own joints to THIS body's own real bones, by NAME
    // (not array order - see Animation playback above) - once, not per
    // frame. Any bone the clip doesn't cover falls back to its own real
    // bind pose, so an incomplete animation still poses every OTHER bone
    // correctly instead of collapsing it to its parent's position.
    s32 boneToJoint[ANIM_MAX_JOINTS];
    CFLBoneLocalPose bindFallback[ANIM_MAX_JOINTS];
    u32 boneCount = hasBody ? CFL_GetBodyBoneCount(&body) : 0;
    if (hasClip && hasBody) {
        for (u32 i = 0; i < boneCount; i++) {
            const char* boneName = CFL_GetBodyBoneName(&body, i);
            boneToJoint[i] = -1;
            for (u32 j = 0; boneName && j < clip.jointCount; j++) {
                if (strcmp(boneName, clip.jointNames[j]) == 0) { boneToJoint[i] = (s32)j; break; }
            }
            CFL_GetBodyBoneBindLocalPose(&body, i, &bindFallback[i]);
        }
    }

    float animFrame = 0.0f;
    bool playing = hasClip && hasBody;

    while (aptMainLoop()) {
        hidScanInput();
        if (hidKeysDown() & KEY_START) break;
        if (hidKeysDown() & KEY_A) playing = !playing;

        if (playing) {
            animFrame += clip.framerate / 60.0f; // fixed-step, assumes ~60fps display refresh
            CFLBoneLocalPose sampledByJoint[ANIM_MAX_JOINTS];
            sampleAnimClip(&clip, animFrame, sampledByJoint);
            CFLBoneLocalPose poseByBone[ANIM_MAX_JOINTS];
            for (u32 i = 0; i < boneCount; i++)
                poseByBone[i] = (boneToJoint[i] >= 0) ? sampledByJoint[boneToJoint[i]] : bindFallback[i];
            CFL_PoseBodyModel(&body, poseByBone, boneCount);
        }

        // ... C3D_FrameBegin/drawModelWithBody/C3D_FrameEnd exactly as the
        // previous example ...
    }

    free(clip.framePoses);
    // ... CFL_DeleteBodyModel/CFL_DeleteModel/CFL_Finalize/gfxExit as before ...
    return 0;
}
```

### Making an icon with a body attached

Builds on "Creating a transparent icon" above - the only difference is
one `CFL_AttachBody` call before rendering. Toggling the body on/off
later (e.g. a UI button) is just calling `CFL_AttachBody` again
followed by another `CFL_CommandMakeModelIcon` call on the *same*
`C3D_Tex` - no need to free and recreate the texture yourself in
between (see [Icon rendering](#icon-rendering) above for the ownership
rules):

```c
CFLCharModel model = {0};
CFL_InitCharModel(&model, &ret.mii, CFL_RESOLUTION_256, CFL_EXPRESSION_FLAG(CFL_EXPRESSION_NORMAL));

CFLBodyModel body = {0};
bool hasBody = CFL_LoadBodyModel(body_iqm, body_iqm_size, &ret.mii, &body);

C3D_Tex icon = {0};

if (hasBody) {
	CFL_AttachBody(&model, &body);
}
CFL_CommandMakeModelIcon(&model, CFL_EXPRESSION_NORMAL, 256, NULL, &icon);
// `icon` now shows the head-on-body composite (or just the head, if
// hasBody was false) - draw it as a textured quad like any C3D_Tex.

// ...later, toggle the body off without reselecting a Mii - just call
// again on the same texture, no manual free/recreate needed in between:
CFL_AttachBody(&model, NULL);
CFL_CommandMakeModelIcon(&model, CFL_EXPRESSION_NORMAL, 256, NULL, &icon);

// Done for good:
C3D_TexDelete(&icon);
if (hasBody) CFL_DeleteBodyModel(&body);
CFL_DeleteModel(&model);
```

## Status

Reverse-engineered from a retail 3DS title binary's debug info and
cross-referenced against the real, compiled RFL (Wii) and FFL (Wii U)
Mii libraries. Most of it has been validated on real 3DS hardware;
some corners are still being tracked down.
