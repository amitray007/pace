.PHONY: benchmark build check format format-check generate install install-build interaction-benchmark launch lint reference-fetch reference-frames release-archive release-preflight release-smoke run signing-identity test visual-benchmark

VISUAL_CAPTURE ?=
VISUAL_OUTPUT ?= .local/review/visual-benchmark
RELEASE_VERSION ?= 0.1.0
RELEASE_BUILD_NUMBER ?= 1
RELEASE_BUNDLE_ID ?= com.amitray.Pace.dev
RELEASE_DERIVED_DATA ?= .build/release-preflight
RELEASE_ARTIFACTS ?= .build/release-artifacts
INSTALL_DIR ?= /Applications
INSTALL_DERIVED_DATA ?= .build/install
INSTALL_APP = $(INSTALL_DERIVED_DATA)/Build/Products/Release/Pace.app
RELEASE_ARTIFACT_BASENAME = Pace-$(RELEASE_VERSION)-$(RELEASE_BUILD_NUMBER)-macos-universal-unsigned

benchmark:
	swift run -c release pace-benchmark core --samples 25 --iterations 20 --max-p95-ms 5

interaction-benchmark:
	swift run -c release pace-benchmark activation --samples 25 --iterations 200 --max-p95-ms 0.5

visual-benchmark:
	@test -n "$(VISUAL_CAPTURE)" || (echo "Set VISUAL_CAPTURE to a rail screenshot." >&2; exit 1)
	swift run -c release pace-benchmark visual \
		--reference .local/references/frames/settings-claude-detail.png \
		--capture "$(VISUAL_CAPTURE)" \
		--output-dir "$(VISUAL_OUTPUT)" \
		--reference-region-start 0.57 \
		--reference-region-start-y 0.20 \
		--reference-region-end-y 0.82

generate:
	xcodegen generate

format:
	swift run swiftformat --cache ignore .

format-check:
	swift run swiftformat --cache ignore --lint .

lint:
	swift package plugin --allow-writing-to-package-directory swiftlint --strict

reference-fetch:
	Scripts/fetch-reference-media.sh

reference-frames: reference-fetch
	Scripts/extract-reference-frames.sh

release-preflight: generate
	xcodebuild -project Pace.xcodeproj -scheme Pace -configuration Release \
		-derivedDataPath "$(RELEASE_DERIVED_DATA)" CODE_SIGNING_ALLOWED=NO \
		MARKETING_VERSION="$(RELEASE_VERSION)" \
		CURRENT_PROJECT_VERSION="$(RELEASE_BUILD_NUMBER)" \
		ONLY_ACTIVE_ARCH=NO build
	bash Scripts/verify-release-bundle.sh \
		"$(RELEASE_DERIVED_DATA)/Build/Products/Release/Pace.app" \
		"$(RELEASE_BUNDLE_ID)" "$(RELEASE_VERSION)" "$(RELEASE_BUILD_NUMBER)" "15.0"

release-archive: release-preflight
	bash Scripts/package-release-artifact.sh \
		"$(RELEASE_DERIVED_DATA)/Build/Products/Release/Pace.app" \
		"$(RELEASE_ARTIFACTS)" \
		"$(RELEASE_BUNDLE_ID)" "$(RELEASE_VERSION)" "$(RELEASE_BUILD_NUMBER)" "15.0"

release-smoke: release-archive
	bash Scripts/smoke-release-artifact.sh \
		"$(RELEASE_ARTIFACTS)/$(RELEASE_ARTIFACT_BASENAME).zip" \
		"$(RELEASE_ARTIFACTS)/$(RELEASE_ARTIFACT_BASENAME).zip.sha256"

test:
	swift test

build: generate
	xcodebuild -project Pace.xcodeproj -scheme Pace -configuration Debug \
		-derivedDataPath .build/xcode-derived-data CODE_SIGNING_ALLOWED=NO build

check: format-check lint test build

# Build the Release application into a dedicated derived-data path for installing.
install-build: generate
	xcodebuild -project Pace.xcodeproj -scheme Pace -configuration Release \
		-derivedDataPath "$(INSTALL_DERIVED_DATA)" CODE_SIGNING_ALLOWED=NO \
		MARKETING_VERSION="$(RELEASE_VERSION)" \
		CURRENT_PROJECT_VERSION="$(RELEASE_BUILD_NUMBER)" \
		ONLY_ACTIVE_ARCH=YES build

# Create the local signing identity if it does not exist yet.
signing-identity:
	@bash Scripts/create-signing-identity.sh

# Build, then sign and copy the application into INSTALL_DIR.
install: signing-identity install-build
	bash Scripts/install-app.sh "$(INSTALL_APP)" "$(INSTALL_DIR)"

# Install, then launch the installed application.
run: install
	open -a "$(INSTALL_DIR)/Pace.app"

# Launch the already-installed application without rebuilding.
launch:
	open -a "$(INSTALL_DIR)/Pace.app"
