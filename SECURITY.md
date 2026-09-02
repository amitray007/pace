# Security

## Reporting a vulnerability

Report security issues privately through
[GitHub Security Advisories](https://github.com/amitray007/pace/security/advisories/new), not as a
public issue.

Include what you found, how to reproduce it, and what an attacker could do with it. You will get a
first response within a week.

Pace is maintained by one person in their spare time. There is no bug bounty, and fixes for serious
issues will be prioritised over everything else but may still take time.

## What Pace touches

Understanding the threat model matters more than a list of promises, so here is what the app
actually does.

**Credentials.** Pace reads credentials that other tools have already stored on your Mac:

| Provider | Source |
| --- | --- |
| Claude | `Claude Code-credentials` in the login keychain, or a Claude Code profile directory |
| Codex | The Codex app server, launched with your `CODEX_HOME` |
| Cursor | `cursor-access-token` and `cursor-refresh-token` in the login keychain |
| Grok | `auth.json` in the Grok profile directory |
| GitHub Copilot | The `gh` CLI's own authentication |

Pace never prompts for a password, never stores a credential of its own, and never writes to a
credential another tool owns. macOS asks for your approval the first time it reads each keychain
item, and that approval is what grants access — not anything Pace does.

**Network.** Pace talks only to the providers you have connected:

- `api.anthropic.com`, `platform.claude.com`
- `api2.cursor.sh`
- `api.github.com`
- `auth.x.ai`, `cli-chat-proxy.grok.com`

There is no telemetry, no analytics, no crash reporting, and no server operated by this project.

**On disk.** `~/Library/Application Support/Pace/` holds `state.json` (usage snapshots) and
`preferences.json`. Both are plain JSON with your account identifiers and quota readings in them.
Neither contains a credential.

## Undocumented endpoints

Two providers are read through endpoints they do not publish:

- GitHub's `api.github.com/copilot_internal/user`
- Cursor's `api2.cursor.sh/aiserver.v1.DashboardService/*`

These are the same endpoints those vendors' own clients use, reached with the credential you have
already authorised on your machine. They can change or be withdrawn at any time. Pace reports the
failure rather than showing a stale number when that happens.

Pace does not read browser cookies, does not copy tokens between providers, and does not scrape web
sessions. If a future provider cannot be supported without doing one of those things, it will not
be supported.

## Unsigned releases

Releases are **not** signed with an Apple Developer ID and **not** notarized, because this project
has no Apple Developer Program membership behind it.

What that means for you:

- macOS quarantines the download. The Homebrew cask strips the quarantine flag and applies an
  ad-hoc signature so the app will open.
- There is no cryptographic proof of who built the artifact. The SHA-256 in the cask verifies the
  file has not changed since it was published, but it does not attest to who published it.
- If the release pipeline or the tap repository were compromised, an installed build could be
  replaced without a signature check catching it.
- Keychain approvals are per build. macOS records "Always Allow" for a Developer ID application
  under its team, and for anything else under the binary's own code hash. Pace never raises the
  keychain dialog on its own; you grant access from the account's "Allow keychain access" action,
  and each update asks again once per credential.

Build from source if that risk matters to you. The release workflow is in
`.github/workflows/release.yml` and builds from a tagged commit, so you can compare.

## Scope

In scope: credential handling, the provider adapters, what Pace writes to disk, and the release
pipeline.

Out of scope: vulnerabilities in the providers' own APIs or CLIs, and anything requiring an attacker
who already has code execution as your user — at that point they can read the same keychain Pace
does.
