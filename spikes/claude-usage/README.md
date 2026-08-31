# Claude usage feasibility spike

This executable proves that Pace can read Claude subscription limits without a running Claude
Code process. It is not linked into the Pace application.

## Flow

1. Resolve an explicit Claude Code config directory.
2. Read that profile's OAuth credential from its isolated macOS Keychain service without allowing
   an authentication prompt. Fall back to the profile's `.credentials.json` file.
3. Require `user:profile` access.
4. Call `GET https://api.anthropic.com/api/oauth/profile` and compare the returned account and
   organization with the registered identity when one is supplied.
5. Only after identity verification, call `GET https://api.anthropic.com/api/oauth/usage`.
6. Map the legacy session and weekly fields plus every usable entry in the dynamic `limits` array.

The command prints only a short identity fingerprint, plan, credential-source kind, and normalized
metrics. It never prints tokens, email addresses, organization names, or raw identifiers. It does
not refresh, rotate, or write credentials.

```sh
swift run claude-usage-spike
swift run claude-usage-spike --profile /absolute/path/to/claude-profile
swift run claude-usage-spike \
  --profile /absolute/path/to/personal \
  --profile /absolute/path/to/work
```

Profiles are refreshed sequentially because the usage endpoint rate-limits aggressive polling.
Two directories that resolve to the same account and organization fail as a duplicate rather than
creating two Pace accounts.

## Evidence recorded on 2026-08-31

- Claude Code 2.1.251 reported one authenticated Max account.
- A fresh custom `CLAUDE_CONFIG_DIR` reported signed out instead of inheriting the default login.
- The default profile's OAuth profile and Claude CLI organization matched.
- The profile and usage requests returned HTTP 200.
- The redacted spike read its credential from Keychain and returned Session, Weekly, and Fable.
- Sixteen deterministic spike tests passed, including two-profile isolation, identity mismatch,
  stale Keychain fallback, missing scope, rate limiting, dynamic limits, and signed-out behavior.

The implementation follows the compatibility behavior in OpenUsage commit
`05c40a1dc50a16ecdc7b55d2e4fadf26827b4f61`. OpenUsage is MIT licensed and had 3,959 GitHub stars
when reviewed. Anthropic does not document the profile or usage endpoints as a public integration
API, so Pace must keep this adapter isolated and locally disableable.

## Not yet proven

- Two distinct live Claude accounts on this Mac.
- Login and reauthentication for a Pace-managed secondary config directory.
- Safe refresh-token rotation without racing Claude Code.
- Team and Enterprise account response variants.
- Long-running polling behavior and actual 429 cooldown recovery.

Do not promote this code into `PaceCore` or the application until these checks pass and the
simulated-data visual shell is approved.
