import Foundation
import InAppSettings
import MessageUtils
import Postbox
import SwiftSignalKit
import TelegramCore

enum ChatRegexFilterProjection {
    private static let queue = Queue(name: "ChatRegexFilters")
    private static let maximumEntries = 512

    static func hiddenItems(entries: [MessageHistoryEntry], rules: [LocalMessageFilterRule], accountPeerId: PeerId) -> Signal<Set<ChatLocalHiddenItem>, NoError> {
        guard !rules.isEmpty, !entries.isEmpty, entries.count <= maximumEntries else { return .single([]) }
        return Signal { subscriber in
            guard let evaluation = LocalMessageFilterEvaluation() else {
                subscriber.putNext([])
                subscriber.putCompletion()
                return EmptyDisposable
            }
            queue.async {
                guard !evaluation.isCancelled else { return }
                evaluation.prepare(rules)
                guard !evaluation.isCancelled else { return }
                var messages: [ChatLocalHiddenItem: [Message]] = [:]
                var orderedItems: [ChatLocalHiddenItem] = []
                for entry in entries {
                    let message = entry.message
                    guard message.id.namespace == Namespaces.Message.Cloud, message.effectivelyIncoming(accountPeerId),
                          message.adAttribute == nil, !message.media.contains(where: { $0 is TelegramMediaAction }) else { continue }
                    let key = ChatLocalHiddenItem(message)
                    if messages[key] == nil {
                        orderedItems.append(key)
                    }
                    messages[key, default: []].append(message)
                }

                var hidden: Set<ChatLocalHiddenItem> = []
                for key in orderedItems {
                    guard evaluation.canEvaluate else { break }
                    if let group = messages[key], let input = makeInput(group), evaluation.shouldHide(input) {
                        hidden.insert(key)
                    }
                }
                guard !evaluation.isCancelled else { return }
                subscriber.putNext(hidden)
                subscriber.putCompletion()
            }
            return ActionDisposable { evaluation.cancel() }
        }
    }

    private static func makeInput(_ messages: [Message]) -> String? {
        var result = ""
        var remaining = LocalMessageFilterEvaluation.maximumInputLength

        func append(_ value: String) -> Bool {
            let length = value.utf16.prefix(remaining + 1).count
            guard length <= remaining else { return false }
            result.append(value)
            remaining -= length
            return true
        }

        for message in messages {
            guard append(message.text), append("\n") else { return nil }
            let entities = message.textEntities?.entities ?? []
            guard entities.count <= 256 else { return nil }
            let text = message.text as NSString
            for entity in entities {
                let link: String
                switch entity.type {
                case .Url:
                    guard entity.range.lowerBound >= 0, entity.range.upperBound <= text.length else { continue }
                    link = text.substring(with: NSRange(location: entity.range.lowerBound, length: entity.range.count))
                case let .TextUrl(url):
                    link = url
                default:
                    continue
                }
                guard append(link), append("\n") else { return nil }
            }
        }
        for message in messages {
            if let markup = message.replyMarkup {
                guard markup.rows.count <= 16 else { return nil }
                for row in markup.rows {
                    guard row.buttons.count <= 16 else { return nil }
                    for button in row.buttons {
                        let payload: String
                        switch button.action {
                        case let .url(url):
                            payload = url
                        case let .callback(_, data):
                            let bytes = data.makeData()
                            guard bytes.count <= remaining else { return nil }
                            payload = String(decoding: bytes, as: UTF8.self)
                        default:
                            payload = ""
                        }
                        guard append("<button>"), append(button.title), append(" "), append(payload), append("</button>\n") else { return nil }
                    }
                }
            }
            guard append("<type>\(mediaType(message))</type>"), messages.count == 1 || append("\n") else { return nil }
        }
        return result
    }

    private static func mediaType(_ message: Message) -> Int {
        if message.attributes.contains(where: { $0 is RichTextMessageAttribute }) { return 36 }
        guard let media = message.media.first else { return 0 }
        switch media {
        case is TelegramMediaImage: return 1
        case is TelegramMediaMap: return 4
        case is TelegramMediaContact: return 12
        case is TelegramMediaDice: return 15
        case is TelegramMediaPoll, is TelegramMediaTodo: return 17
        case is TelegramMediaStory: return 23
        case is TelegramMediaGiveaway: return 26
        case is TelegramMediaGiveawayResults: return 28
        case is TelegramMediaPaidContent: return 29
        case let file as TelegramMediaFile:
            if file.isInstantVideo { return 5 }
            if file.isVoice { return 2 }
            if file.isMusic { return 14 }
            if file.isAnimatedSticker || file.isVideoSticker { return 15 }
            if file.isSticker { return 13 }
            if file.isAnimated { return 8 }
            if file.isVideo { return 3 }
            return 9
        default: return 0
        }
    }
}
