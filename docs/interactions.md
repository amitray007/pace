# Interaction and motion

## Interaction principles

- Require deliberate intent before the edge rail accepts pointer input.
- Keep the menu bar conventional and immediately available.
- Preserve spatial continuity between a provider ring and its details.
- Make every rapid interaction interruptible.
- Prefer short state-indicating motion over decorative animation.
- Keep scrollbars, trackpad gestures, window resizing, and full-screen work unaffected.

## Surface model

```text
Menu-bar status item ──click──▶ provider and account panel
          │
          └────────────── reads shared normalized state

Mini edge handle ──activate──▶ provider rail ──select──▶ attached details
          ▲                                      │
          └──────────── leave or dismiss ◀───────┘
```

The two surfaces share provider selection, account selection, snapshots, freshness, and settings.
Closing one surface does not stop provider refreshes required by the other.

## Edge activation

The edge rail supports three modes:

| Mode | Intended user | Safety behavior |
| --- | --- | --- |
| Shift plus hover | Recommended | The window stays click-through until Shift and the edge hotspot are both active. |
| Click handle | Conventional fallback | Only the visible mini handle accepts the click. |
| Plain hover | Opt-in | A configurable dwell and intent check reject passing pointer movement. |

Users can replace Shift with another supported modifier. The implementation must verify global
modifier detection and avoid requesting Accessibility or Input Monitoring permission only for a
cosmetic interaction. If a permission is unavoidable, click activation remains the default.

### Scrollbar and drag protection

Do not activate the rail while any of these conditions is true:

- a mouse button is down;
- a scrollbar or window-resize drag is active;
- scroll-wheel or trackpad momentum was observed recently;
- the pointer is moving rapidly along the edge;
- the active full-screen application is excluded;
- the user has temporarily suspended the rail.

When collapsed, the edge panel ignores mouse events. When open, only the visible rail and attached
panel accept pointer events. Transparent parts of the window return events to the application
underneath.

The implementation must test traditional scrollbars, overlay scrollbars, scroll thumbs, page
tracks, horizontal scrolling, browser content, editors, and multiple displays.

## Rail states

```text
hidden
  └─ activation intent ─▶ rail
                           ├─ provider hover/click ─▶ detail(provider, account)
                           ├─ settings ─────────────▶ settings window
                           └─ dismiss ──────────────▶ hidden
```

The detail panel and rail form one pointer-safe region. A menu-aim corridor protects diagonal
movement from the active provider ring into the detail panel. Crossing that corridor must not close
the panel or switch providers accidentally.

Provider selection can use a small hover delay. Dismissal uses a longer grace period. Exact values
come from comparison with the video and real pointer testing.

## Motion contract

The rail is used tens of times per day. Motion must be fast and subtle. Its purposes are spatial
consistency, state indication, and preventing abrupt geometry changes.

- The mini handle and rail are one morphing black silhouette.
- Entry and exit originate at the selected screen edge.
- The connector stays attached to the active ring.
- One persistent detail panel moves and resizes between provider rows.
- New interactions retarget from the current visible state instead of restarting an animation.
- Content can crossfade while the shell moves, but labels must remain readable.
- Ring and progress refreshes use restrained motion and do not replay the panel entrance.
- Reduced motion preserves the states with short fades and direct geometry changes.

Use Core Animation layers for the shell and other motion that needs exact path interpolation,
timing, or interruption. Measure durations and easing from the source video. Do not accept default
SwiftUI transitions without comparison.

Verify reveal, provider switching, rapid reversal, dismissal, and refresh at 60 Hz and 120 Hz.
Inspect frame pacing with Instruments before calling the motion smooth.

## Menu-bar behavior

- Clicking the status item opens the panel without animation that delays access.
- Provider tabs change the active provider.
- The account switcher changes only the account inside that provider.
- The panel remembers one selected account per provider.
- The status item can represent the selected quota or the most urgent enabled quota.
- Keyboard navigation reaches provider tabs, accounts, quota rows, refresh, and settings.
- Closing the panel restores focus to the previous application.

## Settings categories

Keep settings grouped by user intent:

1. **Surfaces:** menu bar, rail, or both; edge; display; position; full-screen behavior.
2. **Activation:** click, modifier-hover, or dwell-hover; modifier; delays; suspension shortcut.
3. **Providers:** enabled providers, account order, selected account, headline quota, refresh.
4. **Notifications:** thresholds, quiet hours, reset reminders, stale-data warnings.
5. **Accessibility:** reduced motion, contrast, text scale, keyboard shortcuts.

Do not expose internal animation control points or arbitrary theme values in the first release.
