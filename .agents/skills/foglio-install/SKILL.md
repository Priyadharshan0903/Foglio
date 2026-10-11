---
name: foglio-install
description: Build and verify the latest Foglio DMG, refresh website downloads, and replace the local Foglio application with a backup. Use when asked to swap, install, or update Foglio in Applications.
---

# Update the installed Foglio app

Work from the Foglio repository root (the directory with `Package.swift` and
`Makefile`). Read [AGENTS.md](../../../AGENTS.md) for repository requirements.
This skill uses ordinary shell commands and needs no particular model or MCP host.

## Run

When the user asks to update the installed app, use:

```sh
make update-app
```

This builds a fresh release app and `FoglioMCP`, packages and verifies the versioned
DMG, refreshes the website download/checksum, and installs the matching app bundle
in `~/Applications/Foglio.app`. The existing installer keeps `Previous.app` in a
printed backup directory, quits a running Foglio normally, and verifies signatures.
It never changes the user's library. Installing the bundle from the same build
avoids disk-image mounting failures in restricted macOS environments.

## Restricted runners

Prepare the reviewable artifacts first, then run the installation separately:

```sh
FOGLIO_DISABLE_SWIFT_SANDBOX=1 make prepare-update
make install-built
```

Use `FOGLIO_DISABLE_SWIFT_SANDBOX=1` only if the runner cannot create SwiftPM's
nested sandbox. Request the runner's native escalation for `make install-built`
when writing `~/Applications` or using AppleScript requires it. An install request
already authorizes replacement; do not add another conversational confirmation.

`install-built` expects the freshly prepared bundle. Do not use an older leftover
DMG or install another app from an arbitrary folder. Rebuild if the app source has
changed since preparation. For a build-only request, stop after `prepare-update`.

## Check and hand off

- Existing scripts own bundling, signing, DMG verification, backup, and rollback:
  [dmg.sh](../../../scripts/dmg.sh) and [install.sh](../../../scripts/install.sh).
  Do not reimplement installation or force-kill a running app.
- `install-built` compares installed app and MCP executable bytes with the build.
  A successful install prints the destination, version, and previous-copy backup.
- If a step fails, stop before the next dependent step. Inspect the error and fix
  that step; do not bypass signature checks or claim replacement succeeded.
- Respect an explicitly requested destination; the existing installer defaults
  to the user's Applications folder. A different destination needs adapting the
  installer, not silently changing the target.
- Report installed path, version, and backup. Tell the user to reopen Foglio and
  reconnect their agent sessions after connector schema changes. Do not publish,
  push, or automatically launch GUI apps as part of this install workflow.
