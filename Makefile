.PHONY: benchmark build check format format-check generate lint reference-fetch reference-frames test visual-benchmark

VISUAL_CAPTURE ?=
VISUAL_OUTPUT ?= .local/review/visual-benchmark

benchmark:
	swift run -c release pace-benchmark core --samples 25 --iterations 20 --max-p95-ms 5

visual-benchmark:
	@test -n "$(VISUAL_CAPTURE)" || (echo "Set VISUAL_CAPTURE to a rail screenshot." >&2; exit 1)
	swift run -c release pace-benchmark visual \
		--reference .local/references/frames/primary-claude-detail.png \
		--capture "$(VISUAL_CAPTURE)" \
		--output-dir "$(VISUAL_OUTPUT)"

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
