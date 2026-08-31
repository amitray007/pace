.PHONY: benchmark build check format format-check generate lint reference-fetch reference-frames test

benchmark:
	swift run -c release pace-benchmark core --samples 25 --iterations 20 --max-p95-ms 5

generate:
	xcodegen generate

format:
	swift package plugin --allow-writing-to-package-directory swiftformat --cache ignore .

format-check:
	swift package plugin --allow-writing-to-package-directory swiftformat --cache ignore --lint .

lint:
	swift package plugin --allow-writing-to-package-directory swiftlint --strict

reference-fetch:
	Scripts/fetch-reference-media.sh

reference-frames: reference-fetch
	Scripts/extract-reference-frames.sh

test:
	swift test

build: generate
	xcodebuild -project Pace.xcodeproj -scheme Pace -configuration Debug \
		-derivedDataPath .build/xcode-derived-data CODE_SIGNING_ALLOWED=NO build

check: format-check lint test build
