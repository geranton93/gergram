import Foundation
import InAppSettings
import Postbox
import TelegramCore
import XCTest

final class LocalMessageFilterTransferTests: XCTestCase {
    private let source = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(42))
    private let destination = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(87))
    private let channel = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(0x0020_0000_0000_0011))

    func testGlobalRulesRoundTripAcrossAccountsWithoutSharingTheOwner() throws {
        var preferences = LocalMessageFilterPreferences()
        preferences.isEnabled = true
        preferences.includesChats = true
        XCTAssertTrue(preferences.upsert(LocalMessageFilterRule(id: UUID(), pattern: "urgent", chatId: nil, isEnabled: true, isReversed: false, isCaseInsensitive: true)))

        let data = try LocalMessageFilterTransfer.encode(preferences, accountPeerId: source)
        XCTAssertEqual(try LocalMessageFilterTransfer.decode(data, accountPeerId: destination), preferences)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(document["account"])
    }

    func testScopedRulesAndExclusionsRequireTheSameAccount() throws {
        var preferences = LocalMessageFilterPreferences()
        let sharedId = UUID()
        XCTAssertTrue(preferences.upsert(LocalMessageFilterRule(id: sharedId, pattern: "notice", chatId: nil, isEnabled: true, isReversed: false, isCaseInsensitive: false)))
        XCTAssertTrue(preferences.upsert(LocalMessageFilterRule(id: UUID(), pattern: "^(one|two)$", chatId: channel, isEnabled: false, isReversed: true, isCaseInsensitive: false)))
        preferences.setSharedRuleExcluded(sharedId, chatId: channel, excluded: true)

        let data = try LocalMessageFilterTransfer.encode(preferences, accountPeerId: source)
        XCTAssertEqual(try LocalMessageFilterTransfer.decode(data, accountPeerId: source), preferences)
        XCTAssertThrowsError(try LocalMessageFilterTransfer.decode(data, accountPeerId: destination)) { error in
            XCTAssertEqual(error as? LocalMessageFilterTransfer.Error, .differentAccount)
        }
    }

    func testUntrustedInputIsValidatedBeforeApplyingAnyRules() throws {
        let ruleId = UUID().uuidString
        let rule: [String: Any] = ["id": ruleId, "pattern": "word", "isEnabled": true, "isReversed": false, "isCaseInsensitive": false]

        func decode(_ changes: [String: Any]) throws -> LocalMessageFilterPreferences {
            let base: [String: Any] = ["format": "gergram-message-filters", "version": 1, "account": ["namespace": 0, "id": "42"], "isEnabled": true, "includesChats": false, "rules": [rule], "exclusions": []]
            let data = try JSONSerialization.data(withJSONObject: base.merging(changes) { _, new in new })
            return try LocalMessageFilterTransfer.decode(data, accountPeerId: source)
        }

        XCTAssertThrowsError(try decode(["version": 2])) { XCTAssertEqual($0 as? LocalMessageFilterTransfer.Error, .unsupportedVersion) }
        XCTAssertThrowsError(try decode(["rules": [rule, rule]]))
        XCTAssertThrowsError(try decode(["rules": [rule.merging(["pattern": "("]) { _, new in new }]]))
        XCTAssertThrowsError(try decode(["rules": [rule.merging(["chat": ["namespace": 99, "id": "1"]]) { _, new in new }]])) {
            XCTAssertEqual($0 as? LocalMessageFilterTransfer.Error, .invalidFile)
        }
        XCTAssertThrowsError(try decode(["rules": [rule.merging(["chat": ["namespace": 2, "id": "9223372036854775807"]]) { _, new in new }]])) {
            XCTAssertEqual($0 as? LocalMessageFilterTransfer.Error, .invalidFile)
        }
        XCTAssertThrowsError(try decode(["exclusions": [["chat": ["namespace": 2, "id": "1"], "ruleIds": [UUID().uuidString]]]])) {
            XCTAssertEqual($0 as? LocalMessageFilterTransfer.Error, .invalidFile)
        }
        XCTAssertThrowsError(try LocalMessageFilterTransfer.decode(Data(count: LocalMessageFilterTransfer.maximumBytes + 1), accountPeerId: source)) {
            XCTAssertEqual($0 as? LocalMessageFilterTransfer.Error, .fileTooLarge)
        }
    }

    func testMaximumSupportedRuleSetAndExclusionsCanBeExportedAndImported() throws {
        var preferences = LocalMessageFilterPreferences()
        let pattern = String(repeating: "\\s", count: LocalMessageFilterEvaluation.maximumPatternLength / 2)
        for _ in 0 ..< LocalMessageFilterPreferences.maximumRules {
            XCTAssertTrue(preferences.upsert(LocalMessageFilterRule(pattern: pattern)))
        }
        for index in 1 ... LocalMessageFilterPreferences.maximumExcludedChats {
            let chatId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(Int64(index)))
            for rule in preferences.rules {
                XCTAssertTrue(preferences.setSharedRuleExcluded(rule.id, chatId: chatId, excluded: true))
            }
        }

        let data = try LocalMessageFilterTransfer.encode(preferences, accountPeerId: source)
        XCTAssertLessThanOrEqual(data.count, LocalMessageFilterTransfer.maximumBytes)
        XCTAssertEqual(try LocalMessageFilterTransfer.decode(data, accountPeerId: source), preferences)
    }

    func testSharedBackupUsesStableAdditiveMergeAndPreservesLocalSettings() throws {
        var current = LocalMessageFilterPreferences()
        current.isEnabled = true
        current.includesChats = true
        let existingShared = LocalMessageFilterRule(pattern: "first")
        let scoped = LocalMessageFilterRule(pattern: "second", chatId: channel)
        let unchanged = LocalMessageFilterRule(pattern: "third")
        XCTAssertTrue(current.upsert(existingShared))
        XCTAssertTrue(current.upsert(scoped))
        XCTAssertTrue(current.upsert(unchanged))
        XCTAssertTrue(current.setSharedRuleExcluded(existingShared.id, chatId: channel, excluded: true))

        let addedFirst = UUID()
        let addedLast = UUID()
        let backup = try sharedBackup([
            backupRule(id: addedFirst, pattern: "^(résumé)$", enabled: false, caseInsensitive: true),
            backupRule(id: existingShared.id, pattern: "^(one|two)$", reversed: true),
            backupRule(id: unchanged.id, pattern: unchanged.pattern),
            backupRule(id: addedLast, pattern: "last"),
        ])
        let merge = try backup.merging(into: current)
        XCTAssertEqual(merge.added, 2)
        XCTAssertEqual(merge.updated, 1)
        XCTAssertEqual(merge.preferences.rules.map(\.id), [existingShared.id, scoped.id, unchanged.id, addedFirst, addedLast])
        XCTAssertEqual(merge.preferences.rules.map(\.pattern), ["^(one|two)$", "second", "third", "^(résumé)$", "last"])
        XCTAssertTrue(merge.preferences.rules[0].isReversed)
        XCTAssertFalse(merge.preferences.rules[3].isEnabled)
        XCTAssertTrue(merge.preferences.rules[3].isCaseInsensitive)
        XCTAssertEqual(merge.preferences.excludedSharedRuleIds, current.excludedSharedRuleIds)
        XCTAssertTrue(merge.preferences.isEnabled)
        XCTAssertTrue(merge.preferences.includesChats)
        let repeatImport = try backup.merging(into: merge.preferences)
        XCTAssertEqual(repeatImport.added, 0)
        XCTAssertEqual(repeatImport.updated, 0)
        XCTAssertEqual(repeatImport.preferences, merge.preferences)
    }

    func testSharedBackupRejectsScopesCommandsUnknownFieldsAndInvalidRules() throws {
        let shared = backupRule()
        let duplicates = [shared, shared]
        let badPattern = backupRule(pattern: "(")
        let tooLong = backupRule(pattern: String(repeating: "a", count: LocalMessageFilterEvaluation.maximumPatternLength + 1))
        let badBool = shared.merging(["enabled": 1]) { _, new in new }
        let badID = shared.merging(["id": "bad"]) { _, new in new }
        let missingDialogId = shared.filter { $0.key != "dialogId" }
        let extraRuleKey = shared.merging(["action": "remove"]) { _, new in new }
        let cases: [([String: Any], LocalMessageFilterTransfer.Error)] = [
            (["version": 3], .unsupportedVersion),
            (["filters": [backupRule(dialogId: 42)]], .unsupportedSharedBackup),
            (["filters": [backupRule(dialogId: -42)]], .unsupportedSharedBackup),
            (["exclusions": [["dialogId": -42, "filterId": shared["id"]!]]], .unsupportedSharedBackup),
            (["peers": ["-42": "peer"]], .unsupportedSharedBackup),
            (["removeFiltersById": [shared["id"]!]], .unsupportedSharedBackup),
            (["removeExclusions": [["dialogId": 42, "filterId": shared["id"]!]]], .unsupportedSharedBackup),
            (["futureField": true], .invalidFile),
            (["peers": []], .invalidFile),
            (["exclusions": false], .invalidFile),
            (["filters": []], .invalidFile),
            (["filters": duplicates], .invalidFile),
            (["filters": [shared, badPattern]], .invalidFile),
            (["filters": [tooLong]], .invalidFile),
            (["filters": [badBool]], .invalidFile),
            (["filters": [badID]], .invalidFile),
            (["filters": [missingDialogId]], .invalidFile),
            (["filters": [extraRuleKey]], .invalidFile),
            (["filters": (0 ... LocalMessageFilterPreferences.maximumRules).map { _ in backupRule() }], .tooManyRules),
        ]
        for (changes, expected) in cases {
            XCTAssertThrowsError(try sharedBackup([shared], changes: changes)) {
                XCTAssertEqual($0 as? LocalMessageFilterTransfer.Error, expected, "\(changes.keys.sorted())")
            }
        }
        XCTAssertThrowsError(try LocalMessageFilterTransfer.decodeImport(Data(count: LocalMessageFilterTransfer.maximumBytes + 1), accountPeerId: source)) {
            XCTAssertEqual($0 as? LocalMessageFilterTransfer.Error, .fileTooLarge)
        }
    }

    func testMergeRejectsScopedIdentifierCollisionAndCapacityOverflow() throws {
        var current = LocalMessageFilterPreferences()
        let scoped = LocalMessageFilterRule(pattern: "scoped", chatId: channel)
        XCTAssertTrue(current.upsert(scoped))
        let backup = try sharedBackup([backupRule(), backupRule(id: scoped.id)])
        XCTAssertThrowsError(try backup.merging(into: current)) {
            XCTAssertEqual($0 as? LocalMessageFilterTransfer.Error, .sharedRuleCollision)
        }
        XCTAssertEqual(current.rules, [scoped])

        for _ in 1 ..< LocalMessageFilterPreferences.maximumRules {
            XCTAssertTrue(current.upsert(LocalMessageFilterRule(pattern: "existing")))
        }
        let overflow = try sharedBackup([backupRule()])
        XCTAssertThrowsError(try overflow.merging(into: current)) {
            XCTAssertEqual($0 as? LocalMessageFilterTransfer.Error, .tooManyRules)
        }
        XCTAssertEqual(current.rules.count, LocalMessageFilterPreferences.maximumRules)
    }

    func testNativeImportsStillUseReplacementAndAccountCheck() throws {
        var current = LocalMessageFilterPreferences()
        XCTAssertTrue(current.upsert(LocalMessageFilterRule(pattern: "native", chatId: channel)))
        let data = try LocalMessageFilterTransfer.encode(current, accountPeerId: source)
        if case let .replacement(decoded) = try LocalMessageFilterTransfer.decodeImport(data, accountPeerId: source) {
            XCTAssertEqual(decoded, current)
        } else {
            XCTFail("Expected native replacement")
        }
        XCTAssertThrowsError(try LocalMessageFilterTransfer.decodeImport(data, accountPeerId: destination)) {
            XCTAssertEqual($0 as? LocalMessageFilterTransfer.Error, .differentAccount)
        }
    }

    private func backupRule(id: UUID = UUID(), pattern: String = "notice", dialogId: Int? = nil, enabled: Bool = true, reversed: Bool = false, caseInsensitive: Bool = false) -> [String: Any] {
        ["id": id.uuidString.lowercased(), "text": pattern, "dialogId": dialogId.map { $0 as Any } ?? NSNull(),
         "enabled": enabled, "reversed": reversed, "caseInsensitive": caseInsensitive]
    }

    private func sharedBackup(_ rules: [[String: Any]], changes: [String: Any] = [:]) throws -> LocalMessageFilterTransfer.SharedRuleBackup {
        let document: [String: Any] = ["version": 2, "filters": rules, "exclusions": [], "peers": [:], "removeFiltersById": NSNull(), "removeExclusions": NSNull()]
        let data = try JSONSerialization.data(withJSONObject: document.merging(changes) { _, new in new })
        guard case let .sharedRules(backup) = try LocalMessageFilterTransfer.decodeImport(data, accountPeerId: destination) else {
            throw LocalMessageFilterTransfer.Error.invalidFile
        }
        return backup
    }
}
