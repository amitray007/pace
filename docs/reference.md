# Reference media and measurements

Pace uses public source media as an acceptance target. The media stays in `.local/` and is not
committed. Run `make reference-frames` to download, verify, and extract the review set.

## Source authority

| Source | Runtime role | Local file | SHA-256 |
| --- | --- | --- | --- |
| [Primary side-notch post](https://x.com/hivinz_/status/2093651446927626294) | Interaction, scale, attached-panel movement | `side-notch-primary.mp4` | `58252dae5269a40ab3ffea2b1fc83f96db8938adbc2814e16b61f764147bd901` |
| Primary side-notch image | Black shell, rings, spacing, and 73/21/52 fixture | `side-notch-primary-2000.jpg` | `f971ffee7c34d130bdc793c642e0e39e32ea363d54fe2b2a4905f2bbb133c899` |
| [Settings refinement post](https://x.com/hivinz_/status/2094082881371156571) | Final rail contour, lower arc, and settings control | `side-notch-settings.mp4` | `612b1b555bd5f76a53a4bfa387cba82cd9dfeba9f8c95fb8e8870f2f96d7c283` |
| Settings refinement image | Refined silhouette and negative space | `side-notch-settings-2000.jpg` | `c86cbb111ab752088c0a853beacaa014776f11c987fe511175976b42a33ddc52` |
| [DHH usage-panel post](https://x.com/dhh/status/2090005543112851862) | Menu-bar information hierarchy only | `menu-panel-dhh.jpg` | `d8212531cda6687dbdb8fa41b91156449a73bb4be4963e6a1eed91e7c0f8f9a1` |

The primary video is 2380 x 2160, 60 fps, and 20.50 seconds. The refinement video is 1552 x
1552, 60 fps, and 20.87 seconds. The images are 2000 x 2000, except the 1572 x 1404 menu-panel
image.

## Canonical frames

Frame timestamps are stable inputs to screenshot and motion review. They are not inferred motion
durations.

| State | Video | Timestamp | Extracted file |
| --- | --- | ---: | --- |
| Mini handle | Primary | 0.50 s | `primary-mini.png` |
| Cursor detail | Primary | 2.50 s | `primary-cursor-detail.png` |
| Claude detail | Primary | 3.50 s | `primary-claude-detail.png` |
| Codex detail | Primary | 5.50 s | `primary-codex-detail.png` |
| Dismissal transition | Primary | 12.75 s | `primary-dismissal.png` |
| Refined mini handle | Settings | 0.50 s | `settings-mini.png` |
| Refined Cursor detail | Settings | 2.50 s | `settings-cursor-detail.png` |
| Refined Claude detail | Settings | 4.00 s | `settings-claude-detail.png` |
| Refined rail | Settings | 8.00 s | `settings-rail.png` |
| Settings hover | Settings | 10.00 s | `settings-button.png` |
| Refined Codex detail | Settings | 12.50 s | `settings-codex-detail.png` |

## Measured geometry

Measurements use the 1552 x 1552 refinement video. The video appears to show a Retina desktop,
so the point values below use a 2:1 estimate. They remain provisional until the running application
is overlaid at the same desktop scale.

| Token | Source pixels | Initial app points |
| --- | ---: | ---: |
| Rail width | 139 px | 70 pt |
| Rail body height | 640 px | 320 pt |
| Provider ring diameter | 80 px | 40 pt |
| Provider row spacing | about 200 px | 100 pt |
| Detail panel width | 451 px | 226 pt |
| Detail panel height | 278 px | 139 pt |
| Detail connector depth | about 56 px | 28 pt |
| Detail panel corner radius | about 32 px | 16 pt |
| Settings circle diameter | about 90 px | 45 pt |

## Initial implementation tokens

The first static shell uses a 324 x 416 pt transparent canvas. The rail starts at x = 254 pt. Its
visible contour starts 30 pt below the canvas top so the attached panel can sit above the rail as it
does in the refinement video. Provider group centers are y = 92, 194, and 297 pt. The attached
panel is 226 x 139 pt, and its connector extends 28 pt to the active provider center. The connector
spans 17 pt above and below that center.

| Token | Value |
| --- | --- |
| Shell | `#000000` |
| Ring track | `#2B2B2B` |
| Claude accent | `#F75C33` |
| Codex accent | `#2BF09E` |
| Cursor accent | `#C7FF1A` |
| Menu-panel background | approximately `#09090A` |
| Ring percentage | 13 pt bold monospaced digits |
| Detail title | 11 pt semibold |
| Detail labels | 8.5 pt medium |
| Menu panel | 326 pt wide; 204-291 pt high for current simulated providers |

These are recorded implementation inputs, not claimed source design values. Screenshot overlays must
still correct them when a visible difference appears.

## Provider-mark provenance

Pace vendors monochrome SVG marks and renders them as template images. It does not redraw provider
marks with SwiftUI primitives or substitute unrelated system symbols.

| Provider | Asset source | Local SHA-256 |
| --- | --- | --- |
| Claude | Anthropic's official [media resources](https://www.anthropic.com/press-kit), `Claude Spark - Clay.svg` | `6d53db4be375e899c937c26cf16684a80d6e869b1928d72b37748bef2560e219` |
| Codex | OpenUsage's pinned OpenAI mark at commit `05c40a1dc50a16ecdc7b55d2e4fadf26827b4f61`, checked against [OpenAI's brand guide](https://openai.com/brand/) | `f48c19561ddb2ce3be624c428acea98d07d8924d5e91c07a57b85d555c61a13b` |
| Cursor | Cursor's official [brand asset pack](https://cursor.com/brand), `CUBE_2D_LIGHT.svg` | `9e8ae47a4e41c3475cd119e761f868f75b27e382c71023fb985123fe0a8f9a25` |
| GitHub Copilot | GitHub's official Primer Octicons `copilot-24.svg` at commit `0e21a4c2d8449102f10e533d241f04797af0914c` | `ca6cd98b226e71deae14ab2134a68a9a6d8807e1a351ff7d6ac668dbedfe2b22` |
| Grok | OpenUsage's corrected Grok mark from [change `c3777d5`](https://github.com/robinebers/openusage/commit/c3777d5929d14ea4b736939692c2dff7cc9e138e), pinned in Pace to commit `05c40a1dc50a16ecdc7b55d2e4fadf26827b4f61` | `4df0f1ffa82bc3c0f155b84617d349c28745b18a211a4066a7f591ef4704c1ad` |

The marks identify the corresponding provider inside Pace. Their owners retain all trademark and
artwork rights. Re-check the providers' current brand terms before public distribution.

The rail is flush with the right screen edge. The app must derive the organic top, inner, and lower
curves from the media instead of rounding a rectangle. The attached detail is one persistent panel,
not a sequence of detached popovers.

## Fixture contract

The static review fixture uses Claude 73%, Codex 21%, and Cursor 52% for the rail. Claude exposes
`Current session` at 73% and `All models` at 7%. Account-specific values remain isolated when the
user switches between Personal and Work. These values are review inputs, not provider assumptions.

## Running deterministic captures

Build the native app, then set a static state when launching its executable:

```sh
make build
PACE_REFERENCE_PREVIEW=claude PACE_REFERENCE_MENU=1 \
  .build/xcode-derived-data/Build/Products/Debug/Pace.app/Contents/MacOS/Pace
```

`PACE_REFERENCE_PREVIEW` accepts `mini`, `rail`, `claude`, `codex`, or `cursor`. Set
`PACE_REFERENCE_EDGE=left` to verify the mirrored edge treatment; right is the default. Omit
`PACE_REFERENCE_MENU=1` to capture only the edge surface. These variables change presentation only;
the data always comes from `SimulatedScenarios.visualReference()`.

Set `PACE_REFERENCE_MOTION=1` with the mini preview to run a deterministic reveal, provider-switch,
rapid-retarget, and dismissal sequence for frame capture. This harness does not enable pointer
input or provider access. Set `PACE_REFERENCE_MOTION_DELAY` to the number of seconds that capture
automation needs before the first reveal. The default is two seconds.

The source recordings settle the rail reveal in about 0.30 seconds and a provider-panel switch in
about 0.20 to 0.30 seconds. Pace therefore uses a 0.28-second reveal and a 0.22-second detail
retarget with a cubic `(0.2, 0.8, 0.2, 1)` timing function. Content enters after a 0.08-second shell
head start, fades over 0.14 seconds, and clears in 0.08 seconds on dismissal. Reduced Motion applies
geometry directly and keeps a 0.10-second state fade. These are measured implementation tokens,
not provider behavior.

After saving a rail capture, generate normalized silhouette evidence with:

```sh
make visual-benchmark VISUAL_CAPTURE=.local/review/current/rail-claude.png
```

The default comparison uses the later Claude-detail frame because it includes the final lower arc
and settings control. The benchmark writes ignored local masks and difference images. Its numerical
output is diagnostic; the visual acceptance matrix in `docs/design.md` remains authoritative.
