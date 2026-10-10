# Foglio landing page

A local, buildless landing page with cinematic paper artwork, native app previews, scroll-driven feature transitions, eight working theme previews, and a real DMG download. Nothing has been published.

## Preview

From this folder:

```sh
npm run build
npm run dev
```

Open **http://127.0.0.1:4173**. `npm run build` first prepares the downloadable release from the repository's `build/` folder. The page itself has no runtime dependencies, remote fonts, analytics, or CDN scripts.

Keep the server terminal running while viewing the page. `ERR_CONNECTION_REFUSED` means the server is stopped; run `npm run dev` again. From the repository root, use `npm --prefix website run dev`.

`npm run preview` serves the production output. The static, self-contained deployment folder is `website/dist/`; it includes the DMG, checksum, fonts, and optimized images. The source page can also be opened directly after preparing downloads, though an HTTP preview is recommended.

## Images and motion

All assets live in [assets](assets/). See [the asset guide](assets/ASSETS.md) for composition, provenance, accessibility, and animation guidance. Full generation prompts are in [prompts.json](assets/prompts.json).

- `assets/originals/`: untouched generated PNGs and native app renders.
- `assets/images/`: optimized WebP images and the existing app icon, consumed by the page.
- `assets/fonts/`: the app's bundled Geist fonts and their OFL license.

The hero enters in staggered layers, the product window responds gently to the pointer, feature previews crossfade as their accompanying story enters view, and the paper sculpture floats independently. Scroll work is scheduled with `requestAnimationFrame` and limited to visible sections. Motion is reduced on mobile and disabled when the visitor prefers reduced motion. The page and download remain usable without JavaScript.

The theme showcase groups its preview and swatches in one panel. Theme names, descriptions, and accent colors update together after the next image is ready. Use the swatches, previous/next buttons, or arrow keys while a swatch has focus; Home and End jump to the first and last palettes. The current preview stays visible during loading, and reduced-motion mode switches without a crossfade. Branding uses the selected Refined Margin icon.

App previews contain fictional example content from an isolated library, not personal notes or tasks. The calendar is an explicitly labeled HTML illustration of the supported workflow, not a screenshot.

## Update the download

1. Build the new release with the repository's `scripts/dmg.sh`.
2. Update `release.json` to match that artifact's version and filename.
3. Run `npm run build`.

The build checks that the source contains a complete UDIF disk image, copies only that selected release, computes its SHA-256 checksum, and updates version text and download links in the production HTML. Source downloads and production output are ignored by Git. Do not commit the generated DMG copies.

The current download is **0.3.3**, **Apple silicon**, **macOS 14+**. It is a locally signed preview, not a notarized public release; the page makes this clear in its questions section. This landing page does not change app signing, licensing, or release policy.

## Build

```sh
npm run build
```

The website needs only Node.js; no npm packages need to be installed. The build prepares the page, assets, DMG, and checksum in `dist/`. Use the local preview to review the page and its interactions.

To regenerate the native screenshots, run from the repository root:

```sh
FOGLIO_LANDING_ASSETS=website/assets/originals/app swift run --disable-sandbox FoglioTests
```

Then convert the PNGs with `cwebp -q 92` into the matching filenames in `assets/images/`. The optional renderer is [LandingAssets.swift](../Tests/FoglioTests/LandingAssets.swift); it does not open calendar accounts or modify the real app library.

Before public launch, set an absolute Open Graph image URL for the final domain and update the download metadata to the intended release. No public domain, legal claims, testimonials, pricing, or tracking have been invented.
