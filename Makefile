.PHONY: generate build release install dmg icon test open clean

RELEASE_APP = build/Build/Products/Release/Voixa.app
VERSION = $(shell grep MARKETING_VERSION project.yml | sed 's/.*"\(.*\)"/\1/')
DMG = build/Voixa-$(VERSION).dmg

generate:
	xcodegen generate

build: generate
	xcodebuild -project Voixa.xcodeproj -scheme Voixa -configuration Debug -derivedDataPath build build

release: generate
	xcodebuild -project Voixa.xcodeproj -scheme Voixa -configuration Release -derivedDataPath build build

# Builds Release, replaces /Applications/Voixa.app and starts it.
install: release
	-pkill -x Voixa
	rm -rf /Applications/Voixa.app
	cp -R $(RELEASE_APP) /Applications/
	open /Applications/Voixa.app

# Builds Release and packages it as a drag-to-Applications disk image.
# Not notarized: other Macs will block it until it is signed with a
# Developer ID certificate and notarized.
dmg: release
	rm -rf build/dmg $(DMG)
	mkdir -p build/dmg
	cp -R $(RELEASE_APP) build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "Voixa" -srcfolder build/dmg -format UDZO -ov $(DMG)
	rm -rf build/dmg
	@echo "Created $(DMG)"

# Redraws the app icon (scripts/make-icon.swift) at every size macOS needs.
ICONSET = App/Resources/Assets.xcassets/AppIcon.appiconset
icon:
	swift scripts/make-icon.swift build/icon-1024.png
	for pt in 16 32 128 256 512; do \
		sips -z $$pt $$pt build/icon-1024.png --out $(ICONSET)/icon_$${pt}x$${pt}.png >/dev/null; \
		sips -z $$((pt * 2)) $$((pt * 2)) build/icon-1024.png --out $(ICONSET)/icon_$${pt}x$${pt}@2x.png >/dev/null; \
	done

test:
	swift test --package-path Packages/VoixaKit

open: generate
	open Voixa.xcodeproj

clean:
	rm -rf build Voixa.xcodeproj Packages/VoixaKit/.build
