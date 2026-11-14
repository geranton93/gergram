#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECTS=(
    Telegram.xcodeproj/project.pbxproj
    submodules/CodeSyntax/CodeSyntax/CodeSyntax.xcodeproj/project.pbxproj
    submodules/Sparkle/Sparkle.xcodeproj/project.pbxproj
    core-xprojects/OpenH264/OpenH264.xcodeproj/project.pbxproj
    core-xprojects/openssl/OpenSSLEncryption.xcodeproj/project.pbxproj
    core-xprojects/libopus/libopus.xcodeproj/project.pbxproj
    core-xprojects/libvpx/libvpx.xcodeproj/project.pbxproj
    core-xprojects/Mozjpeg/Mozjpeg.xcodeproj/project.pbxproj
    core-xprojects/libwebp/libwebp.xcodeproj/project.pbxproj
    core-xprojects/dav1d/dav1d.xcodeproj/project.pbxproj
    core-xprojects/ffmpeg/ffmpeg.xcodeproj/project.pbxproj
    core-xprojects/webrtc/webrtc.xcodeproj/project.pbxproj
    core-xprojects/tde2e/tde2e.xcodeproj/project.pbxproj
    core-xprojects/wallet-engine/WalletEngine.xcodeproj/project.pbxproj
    core-xprojects/mtproto-engine/MTProtoEngine.xcodeproj/project.pbxproj
)
TELEGRAM_CORE_MANIFEST=submodules/telegram-ios/submodules/TelegramCore/Package.swift
SHADER_MANIFESTS=(
    packages/CallVideoLayer/Package.swift
    packages/DustLayer/Package.swift
    submodules/telegram-ios/submodules/MetalEngine/Package.swift
)
SHADER_RESOURCES='(,\s*resources:\s*\[\s*\.copy\("[^"]+\.metal"\)(?:\s*,\s*\.copy\("[^"]+\.metal"\))*\s*\])'
BUILD_CONFIGURATION='^\t\t([0-9A-Fa-f]{24}) (?:/\*[^\n]*?\*/ )?= \{\n\t\t\tisa = XCBuildConfiguration;\n.*?^\t\t\};\n'
OLD_DEPLOYMENT_TARGET='(?:10|11)(?:\.\d+)*'
failed=0

usage() {
    cat >&2 <<EOF
usage: scripts/xcode27.sh apply|revert

  apply    make the local changes from XCODE27.md so the project builds with Xcode 27
  revert   undo only those changes, keeping any other edits in the same files
EOF
    exit 2
}

fail() {
    echo "$1" >&2
    failed=1
}

head_version() {
    git -C "$(dirname "$1")" show "HEAD:./$(basename "$1")"
}

update() {
    local action="$1" path="$2" file="$ROOT/$2" before
    if [[ ! -f "$file" || -L "$file" || ! -w "$file" ]]; then
        fail "missing or unwritable: $path"
        return
    fi
    before="$(shasum "$file")"
    "$action" "$path" "$file"
    if [[ "$(shasum "$file")" == "$before" ]]; then
        echo "unchanged: $path"
    else
        echo "changed:   $path"
    fi
}

stage() {
    local action="$1" path="$2" input="$ROOT/$2" output="$scratch/after/$2" original="$scratch/before/$2"
    if [[ ! -f "$input" || -L "$input" || ! -w "$input" ]]; then
        fail "missing or unwritable: $path"
        return
    fi
    mkdir -p "$(dirname "$output")" "$(dirname "$original")"
    cp "$input" "$original"
    cp "$original" "$output"
    "$action" "$path" "$output"
}

raise_deployment_target() {
    update_deployment_target apply "$1" "$2"
    if grep -qE 'MACOSX_DEPLOYMENT_TARGET[[:space:]]*=[[:space:]]*"?1[01]([.;"]|[[:space:]])' "$2"; then
        fail "unexpected layout, set 12.0 by hand: $1"
    fi
}

restore_deployment_target() {
    update_deployment_target revert "$1" "$2"
}

update_deployment_target() {
    local head
    head="$(head_version "$ROOT/$2")" || { fail "not in HEAD: $2"; return; }
    BUILD_CONFIGURATION="$BUILD_CONFIGURATION" OLD_DEPLOYMENT_TARGET="$OLD_DEPLOYMENT_TARGET" perl -e '
        my ($action, $file) = @ARGV;
        local $/;
        my $head = <STDIN>;
        my %original;
        my $oldTarget = qr/"$ENV{OLD_DEPLOYMENT_TARGET}"|$ENV{OLD_DEPLOYMENT_TARGET}/;
        while ($head =~ /$ENV{BUILD_CONFIGURATION}/gms) {
            my ($id, $entry) = ($1, $&);
            $original{$id} = $1 if $entry =~ /MACOSX_DEPLOYMENT_TARGET = ($oldTarget);/;
        }
        open my $in, "<", $file or die "$file: $!\n";
        my $text = <$in>;
        close $in;
        my $restored = $text;
        $restored =~ s{$ENV{BUILD_CONFIGURATION}}{
            my ($id, $entry) = ($1, $&);
            my $value = $original{$id};
            if ($action eq "apply" && $entry =~ /MACOSX_DEPLOYMENT_TARGET = ($oldTarget);/) {
                die "local deployment target differs from HEAD in configuration $id\n" if !defined($value) || $value ne $1;
                my $target = substr($value, 0, 1) eq q{"} ? q{"12.0"} : "12.0";
                $entry =~ s/(MACOSX_DEPLOYMENT_TARGET = )\Q$value\E;/$1$target;/;
            } elsif ($action eq "revert" && defined $value) {
                $entry =~ s/(MACOSX_DEPLOYMENT_TARGET = )(?:12\.0|"12\.0");/$1$value;/;
            }
            $entry;
        }gmse;
        exit 0 if $restored eq $text;
        open my $out, ">", $file or die "$file: $!\n";
        print $out $restored;
        close $out;
    ' "$1" "$3" <<< "$head" || fail "Could not $1 deployment target: $2"
}

relax_telegram_core_warnings() {
    perl -0pi -e '
        s/swiftSettings: \[\.unsafeFlags\(\["-warnings-as-errors"\]\)\]/swiftSettings: [\n                .unsafeFlags([\n                    "-warnings-as-errors",\n                    "-Wwarning", "ImplicitStrongCapture"\n                ])\n            ]/
            unless /ImplicitStrongCapture/;
    ' "$2"
    if ! grep -q ImplicitStrongCapture "$2"; then
        fail "unexpected layout, edit by hand: $1"
    fi
}

restore_telegram_core_warnings() {
    perl -0pi -e '
        s/swiftSettings: \[\s*\.unsafeFlags\(\[\s*"-warnings-as-errors",\s*"-Wwarning",\s*"ImplicitStrongCapture"\s*\]\)\s*\]/swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]/;
    ' "$2"
    if grep -q ImplicitStrongCapture "$2"; then
        fail "unexpected layout, restore by hand: $1"
    fi
}

remove_shader_resources() {
    SHADER_RESOURCES="$SHADER_RESOURCES" perl -0pi -e 's/$ENV{SHADER_RESOURCES}//g' "$2"
    if grep -q '\.metal")' "$2"; then
        fail "unexpected layout, edit by hand: $1"
    fi
}

restore_shader_resources() {
    local head
    grep -q '\.metal")' "$2" && return
    head="$(head_version "$2")" || { fail "not in HEAD: $1"; return; }
    SHADER_RESOURCES="$SHADER_RESOURCES" perl -e '
        my ($file) = @ARGV;
        local $/;
        my $head = <STDIN>;
        my ($anchor, $resources) = $head =~ /(path:\s*"[^"]*")$ENV{SHADER_RESOURCES}/ or exit 0;
        open my $in, "<", $file or die "$file: $!\n";
        my $text = <$in>;
        close $in;
        $text =~ s/\Q$anchor\E/$anchor$resources/ or die "cannot find $anchor in $file\n";
        open my $out, ">", $file or die "$file: $!\n";
        print $out $text;
        close $out;
    ' "$2" <<< "$head" || fail "restore by hand: $1"
}

apply() {
    local path
    scratch=$(mktemp -d)
    trap 'rm -rf "$scratch"' EXIT
    for path in "${PROJECTS[@]}"; do
        stage raise_deployment_target "$path"
    done
    stage relax_telegram_core_warnings "$TELEGRAM_CORE_MANIFEST"
    for path in "${SHADER_MANIFESTS[@]}"; do
        stage remove_shader_resources "$path"
    done
    if (( failed )); then
        return
    fi

    local paths=("${PROJECTS[@]}" "$TELEGRAM_CORE_MANIFEST" "${SHADER_MANIFESTS[@]}")
    for path in "${paths[@]}"; do
        if [[ -L "$ROOT/$path" || ! -w "$ROOT/$path" ]] || ! cmp -s "$scratch/before/$path" "$ROOT/$path"; then
            fail "changed during preparation: $path"
        fi
    done
    if (( failed )); then
        return
    fi
    for path in "${paths[@]}"; do
        if cmp -s "$scratch/before/$path" "$scratch/after/$path"; then
            echo "unchanged: $path"
        else
            cat "$scratch/after/$path" > "$ROOT/$path"
            echo "changed:   $path"
        fi
    done
    if ! xcodebuild -showComponent MetalToolchain >/dev/null 2>&1; then
        echo "Could not verify the Metal toolchain. Check with: xcodebuild -showComponent MetalToolchain" >&2
        echo "If Xcode reports no installed asset, run: xcodebuild -downloadComponent MetalToolchain" >&2
    fi
}

revert() {
    local path
    for path in "${PROJECTS[@]}"; do
        update restore_deployment_target "$path"
    done
    update restore_telegram_core_warnings "$TELEGRAM_CORE_MANIFEST"
    for path in "${SHADER_MANIFESTS[@]}"; do
        update restore_shader_resources "$path"
    done
}

case "${1:-}" in
    apply) apply ;;
    revert) revert ;;
    *) usage ;;
esac
exit "$failed"
