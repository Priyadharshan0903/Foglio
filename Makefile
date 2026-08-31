.PHONY: build run test bundle app clean

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

clean:
	rm -rf .build build
