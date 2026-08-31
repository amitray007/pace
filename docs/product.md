# Product requirements

## Product statement

Pace helps people pace AI usage before session, weekly, model-specific, credit, or spending
limits interrupt their work. It provides a dependable menu-bar panel and an optional ambient edge
rail without becoming a full analytics dashboard.

The first user is a macOS developer who uses several coding agents, providers, and accounts during
the same week.

## Goals

- Show current consumption, remaining capacity, and reset time at a glance.
- Support multiple providers and multiple accounts per provider.
- Keep one provider active at a time in detailed views.
- Make missing, stale, or unsupported data clear.
- Offer an exact, polished edge-rail experience without interfering with normal macOS interaction.
- Provide a conventional menu-bar surface when the rail is hidden or unsuitable.
- Keep account access and usage data local.

## Non-goals for the first release

- Team leaderboards or social comparison.
- Cloud sync or a hosted account system.
- Long-term analytics dashboards.
- Provider support based on browser-cookie extraction, silent token copying, or unreviewed private
  endpoint scraping.
- Arbitrary theme builders that weaken the reference design.
- Predicting undocumented provider limits from token counts.

## Presentation modes

Users choose one of three modes:

| Mode | Purpose | Behavior |
| --- | --- | --- |
| Menu bar | Dependable daily access | A status item opens the selected provider and account limits. |
| Edge rail | Ambient awareness | A mini handle reveals the high-fidelity provider rail after deliberate activation. |
| Both | Power-user visibility | Both surfaces read the same state and preserve the same selection. |

The current recommendation is menu bar by default. The edge rail is opt-in until its scrollbar and
pointer-safety checks pass.

## Provider and account semantics

A provider owns one or more accounts. An account owns zero or more provider-defined quota buckets.
Examples include session, weekly, model-specific weekly, monthly credit, and spend-control limits.

Detailed views show one provider at a time. The user can then select an account inside that
provider. The app remembers the last selected account for each provider.

An optional **All accounts** summary can list accounts for the selected provider. It must not
average their percentages. It highlights the account and bucket nearest exhaustion.

Pace may discover an existing local provider profile without registering it. The user explicitly
enables a discovered account before Pace reads protected credentials or contacts the provider.
Changing the identity inside a profile never changes the identity of an existing Pace account.

An account display name is a local preference. Provider identity and quota-subject identity remain
separate so renaming cannot move snapshots between accounts.

The menu-bar status item and edge-rail ring can represent one of these configurable values:

- the selected account's selected quota;
- the most urgent quota for the selected account;
- the most urgent quota across all enabled accounts for that provider.

## Limit presentation

Every quota row shows available fields from this set:

- provider and account;
- quota label;
- used and remaining percentage;
- reset countdown and absolute reset time;
- observation time and freshness;
- plan or model label;
- credit balance or spend-control state;
- unavailable, stale, signed-out, limited, or error state.

The app does not invent a missing bucket or render it as zero percent.

## Customization

Customization should control behavior and information density before decoration.

### Presentation

- Menu bar, edge rail, or both.
- Left or right screen edge.
- Selected display and vertical rail position.
- Rail scale and mini-handle size within fidelity-safe ranges.
- Hide the rail in full-screen applications.

### Activation

- Modifier plus hover, recommended for the edge rail.
- Click the mini handle.
- Plain hover with a dwell delay, opt-in.
- Configurable modifier key, dwell delay, and dismissal delay.

Shift is the proposed default modifier. Implementation must verify that modifier detection does not
require an unreasonable system permission. Click remains the permission-free fallback.

### Data

- Provider and account visibility and order.
- Selected account and headline quota for each provider.
- Refresh interval within provider-safe bounds.
- Threshold notifications and quiet hours.
- Absolute, relative, or combined reset-time display.

### Accessibility

- Reduced motion.
- Keyboard command for opening the active surface.
- VoiceOver descriptions for provider, account, usage, reset, and freshness.
- High-contrast status treatment that does not rely only on color.

## Success criteria

- A user can understand the most urgent limit in less than two seconds.
- The edge rail never prevents scrollbar use, dragging, scrolling, or window resizing.
- The menu-bar panel remains useful when the edge rail is disabled.
- Provider and account switching does not cause data from one identity to appear under another.
- Stale data is never presented as current.
- The reference rail passes explicit visual and motion approval before live data integration.
