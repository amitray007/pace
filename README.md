# Pace

Pace is a local-first macOS utility for monitoring AI session, weekly, model-specific,
credit, and spend limits without opening each provider's account page.

It has two presentation modes backed by the same data:

- a high-fidelity screen-edge rail based on
  [Vinz's side-notch reference](https://x.com/hivinz_/status/2093651446927626294);
- a conventional menu-bar panel based on the hierarchy in
  [DHH's usage-panel reference](https://x.com/dhh/status/2090005543112851862).

The edge rail is the signature surface. Its silhouette, density, connected provider panel, hover
behavior, and motion must achieve perceptual and behavioral parity with the reference. The menu bar
is the dependable default surface. Users can enable either surface or both.

## Current status

Pace is the settled product name. Its native application foundation now includes provider-neutral
accounts, normalized quota snapshots, deterministic simulated data, shared selection, refresh
orchestration, and local persistence. Live provider adapters remain behind the simulated-data visual
approval gate.

The first static native surfaces now run against a dedicated visual-reference fixture. AppKit owns
the menu-bar status item and click-through edge panel. Core Animation draws the rail, connector,
settings attachment, and progress rings. The menu panel and rail share provider and account
selection. Interruptible motion, pointer-safe activation, keyboard access, and honest simulated
states are implemented; hardware interaction testing and final reference-media approval remain
open.

A production-separated Codex adapter and its original Swift spike read limits through the supported
local app-server protocol without copying account tokens or calling private web endpoints. The
adapter supports explicit isolated `CODEX_HOME` profiles, reuses one supervised process per
profile, and forwards rate-limit updates into shared state. Request deadlines do not block Swift's
cooperative executor, and disabling or removing an account stops its monitor and profile process.
Explicit account onboarding and live app configuration remain before live values replace the
simulated shell.

The account core keeps discovery and registration separate. A discovery request never adds an
account to Pace. The selected candidate must be added explicitly, can receive a local name, and can
then be refreshed, disabled, re-enabled, renamed, or removed. The same real provider profile or
Keychain source cannot be registered twice, even if its reported identity changes.

A separate Claude compatibility spike verifies OAuth identity before reading usage, supports
explicit isolated profile directories, and keeps all credential and endpoint code outside the app.

The Cursor compatibility spike verifies identity directly with Cursor before reading usage. It
supports the default Cursor Agent Keychain login and isolated Cursor Agent file profiles without
reading Cursor Desktop state or browser cookies.

The Grok compatibility spike uses xAI's officially supported `GROK_HOME` isolation. It verifies the
session through Grok's `/user` endpoint before reading billing and never relies on a running Grok
process.

The GitHub Copilot compatibility spike binds each account through an explicit GitHub CLI username,
verifies its durable identity with GitHub's documented `/user` API, and then reads its personal
Copilot quota. It does not depend on a running editor, Copilot CLI, or coding harness.

Run the feasibility spikes with the corresponding authenticated installation:

```sh
swift spikes/codex-rate-limits.swift
swift run claude-usage-spike
swift run cursor-usage-spike
swift run grok-usage-spike
swift run github-copilot-usage-spike
```

## Development

Pace uses Swift 6, Swift Testing, XcodeGen, SwiftFormat, and SwiftLint. Formatting and linting are
resolved as pinned Swift package plugins, so they do not require global installation. XcodeGen is
the only project-generation command.

```sh
make generate       # create Pace.xcodeproj
make format         # format Swift sources
make check          # format check, lint, tests, and macOS app build
make benchmark      # measure the release-mode simulated refresh pipeline
make visual-benchmark VISUAL_CAPTURE=path/to/capture.png  # compare the rail silhouette
make reference-fetch  # download the public reference media into ignored local storage
make reference-frames # verify and extract the canonical visual-review frames
```

The current deployment target is macOS 15 for the core foundation. The oldest supported macOS
version remains subject to the reference rail's AppKit and Core Animation verification.

## Documentation

- [Product requirements](docs/product.md)
- [Visual design contract](docs/design.md)
- [Reference media and measurements](docs/reference.md)
- [Interaction and motion](docs/interactions.md)
- [Technical architecture](docs/architecture.md)
- [Delivery roadmap](docs/roadmap.md)

## Product principles

- Treat the product as an instrument, not an analytics dashboard.
- Keep the menu bar reliable and the edge rail optional.
- Never obstruct scrollbars, window resizing, or full-screen work.
- Support multiple accounts while showing one provider at a time in detailed views.
- Display provider-defined quota buckets instead of assuming fixed five-hour and weekly limits.
- Show stale and unavailable data honestly.
- Keep credentials and normalized usage snapshots on the device.
- Validate visual and motion work in the running macOS application.
