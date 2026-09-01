#!/usr/bin/env bash

# Capture the built application's surfaces into an output directory.
#
# Each state runs a separate short-lived instance with a deterministic preview
# state, waits for the surface to settle, records the Pace window bounds, and
# captures a screenshot cropped to those bounds with a small margin. This gives
# repeatable review frames without driving the pointer.

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "usage: $0 APP_PATH OUTPUT_DIR [STATE ...]" >&2
    exit 64
fi

app_path=$1
output_dir=$2
shift 2
states=("$@")
if [[ ${#states[@]} -eq 0 ]]; then
    states=(mini rail claude codex cursor grok githubCopilot)
fi

script_dir=$(cd "$(dirname "$0")" && pwd -P)
executable="$app_path/Contents/MacOS/Pace"

if [[ ! -x $executable ]]; then
    echo "missing application executable: $executable" >&2
    exit 1
fi

if [[ -z $output_dir || $output_dir == / ]]; then
    echo "unsafe capture output directory: '$output_dir'" >&2
    exit 64
fi

edge=${PACE_CAPTURE_EDGE:-right}
settle=${PACE_CAPTURE_SETTLE:-2.0}
margin=${PACE_CAPTURE_MARGIN:-24}
scenario=${PACE_CAPTURE_SCENARIO:-}

mkdir -p "$output_dir"

bounds_tool="${TMPDIR:-/tmp}/pace-window-bounds"
if [[ ! -x $bounds_tool || $script_dir/pace-window-bounds.swift -nt $bounds_tool ]]; then
    swiftc -O "$script_dir/pace-window-bounds.swift" -o "$bounds_tool"
fi

for state in "${states[@]}"; do
    # A previous instance must be gone before the next one launches.
    pkill -x Pace >/dev/null 2>&1 || true
    sleep 0.5

    env_args=(
        PACE_REFERENCE_PREVIEW="$state"
        PACE_REFERENCE_EDGE="$edge"
    )
    if [[ -n $scenario ]]; then
        env_args+=(PACE_SIMULATED_STATE="$scenario")
    fi

    env "${env_args[@]}" "$executable" >/dev/null 2>&1 &
    instance_pid=$!
    sleep "$settle"

    if bounds=$("$bounds_tool"); then
        screencapture -x -o "$output_dir/$state-screen.png"
        read -r x y width height scale <<<"$bounds"
        /usr/bin/env python3 "$script_dir/crop-region.py" \
            "$output_dir/$state-screen.png" "$output_dir/$state.png" \
            "$x" "$y" "$width" "$height" "$margin" "$scale"
        rm -f "$output_dir/$state-screen.png"
    else
        echo "no Pace window captured for state '$state'" >&2
    fi

    kill "$instance_pid" >/dev/null 2>&1 || true
    wait "$instance_pid" 2>/dev/null || true
done

pkill -x Pace >/dev/null 2>&1 || true
printf 'captured=%s\n' "$output_dir"
