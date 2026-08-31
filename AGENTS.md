# Pace project agreement

Pace is a native macOS usage-limit instrument with menu-bar and screen-edge presentations.

## Product invariants

- Read `docs/product.md`, `docs/design.md`, and `docs/interactions.md` before changing visible
  behavior.
- Treat the edge-rail image and video reference as an acceptance target. Do not replace it with a
  generic sidebar, popover, or approximate SwiftUI layout.
- Build and approve the simulated-data visual shell before connecting live providers.
- Keep the collapsed edge surface click-through. It must not obstruct scrollbars, resize handles,
  pointer drags, scrolling, or trackpad momentum.
- Use one provider at a time in detailed views. Support multiple accounts within each provider.
- Never average usage percentages across accounts. Select an account or show the most urgent quota.
- Render the quota buckets returned by each provider. Do not assume every account exposes the same
  windows.
- Show observation time, stale data, missing buckets, signed-out state, and provider errors.
- Do not read browser cookies or silently copy OAuth tokens. A reviewed compatibility adapter may
  call an undocumented provider endpoint only when its source, identity checks, credential
  ownership, polling limits, and failure behavior are documented.
- Store only normalized snapshots and preferences unless a documented feature requires more.

## Native implementation

- Use SwiftUI for application views and AppKit for status-item and window behavior.
- Use a non-activating `NSPanel` for the edge surface.
- Use Core Animation for the rail silhouette, attached-panel movement, and other motion that needs
  exact timing or interruption behavior.
- Keep presentation, provider adapters, normalized state, and persistence separate.
- Preserve reduced-motion behavior, keyboard access, VoiceOver labels, and high-contrast states.

## Verification

- Verify visual work in the running macOS application.
- Compare edge-rail screenshots and recordings with the reference frames in `docs/design.md`.
- Test pointer behavior with overlay scrollbars, scrollbar drags, trackpad momentum, full-screen
  applications, Stage Manager, Spaces, and multiple displays.
- Run the smallest relevant code checks after implementation files and commands exist.
- State any hardware, refresh-rate, provider, or authentication path that remains unverified.

Do not commit, push, publish, release, or alter system permissions without explicit authorization.
