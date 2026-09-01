# Local readiness boundary

This reference records what Pace proves locally and what still needs human input, additional
hardware, provider accounts, release credentials, or publication authority. It prevents an external
validation gate from looking like unfinished local implementation.

The checkpoint applies to branch `feat/core-foundation` at commit `3b0d791`. The worktree was clean
when the audit began on 2026-09-01.

## Completion matrix

| Roadmap area | Local evidence | Status | External evidence still required |
| --- | --- | --- | --- |
| Product record | Product, design, interaction, architecture, privacy, provider, and delivery decisions agree on Pace and its boundaries. | Complete | None. |
| Core foundation | Focused tests cover account isolation and lifecycle, normalized snapshots, deterministic refresh, persistence, and shared selection. | Complete | None. |
| Provider feasibility | Claude, Codex, Cursor, Grok, and GitHub Copilot have deterministic multi-profile isolation, identity and failure tests, and one existing-auth read-only smoke check. | Locally ready | Use two distinct live accounts per provider. Exercise live credential rotation and supported organization or Enterprise variants. |
| Reference harness | `make reference-frames` verifies five pinned source hashes and extracts eleven named canonical frames. The deterministic visual fixture and measured geometry, color, typography, path, duration, and easing tokens are recorded. | Complete | The unpublished source design control points are not available. Perceptual review remains authoritative. |
| Static native surfaces | The native menu panel, rail, attached detail, settings entry, mirrored edges, display placement, provider ordering, and shared simulated selection run in deterministic capture modes. | Locally ready | The user must approve side-by-side visual fidelity. Repeat the capture on another display size. |
| Motion and pointer safety | Core Animation transitions are presentation-layer-aware and interruptible. The deterministic Release sequence passes on the built-in 120 Hz display. Physical checks cover collapsed scrolling, overlay scrollbar track and thumb input, expanded transparent regions on both edges, visible controls, full screen, and one traditional horizontal scroller. | Locally ready | Check 60 Hz pacing, a second display, trackpad momentum, resize handles, Spaces, and Stage Manager. The user must approve the motion beside the source video. |
| Shared application behavior | Both surfaces share provider and account state without percentage averaging. Tests and native review cover freshness and failure states, keyboard access, VoiceOver descriptions, increased contrast, reduced motion, launch-at-login state handling, notification rules, and normalized persistence. | Locally ready | Approve final Settings layout. Test launch at login with a signed build. Explicitly request notification permission and verify a delivered banner. |
| Provider integrations | Production-separated adapters implement explicit account registration, local naming, refresh, enable, disable, removal, identity verification, conservative polling, and live-to-simulated fallback. Credentials remain in provider-owned stores. | Locally ready | Compare displayed values with each provider's own live surface for the required account combinations. Re-run compatibility checks when providers change private endpoints. |
| Distribution | `make release-preflight`, `make release-archive`, and `make release-smoke` build, inspect, package, checksum, extract, launch, observe, terminate, and clean up an unsigned universal application without installation. Repeated builds produced identical archive bytes. | Unsigned local release ready | Choose the public bundle identifier, minimum macOS version, architecture support, license, and provider-mark terms. Then authorize signing, notarization, clean-machine installation, update testing, CI, and publication separately. |

## Local install identity

`make install` builds the Release application, signs it with a local
self-signed certificate, and copies it to `/Applications`. The certificate is
created on demand by `Scripts/create-signing-identity.sh` and is trusted only in
this user's trust domain. It is not an Apple Developer ID and it does not
support distribution or notarization.

The identity exists because of the keychain. macOS stores an "Always Allow"
decision against an application's designated requirement. Signing produces
`identifier "com.amitray.Pace.dev" and certificate root H"63f2ec…"`, which does
not change when the binary does, so an approval granted once holds across
rebuilds. An ad-hoc signature's requirement is the binary's own CDHash, which
made every rebuild a different application and discarded every approval.

Each provider credential is a separate keychain item with its own access
control, so each still needs one approval the first time. Pace reads these items
and never writes them; the credentials stay owned by Claude Code and Cursor.

## Current Mac coverage

The local runtime audit used an Apple silicon Mac with one connected built-in display at 1728 x
1117 points and 120 Hz. Stage Manager was disabled. This machine cannot provide 60 Hz,
multi-display, or enabled Stage Manager evidence without a deliberate environment change. The audit
did not change display settings, Spaces, Stage Manager, permissions, Login Items, or notification
authorization.

## Reproducible local gates

Run these commands from the repository root:

```sh
make reference-frames
make check
make benchmark
make interaction-benchmark
make release-smoke
```

`make check` covers strict formatting, strict lint, all package tests, and the unsigned Debug app
build. The two benchmarks enforce the documented release-mode p95 ceilings. `make release-smoke`
rebuilds the unsigned Release artifact before validating its checksum, extraction, launch, real rail
window, graceful exit, and cleanup.

## Next evidence order

1. Review the running rail and menu panel beside the canonical frames and recordings.
2. Run the remaining pointer and frame-pacing matrix on 60 Hz and a second display.
3. Register two real accounts for each provider and compare every returned bucket with the
   provider's own surface.
4. Decide the public product identity, supported systems, license, and provider-mark use.
5. Authorize signing and notification permission before testing the signed installation paths.

If any check fails, the failure becomes the next local implementation checkpoint. Until then, the
remaining work is validation or release authority, not an unbounded code queue.
