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
}
