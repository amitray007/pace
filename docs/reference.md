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

The rail is flush with the right screen edge. The app must derive the organic top, inner, and lower
curves from the media instead of rounding a rectangle. The attached detail is one persistent panel,
not a sequence of detached popovers.

## Fixture contract

The static review fixture uses Claude 73%, Codex 21%, and Cursor 52% for the rail. Claude exposes
`Current session` at 73% and `All models` at 7%. Account-specific values remain isolated when the
user switches between Personal and Work. These values are review inputs, not provider assumptions.
