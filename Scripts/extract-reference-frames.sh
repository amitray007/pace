#!/bin/sh

set -eu

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "ffmpeg is required to extract reference frames." >&2
    exit 1
fi

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_directory="$repository_root/.local/references/source"
frame_directory="$repository_root/.local/references/frames"

mkdir -p "$frame_directory"

extract_frame() {
    source_path=$1
    timestamp=$2
    output_path=$3

    ffmpeg -hide_banner -loglevel error -y \
        -ss "$timestamp" -i "$source_path" -frames:v 1 "$output_path"
}

primary_video="$source_directory/side-notch-primary.mp4"
settings_video="$source_directory/side-notch-settings.mp4"

if [ ! -f "$primary_video" ] || [ ! -f "$settings_video" ]; then
    echo "Run Scripts/fetch-reference-media.sh first." >&2
    exit 1
fi

extract_frame "$primary_video" 0.50 "$frame_directory/primary-mini.png"
extract_frame "$primary_video" 2.50 "$frame_directory/primary-cursor-detail.png"
extract_frame "$primary_video" 3.50 "$frame_directory/primary-claude-detail.png"
extract_frame "$primary_video" 5.50 "$frame_directory/primary-codex-detail.png"

extract_frame "$settings_video" 0.50 "$frame_directory/settings-mini.png"
extract_frame "$settings_video" 2.50 "$frame_directory/settings-cursor-detail.png"
extract_frame "$settings_video" 4.00 "$frame_directory/settings-claude-detail.png"
extract_frame "$settings_video" 8.00 "$frame_directory/settings-rail.png"
extract_frame "$settings_video" 10.00 "$frame_directory/settings-button.png"
extract_frame "$settings_video" 12.50 "$frame_directory/settings-codex-detail.png"

ffmpeg -hide_banner -loglevel error -y -i "$primary_video" \
    -vf "fps=2,scale=340:-1,tile=7x6" -frames:v 1 \
    "$frame_directory/primary-contact-sheet-500ms.jpg"
ffmpeg -hide_banner -loglevel error -y -i "$settings_video" \
    -vf "fps=2,scale=340:-1,tile=7x6" -frames:v 1 \
    "$frame_directory/settings-contact-sheet-500ms.jpg"

echo "Canonical frames are ready in $frame_directory"
