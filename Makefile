# Put machine-specific settings (e.g. SIGN_IDENTITY) in local.mk; it is gitignored.
-include local.mk
export SIGN_IDENTITY
# KeyboardShortcuts uses #Preview, whose macro plugin ships only with Xcode. An SDKROOT pointing
# at the Command Line Tools SDK hides it, so always build against the selected Xcode.
unexport SDKROOT

CONFIG ?= debug
APP := build/Snap.app

.PHONY: build app run test clean

build:
	swift build -c $(CONFIG)

app:
	scripts/bundle.sh $(CONFIG)

run: app
	-pkill -x Snap
	open $(APP)

test:
	swift test

clean:
	swift package clean
	rm -rf build
