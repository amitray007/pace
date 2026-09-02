#!/usr/bin/env bash

# Build the Release application and install it into a local applications folder.
#
# The installed bundle is signed with a local self-signed identity so macOS sees
# the same code identity across rebuilds.
#
# A signed bundle's designated requirement is derived from its identifier and
# certificate, so it is stable when the binary changes, while an ad-hoc
# signature's designated requirement is the binary's own CDHash. Service
# Management login items and UserNotifications authorization depend on that
# stability, and so does the application list on a keychain item.
#
# It does not make keychain approvals survive a rebuild. securityd also keeps a
# partition list on each item, and a certificate that Apple did not issue is
# classified there by CDHash, so every build still needs one approval per
# credential. Pace never raises that dialog on its own; the user grants access
# from the account's "Allow keychain access" action, so the launch check below
# does not prompt.
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
# identity still gets a working install. The fallback changes the bundle's
# designated requirement on every build, so it reports that rather than
# failing silently.
if security find-identity -v -p codesigning \
    | grep -Fq "$signing_identity"; then
    # No hardened runtime here. It enforces library validation, which requires
    # the process and its embedded frameworks to share a Team ID. A self-signed
    # certificate has none, so the frameworks fail to load. The hardened runtime
    # is a notarization requirement, and this is a local install.
    codesign --force --deep --timestamp=none \
        --sign "$signing_identity" "$staged_path/$app_name"
    signature_kind=$signing_identity
else
    echo "note: '$signing_identity' not found; signing ad-hoc." >&2
    echo "note: the code identity will change on every rebuild." >&2
    echo "note: run Scripts/create-signing-identity.sh to fix this." >&2
    codesign --force --deep --sign - --timestamp=none "$staged_path/$app_name"
    signature_kind=adhoc
fi
codesign --verify --deep --strict "$staged_path/$app_name"

rm -rf "$installed_path"
ditto "$staged_path/$app_name" "$installed_path"

# ditto preserves the source bundle's directory timestamp. Mark the installed
# bundle as changed so launchers invalidate any icon cached for the same bundle
# identifier and version before Launch Services registers the replacement.
touch "$installed_path"

# Refresh Launch Services so the new copy is the one macOS resolves.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$installed_path" >/dev/null 2>&1 || true

# A bundle can sign and verify cleanly and still fail to launch: the hardened
# runtime enforces library validation, which a self-signed identity cannot
# satisfy, and dyld only reports that when the process starts. Launch the
# installed copy once so a broken install fails here rather than silently.
launch_log=$(mktemp "${TMPDIR:-/tmp}/pace-launch.XXXXXX")
"$installed_path/Contents/MacOS/Pace" >"$launch_log" 2>&1 &
launch_pid=$!
sleep 3
if kill -0 "$launch_pid" 2>/dev/null; then
    kill "$launch_pid" 2>/dev/null || true
    wait "$launch_pid" 2>/dev/null || true
    launch_state=ok
else
    wait "$launch_pid" 2>/dev/null || true
    echo "installed application exited immediately:" >&2
    sed 's/^/  /' "$launch_log" >&2
    rm -f "$launch_log"
    exit 1
fi
rm -f "$launch_log"

printf 'installed=%s\n' "$installed_path"
printf 'bundle_id=%s\n' "$bundle_id"
printf 'version=%s\n' "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$installed_path/Contents/Info.plist")"
printf 'signature=%s\n' "$signature_kind"
printf 'launch=%s\n' "$launch_state"
