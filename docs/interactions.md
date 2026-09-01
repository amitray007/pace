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

The current native adapter keeps the 324 x 416 pt visual panel permanently click-through. It uses a
permission-free global mouse monitor and polls the selected modifier only while activation intent
is pending or the rail is open. It does not install a keyboard event tap and does not request
Accessibility or Input Monitoring permission. Separate nonactivating input panels exist only over
the visible 18 x 70 pt click handle in click mode, or over the visible rail, settings control, and
attached detail while expanded. Modifier-hover and dwell-hover have no collapsed input window.

A running Release check on the built-in display used Chrome and an ignored local fixture beneath
the collapsed dwell-hover rail. Right-edge scrolling moved the document from Y 0 to Y 2184 while
the rail stayed collapsed. A visible scrollbar track click moved an isolated edge scroller from Y 0
to Y 802, and dragging its thumb moved it from Y 802 to Y 1664 through the click-through visual
window. Entering Chrome full screen removed every on-screen Pace window reported by Core Graphics;
the collapsed rail returned after leaving full screen. This check did not cover trackpad momentum,
window resize handles, the expanded input regions, horizontal or traditional scrollbar variants,
Spaces, Stage Manager, or another display.

This window footprint is implementation evidence, not the physical pointer exit gate. Rounded
corners still use bounded rectangular input regions, and scrolling directly over an expanded
interactive surface is handled by Pace. Verify real scrollbars, resize handles, dragging, momentum,
Spaces, Stage Manager, full-screen applications, and every selected display before approval.

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
- Command 1 through Command 9 selects the matching visible provider. Option Left Arrow and Option
  Right Arrow cycle only the active provider's accounts.
- The panel remembers one selected account per provider.
- The status item can represent the selected quota or the most urgent enabled quota.
- Keyboard navigation reaches provider tabs, accounts, quota rows, refresh, and settings.
- Command R refreshes usage. Escape closes the panel.
- Closing the panel restores focus to the previous application.

## Settings categories

Keep settings grouped by user intent:

1. **Surfaces:** menu bar, rail, or both; edge; display; position; full-screen behavior.
2. **Activation:** click, modifier-hover, or dwell-hover; modifier; delays; suspension shortcut.
3. **Providers:** enabled providers, account order, selected account, headline quota, refresh.
4. **Notifications:** thresholds, quiet hours, reset reminders, stale-data warnings.
5. **Accessibility:** reduced motion, contrast, text scale, keyboard shortcuts.

The Surfaces group also contains the native Launch Pace at login toggle. It reflects Service
Management state instead of a copied preference. Registration is opt-in. If macOS reports that the
registered item requires approval, Pace keeps the toggle on, explains the state, and opens Login
Items only after the user chooses that action.

The Notifications group uses native controls for a usage threshold, reset lead time, stale-data
warnings, and optional quiet hours. Every rule is off by default. Enabling the first alert rule is
an explicit permission action; opening Pace or Settings never prompts. If an enabled policy was
restored before permission was decided, Settings shows an Allow Notifications button. Denied,
provisional, authorized, and unavailable states use honest text and symbols. Quiet hours delay a
candidate until their local end time instead of discarding it.

GitHub Copilot account setup stays explicit. Clicking Add GitHub Copilot account asks GitHub CLI
for its healthy `github.com` accounts, excludes accounts already registered in Pace, and presents
the remaining usernames in the existing Settings surface. Discovery does not register anything.
Selecting one username triggers identity verification and the first quota refresh. Removing the
Pace account leaves the GitHub CLI login and OAuth credential unchanged.

Do not expose internal animation control points or arbitrary theme values in the first release.

The current Providers section keeps provider ordering and account management in the same native
group. Claude, Codex, Cursor, and Grok registration are always explicit: add the current
`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, Cursor Agent Keychain account, or `GROK_HOME`, or choose another
provider profile folder. Additional Cursor accounts use an isolated home created with
`AGENT_CLI_CREDENTIAL_STORE=file`. Add
current Claude account also honors `CLAUDE_SECURESTORAGE_CONFIG_DIR` and retains that exact
non-secret storage binding. Each real account has a local name, an enable switch, and a remove
action. Removing it never deletes the provider profile or credentials. A real account suppresses
only that provider's simulated fixture while the real account is enabled. Disabling or removing
the last enabled real account restores and refreshes the fixture.
