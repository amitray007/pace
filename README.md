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
orchestration, and local persistence. Codex, Grok, and GitHub Copilot now have
production-separated adapters; the remaining provider spikes stay isolated until their validation
gates pass.

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
The Providers settings section now adds the current profile or an explicitly chosen profile folder.
It never registers an ambient login automatically. A successful add supersedes the simulated Codex
fixture in the active runtime and presentation. Pace retains that fixture as a deterministic local
fallback, and the other provider fixtures remain active until their own adapters are promoted.
Disabling or removing the last enabled real account refreshes that retained fixture before Pace
shows it again.

The account core keeps discovery and registration separate. A discovery request never adds an
account to Pace. The selected candidate must be added explicitly, can receive a local name, and can
then be refreshed, disabled, re-enabled, renamed, or removed. The same real provider profile or
Keychain source cannot be registered twice, even if its reported identity changes.

For multiple Codex accounts, sign each account in through Codex with a separate `CODEX_HOME`, then
choose that folder in Pace. Codex continues to own its credentials. Removing an account from Pace
deletes only Pace's normalized usage and profile reference.

The production Grok adapter reads one explicit `GROK_HOME` at a time. It accepts only a private,
first-party xAI session, verifies the remote `/user` identity before requesting `/billing`, and
polls at a conservative 15-minute baseline with provider retry intervals respected. Pace never
starts or depends on a Grok process. Identity changes stop before quota retrieval and preserve the
last good snapshot as stale.

For multiple Grok accounts, authenticate each account with Grok in a separate `GROK_HOME`, then
choose that folder in Pace. Grok owns login, logout, and credential rotation. Removing an account
from Pace leaves `auth.json` and the profile directory unchanged.

A separate Claude compatibility spike verifies OAuth identity before reading usage, supports
explicit isolated profile directories, and keeps all credential and endpoint code outside the app.

The Cursor compatibility spike verifies identity directly with Cursor before reading usage. It
supports the default Cursor Agent Keychain login and isolated Cursor Agent file profiles without
reading Cursor Desktop state or browser cookies.

The original Grok compatibility spike remains as reproducible source and response-shape evidence
for the production adapter.

The production GitHub Copilot compatibility adapter binds each Pace account to an explicit GitHub
CLI username. It asks `gh auth token --user` for only that account, verifies its durable numeric
identity with GitHub's documented `/user` API, and only then reads personal Copilot quota. Pace
clears ambient token overrides, never changes the active GitHub CLI account, and does not depend on
a running editor, Copilot CLI, or coding harness. Settings discovers healthy GitHub CLI accounts
only after the user clicks Add. The user selects the account to register and can then rename,
disable, re-enable, or remove it without changing GitHub CLI credentials.

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

Set `PACE_APPLICATION_SUPPORT_DIRECTORY` to an isolated directory when testing the normal app
without reading or changing the user's saved Pace state.

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
