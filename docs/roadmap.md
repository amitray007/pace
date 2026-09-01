# Delivery roadmap

The roadmap uses evidence gates instead of dates. Do not connect live provider data before the
reference rail passes visual and interaction approval.

## Phase 0: Product record

Status: complete.

- Record product, design, interaction, architecture, privacy, and provider boundaries.
- Preserve the Codex feasibility spike.
- List unresolved platform and provider checks.
- Record Pace as the settled working product name.

Exit gate: the repository documents the current decisions without contradicting files.

## Phase 1: Core foundation

Status: complete.

- Create the native macOS application and test targets.
- Model provider accounts, credential bindings, quota subjects, normalized buckets, and freshness.
- Add account registration, rename, enable, disable, ordering, removal, and identity-mismatch rules.
- Add a shared snapshot store, refresh coordinator, and per-provider account selection.
- Add deterministic simulated providers and persistence without storing secrets.

Exit gate: focused tests prove account isolation, deterministic refresh, persistence, removal, and
shared selection.

## Phase 2: Provider feasibility spikes

Status: in progress. Claude, Cursor, Grok, Codex, and GitHub Copilot have deterministic production
multi-account isolation and current read-only live smoke checks. Distinct live two-account login
and credential-rotation checks remain open.

- Prove two-account profile isolation for Claude, Cursor, Grok, Codex, and GitHub Copilot where the
  provider supports it.
- Verify identity before quota retrieval and after credential refresh.
- Confirm that provider processes do not need to remain running after login.
- Keep spike credentials, raw responses, and account identifiers out of Git.

Exit gate: each promoted provider has reproducible identity, refresh, account-isolation, and
failure evidence. A spike is not yet connected to the product UI.

## Phase 3: Reference harness

- Retrieve the supplied image and video into an ignored local reference directory.
- Extract canonical frames for the mini handle, full rail, each provider panel, dismissal, and the
  settings arc.
- Record the video's coordinate system, measured geometry, colors, typography, path control points,
  transition durations, and easing observations.
- Create deterministic simulated providers, accounts, buckets, reset times, and error states.

Exit gate: every required visual state has a named reference frame and deterministic fixture.

## Phase 4: Static native surfaces

Status: in progress. The status item, menu panel, shared simulated selection, click-through edge
panel, static rail states, attached detail, rings, settings control, mirrored edges, display and
position selection, provider ordering, activation settings, and diagnostic reference overlays now
run. Final visual approval and remaining platform-size checks are still open.

- Create the macOS application target.
- Build the menu-bar status item and static details panel.
- Build the mini handle, rail silhouette, provider rings, attached panel, and settings control.
- Add shared provider and account selection using simulated data.
- Add settings for surface mode, edge, display, position, activation, and provider ordering.

Exit gate: static captures match the reference geometry and information hierarchy.

## Phase 5: Motion and pointer safety

Status: in progress. The rail shell, attached panel, provider switches, rapid retargeting,
dismissal, and reduced-motion path now use presentation-layer-aware Core Animation. The
deterministic intent engine and permission-free AppKit adapter now implement modifier-hover,
click-handle, dwell, provider travel, dismissal grace, and scroll, drag, fast-motion, and full-screen
suppression. The deterministic Release sequence now passes an Animation Hitches capture on the
built-in 120 Hz display with no post-startup main-thread delay over 33 ms and no sequence hitch over
16.67 ms. A physical single-display Chrome pass confirms that right-edge scrolling, an overlay
scrollbar track click, and a scrollbar-thumb drag pass through the collapsed visual window, and that
the rail orders out for a full-screen application. Trackpad momentum, resize handles, expanded input
regions, horizontal and traditional scrollbar variants, Spaces, Stage Manager, a 60 Hz or
second-display capture, and explicit visual approval remain.

- Implement rail path morphing and attached-panel movement with Core Animation.
- Make every rapid transition interruptible and retargetable.
- Add Shift-hover, click, and dwell activation.
- Add scroll, momentum, drag, resize, and fast-edge-motion suppression.
- Add pointer-safe rail-to-panel travel and dismissal grace.
- Add reduced-motion behavior.

Exit gate:

- Side-by-side recordings pass visual review.
- Scrollbars and underlying applications remain usable.
- Frame pacing is smooth at 60 Hz and 120 Hz.
- The user explicitly approves the rail.

## Phase 6: Shared application behavior

Status: in progress. Both surfaces now share deterministic provider and account selection, preserve
each account's own quota buckets, avoid percentage averaging, and present current, aging, stale,
missing-bucket, signed-out, unavailable, and failed states without turning missing data into zero.
Observation time, last-good stale data, text-and-symbol status, VoiceOver descriptions, direct
provider and account shortcuts, keyboard-reachable quota rows, manual refresh, reduced motion,
increased-contrast tracks, and owner-only normalized state persistence are wired. Launch-at-login
now uses native Service Management with explicit registration, approval, failure, and external
status handling. A deterministic notification core now evaluates per-account threshold crossings,
same-cycle reset reminders, stale-data transitions, and quiet-hour holds without requesting system
permission. A signed-build launch integration check, approved notification settings, native
delivery, and permission-path testing remain.

- Add menu-bar, rail, and both presentation settings.
- Add one-provider-at-a-time details and per-provider account selection.
- Add All accounts without percentage averaging.
- Add keyboard navigation, VoiceOver, high contrast, launch at login, and notifications.
- Persist normalized state and preferences.

Exit gate: both surfaces behave consistently with simulated success, stale, unavailable, signed-out,
and failure states.

## Phase 7: Provider integrations

Status: in progress. A production-separated Codex adapter now discovers explicit `CODEX_HOME`
profiles, verifies the account returned by the supported app-server protocol, and normalizes every
returned limit window. Deterministic two-profile tests and an opt-in live smoke check exist. A
long-running per-profile supervisor now reuses the supported app-server process, refetches sparse
update notifications, marks disconnects honestly, and reconnects with bounded backoff. Its request
transport is asynchronous and deadline-bound, account lifecycle changes reconcile monitors, and
shutdown proves the old process is reaped before replacement. The production app now registers the
current or an explicitly chosen `CODEX_HOME`, supersedes the simulated Codex fixture while a real
account is registered, and keeps all registered profiles in one shared adapter. Runtime replacement
explicitly closes the previous adapter. The account boundary keeps discovery read-only, classifies
identity and credential
conflicts, adds only the selected candidate, enforces one account per real credential source, and
rolls back registration when the initial refresh fails. It exposes rename, enable, disable,
single-account refresh, and removal. Isolated native UI checks have
verified add, restart, rename, disable, re-enable, live bucket rendering, and accessibility labels.
Removal behavior is covered by store and coordinator tests. Grok now uses the same explicit profile
onboarding and simulation fallback. Its production adapter validates owner-private first-party xAI
credentials, verifies `/user` identity before `/billing`, normalizes returned weekly, monthly,
included-credit, and capped pay-as-you-go buckets, and polls each enabled account independently at a
provider-safe interval. Its live smoke passed without a running Grok process. GitHub Copilot now
uses explicit GitHub CLI account selection, documented GitHub identity verification, a separately
isolated quota compatibility reader, independent polling, and the same shared account lifecycle.
Its live smoke passed without an editor, Copilot CLI, or coding harness. Claude now uses explicit
`CLAUDE_CONFIG_DIR` onboarding, source-verified `CLAUDE_SECURESTORAGE_CONFIG_DIR` selection, and the
same shared account lifecycle. Its isolated compatibility reader verifies account and organization
before usage, serializes cancellable requests, bounds redirects and responses, and polls
conservatively. Rotation uses Claude Code's current and legacy OAuth locks plus storage-write lock,
reloads and compares the refresh token, and re-verifies identity before publishing. Concurrent
login changes are adopted or restart cleanly. The read-only live smoke passed without a running
Claude process. Cursor now binds the current Cursor Agent Keychain account or an explicit isolated
file-profile home, verifies the CLI, remote user, and team identity before usage, refreshes access
tokens only in memory, and polls every enabled account independently. Its production read-only
smoke passed without a running Cursor application or agent process.

- Promote validated feasibility spikes into production adapters.
- Add provider-specific account discovery, login, reauthentication, and removal behavior.
- Keep private compatibility endpoints isolated and locally disableable.
- Add manual limits only if they remain useful after live-provider validation.

Exit gate: displayed values match each provider's own surface and never cross account boundaries.

## Phase 8: Distribution

Status: in progress. The generated application now has deterministic development version metadata.
An unsigned local preflight builds the Release configuration and verifies the actual bundle name,
identifier, version, build number, agent-app mode, deployment target, executable architectures,
absence of provider credential files, and absence of a code signature. Public identity, supported
architectures, signing, packaging, installation, and publication remain open.

- Confirm provider-asset permissions.
- Choose minimum macOS version and architecture support.
- Keep version injection and unsigned bundle verification reproducible.
- Add signing, notarization, release archives, checksums, and update behavior.
- Add GitHub Actions and the personal Homebrew tap only when release scope is authorized.

Exit gate: a signed build passes clean-machine installation and privacy checks.

## Open decisions

- Default rail activation after permission and scrollbar testing.
- Oldest supported macOS version.
- Exact multi-account support for each provider.
- Public licensing and use of provider marks.
