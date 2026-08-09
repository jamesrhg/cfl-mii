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
- `CFL_CommandMakeModelIcon` - renders a single model + expression to
  an offscreen square icon texture, matching the real function's own
  camera and depth-range.

See `source/cfl_mii.h` for the full API and struct layout.

## Building

This is a source library, not a standalone app - it has no `main()`.
Add `source/` to a devkitARM 3DS project's `SOURCES`/`INCLUDES` and
link against `citro3d`/`ctru`.

## Status

Reverse-engineered from a retail 3DS title binary's debug info and
cross-referenced against the real, compiled RFL (Wii) and FFL (Wii U)
Mii libraries. Most of it has been validated on real 3DS hardware;
some corners are still being tracked down.
