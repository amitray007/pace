# Technical architecture

## Decision

Build Pace as a native macOS application. Use SwiftUI for application views, AppKit for the
status item and windows, and Core Animation for the reference rail's precise and interruptible
motion.

This choice fits a Mac-only utility that needs non-activating windows, screen-edge placement,
Spaces and full-screen behavior, click-through hit testing, high frame-rate animation, launch at
login, and low idle overhead. Electron and Tauri add no product benefit for the first platform.

## System boundaries

```text
Provider processes and APIs
          │
          ▼
Provider adapters ──▶ snapshot normalizer ──▶ snapshot store
                                                │
                                  account usage status resolver
                                                │
                         ┌──────────────────────┼──────────────────────┐
                         ▼                      ▼                      ▼
                  menu-bar model         edge-rail model        settings model
                         │                      │                      │
                         ▼                      ▼                      ▼
                  status item/panel      NSPanel + CA layers     SwiftUI window
```

Provider adapters do not know about presentation. Views do not parse provider responses.

## Domain model

```swift
struct ProviderAccount: Identifiable, Sendable {
    let id: AccountID
    let providerID: ProviderID
    var displayName: String
    let planName: String?
    let identity: ProviderIdentity
    var isEnabled: Bool
}

struct LimitSnapshot: Identifiable, Sendable {
    let id: String
    let providerID: String
    let accountID: String
    let bucketID: String
    let label: String
    let usedFraction: Double
    let windowDuration: Duration?
    let resetsAt: Date?
    let observedAt: Date
    let freshness: Freshness
}
```

Bucket identity includes provider, account, quota subject when present, and provider-defined bucket
ID. This prevents values
from different identities from overwriting each other.

Snapshot `Freshness` records the state of returned data. `AccountUsageStatus` resolves those
snapshots together with the account connection state. It keeps data freshness separate from the
latest connection issue, so a failed refresh can retain and label the last good snapshots as stale.
A missing bucket is not a zero-percent snapshot.

## Provider interface

The current provider seam supports deterministic account discovery and per-account refresh. It
needs no provider process or harness to remain active.

Production adapters can add these capabilities after their feasibility spikes prove the required
lifecycle:

- discover configured accounts without exposing secrets;
- read an initial normalized snapshot;
- stream updates when the provider supports them;
- report authentication and freshness state;
- reconnect with bounded backoff;
- stop all processes and timers cleanly.

Each adapter declares which account and quota capabilities it supports. The app must not infer that
all providers expose the same window names or reset behavior.

## Provider feasibility

| Provider | Source | Confidence | Boundary |
| --- | --- | --- | --- |
| Codex | Supported local `codex app-server` JSON-RPC | High | Use `account/rateLimits/read` and `account/rateLimits/updated`. Keep each account in a separate `CODEX_HOME`. |
| Claude Code | Source-verified OAuth compatibility adapter | Medium | Verify identity before calling the OAuth usage endpoint. Keep each account in a separate `CLAUDE_CONFIG_DIR`. |
| Cursor | Source-verified compatibility adapter | Medium | Direct identity and usage reads are proven for one default CLI account. Prove two isolated CLI file profiles before product integration. |
| Grok | Source-verified Grok Build compatibility adapter | Medium-high | Keep each account in a separate `GROK_HOME`; verify personal and team behavior separately. |
| GitHub Copilot | GitHub-authenticated usage adapter | Medium-high | Bind every credential to an explicit GitHub identity; never depend on whichever `gh` account happens to be active. |

Sources:

- [Codex app-server protocol](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)
- [OpenUsage Claude provider](https://github.com/robinebers/openusage/blob/main/docs/providers/claude.md)
- [OpenUsage Cursor provider](https://github.com/robinebers/openusage/blob/main/docs/providers/cursor.md)
- [Grok Build authentication](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/02-authentication.md)
- [Cursor usage and limits](https://prod.cursor.com/help/models-and-usage/usage-limits)
- [Cursor CLI authentication](https://docs.cursor.com/en/cli/reference/authentication)

### Codex

Start `codex app-server --stdio`, perform the JSON-RPC initialization handshake, request
`account/rateLimits/read`, then listen for `account/rateLimits/updated`. Keep one background process
while Codex data is enabled. Reconnect with bounded backoff if it exits.

The production adapter foundation resolves the Codex executable without relying on an editor or
harness, replaces ambient `CODEX_HOME` with the selected explicit profile, requests `account/read`
without proactive token refresh, and rejects accounts that do not expose a verifiable ChatGPT
email. It renders all returned limit IDs and primary or secondary windows. The earlier bounded
request process is replaced by one persistent connection per explicit profile. Requests use
correlated IDs, asynchronous pipe I/O, and bounded timeouts. Sparse
`account/rateLimits/updated` notifications trigger a full read instead of clearing omitted fields;
one pending signal closes the read-before-subscribe race. Process exits mark last-good data stale,
then reconnect with bounded backoff. Shutdown closes stdin, waits briefly, and force-reaps a process
that ignores termination before a replacement starts.

The generic refresh coordinator applies streamed results to the same store read by both surfaces.
It reconciles one monitor per enabled account from committed store changes. Registration and
re-enablement start monitoring; disablement and removal cancel it. Store mutations serialize the
complete read-save-publish transaction so concurrent account updates cannot overwrite each other.
An applied delivery and a persistence failure are separate events, which lets both surfaces preserve
last-good state while showing a save error. Explicit app onboarding remains the promotion gate.

The live spike was verified on 2026-08-31 with Codex CLI 0.151.0. The response contained a general
weekly bucket plus model-specific five-hour and weekly buckets. This proves the UI must render
returned buckets dynamically.

### Claude Code

The isolated `claude-usage-spike` reads one or more explicit `CLAUDE_CONFIG_DIR` profiles without a
running Claude Code process. It resolves a profile-specific Keychain item or credential file,
requires `user:profile`, verifies `/api/oauth/profile`, and only then reads `/api/oauth/usage`.
Profiles are checked sequentially because Anthropic rate-limits this endpoint aggressively.

The default profile and a fresh signed-out custom profile were verified on 2026-08-31 with Claude
Code 2.1.251. The default profile returned Session, Weekly, and a model-scoped Fable bucket. A
second distinct live account, refresh-token rotation, and Team or Enterprise response shapes remain
unverified. The spike never refreshes or writes credentials.

### Cursor

The isolated `cursor-usage-spike` supports two credential bindings. The default binding reads the
Cursor Agent Keychain service without allowing an authentication prompt. Additional accounts use a
profile-specific home directory and Cursor Agent's file credential store. Cursor Agent owns login,
reauthentication, and token rotation. Pace stores only the profile path and verified identity.

For every refresh, the spike reads the selected profile only, matches the access-token JWT subject
to `authInfo.authId` in that profile's CLI config, then calls Cursor's
`DashboardService/GetMe`. It requires the server response to return the same authentication ID and
checks the returned user and team against the registered Pace identity. Only then does it call
`DashboardService/GetCurrentPeriodUsage`; `GetPlanInfo` is optional and cannot discard valid usage.
No Cursor process or harness must remain running.

The direct default-profile path was verified on 2026-08-31 with Cursor Agent
2026.07.01-41b2de7. It returned a Team plan and Total Usage, Cursor Models, and Other Models
buckets. A fresh isolated home reported signed out instead of inheriting the default login. Two
distinct live file profiles, file-profile token rotation, request-based Enterprise fallbacks, and
long-running polling remain unverified. The spike never reads Cursor Desktop SQLite state or
browser cookies, and it never refreshes or writes credentials.

### Compatibility adapters

An undocumented endpoint is allowed only behind a provider-specific adapter whose source and
behavior have been reviewed. The adapter must verify the remote identity before publishing data,
use conservative polling and bounded backoff, preserve a last-good snapshot, and fail only the
affected account. Popularity is supporting evidence, not provider authorization.

Provider CLIs own credentials when they offer isolated profiles. Pace stores a non-secret profile
reference and expected identity. The CLI is needed for login or reauthentication, not for ongoing
usage display.

### Multiple accounts

A logical adapter belongs to one provider. Every discovery and refresh operation uses an explicit
account and credential binding, so one adapter can refresh several isolated provider profiles
without depending on ambient login state. If a provider only exposes the currently authenticated
CLI account, the first version must say so instead of pretending to support parallel accounts.

Multiple-account credential handling remains provider-specific. Optional provider-issued API
credentials belong in Keychain. Existing CLI OAuth tokens remain owned by the provider CLI or an
isolated provider profile. Pace never silently converts an ambient login into a Pace-owned token.

## Presentation architecture

### Menu bar

`NSStatusItem` owns the status icon. A semitransient `NSPopover` hosts the SwiftUI menu panel and
keeps provider and account selection open during internal interaction. Its model derives provider
tabs, account selection, quota rows, and the headline value from the shared snapshot store.

### Edge rail

`EdgePanelController` owns a borderless, non-activating `NSPanel`. It follows the selected display's
visible frame and observes display, Space, full-screen, Stage Manager, menu-bar, and Dock changes.

The collapsed panel ignores pointer events. Activation logic arms it only after a configured intent
condition. Visible-shape hit testing prevents transparent window regions from blocking the
application below.

Core Animation layers own the rail path, connector, progress rings, and reference-critical motion.
SwiftUI hosts provider content and settings where layout convenience does not weaken animation or
hit-testing control.

## Persistence and security

- Store normalized snapshots and preferences in Application Support.
- Persist the simulated shell to `state.json` and presentation choices to `preferences.json`; both
  files use owner-only permissions and contain no provider secrets.
- Store optional provider-issued credentials in Keychain.
- Never store conversation text, prompts, browser cookies, or silently copied OAuth tokens.
- Record provider, account, bucket, source, observation time, and error state.
- Keep polling local where possible and use provider-safe intervals.
- Keep notification evaluation local and opt-in.
- Redact account identifiers from diagnostics unless the user explicitly exports them.

## Unresolved implementation checks

- Verify modifier-hover activation, click-through behavior, and suppression on physical hardware
  with overlay scrollbars, pointer drags, full-screen applications, Spaces, and multiple displays.
- Select the oldest supported macOS version after the visual prototype proves required APIs.
- Verify multi-account capabilities independently for every provider.
- Prove two live Claude config directories and safe credential rotation before promoting the
  Claude spike.
- Prove two live Cursor Agent file profiles and safe CLI-owned credential rotation before
  promoting the Cursor spike.
- Measure reference paths, timings, and colors from the source media during the visual phase.
