#!/bin/sh
set -eu

scripts_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"
ios="$scripts_dir/../submodules/telegram-ios"
patch="$scripts_dir/telegram-ios-macos.patch"
capture_patch="$scripts_dir/telegram-ios-local-archive-capture.patch"
maintenance_patch="$scripts_dir/telegram-ios-local-archive-maintenance.patch"
notification_patch="$scripts_dir/telegram-ios-notification-timing.patch"
read_through_patch="$scripts_dir/telegram-ios-read-through.patch"

if [ ! -f "$ios/submodules/TelegramVoip/Package.swift" ]; then
    printf 'Initialize the telegram-ios submodule before preparing the macOS build.\n' >&2
    exit 1
fi

case "$#:${1:-}" in
    0:) target_direction=forward; current_direction=reverse ;;
    1:--reverse) target_direction=reverse; current_direction=forward ;;
    *)
        printf 'Usage: %s [--reverse]\n' "$0" >&2
        exit 2
        ;;
esac

archive="submodules/Postbox/Sources/LocalMessageArchive.swift"
postbox="submodules/Postbox/Sources/Postbox.swift"

apply_group() {
    group="$1"
    direction="$2"
    shift 2
    if [ "$direction" = reverse ]; then
        set -- --reverse "$@"
    fi
    case "$group" in
        base) git -C "$ios" apply --exclude="$archive" --exclude="$postbox" "$@" "$patch" ;;
        archive) git -C "$ios" apply --include="$archive" --include="$postbox" "$@" "$patch" ;;
        capture) git -C "$ios" apply "$@" "$capture_patch" ;;
        maintenance) git -C "$ios" apply "$@" "$maintenance_patch" ;;
        notification) git -C "$ios" apply "$@" "$notification_patch" ;;
        read_through) git -C "$ios" apply "$@" "$read_through_patch" ;;
    esac
}

groups_to_apply=""
for patch_group in base archive capture maintenance notification read_through; do
    if ! apply_group "$patch_group" "$current_direction" --check 2>/dev/null; then
        apply_group "$patch_group" "$target_direction" --check
        groups_to_apply="$groups_to_apply $patch_group"
    fi
done

for patch_group in $groups_to_apply; do
    apply_group "$patch_group" "$target_direction" --whitespace=nowarn
done
