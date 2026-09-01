#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 6 ]]; then
    echo "usage: $0 APP_PATH OUTPUT_DIR BUNDLE_ID VERSION BUILD_NUMBER MINIMUM_MACOS" >&2
    exit 64
fi

app_path=$1
output_dir=$2
expected_bundle_id=$3
expected_version=$4
expected_build_number=$5
expected_minimum_macos=$6
script_dir=$(cd "$(dirname "$0")" && pwd -P)

if [[ ! -d $app_path ]]; then
    echo "missing application bundle: $app_path" >&2
    exit 1
fi

if [[ -z $output_dir || $output_dir == / ]]; then
    echo "unsafe release output directory: '$output_dir'" >&2
    exit 64
fi

app_parent=$(cd "$(dirname "$app_path")" && pwd -P)
app_path="$app_parent/$(basename "$app_path")"
current_directory=$(pwd -P)
if [[ $output_dir == /* ]]; then
    output_candidate=$output_dir
else
    output_candidate="$current_directory/$output_dir"
fi
case "$output_candidate/" in
    "$app_path"/*)
        echo "release output directory cannot be inside the application bundle" >&2
        exit 64
        ;;
esac
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd -P)
if [[ $output_dir == / ]]; then
    echo "unsafe release output directory: '$output_dir'" >&2
    exit 64
fi
case "$output_dir/" in
    "$app_path"/*)
        echo "release output directory cannot be inside the application bundle" >&2
        exit 64
        ;;
esac

bash "$script_dir/verify-release-bundle.sh" \
    "$app_path" \
    "$expected_bundle_id" \
    "$expected_version" \
    "$expected_build_number" \
    "$expected_minimum_macos"

artifact_base="Pace-${expected_version}-${expected_build_number}-macos-universal-unsigned"
archive_name="$artifact_base.zip"
checksum_name="$archive_name.sha256"
archive_path="$output_dir/$archive_name"
checksum_path="$output_dir/$checksum_name"

temporary_root=$(mktemp -d "$output_dir/.pace-release.XXXXXX")
cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

staging_root="$temporary_root/staging"
verification_root="$temporary_root/verification"
candidate_archive="$temporary_root/$archive_name"
candidate_checksum="$temporary_root/$checksum_name"
mkdir -p "$staging_root" "$verification_root"

/usr/bin/ditto "$app_path" "$staging_root/Pace.app"
/usr/bin/xattr -cr "$staging_root/Pace.app"

export LC_ALL=C
export TZ=UTC
find "$staging_root/Pace.app" -exec touch -h -t 202001010000 {} +

(
    cd "$staging_root"
    find Pace.app -print | sort | /usr/bin/zip -X -y -q "$candidate_archive" -@
)

archive_hash=$(shasum -a 256 "$candidate_archive" | awk '{print $1}')
printf '%s  %s\n' "$archive_hash" "$archive_name" > "$candidate_checksum"

(
    cd "$temporary_root"
    shasum -a 256 -c "$checksum_name"
)
/usr/bin/unzip -tq "$candidate_archive"

while IFS= read -r entry; do
    case "$entry" in
        Pace.app | Pace.app/*) ;;
        *)
            echo "archive contains an unexpected path: $entry" >&2
            exit 1
            ;;
    esac
done < <(/usr/bin/unzip -Z1 "$candidate_archive")

/usr/bin/unzip -q "$candidate_archive" -d "$verification_root"
bash "$script_dir/verify-release-bundle.sh" \
    "$verification_root/Pace.app" \
    "$expected_bundle_id" \
    "$expected_version" \
    "$expected_build_number" \
    "$expected_minimum_macos"

if [[ -e $archive_path || -e $checksum_path ]]; then
    if [[ ! -e $archive_path || ! -e $checksum_path ]]; then
        echo "existing release artifact pair is incomplete" >&2
        exit 1
    fi
    if ! cmp -s "$candidate_archive" "$archive_path"; then
        echo "existing immutable release archive differs: $archive_path" >&2
        exit 1
    fi
    if ! cmp -s "$candidate_checksum" "$checksum_path"; then
        echo "existing release checksum differs: $checksum_path" >&2
        exit 1
    fi
else
    mv "$candidate_archive" "$archive_path"
    mv "$candidate_checksum" "$checksum_path"
fi

printf 'archive=%s\n' "$archive_path"
printf 'checksum=%s\n' "$checksum_path"
printf 'sha256=%s\n' "$archive_hash"
