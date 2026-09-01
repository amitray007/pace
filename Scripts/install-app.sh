#!/usr/bin/env bash

# Build the Release application and install it into a local applications folder.
#
# The installed bundle uses an ad-hoc signature so macOS keeps a stable code
# identity across rebuilds. A stable identity is required for Service Management
# login items, UserNotifications authorization, and TCC decisions to survive a
# reinstall. This is a local development install. It is not notarized and it is
# not a distribution artifact.

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 APP_PATH DESTINATION_DIR" >&2
    exit 64
fi

app_path=$1
destination_dir=$2
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

# Ad-hoc sign so the bundle has a stable designated requirement locally.
codesign --force --deep --sign - --timestamp=none "$staged_path/$app_name"
codesign --verify --deep --strict "$staged_path/$app_name"

rm -rf "$installed_path"
ditto "$staged_path/$app_name" "$installed_path"

# Refresh Launch Services so the new copy is the one macOS resolves.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$installed_path" >/dev/null 2>&1 || true

printf 'installed=%s\n' "$installed_path"
printf 'bundle_id=%s\n' "$bundle_id"
printf 'version=%s\n' "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$installed_path/Contents/Info.plist")"
printf 'signature=adhoc\n'
