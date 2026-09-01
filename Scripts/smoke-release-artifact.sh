#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 ARCHIVE_PATH CHECKSUM_PATH" >&2
    exit 64
fi

archive_path=$1
checksum_path=$2
script_dir=$(cd "$(dirname "$0")" && pwd -P)

if [[ ! -f $archive_path ]]; then
    echo "missing release archive: $archive_path" >&2
    exit 1
fi
if [[ ! -f $checksum_path ]]; then
    echo "missing release checksum: $checksum_path" >&2
    exit 1
fi

archive_parent=$(cd "$(dirname "$archive_path")" && pwd -P)
checksum_parent=$(cd "$(dirname "$checksum_path")" && pwd -P)
if [[ $archive_parent != "$checksum_parent" ]]; then
    echo "release archive and checksum must share one directory" >&2
    exit 64
fi
archive_path="$archive_parent/$(basename "$archive_path")"
checksum_path="$checksum_parent/$(basename "$checksum_path")"
archive_name=$(basename "$archive_path")

checksum_line_count=$(wc -l < "$checksum_path" | tr -d '[:space:]')
expected_hash=
expected_name=
unexpected_checksum_field=
if ! read -r expected_hash expected_name unexpected_checksum_field < "$checksum_path"; then
    echo "release checksum must contain one SHA-256 entry for $archive_name" >&2
    exit 1
fi
if [[ $checksum_line_count != 1 || -n ${unexpected_checksum_field:-} ||
    ! $expected_hash =~ ^[0-9a-f]{64}$ || $expected_name != "$archive_name" ]]; then
    echo "release checksum must contain one SHA-256 entry for $archive_name" >&2
    exit 1
fi
actual_hash=$(shasum -a 256 "$archive_path" | awk '{print $1}')
if [[ $actual_hash != "$expected_hash" ]]; then
    echo "release archive checksum mismatch: $archive_path" >&2
    exit 1
fi
printf '%s: OK\n' "$archive_name"

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/pace-release-smoke.XXXXXX")
cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

/usr/bin/unzip -tq "$archive_path"
while IFS= read -r entry; do
    case "$entry" in
        Pace.app | Pace.app/*) ;;
        *)
            echo "release archive contains an unexpected path: $entry" >&2
            exit 1
            ;;
    esac
    case "/$entry/" in
        */../* | */./*)
            echo "release archive contains an unsafe path: $entry" >&2
            exit 1
            ;;
    esac
done < <(/usr/bin/unzip -Z1 "$archive_path")
/usr/bin/unzip -q "$archive_path" -d "$temporary_root/extracted"

app_bundle="$temporary_root/extracted/Pace.app"
if [[ ! -d $app_bundle ]]; then
    echo "release archive did not extract one Pace.app bundle" >&2
    exit 1
fi
app_bundle=$(realpath "$app_bundle")
if ! executable_path=$(realpath "$app_bundle/Contents/MacOS/Pace"); then
    echo "release archive is missing the Pace executable" >&2
    exit 1
fi
case "$executable_path" in
    "$app_bundle"/*) ;;
    *)
        echo "release archive contains an executable outside Pace.app" >&2
        exit 1
        ;;
esac

xcrun --sdk macosx swiftc -parse-as-library \
    "$script_dir/smoke-release-app.swift" \
    -framework AppKit \
    -o "$temporary_root/smoke-release-app"
"$temporary_root/smoke-release-app" \
    "$app_bundle" \
    "$temporary_root/state"

printf 'archive_smoke=true\n'
