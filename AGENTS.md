# Working on Foglio

Foglio is a native macOS app with a local MCP connector and a repository-owned
landing page. Keep these surfaces consistent when implementing a change.

## Change workflow

1. Read the affected app/model code and tests before editing. Preserve library
   data, UUIDs/ticket IDs/status IDs, Markdown, archive compatibility, and user
   preferences. Test with isolated stores, preferences, and calendar fixtures.
2. Put behavior in the owning model/service rather than duplicating it in SwiftUI
   and MCP. Use selected `Theme` tokens for colors, focus, hover, selection, and
   drag feedback. Check light/dark themes, narrow layouts, keyboard access, and
   accessibility for UI changes.
3. **Evaluate connector parity for every feature.** If agents can usefully read or
   perform the behavior, extend an existing tool or add a focused tool in
   `Sources/FoglioConnectorKit/ToolCatalog.swift` and implement it in
   `Sources/FoglioCore/Connectors/AgentService.swift`. Prefer extending the existing
   tool for the same operation. Preserve connection/write permissions, human-draft
   protection, argument validation, optimistic revisions, and persistence errors.
   Validate arguments before mutation. Purely visual changes need no tool; explain
   that decision in the handoff when relevant.
4. **Review documentation and website impact before finishing.** Update relevant
   instructions and feature descriptions in `README.md`, `connectors/README.md`,
   `website/index.html`, and `website/README.md`. Keep connector names, totals,
   read/write labels, descriptions, examples, arguments, and limits synchronized
   across the catalog and these surfaces. Advertise only implemented capabilities.
   Leave unaffected files alone and explain any relevant omission.
5. If screenshots no longer represent the UI, regenerate with native preview
   fixtures and fictional data, never the user's library. Follow
   `docs/images/README.md`; update `website/assets/ASSETS.md` for new/replaced assets.
6. Run relevant checks below and inspect the final diff. Report changes, checks
   passed, and anything unverified. Model tests do not establish that a live drag,
   browser, or agent-host interaction was tested.

## Verification

- App/model/MCP changes: `make test`. The suite is an executable, not `swift test`.
  In restricted runners use `swift build --disable-sandbox --product FoglioMCP`
  followed by `swift run --disable-sandbox FoglioTests`.
- Add meaningful checks for changed persistence, migration, ordering, revisions,
  permissions, and validation. Avoid tests that only mirror layout code.
- Build the app with `swift build --product Foglio`; add `--disable-sandbox` when
  required by the runner.
- `FOGLIO_TASK_PREVIEWS`, `FOGLIO_SETTINGS_PREVIEWS`, and `FOGLIO_LANDING_ASSETS`
  enable isolated native PNG rendering in `FoglioTests`. Inspect relevant images
  for layout changes; see the screenshot guide for regeneration commands.
- Website changes: `npm --prefix website run build`; check links, assets, tool
  inventory, and download metadata. Preview with `npm --prefix website run dev`
  at `http://127.0.0.1:4173` and inspect desktop/mobile when a browser is available.
  Keep Playwright and its tests removed, as the user requested. Do not add npm
  dependencies for routine static page edits.
- Run `git diff --check`. Preserve unrelated user edits.

## Packaging and handoff

- For requests such as "swap the new DMG" or "update Foglio in Applications", use
  the repository's [foglio-install skill](.agents/skills/foglio-install/SKILL.md).
  `make update-app` builds the release, refreshes website downloads, and installs
  with a backup. Restricted agents can split `make prepare-update` from
  `make install-built` for native filesystem approval. These commands work with
  any agent that has terminal access; no model-specific tools are required.

- Keep website work in this repository unless asked to publish. Do not push,
  publish, or replace an installed app unless authorized by the user.
- When asked for a downloadable release, use `./scripts/dmg.sh release`
  (`FOGLIO_DISABLE_SWIFT_SANDBOX=1` when required by the runner). Verify the app
  signature and DMG checksum, then rebuild the website so generated download
  metadata matches the artifact. Coordinate version changes across the bundle,
  MCP server, documentation, and `website/release.json`.
- When asked to replace the installed app, use `scripts/install.sh` for backup
  and the Applications destination. If mounting is unavailable, use the matching
  verified `build/Foglio.app`. Use native escalation for required filesystem writes.
- After connector schema changes, mention that an agent session may need to restart
  or reconnect. Keep transport and permissions unchanged unless requested.
