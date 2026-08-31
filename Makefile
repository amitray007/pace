.PHONY: build check format format-check generate lint test

generate:
	xcodegen generate

format:
	swift package plugin --allow-writing-to-package-directory swiftformat --cache ignore .

format-check:
	swift package plugin --allow-writing-to-package-directory swiftformat --cache ignore --lint .

lint:
	swift package plugin --allow-writing-to-package-directory swiftlint --strict

test:
	swift test

build: generate
	xcodebuild -project Pace.xcodeproj -scheme Pace -configuration Debug \
		-derivedDataPath .build/xcode-derived-data CODE_SIGNING_ALLOWED=NO build

check: format-check lint test build
