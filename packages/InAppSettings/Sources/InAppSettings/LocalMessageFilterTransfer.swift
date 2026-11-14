import Foundation
import Postbox

public enum LocalMessageFilterTransfer {
    public enum Error: Swift.Error, Equatable {
        case fileTooLarge
        case invalidFile
        case unsupportedVersion
        case differentAccount
        case unsupportedSharedBackup
        case sharedRuleCollision
        case tooManyRules
        case noSharedRules
        case invalidLink
        case linkTooLarge
    }

    public enum Import {
        case replacement(LocalMessageFilterPreferences)
        case sharedRules(SharedRuleBackup)
    }

    public struct SharedRuleBackup {
        public let rules: [LocalMessageFilterRule]

        fileprivate init(rules: [LocalMessageFilterRule]) {
            self.rules = rules
        }

        public func merging(into current: LocalMessageFilterPreferences) throws -> SharedRuleImport {
            let existing = current.rules
            var merged = current
            var added = 0
            var updated = 0
            for rule in rules {
                if let previous = existing.first(where: { $0.id == rule.id }) {
                    guard previous.chatId == nil else { throw Error.sharedRuleCollision }
                    guard previous != rule else { continue }
                    updated += 1
                } else {
                    guard merged.rules.count < LocalMessageFilterPreferences.maximumRules else { throw Error.tooManyRules }
                    added += 1
                }
                guard merged.upsert(rule) else { throw Error.invalidFile }
            }
            return SharedRuleImport(preferences: merged, added: added, updated: updated)
        }
    }

    public struct SharedRuleImport {
        public let preferences: LocalMessageFilterPreferences
        public let added: Int
        public let updated: Int
    }

    public static let maximumBytes = 1024 * 1024
    public static let maximumLinkBytes = 8 * 1024
    private static let format = "gergram-message-filters"
    private static let version = 1
    private static let sharedBackupVersion = 2
    private static let sharedLinkPrefix = "gergram://filters/v1/"

    private struct Header: Decodable {
        let format: String
        let version: Int
    }

    private struct ImportHeader: Decodable {
        let format: String?
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

    public static func encodeSharedRules(_ preferences: LocalMessageFilterPreferences) throws -> Data {
        let rules = preferences.rules.filter { $0.chatId == nil }
        guard !rules.isEmpty else { throw Error.noSharedRules }
        guard rules.count <= LocalMessageFilterPreferences.maximumRules else { throw Error.tooManyRules }
        guard Set(rules.map(\.id)).count == rules.count, rules.allSatisfy(LocalMessageFilterEvaluation.isValid) else {
            throw Error.invalidFile
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(SharedRuleBackupDocument(rules: rules))
        guard data.count <= maximumBytes else { throw Error.fileTooLarge }
        return data
    }

    public static func encodeSharedRulesLink(_ preferences: LocalMessageFilterPreferences) throws -> String {
        let link = sharedLinkPrefix + base64URL(try encodeSharedRules(preferences))
        guard link.utf8.count <= maximumLinkBytes else { throw Error.linkTooLarge }
        return link
    }

    public static func decodeSharedRulesLink(_ link: String) throws -> SharedRuleBackup {
        guard link.utf8.prefix(maximumLinkBytes + 1).count <= maximumLinkBytes else { throw Error.linkTooLarge }
        guard link.hasPrefix(sharedLinkPrefix) else { throw Error.invalidLink }
        let payload = String(link.dropFirst(sharedLinkPrefix.count))
        guard !payload.isEmpty, payload.utf8.allSatisfy({ byte in
            (65 ... 90).contains(byte) || (97 ... 122).contains(byte) || (48 ... 57).contains(byte) || byte == 45 || byte == 95
        }) else { throw Error.invalidLink }

        let padding = (4 - payload.utf8.count % 4) % 4
        let encoded = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: padding)
        guard let data = Data(base64Encoded: encoded), base64URL(data) == payload,
              let header = try? JSONDecoder().decode(ImportHeader.self, from: data), header.format == nil,
              header.version == sharedBackupVersion,
              let backup = try? decodeSharedBackup(data) else { throw Error.invalidLink }
        return backup
    }

    private static func base64URL(_ data: Data) -> String {
        return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
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

    public static func decodeImport(_ data: Data, accountPeerId: PeerId) throws -> Import {
        guard data.count <= maximumBytes else { throw Error.fileTooLarge }
        guard let header = try? JSONDecoder().decode(ImportHeader.self, from: data) else { throw Error.invalidFile }
        if header.format != nil {
            return .replacement(try decode(data, accountPeerId: accountPeerId))
        }
        guard header.version == sharedBackupVersion else { throw Error.unsupportedVersion }
        return .sharedRules(try decodeSharedBackup(data))
    }

    private static func decodeSharedBackup(_ data: Data) throws -> SharedRuleBackup {
        let backup: SharedRuleBackupDocument
        do {
            backup = try JSONDecoder().decode(SharedRuleBackupDocument.self, from: data)
        } catch let error as Error {
            throw error
        } catch {
            throw Error.invalidFile
        }
        return SharedRuleBackup(rules: backup.rules)
    }

    private struct BackupKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    private struct SharedRuleBackupDocument: Codable {
        let rules: [LocalMessageFilterRule]

        private enum Key: String, CodingKey {
            case version, filters, exclusions, peers, removeFiltersById, removeExclusions
        }

        init(rules: [LocalMessageFilterRule]) {
            self.rules = rules
        }

        init(from decoder: Decoder) throws {
            let keys = try decoder.container(keyedBy: BackupKey.self).allKeys
            guard keys.allSatisfy({ Key(rawValue: $0.stringValue) != nil }) else { throw Error.invalidFile }
            let values = try decoder.container(keyedBy: Key.self)
            for key in [Key.exclusions, .removeFiltersById, .removeExclusions] where values.contains(key) {
                if try !values.decodeNil(forKey: key), try !values.nestedUnkeyedContainer(forKey: key).isAtEnd {
                    throw Error.unsupportedSharedBackup
                }
            }
            if values.contains(.peers), try !values.decodeNil(forKey: .peers),
               try !values.nestedContainer(keyedBy: BackupKey.self, forKey: .peers).allKeys.isEmpty {
                throw Error.unsupportedSharedBackup
            }

            var filters = try values.nestedUnkeyedContainer(forKey: .filters)
            guard let count = filters.count, count > 0 else { throw Error.invalidFile }
            guard count <= LocalMessageFilterPreferences.maximumRules else { throw Error.tooManyRules }
            var rules: [LocalMessageFilterRule] = []
            rules.reserveCapacity(count)
            var ids = Set<UUID>()
            while !filters.isAtEnd {
                let rule = try filters.decode(SharedBackupRule.self).rule
                guard ids.insert(rule.id).inserted, LocalMessageFilterEvaluation.isValid(rule) else { throw Error.invalidFile }
                rules.append(rule)
            }
            self.rules = rules
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: Key.self)
            try values.encode(LocalMessageFilterTransfer.sharedBackupVersion, forKey: .version)
            try values.encode(rules.map(SharedBackupRule.init(rule:)), forKey: .filters)
            _ = values.nestedUnkeyedContainer(forKey: .exclusions)
            _ = values.nestedContainer(keyedBy: BackupKey.self, forKey: .peers)
            try values.encodeNil(forKey: .removeFiltersById)
            try values.encodeNil(forKey: .removeExclusions)
        }
    }

    private struct SharedBackupRule: Codable {
        let rule: LocalMessageFilterRule

        private enum Key: String, CodingKey {
            case id, text, dialogId, enabled, reversed, caseInsensitive
        }

        init(rule: LocalMessageFilterRule) {
            self.rule = rule
        }

        init(from decoder: Decoder) throws {
            let keys = try decoder.container(keyedBy: BackupKey.self).allKeys
            guard keys.allSatisfy({ Key(rawValue: $0.stringValue) != nil }) else { throw Error.invalidFile }
            let values = try decoder.container(keyedBy: Key.self)
            guard values.contains(.dialogId) else { throw Error.invalidFile }
            guard try values.decodeNil(forKey: .dialogId) else { throw Error.unsupportedSharedBackup }
            rule = try LocalMessageFilterRule(id: values.decode(UUID.self, forKey: .id), pattern: values.decode(String.self, forKey: .text),
                isEnabled: values.decode(Bool.self, forKey: .enabled), isReversed: values.decode(Bool.self, forKey: .reversed),
                isCaseInsensitive: values.decode(Bool.self, forKey: .caseInsensitive))
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: Key.self)
            try values.encode(rule.id.uuidString.lowercased(), forKey: .id)
            try values.encode(rule.pattern, forKey: .text)
            try values.encodeNil(forKey: .dialogId)
            try values.encode(rule.isEnabled, forKey: .enabled)
            try values.encode(rule.isReversed, forKey: .reversed)
            try values.encode(rule.isCaseInsensitive, forKey: .caseInsensitive)
        }
    }
}
