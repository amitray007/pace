#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "usage: $0 APP_PATH BUNDLE_ID VERSION BUILD_NUMBER MINIMUM_MACOS" >&2
    exit 64
fi

app_path=$1
expected_bundle_id=$2
expected_version=$3
expected_build_number=$4
expected_minimum_macos=$5
info_plist="$app_path/Contents/Info.plist"
executable_path="$app_path/Contents/MacOS/Pace"

if [[ ! $expected_version =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "invalid release version: $expected_version" >&2
    exit 64
fi

if [[ ! $expected_build_number =~ ^[1-9][0-9]*$ ]]; then
    echo "invalid release build number: $expected_build_number" >&2
    exit 64
fi

if [[ ! -f $info_plist ]]; then
    echo "missing application Info.plist: $info_plist" >&2
    exit 1
fi

if [[ ! -x $executable_path ]]; then
    echo "missing application executable: $executable_path" >&2
    exit 1
fi

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$info_plist"
}

require_value() {
    local key=$1
    local expected=$2
    local actual
    actual=$(plist_value "$key")
    if [[ $actual != "$expected" ]]; then
        echo "$key mismatch: expected '$expected', found '$actual'" >&2
        exit 1
    fi
}

require_value CFBundleIdentifier "$expected_bundle_id"
require_value CFBundleName Pace
require_value CFBundleExecutable Pace
require_value CFBundlePackageType APPL
require_value CFBundleShortVersionString "$expected_version"
require_value CFBundleVersion "$expected_build_number"
require_value LSApplicationCategoryType public.app-category.developer-tools
require_value LSMinimumSystemVersion "$expected_minimum_macos"
require_value LSUIElement true

if [[ -d $app_path/Contents/_CodeSignature ]]; then
    echo "unsigned preflight unexpectedly contains a code signature" >&2
    exit 1
fi

if find "$app_path" -type f \
    \( -name 'auth.json' -o -name '.credentials.json' -o -name 'credentials.json' \) \
    -print -quit | grep -q .; then
    echo "application bundle contains a provider credential file" >&2
    exit 1
fi

architectures=$(lipo -archs "$executable_path")
if [[ -z $architectures ]]; then
    echo "application executable has no reported architecture" >&2
    exit 1
fi

printf 'bundle_id=%s\n' "$expected_bundle_id"
printf 'version=%s\n' "$expected_version"
printf 'build_number=%s\n' "$expected_build_number"
printf 'minimum_macos=%s\n' "$expected_minimum_macos"
printf 'architectures=%s\n' "$architectures"
printf 'signed=false\n'
