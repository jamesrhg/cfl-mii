# cfl-mii

A reimplementation of Nintendo's CFL Mii-rendering library for 3DS
homebrew, built on top of libctru/citro3d.

It opens the console's system `CFL_Res.dat` Mii resource archive,
parses it, and builds a fully-shaded, textured 3D character model
(head, hair, face, eyes, eyebrows, mouth, nose, glasses, facial hair)
from a `MiiData` struct - the same data libctru's Mii Selector applet
hands you.

## API surface

- `CFL_Initialize` / `CFL_Finalize` - open the archive, set up shared
  GPU state.
- `CFL_InitCharModel` / `CFL_DestroyCharModel` - build/tear down one
  character model instance.
- `CFL_SetExpression` / `CFL_GetExpression` - swap between pre-baked
  facial expressions.
- `CFL_GetPartCount` / `CFL_GetPart` - the model's own draw data
  (vertex/index buffers, textures, material hints) for the caller to
  render however it likes - this library never issues its own
  real-time draw calls.
- `CFL_BindDefaultShader` / `CFL_SetDefaultMaterial` - optional default
  shading (matching real FFL's `FFLDefaultShader`) an app can use
  instead of writing its own `C3D_LightEnv`/material setup.
- `CFL_CommandMakeModelIcon` - renders a single model + expression to
  an offscreen square icon texture, matching the real function's own
  camera and depth-range. Accepts a `CFLIconSetting` for background/
  custom shading control.
- `CFL_EnableSDDebug` - toggles this library's own `sdmc:/3ds/cfl_test.txt`
  debug log (off by default).

See `source/cfl_mii.h` for the full API and struct layout.

## Building

This is a source library, not a standalone app - it has no `main()`.
Add `source/` to a devkitARM 3DS project's `SOURCES`/`INCLUDES` and
link against `citro3d`/`ctru`.

## Examples

Both of these compile and link as-is against nothing but this library,
libctru, and citro3d - no other project files needed.

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

static void drawModel(const CFLCharModel* model, const C3D_Mtx* projection)
{
	CFLShaderLocations loc = CFL_GetShaderLocations();

	C3D_Mtx modelView;
	Mtx_Identity(&modelView);
	Mtx_Translate(&modelView, 0.0f, 0.0f, -2.0f, true);
	Mtx_Scale(&modelView, 0.032f, 0.032f, 0.032f);

	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, loc.projection, projection);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, loc.modelView, &modelView);

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

			if (part->useIndices)
				C3D_DrawElements(GPU_TRIANGLES, part->indexCount, C3D_UNSIGNED_BYTE, part->ibo);
			else
				C3D_DrawArrays(GPU_TRIANGLES, 0, part->vertexCount);
		}
	}
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
	CFL_InitCharModel(&model, &ret.mii, CFL_RESOLUTION_256, CFL_EXPRESSION_FLAG(CFL_EXPRESSION_NORMAL));

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

	CFL_DestroyCharModel(&model);
	CFL_Finalize();
	C3D_Fini();
	gfxExit();
	return 0;
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

	C3D_Tex icon;
	if (CFL_CommandMakeModelIcon(&model, CFL_EXPRESSION_NORMAL, 256, &setting, &icon)) {
		// `icon` is a normal C3D_Tex with real per-pixel alpha - draw it
		// as an alpha-blended textured quad, same as any other
		// transparent texture, then release it when done:
		C3D_TexDelete(&icon); // caller owns it
	}

	CFL_DestroyCharModel(&model);
	CFL_Finalize();
	C3D_Fini();
	gfxExit();
	return 0;
}
```

## Status

Reverse-engineered from a retail 3DS title binary's debug info and
cross-referenced against the real, compiled RFL (Wii) and FFL (Wii U)
Mii libraries. Most of it has been validated on real 3DS hardware;
some corners are still being tracked down.
