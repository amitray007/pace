# Grok usage feasibility spike

This executable proves that Pace can read Grok Build subscription usage without a running Grok
process or coding harness. It is not linked into the Pace application.

## Flow

1. Resolve the default `~/.grok` profile or one or more explicit `GROK_HOME` directories.
2. Read only that profile's owner-private `auth.json`. Accept one first-party xAI OIDC session and
   reject API keys or custom OIDC issuers. Their credentials must never be sent to xAI's public
   subscription endpoint.
3. Call the official Grok CLI proxy `GET /user?include=subscription` with the session token.
4. Compare the returned user, principal, and team with the identity registered by Pace when one is
   supplied. Do not trust the local profile label or a stale local `user_id` as account proof.
5. Only after remote identity verification, call `GET /billing?format=credits` with the canonical
   server `userId` in `x-userid`.
6. Map the returned weekly, monthly, legacy included-credit, and pay-as-you-go buckets.

The command prints only a short identity fingerprint, plan, and normalized metrics. It never prints
tokens, email addresses, names, teams, or raw identifiers. It does not refresh, rotate, or write
credentials.

```sh
swift run grok-usage-spike
swift run grok-usage-spike --grok-home "/absolute/path/to/profile"
swift run grok-usage-spike \
  --grok-home "/absolute/path/to/personal" \
  --grok-home "/absolute/path/to/work"
```

Profiles are checked sequentially. Two profiles that resolve to the same server principal and team
fail as a duplicate instead of creating two Pace accounts.

## Set up an isolated account

Grok owns the credentials and officially supports `GROK_HOME`. Create a private profile directory,
then run Grok's normal browser login:

```sh
grok_home="$HOME/Library/Application Support/Pace/GrokProfiles/work"
mkdir -p "$grok_home"
chmod 700 "$grok_home"
GROK_HOME="$grok_home" grok login
```

Use the same `GROK_HOME` for Grok's own reauthentication or logout commands. Removing an account
from Pace removes only Pace's non-secret profile binding. Deleting the provider-owned directory or
logging it out must remain a separate, explicit action.

The endpoint, header, identity, and response mapping follow xAI's official `grok-build` source at
commit `bc7f02eddd3d84085849dc19ed216f11c23b0571`. OpenUsage commit
`05c40a1dc50a16ecdc7b55d2e4fadf26827b4f61` independently confirms the billing response variants.

## Evidence recorded on 2026-08-31

- Grok 1.0.13 exposed one owner-private default OIDC profile.
- Direct `/user?include=subscription` identity verification and `/billing?format=credits` usage
  retrieval succeeded without a running Grok process.
- The redacted command returned the account plan and its current weekly bucket.
- A fresh `GROK_HOME` reported signed out instead of inheriting the default login.
- Sixteen deterministic tests passed. They cover profile and file isolation, ambiguous, API-key,
  and custom-issuer credentials, expiry, canonical identity ordering, account mismatch and
  duplication, current and legacy billing shapes, omitted protobuf zero values, malformed data,
  authentication failure, and rate limiting.

## Not yet proven

- Two distinct live Grok accounts in separate `GROK_HOME` directories.
- Login, logout, reauthentication, and token rotation for a Pace-managed profile.
- Live personal and team account variants beyond the account used for the redacted check.
- Custom enterprise Grok proxies and their provider-specific identity and billing endpoints.
- Long-running polling behavior and actual 429 cooldown recovery.

Do not promote this code into `PaceCore` or the application until these checks pass and the
simulated-data visual shell is approved.
