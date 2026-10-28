.PHONY: generate build test open clean

generate:
	xcodegen generate

build: generate
	xcodebuild -project Voixa.xcodeproj -scheme Voixa -configuration Debug -derivedDataPath build build

test:
	swift test --package-path Packages/VoixaKit

open: generate
	open Voixa.xcodeproj

clean:
	rm -rf build Voixa.xcodeproj Packages/VoixaKit/.build
