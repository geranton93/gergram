# gergram

gergram is an unofficial native macOS client for Telegram. It extends the Swift and AppKit codebase of [Telegram for macOS](https://github.com/TelegramMessenger/telegram-macos).

The development branch contains the changes below. The integrated macOS build and app-level verification are pending.

## Changes in gergram

| Area | What gergram adds to Telegram for macOS |
| --- | --- |
| App identity | A gergram name and icon, its own bundle and app-group defaults, local configuration for API credentials and signing, and independent update settings. |
| Profile IDs and dates | The existing profile ID option can display and copy the Bot API format for users, groups, and channels. User profiles show the registration month and year when Telegram supplies it. Appearance can show the current member's join date in channel and supergroup profiles. |
| Chat folders | Account-local controls to hide and restore folders, show or hide All Chats, and show or hide folder unread badges. Visible folders can be reordered while hidden folders retain their positions in the saved order. A reachable default folder remains available. |
| Local message visibility | Hide an individual message or album for the current session and restore it from the chat menu. Privacy and Security includes account-local hidden sender rules. The blocked and hidden sender filters cover incoming messages in the transcript, including known forwarded and inline bot sources. Each chat can temporarily show its filtered messages. |
| Message filters | Configure shared and chat-specific regex rules in Privacy and Security. Add a literal rule from selected message text, and import or export a validated JSON filter file for the current account. |
| Message text and details | Turn on **Filter Zalgo Text in Messages** in General settings to remove excessive combining marks and explicit direction controls from ordinary message text and captions on screen. **Message Details** shows and copies IDs, timestamps, available view and forward counts, and eligible cloud attachment metadata. |
| Message Shot | Copy or save a single message or a selection as a PNG from the message menu. Exports include author labels, styled ordinary text and available cached photo or video previews. Text spoilers are masked before rendering, and spoiler or sensitive media use placeholders. **Show Timestamps** controls dates and times. Turn off **Show Background** for a transparent canvas around the message cards. Choose the current chat palette or one of four built-in themes, and optionally include reaction totals. The export preferences are saved locally. gergram checks chat and message export permissions before rendering. |
| Local message archive | Opt in under Privacy and Security to keep eligible incoming deleted text and previous message versions on this Mac. Browse by account, chat or topic, open it directly from supported chat and topic menus, remove an entry or clear the current scope. Capture defaults off. Records are visible for up to 30 days and limited to 4,096 per account. |
| Notifications | Choose immediate message delivery, a minimum delay, or a grace period for other devices. Delayed alerts recheck current privacy and message state. |
| Streamer Mode | A persistent app and menu-bar control requests capture exclusion across gergram windows and suppresses new chat and story notifications while active. Actual capture coverage depends on macOS and the sharing method. |
| Discovery | Disable remote peer discovery in the main chat-list search while keeping local and message results. Hide the Similar Channels profile tab, start post-join recommendations collapsed, or independently hide stories and avatar story indicators in the chat list, its search results and other profiles. |
| Bot button inspection | View or copy inline callback data from the message menu without activating the button. Binary payloads use Base64. |
| Context menu and bot Start | Configure which message commands appear in the regular or extended menu. Search by sender from an eligible message. A bot Start button can preview and clear its pending parameter locally. |
| Settings and composer | gergram settings links open message menu controls, hidden senders, message filters or the local archive for the active account. Mini Apps can open wider or taller. Canceling an attachment preview can return the edited caption to the originating draft. Reordering files or album tiles uses the same attachment order as sending. Choose silent sending per account and override it for an individual send. Enable independent confirmation prompts for file-backed stickers and GIFs. |
| Plugin attachment metadata | Open the metadata for an eligible downloaded `.plugin` attachment. The viewer reads a bounded local file and displays the declared fields as plain text. |
| Pack identifiers and profiles | Copy sticker pack, emoji pack and custom emoji IDs. Profile ID rows label a statistics DC or profile-photo DC when available. |
| Translation and links | Select Google Translate for eligible messages with confirmation in the translation window. Telegram is the default provider. Eligible Spotify links can open in the installed app. Supported social posts can use a wide preview when Telegram supplies suitable media. gergram peer and chat links accept typed numeric IDs for peers known to the current account. |
| On-device transcription | Choose **Transcribe on This Mac** for an eligible incoming voice message or round video. Apple Speech processes supported audio locally, up to 60 seconds and 24 MB. |
| Chat appearance | A compact unread divider surrounds its label. Message, service and reaction timestamps can show seconds in the current locale. Appearance can use the global wallpaper in chats with custom backgrounds. Choose text, a pencil icon or no edited indicator. Direct broadcast-channel authors in supergroups use the Channel badge, and Contacts marks mutual contacts. Choose Preview Media as the Force Click action. Preview custom emoji through the picker with a hold, context menu or VoiceOver action. |
| Stickers | Enable **Show All Recent Stickers** to show eligible stickers from the full synced recent list when available. The default picker displays up to 20. |
| Playback and sessions | Direct playback replenishes a bounded read-ahead window, supports relative and absolute FFmpeg seeks, and releases its demand on cancellation or terminal read failure. Speculative story video downloads use a bounded prefix when metadata is missing and prioritize the next story's media ahead of its reactions. Session details show whether Telegram identifies the session as an official app. |

### Numeric peer and chat links

Use `gergram://peer/user/42` to open a profile and `gergram://chat/channel/42` to open a chat. The raw ID path takes `user`, `group` or `channel`. The `bot-api` path takes a signed Bot API dialog ID, for example `gergram://chat/bot-api/-1000000000042`. The selected account needs the target in its local peer data.

## Planned additions

| Area | What gergram adds |
| --- | --- |
| Message filters | Extend sender filtering to remaining chat surfaces and add reference-format and sharing-link support. |
| Message images | Extend Message Shot with replies, richer media and message layouts. |
| Local message history | Add inline archive markers and local reply links. |
| Chat appearance | Add settings for bubble width and shape, avatar corners, monospace fonts, and remaining timestamp surfaces. |
| Composer controls | Choose visible composer actions and media send confirmations. Extend keyboard reordering controls. |
| Speech models | Add optional support for a locally installed speech model. |
| Message and bot tools | Extend message details with media metadata and look up sticker and emoji pack authors where available. |

## Build from source

Use a Mac with full Xcode, Homebrew, and a Rust toolchain. Initialize the pinned Git submodules from a checkout of gergram.

```sh
git submodule sync --recursive
git submodule update --init --recursive
```

The build requires native framework preparation and a `Local.xcconfig` with the fork's API identity and signing team. Open `Telegram-Mac.xcworkspace` and select the `Telegram` scheme after preparation. [Development guide](docs/fork-development.md)

The implementation plan tracks each phase. The verification register records the remaining acceptance checks for every audited item. [Implementation plan](docs/development-plan.md) · [Verification register](docs/feature-verification.md)

## Upstream and license

The initial upstream revision is [`ec221d8560ca`](https://github.com/TelegramMessenger/telegram-macos/commit/ec221d8560ca693cb921b4e8c576da9b87dff9ef). The upstream project and this fork are licensed under the GNU General Public License, version 2. Upstream copyright and third-party license notices apply to the corresponding code. [License](LICENSE)
