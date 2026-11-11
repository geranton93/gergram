# AyuGram feature audit and implementation backlog

Audit date: 2026-11-11. The target is the native Swift gergram client for macOS.

See the [implementation plan](development-plan.md) for changes already in the development branch and the verification still required.

| Checkout | Revision used |
| --- | --- |
| Sibling AyuGramDesktop, including this project's local fork changes | `d45ed3d102868d7f492a2f6d5f63319fbc74cbf7` |
| Official Telegram for macOS source | `ec221d8560ca693cb921b4e8c576da9b87dff9ef` |
| Native gergram bootstrap | `79f7cac61fa5e3742232728e179e81aa38f6cf9` |
| Previous gergram checkout, consulted for historical scope | `cc78980b09bec0f5dfe15030524d3255d7a2f395` |

The [parity catalog](ayugram-parity.md) records AyuGram source paths and grouped acceptance criteria. The Reference column below maps work items to that catalog or to the additional evidence at the end of this audit. This is a static source audit. All entries still need matching runtime fixtures. The native checkout's recursive submodules and macOS build are pending, so the table identifies candidate shared-core hooks where their implementations could not be inspected locally.

The audit used 99 static settings IDs across the AyuGram settings screens as a coverage check. That count includes section links and actions. Generated Ghost controls, non-settings entry points, and local fork fixes were inspected separately. Work items group closely related controls when they share an implementation and acceptance test.

- **Implement** means an AyuGram-specific workflow needs a native implementation.
- **Extend** means native code covers a meaningful part and the row names the delta.
- **Verify** means source confirms a substantial native match. Run the acceptance check before adding code.
- **Decision** means the behavior needs a live-service, third-party integration, or release decision. The feature remains visible in the parity backlog.
- **P0** establishes the app and QA baseline. **P1** delivers the defining supported behaviors. **P2** completes the remaining verified scope. **R** tracks behaviors that require a release decision.

## P0. Build and settings foundation

| ID | Work item | Action | Acceptance |
| --- | --- | --- | --- |
| B01 | Fork application identity and reproducible Debug build | Implement | Initialize pinned submodules and generated API sources, build the Telegram workspace scheme, and launch with gergram's app name, icon, API identity, bundle ID and account container. Verify the official app can remain installed alongside it. |
| B02 | Gergram settings sections and typed preferences | Extend | Add searchable entries to native Settings. Use existing settings persistence, set explicit global or per-account scope, and verify migration, defaults, reset, and two-account switching. |
| B03 | Parity fixtures and release identity | Implement | Capture paired runtime evidence from both clients. Create synthetic message/media fixtures and disposable accounts, and verify signing, updater isolation and source provenance before release. |

## P1. Core features

| ID | Work item | Reference | Action | Acceptance |
| --- | --- | --- | --- | --- |
| A01 | Copy peer ID in Telegram and Bot API formats | U05 | Extend | Reuse the existing raw ID preference and profile row. Add the alternate format and verify users, groups and channels with large IDs. |
| A02 | Show per-account visible/hidden folders, restore and reorder | F05 | Extend | Retain folder membership, unread state, notifications and shortcuts. Test folder reordering and restore with another account open. |
| A03 | Hide All Chats and folder unread counters independently | F05 | Extend | Preserve unread counts for the Dock and notifications. Check the remaining navigation path when the current folder disappears. |
| A04 | Locally hide a message or album, and reveal filtered content by chat | F02, U06, X13 | Implement | Treat the context-menu hide as session-local. Exercise albums and the Saved Messages exception. Preserve reply targets and unread counters, and test dialog-level reveal separately. |
| A05 | Hide blocked senders and blocked inline bots | F02 | Extend | Native blocked-peer state is an input. Verify messages, forwards, activity, reaction/seen lists and comments, plus reveal and unblock behavior. |
| A06 | Local user and channel shadow bans | F02 | Implement | Scope rules to the chosen account and sender. Show and restore affected messages without a Telegram account block or message deletion. |
| A07 | Global and per-chat regex filters | F01 | Implement | Cover rule order, reversed rules, shared-rule exceptions, quick add, Unicode, invalid patterns and bounded evaluation. |
| A08 | Filter import, export and settings links | F01, U11 | Implement | Validate import size and format, preview before applying, round-trip rules and preserve previous settings on failure. |
| A09 | Zalgo text filter | F03 | Implement | Match the reference on excessive combining marks and preserve expected display for supported languages and normal diacritics. |
| A10 | Message Shot from one or multiple selected messages | U09 | Implement | Reuse native message views where practical. Render text, replies, rich content, albums and media placeholders with copy/export and original selection order. |
| A11 | Message Shot appearance, options and lifetime | U09 | Implement | Persist theme and visibility options. Check dates, header decorations, reactions, reply colors, spoilers and backgrounds. Test closed windows, account switch and protected/view-once fixtures. |
| A12 | Streamer Mode across application windows | M01 | Extend | Reuse native capture exclusion with an independent mode reason. Exercise window and display sharing on supported macOS versions, viewer windows and protected content. Record actual capture coverage for each path. |
| A13 | Streamer Mode for notifications and quick toggle | M01, U04 | Extend | Add app and menu-bar control. Verify in-app behavior against AyuGram and test system notifications separately. Cover account switch, restored defaults and protection state when the mode is disabled. |
| A14 | Capture ordinary deleted messages with a local, account-scoped archive | H01, H04 | Implement | Keep account, peer, topic and message identity stable across restart and retries. Verify the optional bot-message setting. Review ordinary deleted-content behavior before connected release, including which chat types are eligible. View-once and self-destructing content is covered in R07. |
| A15 | Capture ordinary edit history | H01, H02 | Implement | Capture previously loaded eligible incoming revisions and test the reference's self, hidden and unchanged-message rules. Store versions in order, preserve entities/rich text, deduplicate deliveries, and verify account scope. |
| A16 | Browse archived messages and edits | H02 | Implement | Show archive and version history by account, peer and topic. Cover inline marks, filtering and supported reply references. Keep archive rows separate from active message state. |
| A17 | Archive cleanup, retention and schema migration | H03, H04 | Implement | Remove one item or clear by chat/topic. Verify bounded write batches, storage, paging and queries, interrupted upgrades, logout behavior, and overlapping account/peer/message IDs. |
| A18 | Read All and native per-chat/topic read controls | G05, G07 | Verify | Compare native Read All, chat and topic commands with reference server-read actions. Verify visible scope, folder effects and a multi-account fixture. |
| A19 | Message, view and reaction details | U05 | Extend | Reuse existing view/read/reaction lists. Add local inspection fields such as message ID and exact timestamps where the reference exposes them. Preserve data and permissions. |
| A20 | Jump to beginning and sender-scoped search | F06 | Extend | Compare native first-message navigation and search filters. Cover long histories, forums, hidden content and cancellations. |
| A21 | Custom context-menu visibility | U06 | Extend | Offer visible, hidden and modifier-only settings per reference item. Check keyboard and pointer access, stale selection and callbacks after a chat closes. |

## P2. Remaining feature parity

| ID | Work item | Reference | Action | Acceptance |
| --- | --- | --- | --- | --- |
| C01 | Monospace font, message width and avatar/bubble radius | U01 | Extend | Use native theme/text code. Verify the live settings preview, resize, fallback fonts, mixed scripts, one-radius behavior and light/dark themes. |
| C02 | Message tails, rounded stickers and switch animation | U01 | Extend | Compare grouped text, stickers and round video. Respect reduced motion and preserve layout with mixed rows. |
| C03 | Simplify colorful replies and quotes and hide chat-specific backgrounds | U02 | Extend | Override presentation only. Check old/new quote formats, themed backgrounds and the current user's media settings. |
| C04 | Edited/deleted labels, icon-only bottom info and deleted opacity | U02, X01 | Extend | Verify normal/edited/deleted combinations, late layout updates and visual distinction from normal rows. Requires archive rows for deleted content. |
| C05 | Spoiler visibility, reactions by chat type and exact timestamps | U02, U03 | Extend | Test message, reaction and service timestamps independently, and preserve protected-content constraints during export. |
| C06 | Channel-sender and mutual-contact badges | U03 | Extend | Reuse existing sender identity and contact data. Test self, bots, anonymous channel posters and group membership changes. |
| C07 | Hide local Premium presentation selectively | U03, M05 | Extend | Verify badge/status rendering and real subscription state independently. Server features keep their actual eligibility. |
| C08 | Icon picker and Dock badge toggle | U04 | Verify | Native picker and Dock controls exist. Compare asset choices, relaunch, default restoration and unread settings. Add independently licensed icons only for the missing choices. |
| C09 | Configurable app and menu-bar actions | U04 | Extend | Add native equivalents of configurable drawer entries, optional status-item badges and quick actions. Preserve menu, keyboard and accessibility paths. |
| C10 | Force Click preview, quick reaction and haptics | M02 | Verify | Native handlers exist. Compare gesture stage, per-media fallbacks and haptic feedback on real hardware and verify ordinary pointer/keyboard operation. |
| C11 | Use minimum notification delay and position in-app banners | M02 | Extend | Compare the minimum app delay when another client is active. Verify the top-center custom banner position and report OS-controlled notification behavior separately. |
| C12 | Collapse similar-channel recommendations and hide the profile tab | F04 | Extend | Apply independent settings to the post-join chat block and profile tab. Preserve normal navigation and server recommendation state. |
| C13 | Hide story UI and disable global search | F04 | Extend | Check story list and profile surfaces, local search, recent results and restoring visibility. Exclude the newer AyuGram search behavior outside the reference pin. |
| C14 | Channel bottom action, linked-channel navigation and quick admin actions | F06 | Extend | Verify hidden, mute and discuss behavior, missing discussion fallback, linked-channel entry and permission-aware administrative actions. |
| C15 | Bulk remove the user's messages and filtered media | F07 | Extend | Preview sender, peer/topic, date and media scope where supported. Confirm explicit selection and test cancellation, partial failures and retry safety. |
| C16 | Composer control visibility and hover preferences | U07 | Extend | Cover attach, bot commands, emoji, microphone, TTL, gifts and rich editor, plus greeting sticker and fast-share affordances. Verify supported alternative send paths. |
| C17 | Confirmation before sending stickers, GIFs, voice and round video | U07 | Extend | Cancel without a send, accept once, and test caption, forwarded, scheduled and shortcut paths. |
| C18 | Send eligible files as stickers | U07 | Extend | Compare eligibility and encoding. Reuse native composition and show normal file sending for unsupported media. |
| C19 | Recent stickers and only-added emoji/sticker packs | U08 | Extend | Compare the pinned reference limit and pack filters. Verify recents, favorites, incomplete loads and account changes. |
| C20 | GIF controls and voice/round-video seeking | U08 | Verify | Native player and seeking surfaces exist. Check gestures, progress/scrub paths, fetching, paused playback and completion. Port missing entry points only. |
| C21 | Inline-button callback inspection and copying | U05 | Implement | Show the raw payload without activating the bot button. Verify text and binary representation, and respect access to the source message. |
| C22 | Sticker and emoji pack author lookup | U05 | Extend | Reuse native pack preview and profile navigation. Cover server-supplied authors, missing data and unresolvable lookups without unsolicited third-party calls. |
| C23 | Profile music and adaptive cover presentation | U10 | Extend | Reuse the native music/profile UI where available. Test missing cover, cache, player navigation and responsive color adaptation. |
| C24 | Settings search, deep links, localization and reset | U11 | Extend | Native settings search exists. Index new entries, add validated gergram URLs, test per-entry navigation, unknown paths, reset confirmation and English fallback. |
| C25 | Peer ID and chat ID links | U11 | Extend | Compare native ID routing with the reference. Validate ID and active account, handle inaccessible chats and avoid taking over official app links without user choice. |
| C26 | Telegram translation and provider selection | M03 | Extend | Reuse native TranslateUI and provider support. Compare source/target language, single and batch behavior, cancellation and consent for external providers. |
| C27 | Social link previews and link-warning setting | M03 | Extend | Match provider previews and external-link routing, preserve origin handling, and review any change to warnings for untrusted links. |
| C28 | On-device received voice/round-video transcription | M04 | Extend | Reuse native transcription presentation and compatible Speech plumbing. Add provider choice and received-media execution, local-only capability checks, language/model settings, permission denial, cancellations and account isolation. |
| C29 | Whisper Tiny/Base/Small model lifecycle | M04 | Implement | Verify model provenance, downloads, integrity, retry, cache, removal, unsupported devices and user-selected language. Run with no implicit cloud fallback. |
| C30 | Mini-app window size and crash-reporting settings | M05 | Extend | Compare WebView resize and saved state without modifying origin controls. Exercise crash-reporting settings with sanitized fixtures and fork-owned endpoints. |
| C31 | Signed project configuration and community badges | M06 | Implement | Verify accepted, corrupt, expired and unavailable payloads, bounded parsing, cache fallback and signature verification. Use independently owned keys and URLs. |
| C32 | Supported-message re-send, repeat and forward | H06, H07 | Extend | Use native forwarding and enqueue APIs. Distinguish forward attribution from an intentional recreated send. Test captions, rich blocks, albums, topics and retry/cancellation without duplicate sends. |
| C33 | Media transfer lifecycle and streaming performance | H07, X06 | Extend | Reuse native transfer and playback. Check temporary-file cleanup, bounded buffers, simultaneous playback, seek recovery and reduced request volume with fixture measurements. |
| C34 | Profile account/registration and join-date details | X02 | Extend | Present dates the server exposes and distinguish estimated from verified dates. Treat optional external lookups as a separate integration. |
| C35 | Active Sessions official-app indicator | X03 | Verify | Native SessionsUI has a positive official-app badge and tooltip. Compare official, unofficial, current and legacy records before deciding whether to add an explicit negative state. |
| C36 | exteraGram plugin attachment metadata viewer | X04 | Implement | Treat the attachment as data. Show bounded parsed metadata and an unsupported/invalid state, and exercise malformed attachments. |
| C37 | Silent-send default and explicit scheduled sends | G06 | Extend | Reuse native silent and scheduling paths. Cover never/always policy, explicit overrides, text/media, retries and welcome-message attachments. The Ghost-specific routing is tracked under R. |
| C38 | Explicit read-until and local read convenience | G05 | Extend | Preserve distinct local and server effects, newer reads, topic scope and invalid-peer behavior. Review local-only state that affects remote receipts under R. |
| C39 | Peer data-center indicator and copyable sticker/emoji identifiers | X07 | Extend | Check data-center availability and user/group/channel cases. Expose sticker set, emoji set and individual emoji IDs in the same reachable contexts as the reference. |
| C40 | Reorder files and restore a cancelled attachment caption | X08 | Extend | Cover documents, music and image-as-file attachments. Preserve the order used for actual send. Restore the edited caption and formatting to the proper compose context on cancellation. |
| C41 | Inspect and clear bot start payload | X09 | Extend | Compare the shortened payload display and secondary-click clear action. Check long payloads and default bot start behavior. |
| C42 | Unread divider style and custom emoji preview | X10 | Extend | Match the unread pill and hold-to-preview behavior where the native presentation differs. Cover read-marker movement, picker cancellation and input accessibility. |
| C43 | Spotify handoff and permitted story-media saving | X11 | Extend | Verify local Spotify app handoff with browser fallback. Check saving for stories that permit export, and keep protected-media behavior under R08. |
| C44 | Explicit Send With Sound override | X12 | Extend | Show an override when the default is silent. Verify the chosen delivery behavior for text and media with one send per action. |
| C45 | Client-side Premium promotion presentation | F03 | Extend | Compare the local media-speed-up upsell behavior with native prompts and actual entitlement. Verify that official channel sponsored content stays independent. |

## R. Behaviors requiring a release decision

| ID | Reference behavior | Reference | Evidence or gate |
| --- | --- | --- | --- |
| R01 | Ghost master switch, global/per-account mode, locks and quick controls | G01, G07 | Spec and fixture coverage depend on the underlying Ghost behaviors below. |
| R02 | Suppress remote message, media, mention and reaction reads | G02 | Telegram API Terms §1.4 explicitly covers read status and Ghost Mode. Compare history, notifications, forums and separate sessions with local/offline fixtures. |
| R03 | Suppress story views and offer pre-open Ghost prompt | G02, G07 | Compare the native official Premium story stealth feature separately. Verify reaction, reply and view side effects. |
| R04 | Suppress online/last-seen updates, typing, uploads or force offline | G03 | §1.4 covers presence and typing. Test account switches, second sessions, idle timers, cancellation and progress types independently. |
| R05 | Per-account trusted-chat Ghost exceptions and read after interaction | G04, G05 | Verify exact peer/topic boundary, precedence of locks and ordinary versus explicit actions. |
| R06 | Ghost-specific send scheduling and silence | G06 | Compare delayed versus explicit scheduling, exactly-once delivery, welcome attachments and server presence effects. Keep ordinary scheduling in C37. |
| R07 | Retain expired/view-once content or override protected capture | H05 | §1.4 addresses self-destructing content. Keep native countdown, expiry and legitimate burn actions as distinct verification cases. |
| R08 | Copy, save, export or recreate restricted content | H06, X11 | Review Telegram content protections, sender expectations and connected-release behavior for messages and stories. Supported content is covered by C32 and C43. |
| R09 | Suppress sponsored messages in channels | F03 | §3.3 explicitly requires official sponsored-message support. Test native sponsored messages and separately assess local Premium upsell presentation. |
| R10 | Local Premium emoji send/edit encoding and fake capability indicators | M05, X05 | Compare local presentation, sent payloads, editing, fallback and actual server entitlement checks. Preserve real account privileges. |
| R11 | Android-style mini-app identity and external services | M03, M05, X02 | Review origin and client identity effects separately from window sizing. Document what data leaves the app for translators, date lookups or iTunes cover enrichment and require explicit provider selection. |
| R12 | Import the C++ client's existing message archive or settings | H04 | A cross-client migration is separate from upgrading gergram's own database. Legacy archive records can have account ID zero. Establish ownership before any import and exercise mixed-account fixtures without automatically assigning ambiguous records. |

## Additional source evidence

AyuGram paths here are relative to `Telegram/SourceFiles/` at the reference revision. Existing catalog IDs cover other reference paths.

| Ref | Finding | Source |
| --- | --- | --- |
| X01 | Bottom message info has a dedicated icons setting apart from label customization. | `ayu/ui/settings/settings_chats.cpp` and `history/view/history_view_bottom_info.cpp`, `replaceBottomInfoWithIcons`. |
| X02 | Profile details include registration dates and join dates with distinct data sources. | `info/profile/info_profile_actions.cpp` and `ayu/utils/telegram_helpers.cpp`. |
| X03 | Active Sessions reads and displays official-app state. | `api/api_authorizations.cpp` and `settings/sections/settings_active_sessions.cpp`. |
| X04 | exteraGram plugin attachments have a metadata viewer. | `data/data_document_resolver.cpp` and `ayu/ui/boxes/plugin_info_box.cpp`. |
| X05 | Local Premium has separate custom-emoji message encoding in send and edit paths. | `ayu/utils/telegram_helpers.cpp`, `api/api_sending.cpp` and `api/api_editing.cpp`. |
| X06 | The local fork adjusted streaming prefetch and download scheduling. | Commit `a44ebb7a18`, `media/streaming/media_streaming_prefetch.h` and `storage/download_manager_mtproto.cpp`. |
| X07 | Profile rows can show the peer's data center. Pack menus expose set IDs and emoji IDs. | `info/profile/info_profile_actions.cpp`, `ayu/utils/telegram_helpers.cpp` and `boxes/sticker_set_box.cpp`. |
| X08 | Attachment confirmation reorders non-album files and returns edited captions on cancellation. | `boxes/send_files_box.cpp`. |
| X09 | The bot start button displays part of a start payload and can clear it. | `history/history_widget.cpp`. |
| X10 | The unread divider is pill-shaped. The custom emoji picker exposes a press-and-hold preview. | `history/view/history_view_element.cpp` and `chat_helpers/emoji_list_widget.cpp`. |
| X11 | Spotify routing and story export are independent behaviors. | `ayu/ayu_url_handlers.cpp`, `core/ui_integration.cpp` and `media/view/media_view_overlay_widget.cpp`. |
| X12 | The send menu offers a sound override when the AyuGram default is silent. | `menu/menu_send.cpp`. |
| X13 | Context-menu local hide stores message IDs in memory by peer and handles albums outside Saved Messages. | `ayu/ayu_state.cpp` and `ayu/ui/context_menu/context_menu.cpp`. |

## Native implementation anchors

Paths are relative to the pinned native checkout.

| Area | Confirmed anchor and remaining work |
| --- | --- |
| Settings and peer IDs | `packages/SettingsUI/Sources/SettingsUI/GeneralSettingsViewController.swift` and `SearchSettingsController.swift`, `packages/InAppSettings/Sources/InAppSettings/FastSettings.swift`, and the user/group/channel info entry builders under `packages/PeerInfoUI/Sources/PeerInfoUI/`. |
| Folders, Dock and icon | `packages/ChatListUI/Sources/ChatListUI/ChatListRevealItem.swift`, plus `NotificationPreferencesController.swift` and `AppAppearanceViewController.swift` in SettingsUI. Extend local presentation; preserve server folder data. |
| Navigation and recommendations | `ChatController.swift` in ChatUI has a first-message search and a sender-filtered search route. `ChatServiceItem.swift` in ChatUI has per-channel collapse, and `PeerMediaController.swift` in PeerInfoUI owns the Similar Channels tab. |
| Read routes | `Telegram-Mac/account/AccountContext.swift` and `ChatController.swift` in ChatUI handle ordinary history. `Telegram-Mac/app/AppDelegate.swift` and notification helpers also have a direct Mark as Read path. Confirm ChatListUI and thread-specific commands. |
| Message UI | `packages/ChatUI/Sources/ChatUI/ChatMessageMenuItems.swift`, `ChatRowView.swift`, `ChatInputView.swift` and the package's selection and history code. Avoid a parallel chat renderer for Message Shot. |
| Story and media | `StoryChatContent.swift`, `StoryModalController.swift` and `StoryChatListView.swift` in StoriesUI. Use existing TelegramMedia, GalleryUI and AudioPlayerCore behavior for playback and download. |
| Streamer Mode | `packages/CaptureExclusion/Sources/CaptureExclusion/CaptureExclusionManager.swift` provides existing window-level exclusion. Extend account and new-window coverage and trace `Telegram-Mac/account/SharedNotificationManager.swift` for native notifications. |
| Transcription and translation | Received voice/round transcription goes through the engine in ChatUI's `ChatController.swift`. Native composer dictation in `ChatInputDictationEngine.swift` provides adjacent Speech support. Translation UI lives in `packages/TranslateUI/` with provider code in `packages/Translate/`. |
| Archive and protected content | Swift app owns archive UI and settings. Trace the pinned TelegramCore update and Postbox transaction before choosing a capture seam. Keep ordinary archive, expiry, and server messaging as distinct data flows. |

## Delivery order and evidence

1. Close B01–B03, then exercise settings with A01 as the first end-to-end change. Compare native overlap rows early so they do not become duplicate implementations.
2. Deliver folder/filter presentation (A02–A09), then Message Shot and Streamer Mode (A10–A13). Give each a small fixture suite and a disabled-state regression.
3. Deliver the ordinary archive as storage/migration, capture, then views (A17 → A14/A15 → A16). Validate relaunch, multi-account, topic scope and rollback before merging history work.
4. Complete the remaining P1 tools and P2 presentation/integration work. Keep independent provider, permission and release tests for media and third-party features.
5. Record an implementation commit, exact native path, build command and matched reference/native behavior before marking a row done. Cover account switching, cancelled async actions, fallback behavior and accessible entry points where applicable.

Platform-specific Windows/Linux installers, Qt styling internals and Android-only services are outside this macOS parity target. Standalone chat zoom, a distinct link-history feature, a global delete-all-chats workflow and a macOS Ghost-at-launch shortcut remain unconfirmed at the AyuGram reference revision. The per-chat bulk actions, shared-link UI and normal text scaling have separate evidence.

Sources: [Telegram API Terms of Service](https://core.telegram.org/api/terms), [official native Telegram source](https://github.com/TelegramMessenger/telegram-macos), [AyuGram Desktop documentation](https://docs.ayugram.one/desktop/), and the two pinned local checkouts above.
