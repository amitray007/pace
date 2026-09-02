<div align="center">
<img src="docs/media/pace-icon.png" alt="" width="120">
</div>

# Pace

Pace is a macOS menu-bar app that reads your usage limits from Claude, Codex, Cursor, Grok, and
GitHub Copilot and shows them in one place. It reads the credentials those tools already keep on
your Mac, so there is nothing to sign into. Nothing leaves your machine except the requests to each
provider.

[![CI](https://github.com/amitray007/pace/actions/workflows/ci.yml/badge.svg)](https://github.com/amitray007/pace/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)](https://www.apple.com/macos/)

<div align="center">
<img src="docs/media/menu-panel.png" alt="The Pace menu-bar panel showing Claude session, weekly, and Fable quotas" width="380">
</div>

## Install

```sh
brew install --cask amitray007/tap/pace
```

The cask strips the quarantine flag and re-signs the bundle during install, because Pace is not
notarized. Read [unsigned builds](#unsigned-builds) before you decide to trust it.

## What it shows

Providers do not agree on how they measure you. Claude reports a five-hour session alongside a
weekly limit; Cursor reports included usage and API usage separately; Copilot reports credits. Pace
shows the windows each account actually returns instead of flattening them into a single number.

Colour tracks how much is used rather than which provider it belongs to. Green below 50%, yellow to
90%, red above. An exhausted quota looks urgent whoever it belongs to.

The status item holds up to two readings you choose, each a provider and one of its quotas. It
tints itself to match the menu bar like the system's own items, and redraws on every refresh.

There is also an optional rail on the screen edge, one ring per provider, which stays click-through
when collapsed so it never catches scrollbars, drags, or trackpad momentum.

<div align="center">
<img src="docs/media/edge-rail.png" alt="The Pace edge rail on the desktop: a ring per provider on the screen edge, with the Claude usage panel attached to the active ring" width="440">
</div>

## Providers

| Provider | Reads credentials from | Quota windows |
| --- | --- | --- |
| Claude | `Claude Code-credentials` in your keychain, or a Claude Code profile | Session, weekly, per-model |
| Codex | The Codex app server, using `CODEX_HOME` | Rolling 5-hour and 7-day limits |
| Cursor | `cursor-access-token` in your keychain | Included usage, API usage, per-model |
| Grok | `auth.json` in your Grok profile directory | Weekly limit |
| GitHub Copilot | The `gh` CLI you have already authenticated | Credits |

Pace never asks for a password and never stores one. macOS prompts for your approval the first time
it reads each keychain item, and that approval is what grants access. Pace does not read browser
cookies and does not copy tokens between providers.

Two of these endpoints are undocumented: GitHub's `copilot_internal/user` and Cursor's
`DashboardService`. They can change or disappear without warning, and Pace reports the failure
rather than a stale number when they do.

## What it will not do

Pace never shows a number a provider did not return. A quota with no reading shows `--` rather than
`0%`, a missing reset time says so rather than guessing, and stale data stays on screen labelled as
stale instead of the panel emptying out.

It also never averages across accounts. You pick an account, or Pace shows whichever quota is most
urgent. An average is the one number that can hide the limit about to stop you.

## Settings

Launch at login runs through macOS Service Management, and Pace never changes that registration
without you clicking it. Hiding account addresses swaps your email for the provider's name
everywhere, which is worth turning on before you screenshot or screen share. You can also choose
what the menu bar shows, where the rail sits and how it opens, and whether to get notifications for
thresholds, resets, and stale data. Notifications are off until you turn them on.

Usage snapshots and preferences live in `~/Library/Application Support/Pace/` as plain JSON. There
is no telemetry, no analytics, and no account system.

## Development

Requires macOS 15 or later and Xcode with Swift 6.2.

```sh
make build      # debug build
make test       # all test suites
make check      # format, lint, test, build
make install    # build Release, sign locally, install to /Applications
```

`make install` creates a self-signed certificate the first time it runs, so macOS keeps your
keychain approvals between builds. An ad-hoc signature changes identity on every build, which makes
the system prompt every time.

[CONTRIBUTING.md](CONTRIBUTING.md) covers the layout and the rules the code holds itself to.

## Unsigned builds

There is no Apple Developer Program membership behind this project, so releases are not signed with
a Developer ID and not notarized. macOS quarantines the download, and the Homebrew cask clears that
flag and applies an ad-hoc signature so the app will open. Doing it by hand means doing the same.

An unsigned build carries no cryptographic proof of who produced it. If that matters to you, build
from source.

## License

[MIT](LICENSE)
