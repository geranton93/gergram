# gergram implementation plan

**Goal.** Ship a native macOS fork with its own app identity and documented differences from the official Telegram for macOS client.

**Base.** Use [TelegramMessenger/telegram-macos](https://github.com/TelegramMessenger/telegram-macos) as the GitHub fork parent and the local `upstream` remote. The starting upstream revision is `ec221d8560ca693cb921b4e8c576da9b87dff9ef`. Keep `origin` for the independently owned GitHub fork.

**Architecture.** Extend the existing Swift packages and AppKit/TGUIKit views. Keep account data in existing scoped storage, cross-package navigation in existing hooks, and protocol changes in the pinned shared-core patch when required. Use the internal feature audit for behavior, source evidence, and acceptance cases.

## Build and repository

- [x] Confirm the official upstream revision and local Git ancestry.
- [x] Write an English project description with a direct upstream link, source license, and explicit development status.
- [ ] Confirm GitHub's fork parent metadata and set the verified fork as `origin`.
- [ ] Place the checkout at the intended project location and retain the previous checkout as a backup during replacement.
- [ ] Initialize recursive gitlinks, apply the documented Xcode 27 compatibility changes, build native frameworks and generated API sources, and build the Debug workspace scheme.
- [x] Add separate app and extension identities, local build configuration, a fork-owned icon, independent updater settings, and isolated account-container selection.
- [ ] Launch alongside the upstream client and verify both installations.

## Feature delivery

| Sequence | Audit work items | Entry point and evidence |
| --- | --- | --- |
| 1. Settings and identity | B01–B03, A01 | Use SettingsUI and existing settings storage. Verify fresh configuration and migration, then display and copy the selected format in user, group, and channel profiles. |
| 2. Folders and local visibility | A02–A09 | Wire existing folder and history views to account-scoped preferences. Verify navigation, hidden content, unread counts, and server state with two accounts and restart fixtures. |
| 3. Screenshots and streaming privacy | A10–A13 | Use the existing message selection path and window-capture mechanism. Verify image export and record observed capture behavior per macOS version and capture method. |
| 4. Local message archive | A14–A17 | Establish storage, retention, and deletion before capturing ordinary delete and edit events. Verify account, chat and topic scope, restart, ordering, and migration. |
| 5. Chat and profile tools | A18–A21, C14–C18, C21–C22, C25, C34–C36, C38–C41 | Reuse read, search, moderation, composer, profile, and menu paths. Verify native equivalents early and implement the deltas. |
| 6. Presentation and navigation | C01–C13, C19–C20, C23–C24, C42–C44 | Extend native preferences, menus, gestures, player behavior and local presentation. Verify default behavior, accessibility, and support across chat types. |
| 7. Media and services | C26–C33, C37, C45 | Verify translation and speech consent, on-device transcription, model integrity, media transfer, cancellation and native silent/scheduled sending. |
| 8. Connected release decisions | R01–R12 | Record the behavior, actual server effects and applicable API or integration boundary for each item. Verify local behavior with synthetic fixtures before a connected release. |

Independent changes can proceed in parallel. Integrate each change through its normal user entry point and update the public feature list when the corresponding code is present. Keep build, launch and functional verification status explicit.

## Implementation log

The first development changes are source-complete within the scopes below. Each row still needs its integrated app fixture.

| Audit item | Code present | Remaining verification or scope |
| --- | --- | --- |
| B01 | Separate app, share and widget identities, local API/team settings, an original icon, and independent updater configuration. | Resolve the pinned dependencies, sign and launch with the intended team and app group. |
| A01 | Native profile ID preference with Bot API formatting and migration of the existing visibility behavior. | Exercise the Settings control and clipboard output in user, group and channel profiles. |
| A02–A03 | Local folder visibility, visible-folder reordering, All Chats control and independent badge setting. | Verify sidebar and tab navigation, keyboard fallback and account switching in the application. |
| A04 | Session-local message and album hiding with restore from the chat menu. | Exercise unloaded history, replies, topics, search and account switching. |
| A05 | Optional transcript filtering for blocked incoming sources, with per-chat reveal. | Verify incoming and forwarded messages and complete the remaining activity, seen-list and avatar surfaces. |
| A10 | Initial Message Shot for ordinary text and media placeholders, with PNG copy and save actions. | Verify clipboard and file export in the running app. Media thumbnails, rich messages and A11 layout controls remain planned. |
| A12–A13 | Persistent Streamer Mode, app and status menus, window exclusion requests and suppression of new notifications. | Exercise each supported capture method and existing notification state on macOS. |
| C05, C12–C13 | Message timestamp seconds, Similar Channels controls and optional suppression of remote peer discovery. | Service/reaction timestamps and story visibility remain planned. Verify live settings updates. |
| C21 | Inline callback display and copy with binary-safe representation. | Exercise a real inline keyboard and confirm that inspecting a payload leaves the bot action inactive. |
| C34, C42 | Server-provided registration month/year in profiles and a compact unread divider. | Verify profile and history presentation. Join-date and optional lookup paths remain planned. |

The CaptureExclusion and ApiCredentials packages compiled, the release verification fixtures passed, and the changed Swift sources parsed. Focused standalone fixtures exercised ID and timestamp formatting, folder preferences, capture state, PNG rendering and its limits, and binary callback data. The SidebarUI and PeerInfoUI package tests could not resolve the pinned SSignalKit dependency. Git could not reach GitHub to initialize the recursive submodules. The integrated workspace build exited before compilation.

## Verification

- Check a fresh install and an existing settings store. Exercise account switches, app restart, and defaults with every new persisted control.
- Compare user, group, channel and forum workflows. Include permissions, cancellation and disabled-feature behavior where applicable.
- Confirm read or send controls at all relevant entry points before assuming a chat-view hook covers the engine. Use disposable accounts and synthetic fixtures.
- Run package checks where they cover the change and `xcodebuild -workspace Telegram-Mac.xcworkspace -scheme Telegram -configuration Debug build` for integrated verification. Record the command and result in the implementation log.
- Verify GitHub fork parent metadata separately from local Git ancestry. Keep source notices and keep development credentials out of Git.
