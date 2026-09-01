#!/usr/bin/env bash

# Build the Release application and install it into a local applications folder.
#
# The installed bundle is signed with a local self-signed identity so macOS sees
# the same code identity across rebuilds.
#
# This matters for the keychain. A signed bundle's designated requirement is
# derived from its identifier and certificate, so it is stable when the binary
# changes. An ad-hoc signature's designated requirement is the binary's own
# CDHash, so every rebuild is a different application as far as macOS is
# concerned, and every stored "Always Allow" decision stops matching. Signing
# the same way each time is what lets a credential be approved once.
#
# Service Management login items and UserNotifications authorization depend on
# the same stability.
#
# This is a local development install. It is not notarized and it is not a
# distribution artifact.

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 APP_PATH DESTINATION_DIR" >&2
    exit 64
fi

app_path=$1
destination_dir=$2
signing_identity=${PACE_SIGNING_IDENTITY:-Pace Local Signing}
app_name=$(basename "$app_path")
installed_path="$destination_dir/$app_name"

if [[ ! -d $app_path ]]; then
    echo "missing built application bundle: $app_path" >&2
    exit 1
fi

if [[ ! -x "$app_path/Contents/MacOS/Pace" ]]; then
    echo "missing application executable: $app_path/Contents/MacOS/Pace" >&2
    exit 1
fi

if [[ -z $destination_dir || $destination_dir == / ]]; then
    echo "unsafe install destination: '$destination_dir'" >&2
    exit 64
fi

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")

# Refuse to replace anything that is not a Pace bundle with this identifier.
if [[ -e $installed_path ]]; then
    if [[ ! -d $installed_path ]]; then
        echo "install destination exists and is not a bundle: $installed_path" >&2
        exit 1
    fi
    installed_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
        "$installed_path/Contents/Info.plist" 2>/dev/null || true)
    if [[ $installed_bundle_id != "$bundle_id" ]]; then
        echo "refusing to replace '$installed_path' with bundle id '$installed_bundle_id'" >&2
        exit 1
    fi
fi

# Quit a running copy so the replacement does not race a live process.
if pgrep -x Pace >/dev/null 2>&1; then
    echo "quitting running Pace"
    osascript -e 'tell application id "'"$bundle_id"'" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do
        pgrep -x Pace >/dev/null 2>&1 || break
        sleep 0.25
    done
    if pgrep -x Pace >/dev/null 2>&1; then
        pkill -x Pace || true
        sleep 0.5
    fi
fi

mkdir -p "$destination_dir"

staged_path=$(mktemp -d "${TMPDIR:-/tmp}/pace-install.XXXXXX")
trap 'rm -rf "$staged_path"' EXIT
ditto "$app_path" "$staged_path/$app_name"

# Sign with the local identity, falling back to ad-hoc so a machine without the
# identity still gets a working install. The fallback re-prompts for keychain
# access after every build, so it reports that rather than failing silently.
if security find-identity -v -p codesigning \
    | grep -Fq "$signing_identity"; then
    codesign --force --deep --options runtime --timestamp=none \
        --sign "$signing_identity" "$staged_path/$app_name"
    signature_kind=$signing_identity
else
    echo "note: '$signing_identity' not found; signing ad-hoc." >&2
    echo "note: keychain approvals will not survive a rebuild." >&2
    echo "note: run Scripts/create-signing-identity.sh to fix this." >&2
    codesign --force --deep --sign - --timestamp=none "$staged_path/$app_name"
    signature_kind=adhoc
fi
codesign --verify --deep --strict "$staged_path/$app_name"

rm -rf "$installed_path"
ditto "$staged_path/$app_name" "$installed_path"

# Refresh Launch Services so the new copy is the one macOS resolves.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$installed_path" >/dev/null 2>&1 || true

printf 'installed=%s\n' "$installed_path"
printf 'bundle_id=%s\n' "$bundle_id"
printf 'version=%s\n' "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$installed_path/Contents/Info.plist")"
printf 'signature=%s\n' "$signature_kind"
