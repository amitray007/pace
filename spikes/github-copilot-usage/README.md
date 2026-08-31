# GitHub Copilot usage feasibility spike

This executable proves that Pace can read GitHub Copilot quota data without a running editor,
Copilot CLI, or coding harness. It is not linked into the Pace application.

## Flow

1. Ask the official GitHub CLI for every healthy `github.com` account, or accept one or more
   explicit `--github-user` bindings.
2. For each binding, call `gh auth token --hostname github.com --user <login>`. Clear ambient
   `GH_TOKEN`, `GITHUB_TOKEN`, and `GH_CONFIG_DIR` values first so they cannot replace the selected
   account. The command runs with prompts disabled.
3. Verify the token through GitHub's documented `GET /user` API. During registration, require its
   login to match the selected GitHub CLI user. Store the returned durable numeric user ID as the
   future account identity.
4. Only after identity verification, call `GET /copilot_internal/user` with the client headers used
   by current OpenUsage. This quota endpoint is not a public GitHub API contract, so it remains a
   separately disableable compatibility adapter.
5. Map the returned Credits, Extra Usage, Chat, and Completions buckets. Preserve an honest empty
   personal state for organization-managed seats when GitHub returns no per-user quota.

The command prints only a short identity fingerprint, plan, and normalized metrics. It never prints
tokens, GitHub logins, names, email addresses, organizations, or raw identifiers. It does not switch
the active GitHub CLI account or write GitHub credentials.

```sh
swift run github-copilot-usage-spike
swift run github-copilot-usage-spike --github-user personal-user
swift run github-copilot-usage-spike \
  --github-user personal-user \
  --github-user work-user
```

## Add and remove accounts

GitHub CLI officially supports multiple accounts on the same host. Add each account with its normal
browser login:

```sh
gh auth login --hostname github.com
gh auth status --hostname github.com
```

Pace will discover healthy accounts but will not register one until `/user` verifies it. Removing an
account from Pace removes only Pace's non-secret login and durable-ID binding. Logging out of GitHub
CLI or revoking its OAuth authorization remains a separate, explicit user action.

The documented account selection and identity APIs come from GitHub CLI and GitHub REST. The quota
request and response mapping follow OpenUsage commit
`05c40a1dc50a16ecdc7b55d2e4fadf26827b4f61`, which was MIT licensed and had 3,960 GitHub stars when
reviewed.

## Verified on 2026-08-31

- All 14 focused tests pass, including account discovery, explicit token selection, ambient-token
  removal, official identity verification, duplicate rejection, quota variants, and rate limits.
- The installed GitHub CLI reported one healthy `github.com` account.
- A live run verified that account through `GET /user`, then returned its Individual Copilot plan,
  Credits bucket, and reset timestamp from the compatibility endpoint.
- The live run did not require a running editor, Copilot CLI, or coding harness and did not change
  the active GitHub CLI account.
- The result was inspected only through redacted normalized output. No token, login, raw ID, or raw
  response was printed or stored.

## Not yet proven

- Two distinct live GitHub.com accounts in one GitHub CLI store.
- Login, logout, reauthentication, username changes, and token rotation for a Pace binding.
- Copilot Free, Business, and Enterprise live response variants.
- Organization-wide AI-credit billing. GitHub's public billing API is administrator-only and does
  not expose a personal per-seat denominator.
- Long-running polling behavior and actual secondary-rate-limit recovery.

Do not promote this code into `PaceCore` or the application until these checks pass and the
simulated-data visual shell is approved.
