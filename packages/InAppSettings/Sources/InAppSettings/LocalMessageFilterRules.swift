import Foundation
import Postbox
import TelegramCore

public struct LocalMessageFilterRule: Codable, Equatable, Identifiable {
    public let id: UUID
    public let chatId: PeerId?
    public var pattern: String
    public var isEnabled: Bool
    public var isReversed: Bool
    public var isCaseInsensitive: Bool

    public init(id: UUID = UUID(), pattern: String, chatId: PeerId? = nil, isEnabled: Bool = true, isReversed: Bool = false, isCaseInsensitive: Bool = false) {
        self.id = id
        self.chatId = chatId
        self.pattern = pattern
        self.isEnabled = isEnabled
        self.isReversed = isReversed
        self.isCaseInsensitive = isCaseInsensitive
    }
}

public struct LocalMessageFilterPreferences: Codable, Equatable {
    public static let maximumRules = 64
    public static let maximumExcludedChats = 256

    public var isEnabled = false
    public var includesChats = false
    public private(set) var rules: [LocalMessageFilterRule] = []
    public private(set) var excludedSharedRuleIds: [PeerId: Set<UUID>] = [:]

    public init() {}

    public func applicableRules(chatId: PeerId, isBroadcast: Bool) -> [LocalMessageFilterRule] {
        guard isEnabled, includesChats || isBroadcast else { return [] }
        let exclusions = excludedSharedRuleIds[chatId] ?? []
        var chatRules: [LocalMessageFilterRule] = []
        var sharedRules: [LocalMessageFilterRule] = []
        for rule in rules.prefix(Self.maximumRules) where rule.isEnabled {
            if rule.chatId == chatId {
                chatRules.append(rule)
            } else if rule.chatId == nil, !exclusions.contains(rule.id) {
                sharedRules.append(rule)
            }
        }
        return chatRules + sharedRules
    }

    public static func acceptsChat(_ chatId: PeerId) -> Bool {
        let namespace = chatId.namespace
        return chatId.id._internalGetInt64Value() > 0 && (namespace == Namespaces.Peer.CloudUser || namespace == Namespaces.Peer.CloudGroup || namespace == Namespaces.Peer.CloudChannel)
    }

    @discardableResult
    public mutating func upsert(_ rule: LocalMessageFilterRule) -> Bool {
        guard rule.chatId.map(Self.acceptsChat) ?? true, LocalMessageFilterEvaluation.isValid(rule) else { return false }
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            guard rules[index].chatId == rule.chatId else { return false }
            rules[index] = rule
        } else {
            guard rules.count < Self.maximumRules else { return false }
            rules.append(rule)
        }
        return true
    }

    public mutating func remove(ruleId: UUID) {
        rules.removeAll { $0.id == ruleId }
        for chatId in Array(excludedSharedRuleIds.keys) {
            excludedSharedRuleIds[chatId]?.remove(ruleId)
            if excludedSharedRuleIds[chatId]?.isEmpty == true {
                excludedSharedRuleIds.removeValue(forKey: chatId)
            }
        }
    }

    @discardableResult
    public mutating func setSharedRuleExcluded(_ ruleId: UUID, chatId: PeerId, excluded: Bool) -> Bool {
        guard Self.acceptsChat(chatId), rules.contains(where: { $0.id == ruleId && $0.chatId == nil }) else { return false }
        if excluded {
            guard excludedSharedRuleIds[chatId] != nil || excludedSharedRuleIds.count < Self.maximumExcludedChats else { return false }
            excludedSharedRuleIds[chatId, default: []].insert(ruleId)
        } else {
            excludedSharedRuleIds[chatId]?.remove(ruleId)
            if excludedSharedRuleIds[chatId]?.isEmpty == true {
                excludedSharedRuleIds.removeValue(forKey: chatId)
            }
        }
        return true
    }
}
