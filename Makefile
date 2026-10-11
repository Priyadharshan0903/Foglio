.PHONY: build run test mcp bundle app dmg install prepare-update install-built update-app clean

build:
	swift build

# Runs the raw binary — fine for quick checks, but it has no Info.plist so
# macOS treats it as a background process. Use `make app` for the real thing.
run: build
	swift run Foglio

# `swift test` is unusable without Xcode (see Package.swift), so the suite is a
# plain executable.
test:
	@swift build --product FoglioMCP
	@swift run FoglioTests

mcp:
	@swift build --product FoglioMCP

bundle:
	@./scripts/bundle.sh debug

app: bundle
	@open build/Foglio.app

# A release build wrapped in a drag-to-install disk image.
dmg:
	@./scripts/dmg.sh release

# Replaces the copy in ~/Applications from that image. No admin rights needed:
# /Applications is writable only by the admin group, ~/Applications by you.
install: dmg
	@./scripts/install.sh

# Prepare all artifacts before an agent requests filesystem permission to install.
prepare-update: dmg
	@npm --prefix website run build

# Use the bundle just packaged by prepare-update; no DMG mounting is needed.
install-built:
	@./scripts/install.sh build/Foglio.app
	@cmp build/Foglio.app/Contents/MacOS/Foglio "$(HOME)/Applications/Foglio.app/Contents/MacOS/Foglio"
	@cmp build/Foglio.app/Contents/MacOS/FoglioMCP "$(HOME)/Applications/Foglio.app/Contents/MacOS/FoglioMCP"
	@echo "Installed app and MCP helper match the prepared build."

# Portable entrypoint for people and agents; sequential even with make -j.
update-app: prepare-update
	@$(MAKE) install-built

clean:
	rm -rf .build build
