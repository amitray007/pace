#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_directory="$repository_root/.local/references/source"

mkdir -p "$source_directory"

fetch() {
    output_path=$1
    expected_sha256=$2
    url=$3

    if [ ! -f "$output_path" ]; then
        temporary_path="${output_path}.download"
        trap 'rm -f "$temporary_path"' EXIT HUP INT TERM
        curl --fail --location --retry 3 --silent --show-error \
            --output "$temporary_path" "$url"
        mv "$temporary_path" "$output_path"
        trap - EXIT HUP INT TERM
    fi

    actual_sha256=$(shasum -a 256 "$output_path" | awk '{ print $1 }')
    if [ "$actual_sha256" != "$expected_sha256" ]; then
        echo "Reference hash mismatch: $output_path" >&2
        echo "Expected $expected_sha256, received $actual_sha256" >&2
        exit 1
    fi
}

fetch \
    "$source_directory/side-notch-primary-2000.jpg" \
    "f971ffee7c34d130bdc793c642e0e39e32ea363d54fe2b2a4905f2bbb133c899" \
    "https://pbs.twimg.com/media/HQ4gtfXa0AAOVHK.jpg?name=orig"

fetch \
    "$source_directory/side-notch-primary.mp4" \
    "58252dae5269a40ab3ffea2b1fc83f96db8938adbc2814e16b61f764147bd901" \
    "https://video.twimg.com/amplify_video/2093646963967414272/vid/avc1/2380x2160/aGACQ9zkedheCLXB.mp4?tag=29"

fetch \
    "$source_directory/side-notch-settings-2000.jpg" \
    "c86cbb111ab752088c0a853beacaa014776f11c987fe511175976b42a33ddc52" \
    "https://pbs.twimg.com/media/HQ-pm-Ea0AEyuyv.jpg?name=orig"

fetch \
    "$source_directory/side-notch-settings.mp4" \
    "612b1b555bd5f76a53a4bfa387cba82cd9dfeba9f8c95fb8e8870f2f96d7c283" \
    "https://video.twimg.com/amplify_video/2094079037639680001/vid/avc1/1552x1552/S-vrQamKoX9aWzVu.mp4?tag=29"

fetch \
    "$source_directory/menu-panel-dhh.jpg" \
    "d8212531cda6687dbdb8fa41b91156449a73bb4be4963e6a1eed91e7c0f8f9a1" \
    "https://pbs.twimg.com/media/HQEw8g2WAAAhDts.jpg?name=orig"

echo "Reference media is ready in $source_directory"
