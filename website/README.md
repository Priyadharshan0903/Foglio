# Foglio landing page

A local, buildless landing page with cinematic paper artwork, native app previews, scroll-driven feature transitions, eight working theme previews, a local MCP connector showcase, and a real DMG download. Publishing is managed by the repository’s Pages workflow; local edits can be reviewed with the commands below.

## Preview

From this folder:

```sh
npm run build
npm run dev
```

Open **http://127.0.0.1:4173**. `npm run build` first prepares the downloadable release from the repository's `build/` folder. The page itself has no runtime dependencies, remote fonts, analytics, or CDN scripts.

Keep the server terminal running while viewing the page. `ERR_CONNECTION_REFUSED` means the server is stopped; run `npm run dev` again. From the repository root, use `npm --prefix website run dev`.

`npm run preview` serves the production output. The static, self-contained deployment folder is `website/dist/`; it includes the DMG, checksum, fonts, and optimized images. The source page can also be opened directly after preparing downloads, though an HTTP preview is recommended.

## Connector showcase

The **Connectors** navigation link opens a dedicated section with setup steps for Codex, Claude Code, and Claude Desktop, a native Agent connections settings screenshot, and all **26 MCP tools** grouped by connection, task workflow, tasks, notes, calendar, and meeting follow-ups. Each tool includes a short purpose and a Read/Write label. Native disclosure controls work with or without JavaScript.

The section explains reading by default, the Allow changes switch, local stdio/socket transport, revision checks, and calendar editing limits. It also distinguishes a local connection from the agent provider’s handling of content. Full configuration and parameters are in the [connector guide](../connectors/README.md). Keep the tool names and access labels aligned with [ToolCatalog.swift](../Sources/FoglioConnectorKit/ToolCatalog.swift) when tools change.

Task copy covers saved ordering within columns as well as moves between stages. `tasks_list` returns manual order; `task_move` supports `before_id` / `after_id` with an `order_revision` for conflict protection. These extend existing tools, so the inventory stays at 26. Follow the repository's [AGENTS.md](../AGENTS.md) change workflow to keep app behavior, connector schemas, website, documentation, screenshots, and release artifacts aligned.

The board drag interaction uses a full-size lifted card preview, a theme-colored placeholder, and animated card reflow (disabled with Reduce Motion). The lane highlight and insertion line stay visible together. Holding a card near a lane's top/bottom or the board's left/right edges scrolls continuously, faster toward the edge, until the pointer moves away or the drag ends. Only dropping commits the projected move; cancelling restores the layout. This is pointer interaction; connector ordering arguments are unchanged because agents can already position tasks directly with `task_move`. See [Linear's board workflow](https://linear.app/docs/board-layout) for the interaction reference; Foglio implements its own native macOS behavior.

## Images and motion

Completed task titles stay struck through in the native board and list. A fresh move into any Done-category status reveals the strike from left to right; reopening removes it, and Reduce Motion applies the final style immediately. Existing connector completion operations drive the same feedback, so no tool changes are needed.

All assets live in [assets](assets/). See [the asset guide](assets/ASSETS.md) for composition, provenance, accessibility, and animation guidance. Full generation prompts are in [prompts.json](assets/prompts.json).

- `assets/originals/`: untouched generated PNGs and native app renders.
- `assets/images/`: optimized WebP images and the existing app icon, consumed by the page.
- `assets/fonts/`: the app's bundled Geist fonts and their OFL license.

The hero enters in staggered layers, the product window responds gently to the pointer, feature previews crossfade as their accompanying story enters view, and the paper sculpture floats independently. Scroll work is scheduled with `requestAnimationFrame` and limited to visible sections. Motion is reduced on mobile and disabled when the visitor prefers reduced motion. The page and download remain usable without JavaScript.

The theme showcase groups its preview and swatches in one panel. Theme names, descriptions, and accent colors update together after the next image is ready. Use the swatches, previous/next buttons, or arrow keys while a swatch has focus; Home and End jump to the first and last palettes. The current preview stays visible during loading, and reduced-motion mode switches without a crossfade. Branding uses the selected Refined Margin icon.

App previews contain fictional example content from an isolated library, not personal notes or tasks. The calendar is an explicitly labeled HTML illustration of the supported workflow, not a screenshot.

## Update the download

From the repository root, `make update-app` builds a fresh DMG, refreshes this website's download/checksum, and replaces `~/Applications/Foglio.app` with a backup. For preparing artifacts without installing, use `make prepare-update`. Agents can follow the model-independent [foglio-install skill](../.agents/skills/foglio-install/SKILL.md), linked from `AGENTS.md`.

1. Build the new release with the repository's `scripts/dmg.sh`.
2. Update `release.json` to match that artifact's version and filename.
3. Run `npm run build`.

The build checks that the source contains a complete UDIF disk image, copies only that selected release, computes its SHA-256 checksum, and updates version text and download links in the production HTML. Source downloads and production output are ignored by Git. Do not commit the generated DMG copies.

The current download is **0.5.0**, **Apple silicon**, **macOS 14+**. It is a locally signed preview, not a notarized public release; the page makes this clear in its questions section. This landing page does not change app signing, licensing, or release policy.

## Deploy

Every push to `main` runs [.github/workflows/pages.yml](../.github/workflows/pages.yml): it builds the app and DMG on macOS, builds this site around that exact DMG, and publishes `dist/` to GitHub Pages. It can also be started by hand from the Actions tab. The run fails if the app version and `release.json` disagree, so bump both together. The CI image's Applications shortcut points at `/Applications`. The DMG is ad-hoc signed until a Developer ID is available.

## Build

```sh
npm run build
```

The website needs only Node.js; no npm packages need to be installed. The build prepares the page, assets, DMG, and checksum in `dist/`. Use the local preview to review the page and its interactions.

To regenerate the native screenshots, run from the repository root:

```sh
FOGLIO_LANDING_ASSETS=website/assets/originals/app swift run --disable-sandbox FoglioTests
```

Then convert the PNGs with `cwebp -q 92` into the matching filenames in `assets/images/`. The optional renderers are [LandingAssets.swift](../Tests/FoglioTests/LandingAssets.swift), [TaskPreviews.swift](../Tests/FoglioTests/TaskPreviews.swift), and [SettingsPreviews.swift](../Tests/FoglioTests/SettingsPreviews.swift). Follow the [screenshot regeneration guide](../docs/images/README.md) to refresh the task board and connector settings as well. These fixtures do not access personal calendar accounts or modify the real app library.

Before public launch, set an absolute Open Graph image URL for the final domain and update the download metadata to the intended release. No public domain, legal claims, testimonials, pricing, or tracking have been invented.
