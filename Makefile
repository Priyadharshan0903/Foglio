.PHONY: build run test bundle app dmg install clean

build:
	swift build

# Runs the raw binary — fine for quick checks, but it has no Info.plist so
# macOS treats it as a background process. Use `make app` for the real thing.
run: build
	swift run Foglio

# `swift test` is unusable without Xcode (see Package.swift), so the suite is a
# plain executable.
test:
	@swift run FoglioTests

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

clean:
	rm -rf .build build
