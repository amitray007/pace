# Cursor usage feasibility spike

This executable proves that Pace can read Cursor plan usage without a running Cursor application,
Cursor Agent process, or coding harness. It is not linked into the Pace application.

## Flow

1. Resolve the default Cursor Agent profile or one or more explicit isolated profile homes.
2. Read only the selected profile's access token. The default profile uses Cursor Agent's Keychain
   service without allowing an authentication prompt. An isolated profile uses
   `$HOME/.cursor/auth.json` and must be private to the current user.
3. Match the access-token JWT subject to `authInfo.authId` in that profile's
   `.cursor/cli-config.json`.
4. Call Cursor's `DashboardService/GetMe` and require the server authentication ID to match the
   same binding. Compare the returned user and team with the registered identity when supplied.
5. Only after identity verification, call `DashboardService/GetCurrentPeriodUsage`.
6. Map the returned total, Cursor-model, other-model, and extra-usage buckets. Read plan information
   from `GetPlanInfo` as an optional enhancement.

The command prints only a short identity fingerprint, plan, credential-source kind, and normalized
metrics. It never prints tokens, email addresses, team names, or raw identifiers. It does not
refresh, rotate, or write credentials.

```sh
swift run cursor-usage-spike
swift run cursor-usage-spike --profile-home /absolute/path/to/cursor-profile-home
swift run cursor-usage-spike \
  --profile-home /absolute/path/to/personal-home \
  --profile-home /absolute/path/to/work-home
```

Profiles are checked sequentially. Two profiles that resolve to the same server user and team fail
as a duplicate instead of creating two Pace accounts.

## Set up an isolated account

Cursor Agent owns the credentials. Create a dedicated profile home and run its normal browser login
with the source-verified file credential store:

```sh
cursor_profile="$HOME/Library/Application Support/Pace/CursorProfiles/work"
mkdir -p "$cursor_profile"
env \
  HOME="$cursor_profile" \
  CURSOR_CONFIG_DIR="$cursor_profile/.cursor" \
  CURSOR_DATA_DIR="$cursor_profile/.cursor" \
  AGENT_CLI_CREDENTIAL_STORE=file \
  cursor-agent login
```

Use the same environment for `cursor-agent status` or `cursor-agent logout`. Removing an account
from Pace removes only Pace's non-secret profile binding. Deleting the provider-owned profile or
logging it out must remain a separate, explicit action.

`CURSOR_CONFIG_DIR`, `CURSOR_DATA_DIR`, and `AGENT_CLI_CREDENTIAL_STORE=file` are current
source-verified Cursor Agent behavior, not a documented compatibility promise. The installed
2026.07.01-41b2de7 bundle stores file credentials at `$HOME/.cursor/auth.json` with mode `0600`.

## Evidence recorded on 2026-08-31

- Cursor Agent 2026.07.01-41b2de7 reported one authenticated account.
- Direct `DashboardService/GetMe`, `GetCurrentPeriodUsage`, and `GetPlanInfo` calls succeeded.
- The redacted default-profile spike read its access token from Keychain and returned a Team plan
  with Total Usage, Cursor Models, and Other Models buckets.
- A fresh profile home reported signed out instead of inheriting the default Keychain login.
- Sixteen deterministic spike tests passed. They cover environment isolation, credential and
  authentication-ID binding, remote identity ordering, duplicate accounts, dynamic percentage and
  amount metrics, optional plan failure, malformed data, and rate limiting.

The endpoint and response mapping follows OpenUsage commit
`05c40a1dc50a16ecdc7b55d2e4fadf26827b4f61`. OpenUsage is MIT licensed and had 3,960 GitHub stars
when reviewed. Cursor's public documentation describes account usage and CLI login but does not
publish this personal usage API, so Pace must keep the adapter isolated and locally disableable.

## Not yet proven

- Two distinct live Cursor accounts in separate file profiles.
- Login, logout, reauthentication, and access-token rotation for a Pace-managed profile.
- Team and Enterprise response variants beyond the live Team percentage response.
- Request-based Enterprise usage and optional credit, prepaid-balance, Grok Bot, and CSV endpoints.
- Long-running polling behavior and actual 429 cooldown recovery.

Do not promote this code into `PaceCore` or the application until these checks pass and the
simulated-data visual shell is approved.
