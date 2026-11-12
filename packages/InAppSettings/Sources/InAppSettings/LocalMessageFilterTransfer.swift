import Foundation
import Postbox

public enum LocalMessageFilterTransfer {
    public enum Error: Swift.Error, Equatable {
        case fileTooLarge
        case invalidFile
        case unsupportedVersion
        case differentAccount
    }

    public static let maximumBytes = 1024 * 1024
    private static let format = "gergram-message-filters"
    private static let version = 1

    private struct Header: Decodable {
        let format: String
        let version: Int
    }

    private struct Chat: Codable {
        let namespace: Int32
        let id: String

        init(_ peerId: PeerId) {
            namespace = peerId.namespace._internalGetInt32Value()
            id = String(peerId.id._internalGetInt64Value())
        }

        func peerId() throws -> PeerId {
            guard (0 ... 7).contains(namespace), let value = Int64(id), value > 0, value <= 0x00ff_ffff_ffff_ffff else {
                throw Error.invalidFile
            }
            let peerId = PeerId(namespace: ._internalFromInt32Value(namespace), id: ._internalFromInt64Value(value))
            guard LocalMessageFilterPreferences.acceptsChat(peerId) else { throw Error.invalidFile }
            return peerId
        }
    }

    private struct Rule: Codable {
        let id: UUID
        let pattern: String
        let chat: Chat?
        let isEnabled: Bool
        let isReversed: Bool
        let isCaseInsensitive: Bool

        init(_ rule: LocalMessageFilterRule) {
            id = rule.id
            pattern = rule.pattern
            chat = rule.chatId.map(Chat.init)
            isEnabled = rule.isEnabled
            isReversed = rule.isReversed
            isCaseInsensitive = rule.isCaseInsensitive
        }

        func localRule() throws -> LocalMessageFilterRule {
            return LocalMessageFilterRule(id: id, pattern: pattern, chatId: try chat?.peerId(), isEnabled: isEnabled, isReversed: isReversed, isCaseInsensitive: isCaseInsensitive)
        }
    }

    private struct Exclusion: Codable {
        let chat: Chat
        let ruleIds: [UUID]
    }

    private struct Document: Codable {
        let format: String
        let version: Int
        let account: Chat?
        let isEnabled: Bool
        let includesChats: Bool
        let rules: [Rule]
        let exclusions: [Exclusion]

        var hasChatScopes: Bool {
            return !exclusions.isEmpty || rules.contains { $0.chat != nil }
        }
    }

    public static func encode(_ preferences: LocalMessageFilterPreferences, accountPeerId: PeerId) throws -> Data {
        let rules = preferences.rules.map(Rule.init)
        let exclusions = preferences.excludedSharedRuleIds.sorted { $0.key < $1.key }.map { peerId, ids in
            return Exclusion(chat: Chat(peerId), ruleIds: ids.sorted { $0.uuidString < $1.uuidString })
        }
        let hasChatScopes = !exclusions.isEmpty || rules.contains { $0.chat != nil }
        let document = Document(format: format, version: version, account: hasChatScopes ? Chat(accountPeerId) : nil, isEnabled: preferences.isEnabled, includesChats: preferences.includesChats, rules: rules, exclusions: exclusions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= maximumBytes else { throw Error.fileTooLarge }
        return data
    }

    public static func decode(_ data: Data, accountPeerId: PeerId) throws -> LocalMessageFilterPreferences {
        guard data.count <= maximumBytes else { throw Error.fileTooLarge }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data), header.format == format else {
            throw Error.invalidFile
        }
        guard header.version == version else { throw Error.unsupportedVersion }
        guard let document = try? decoder.decode(Document.self, from: data),
              document.rules.count <= LocalMessageFilterPreferences.maximumRules,
              document.exclusions.count <= LocalMessageFilterPreferences.maximumExcludedChats else { throw Error.invalidFile }
        if document.hasChatScopes {
            guard let account = document.account, try account.peerId() == accountPeerId else { throw Error.differentAccount }
        }

        var preferences = LocalMessageFilterPreferences()
        preferences.isEnabled = document.isEnabled
        preferences.includesChats = document.includesChats
        var seenIds = Set<UUID>()
        for rule in document.rules {
            guard seenIds.insert(rule.id).inserted, preferences.upsert(try rule.localRule()) else { throw Error.invalidFile }
        }

        var seenChats = Set<PeerId>()
        for exclusion in document.exclusions {
            let peerId = try exclusion.chat.peerId()
            let ruleIds = Set(exclusion.ruleIds)
            guard seenChats.insert(peerId).inserted, !ruleIds.isEmpty, ruleIds.count == exclusion.ruleIds.count,
                  ruleIds.count <= LocalMessageFilterPreferences.maximumRules else { throw Error.invalidFile }
            for ruleId in ruleIds {
                guard preferences.setSharedRuleExcluded(ruleId, chatId: peerId, excluded: true) else { throw Error.invalidFile }
            }
        }
        return preferences
    }
}
