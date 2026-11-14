#!/bin/bash
set -eo pipefail

DIR=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$DIR/../.." && pwd -P)

usage() {
    echo "usage: tools/networklab/run.sh <label> <test|main> <rust|mtProtoKit> <direct|netsim-profile> [-PerfLabScenarios a,b ...]"
    echo "Set NETWORKLAB_APP to a Debug gergram app bundle or use this checkout's DerivedData build."
    echo "Use -PerfLabOutput <directory> to override the fork's app-group output directory."
}

fail() {
    echo "NetworkLab: $*" >&2
    exit 1
}

if [[ "$1" == --help ]]; then
    usage
    exit 0
fi
if [[ $# -lt 4 ]]; then
    usage >&2
    exit 1
fi

label=$1
account=$2
engine=$3
profile=$4
shift 4
case "$label" in ""|*/*|*$'\n'*|*$'\r'*) fail "Use a nonempty label without path separators or line breaks." ;; esac
case "$account" in test|main) ;; *) fail "Choose test or main as the account." ;; esac
case "$engine" in rust|mtProtoKit) ;; *) fail "Choose rust or mtProtoKit as the engine." ;; esac
[[ -n "$profile" ]] || fail "Specify a network profile."

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null
}

app=${NETWORKLAB_APP:-}
if [[ -z "$app" ]]; then
    for data in "$HOME/Library/Developer/Xcode/DerivedData"/*; do
        workspace_path=$(plist_value WorkspacePath "$data/info.plist") || continue
        case "$workspace_path" in "$ROOT"/*) ;; *) continue ;; esac
        for candidate in "$data/Build/Products/Debug"/*.app; do
            candidate_plist="$candidate/Contents/Info.plist"
            [[ -f "$candidate_plist" ]] || continue
            [[ $(plist_value SOURCE "$candidate_plist") == DEBUG ]] || continue
            [[ -n $(plist_value GergramTeamID "$candidate_plist") ]] || continue
            candidate_id=$(plist_value GergramBundleID "$candidate_plist") || continue
            [[ -n "$candidate_id" && "$candidate_id" == "$(plist_value CFBundleIdentifier "$candidate_plist")" ]] || continue
            if [[ -z "$app" || "$candidate_plist" -nt "$app/Contents/Info.plist" ]]; then
                app=$candidate
            fi
        done
    done
fi

[[ -d "$app" ]] || fail "Debug gergram app bundle missing. Set NETWORKLAB_APP to the built app."
app=$(cd "$app" && pwd -P)
plist="$app/Contents/Info.plist"
bundle_id=$(plist_value CFBundleIdentifier "$plist") || fail "Cannot read CFBundleIdentifier from $plist."
gergram_id=$(plist_value GergramBundleID "$plist") || fail "Missing GergramBundleID in $plist."
team_id=$(plist_value GergramTeamID "$plist") || fail "Missing GergramTeamID in $plist."
executable=$(plist_value CFBundleExecutable "$plist") || fail "Missing CFBundleExecutable in $plist."
case "$bundle_id" in ""|*[!a-zA-Z0-9.-]*) fail "Invalid app bundle identifier." ;; esac
case "$team_id" in ""|*[!a-zA-Z0-9]*) fail "Invalid gergram team identifier." ;; esac
case "$executable" in ""|*/*) fail "Invalid app executable name." ;; esac
[[ "$bundle_id" == "$gergram_id" && $(plist_value SOURCE "$plist") == DEBUG ]] || fail "Select a configured Debug gergram bundle."
[[ -f "$app/Contents/MacOS/$executable" && -x "$app/Contents/MacOS/$executable" ]] || fail "The executable named by $plist is missing."
if [[ $(lsappinfo find "bundleID=$bundle_id" 2>/dev/null || true) == ASN:* ]]; then
    fail "$bundle_id is already running. Quit it before launching the benchmark."
fi

output="$HOME/Library/Group Containers/$team_id.$bundle_id/debug/perf-lab"
app_args=()
while [[ $# -gt 0 ]]; do
    if [[ "$1" == -PerfLabOutput ]]; then
        [[ -n "$2" && "$2" != -PerfLab* ]] || fail "-PerfLabOutput requires a directory."
        output=$2
        shift 2
    else
        app_args+=("$1")
        shift
    fi
done

results=${NETWORKLAB_RESULTS:-$DIR/results}
mkdir -p -- "$results" "$output"
results=$(cd "$results" && pwd -P)
output=$(cd "$output" && pwd -P)
started=$(mktemp "$output/.network-lab-start.XXXXXX")
proxy_pid=

cleanup() {
    if [[ -n "$proxy_pid" ]]; then
        kill "$proxy_pid" 2>/dev/null || true
        wait "$proxy_pid" 2>/dev/null || true
    fi
    rm -f -- "$started"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

proxy_args=()
proxy_log="$results/network-$label-proxy.log"
if [[ "$profile" != direct ]]; then
    bench="$ROOT/submodules/telegram-ios/third-party/mtproto-engine/target/release/mtproto-bench"
    [[ -x "$bench" ]] || fail "Build mtproto-bench before using a network simulator profile."
    bench_args=(proxy --profile "$profile" --bind 127.0.0.1:1081)
    if [[ -n "$NETWORKLAB_OUTAGES" ]]; then
        bench_args+=(--outage-every "$NETWORKLAB_OUTAGES")
    fi
    "$bench" "${bench_args[@]}" 2> "$proxy_log" &
    proxy_pid=$!
    sleep 1
    kill -0 "$proxy_pid" 2>/dev/null || fail "The simulator exited. See $proxy_log."
    proxy_args=(-PerfLabProxy 127.0.0.1:1081)
fi

run_app() {
    open -n -W -a "$app" --args -PerfLab network -PerfLabLabel "$label" -PerfLabQuit \
        -PerfLabAccount "$account" -PerfLabNetworkEngine "$engine" \
        "${proxy_args[@]}" "${app_args[@]}" -PerfLabOutput "$output"
}

switch_marker="$output/network-lab-engine-switched"
rm -f -- "$switch_marker"
run_app
if [[ -f "$switch_marker" ]]; then
    rm -f -- "$switch_marker"
    echo "Engine switched to $engine, relaunching."
    run_app
    [[ ! -f "$switch_marker" ]] || fail "The requested engine did not activate after relaunch."
fi

matching_reports() {
    local file
    while IFS= read -r file; do
        case "${file##*/}" in "network-$label-"*.json) printf '%s\n' "$file" ;; esac
    done
}

report=$(find "$output" -maxdepth 1 -type f -newer "$started" -print | matching_reports | LC_ALL=C sort | tail -1)
[[ -n "$report" ]] || fail "No new report in $output. See network-lab-log.txt in that directory."
destination="$results/${report##*/}"
if [[ "$report" != "$destination" ]]; then
    cp -- "$report" "$destination"
fi
echo "$destination"
cat -- "$destination"
if [[ "$profile" != direct ]]; then
    tail -2 "$proxy_log"
fi
