# Icon pipeline (sandbox-verified, 2026-11-07)

Best-quality icon creation this environment can do, proven end-to-end in
`/workspace/Workspace/tmp/icon-lab` (contact sheet: `icon-contact-sheet.png`).

## Doctrine (why it's built this way)

**Vectors are the masters; rasters are always derived.** Launcher icons must be
crisp at 48 dp and survive mask shapes — no raster workflow, however glossy,
beats an authored SVG scaled down from a perfect curve. AI raster is for
*concepts*, never for shipping. Flat glyph / two-tone / negative-space prompts
vectorize cleanly; glass, gradient-mesh and heavy 3D produce path-soup when
traced (industry consensus — e.g. svgmaker.io's 2026 vectorize-first guide).

## Verified sandbox stack

| step | tool | note |
|---|---|---|
| SVG → PNG render | **`@resvg/resvg-js` via pnpm** (`/tmp/iconlab`, install `pnpm add @resvg/resvg-js`) | Chrome-class static-SVG renderer; `pnpm`+`node` exist, `npm`/`npx` do not |
| compositing, masks, contact sheets | **Pillow** (tools/python) | round-mask + themed-mono previews are 10-line scripts |
| raster→vector (when adopting an AI concept) | **`vtracer`** (pip) | colour tracing; then hand-cleanup in SVG source |
| ~~cairosvg~~ | ✗ dead here | wants native libcairo, container has none, no apt |
| ~~headless chromium~~ | ✗ not installed | the earlier `npx playwright install` died (no npx); resvg made it moot |

Optional concept stage (not yet installed): `pip install torch --index-url
https://download.pytorch.org/whl/cpu` + `diffusers` → **SDXL-Turbo**, 4 steps,
~1–3 min/512 px image on 32 cores (~10 GB RAM of ~21 GB free). Prompt recipe
that traces well: *"flat minimal app icon, single glyph, two colors, negative
space, no gradient, no shadow, centered, 64px grid"* × 8 per direction; owner
picks; the pick gets re-authored as clean SVG (trace only as scaffolding).

## Production procedure (the actual delivery chain)

1. **Master SVGs, three layers per Google adaptive spec (108 dp canvas):**
   `bg.svg` solid brand colour · `fg.svg` glyph inside the **66 dp safe circle**
   (nothing critical outside it — round/squircle masks eat the corners) ·
   `mono.svg` same silhouette, single colour (Android 13 themed icons).
   No text beyond a lettermark, no baked shadows, no gradients across the safe
   edge.
2. **Render all targets** (resvg, script pattern already in `render.js`):
   mipmaps 48/72/96/144/192 (+216 xxxhdpi), Play 512 (32-bit PNG, alpha for
   legacy), fg layer at 432, mono at 432 → place under
   `app/android/app/src/main/res/` + adaptive XMLs in `mipmap-anydpi-v26`
   (manual placement — beats `flutter_launcher_icons` for full layer control).
3. **QA gates before commit** (contact sheet image in the PR/issue, like today):
   48 px legibility check · round-mask preview · themed-mono preview ·
   fg/bg contrast ≥ 4.5:1 · airplane-mode *and* dark-home-screen eyeball on
   device (kit install, screenshot, done).

## Status & the open design decision

First candidate derived from the site's favicon "S" renders clean through every
gate today (see contact sheet). **Open owner call: Steiner lettermark ("S",
family continuity with Vault/site) vs an app-specific glyph** (wallet/coin/leaf
— distinct at a glance on a home screen). The SDXL-Turbo concept stage exists
to widen that exploration before a 10-year asset is frozen; ~an afternoon
including model download if you want it.
