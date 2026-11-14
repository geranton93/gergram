# gergram development

gergram is an unofficial native macOS client based on [TelegramMessenger/telegram-macos](https://github.com/TelegramMessenger/telegram-macos). The initial upstream baseline is [`ec221d8560ca693cb921b4e8c576da9b87dff9ef`](https://github.com/TelegramMessenger/telegram-macos/commit/ec221d8560ca693cb921b4e8c576da9b87dff9ef).

## Repository workflow

Use `upstream` for the official repository. Use `origin` for the writable fork only after checking which repository it resolves to. An older gergram checkout may have different remotes and a separate commit history. Keep its history available during migration and carry forward project changes explicitly.

```sh
git remote -v
git status --short --branch
git merge-base --is-ancestor ec221d8560ca693cb921b4e8c576da9b87dff9ef HEAD
```

The ancestry check should succeed in a Git checkout based on the pinned revision. If `git rev-parse --is-shallow-repository` reports `true`, run `git fetch --unshallow upstream` before reviewing earlier upstream history. A GitHub source archive contains files only and needs a proper checkout before it can initialize pinned submodules or run the Git-aware build scripts.

Fetch from `upstream` and review the incoming changes before updating the development branch. Work on a feature branch and keep upstream synchronization separate from feature commits. Check new submodule revisions, shared-core patches, and native builds when updating the base.

```sh
git fetch upstream
git log --oneline --left-right HEAD...upstream/master
```

## Settings links

Links open a native settings screen for the account selected by the app. Change a preference from its control after the screen opens.

| General setting | Link path after `gergram://settings/` |
| --- | --- |
| Message Context Menu | `general/message-context-menu` |
| On-Device Transcription Language | `general/on-device-transcription-language` |
| Filter Zalgo Text in Messages | `general/filter-zalgo-text` |
| Mini App Window Size | `general/mini-app-window-size` |
| Hide Stories in Chat List | `general/hide-chat-list-stories` |
| Hide Stories in Profiles | `general/hide-profile-stories` |
| Channel Bottom Action | `general/channel-bottom-action` |
| Send Without Sound by Default | `general/send-without-sound` |

Appearance supports `appearance/message-bubble-corners`, `appearance/avatar-corners` and `appearance/edited-message-label`. Privacy and Security supports `privacy/locally-hidden-senders`, `privacy/message-filters` and `privacy/local-message-archive`.

## Prepare a checkout

Use full Xcode, Homebrew, and Rust via rustup. Upstream uses Xcode 26. The current development machine was identified as arm64 with Xcode 27.0 and Swift 6.4, so use the local Xcode 27 steps below on that toolchain. On Apple Silicon, upstream setup also checks for Rosetta 2 to run the x86_64 `tde2e` code generator.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
xcrun swift --version
brew --version
rustup --version
git submodule sync --recursive
git submodule update --init --recursive
git submodule status --recursive
```

Set `DEVELOPER_DIR` to the full Xcode installation in use. If a recursive submodule fetch fails on an SSH URL and you use HTTPS, retry with command-scoped URL rewrites. A leading `-`, `+`, or `U` in `git submodule status --recursive` marks an uninitialized submodule, a checkout at another revision, or a conflict, respectively.

```sh
git -c url.https://github.com/.insteadOf=git@github.com: \
    -c url.https://gitlab.com/.insteadOf=git@gitlab.com: \
    submodule update --init --recursive
```

## Configure the fork identity

Copy the build configuration template to the ignored local file.

```sh
cp -n Local.xcconfig.example Local.xcconfig
```

- Obtain the fork's API ID and hash at [my.telegram.org](https://my.telegram.org). Set `GERGRAM_API_ID` and `GERGRAM_API_HASH` in `Local.xcconfig`. Keep credentials out of committed files and build logs. [Telegram API application setup](https://core.telegram.org/api/obtaining_api_id)
- Set `GERGRAM_TEAM_ID` to your Apple development team. The default application identity is `org.gergram.macos`. Provision signing and app-group capabilities for the application and share extension, then verify the fork opens its own container before logging in.
- The fork provides its own display name and icon. Update feeds and crash reporting require fork-owned configuration. Configure signing, notarization, and signed update metadata before distributing a build. [Upstream build and fork instructions](../INSTALL.md)

## Build the app

Run the setup script after initializing the recursive submodules. It prepares Homebrew dependencies and applies the clang compatibility adjustment to tg_owt. For Xcode 27, apply the compatibility changes after setup and before compiling native frameworks. They raise the local deployment targets and adjust Swift and Metal build settings. Check the Metal component and download it if Xcode reports it missing.

```sh
bash scripts/setup_build_env.sh

# Xcode 27 only
bash scripts/xcode27.sh apply
xcodebuild -showComponent MetalToolchain
# If missing: xcodebuild -downloadComponent MetalToolchain

CMAKE_POLICY_VERSION_MINIMUM=3.5 bash scripts/configure_frameworks.sh
xcodebuild -workspace Telegram-Mac.xcworkspace -scheme Telegram -configuration Debug build
```

Open `Telegram-Mac.xcworkspace` in Xcode for interactive debugging. The `Telegram` scheme runs the main app, and `TelegramShare` targets the share extension. The workspace also links projects required by the app. Native framework preparation generates API and shared-core sources before Xcode resolves the local Swift packages.

Xcode 27 compatibility edits are local. Run `bash scripts/xcode27.sh revert` before staging any affected files. Framework preparation applies the Telegram-iOS patch groups for compatibility and fork features. With native frameworks already available, `sh scripts/prepare-telegram-ios.sh` applies any pending group. Use its `--reverse` option before moving the Telegram-iOS checkout to a different revision. [Xcode 27 compatibility](../XCODE27.md) · [Upstream build details](../INSTALL.md)

The FlatBuffers compiler must match the pinned Swift runtime. Framework preparation builds and caches version 24.12.23 from the verified upstream revision in the checkout's ignored `.build` directory when needed. To prepare it offline, run `bash scripts/build-flatc.sh /path/to/flatbuffers` with a local Git checkout at the same commit. A build host with its own trusted compiler can set `GERGRAM_FLATC` to the absolute path. The generator rejects other versions and quarantined tools before running schema generation. [FlatBuffers CMake documentation](https://flatbuffers.dev/building/)

### Check Xcode workspace recognition

Run these checks from the repository in the macOS terminal or build runner you intend to use.

```sh
xcodebuild -checkFirstLaunchStatus
xmllint --noout Telegram-Mac.xcworkspace/contents.xcworkspacedata
xcodebuild -list -workspace Telegram-Mac.xcworkspace
git submodule status --recursive
xcrun --sdk macosx metal --version
```

A valid workspace can fail with exit 66 when the command's environment cannot query the Launch Services document type. In the managed terminal used for this project, the same Xcode 27.0 binary rejected a fresh one-project workspace and an Apple template workspace. It listed the minimal project directly. The filesystem probe read the workspace XML successfully and returned `kLSDataUnavailableErr` for the workspace content type. Run the workspace check in a regular macOS terminal or a macOS build runner with these system services available. [Apple Launch Services error reference](https://developer.apple.com/documentation/coreservices/3074489-anonymous/klsdataunavailableerr) · [Codex issue with the same workspace error](https://github.com/openai/codex/issues/10390)

An error writing `ManifestLoading` or `org.swift.swiftpm/manifests` occurs during package resolution. For diagnosis of the project entry point in a managed terminal, route Foundation, SwiftPM and Clang caches to a temporary directory. The local package manifests can run with Xcode's inner manifest sandbox disabled when the outer environment already confines the process.

```sh
probe=$(mktemp -d)
mkdir -p "$probe/user/Library/Caches" "$probe/modules"
CFFIXED_USER_HOME="$probe/user" \
SWIFTPM_MODULECACHE_OVERRIDE="$probe/modules" \
CLANG_MODULE_CACHE_PATH="$probe/modules" \
xcodebuild -project Telegram.xcodeproj -scheme Telegram -resolvePackageDependencies \
    -IDEPackageSupportDisableManifestSandbox=YES
```

This command reaches dependency resolution in the managed terminal. A missing `SSignalKit` directory then indicates that the pinned Telegram-iOS checkout is still missing. The workspace check remains the integrated build gate. Metal is an optional Xcode component installed separately from the SDK. [Apple Metal Toolchain installation](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)

## Where features belong

| Area | Entry point |
| --- | --- |
| App startup and integration | `Telegram-Mac/app/`, `Telegram-Mac/account/`, and `Telegram-Mac/packages-integration/hooks/` |
| Settings, chat, and chat list UI | `packages/SettingsUI/`, `packages/ChatUI/`, and `packages/ChatListUI/` |
| Native UI and preferences | AppKit-based `packages/TGUIKit/` and `packages/InAppSettings/` |
| Protocol and persistence | `submodules/telegram-ios/submodules/TelegramCore/` and `submodules/telegram-ios/submodules/Postbox/` |
| Native libraries | `core-xprojects/` and pinned dependencies in `submodules/` |

Implement feature behavior in the owning Swift package. Follow the existing `AccountContextProtocol` and hook patterns for app-only dependencies and use `FeatureNavigationHooks` for navigation between features. Keep changes to shared TelegramCore and Postbox focused on behavior that belongs in those layers. Record the macOS integration point and acceptance checks in the implementation plan. [Implementation plan](development-plan.md)

## Verify changes

Start with the owning package or relevant upstream checks, then build the normal workspace entry point. Run the following only when their scope applies. The wallet package requires its generated framework from native build preparation.

```sh
swift test --package-path packages/WalletEngine
python3 tools/tests/telegram-api-generation/test_generation.py
python3 tools/tests/no-paid-messages-token/run.py
python3 tools/tests/read-through/run.py
python3 -m unittest discover -s buildbox -p 'test_verify_no_labs.py' -v
git diff --check
```

For user-facing changes, verify the workflow in the signed fork with a dedicated test account. Record the Xcode version, relevant deployment target, exact commands, and observed results. Package tests and a successful workspace build cover different things from signing, launch, login, and the feature workflow.
