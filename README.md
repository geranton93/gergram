# gergram

gergram is an unofficial native macOS client for Telegram. It extends the Swift and AppKit codebase of [Telegram for macOS](https://github.com/TelegramMessenger/telegram-macos).

The development branch contains the changes below. The integrated macOS build and app-level verification are pending.

## Changes in gergram

| Area | What gergram adds to Telegram for macOS |
| --- | --- |
| App identity | A gergram name and icon, its own bundle and app-group defaults, local configuration for API credentials and signing, and independent update settings. |
| Profile IDs and dates | The existing profile ID option can display and copy the Bot API format for users, groups, and channels. User profiles show the registration month and year when Telegram supplies it. |
| Chat folders | Account-local controls to hide and restore folders, show or hide All Chats, and show or hide folder unread badges. Visible folders can be reordered while hidden folders retain their positions in the saved order. A reachable default folder remains available. |
| Local message visibility | Hide an individual message or album for the current session and restore hidden messages from the chat menu. The optional blocked-sender filter covers incoming messages in the transcript, including known forwarded and inline bot sources. Each chat can temporarily show its filtered messages. |
| Message Shot | Copy or save a single message or a selection as a PNG from the message menu. The first renderer includes author and time labels, styled ordinary text, and media placeholders. It checks chat and message export permissions before rendering. |
| Streamer Mode | A persistent app and menu-bar control requests capture exclusion across gergram windows and suppresses new chat and story notifications while active. Actual capture coverage depends on macOS and the sharing method. |
| Discovery | Disable remote peer discovery in the main chat-list search while keeping local and message results. Hide the Similar Channels profile tab and start post-join recommendations collapsed. |
| Bot button inspection | View or copy inline callback data from the message menu without activating the button. Binary payloads use Base64. |
| Chat appearance | A compact unread divider surrounds its label. Message timestamps can show seconds in the current locale. |

## Planned additions

| Area | What gergram adds |
| --- | --- |
| Message filters | Apply regular-expression rules globally or per chat, with import and export. Add sender-specific rules and extend filtering to remaining chat surfaces. |
| Message images | Extend Message Shot with media rendering, rich-message layouts, and controls for themes, timestamps, reactions, and spoilers. |
| Local message history | Keep an opt-in, account-scoped record of eligible ordinary messages previously seen on this Mac. Browse earlier versions and deletion records, set retention, and clear stored entries. |
| Chat appearance | Add settings for bubble width and shape, avatar corners, monospace fonts, timestamp precision, and message context-menu visibility. |
| Composer controls | Choose visible composer actions and media send confirmations. Reorder file attachments and restore edited captions to the draft after cancellation. |
| On-device transcription | Transcribe received voice messages and round videos on the Mac with supported local recognition, with optional local model support planned separately. |
| Message and bot tools | Inspect exact message identifiers and timestamps, and look up sticker and emoji pack authors where available. |

## Build from source

Use a Mac with full Xcode, Homebrew, and a Rust toolchain. Initialize the pinned Git submodules from a checkout of gergram.

```sh
git submodule sync --recursive
git submodule update --init --recursive
```

The build requires native framework preparation and a `Local.xcconfig` with the fork's API identity and signing team. Open `Telegram-Mac.xcworkspace` and select the `Telegram` scheme after preparation. [Development guide](docs/fork-development.md)

The implementation plan tracks each phase and its verification status. [Implementation plan](docs/development-plan.md)

## Upstream and license

The initial upstream revision is [`ec221d8560ca`](https://github.com/TelegramMessenger/telegram-macos/commit/ec221d8560ca693cb921b4e8c576da9b87dff9ef). The upstream project and this fork are licensed under the GNU General Public License, version 2. Upstream copyright and third-party license notices apply to the corresponding code. [License](LICENSE)
