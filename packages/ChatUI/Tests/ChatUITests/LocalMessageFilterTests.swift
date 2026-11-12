import Foundation
import Postbox
import TelegramCore
import XCTest
@testable import InAppSettings

final class LocalMessageFilterTests: XCTestCase {
    private let chat = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(8))
    private let otherChat = PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(8))

    func testRuleOrderExclusionsAndExplicitChatOptInRoundTrip() throws {
        var preferences = LocalMessageFilterPreferences()
        let shared = LocalMessageFilterRule(pattern: "shared")
        let local = LocalMessageFilterRule(pattern: "local", chatId: chat)
        let other = LocalMessageFilterRule(pattern: "other", chatId: otherChat)
        let disabled = LocalMessageFilterRule(pattern: "disabled", isEnabled: false)
        for rule in [shared, local, other, disabled] {
            XCTAssertTrue(preferences.upsert(rule))
        }
        XCTAssertEqual(preferences.applicableRules(chatId: chat, isBroadcast: true), [])

        preferences.isEnabled = true
        XCTAssertEqual(preferences.applicableRules(chatId: chat, isBroadcast: true), [local, shared])
        XCTAssertEqual(preferences.applicableRules(chatId: otherChat, isBroadcast: false), [])
        XCTAssertTrue(preferences.setSharedRuleExcluded(shared.id, chatId: chat, excluded: true))
        XCTAssertFalse(preferences.setSharedRuleExcluded(local.id, chatId: chat, excluded: true))
        preferences.includesChats = true
        let reloaded = try JSONDecoder().decode(LocalMessageFilterPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(reloaded.applicableRules(chatId: chat, isBroadcast: true), [local])
        XCTAssertEqual(reloaded.applicableRules(chatId: otherChat, isBroadcast: false), [other, shared])

        preferences.remove(ruleId: shared.id)
        XCTAssertTrue(preferences.excludedSharedRuleIds.isEmpty)
    }

    func testInvalidAndOversizedPatternsAreRejected() {
        var preferences = LocalMessageFilterPreferences()
        XCTAssertFalse(preferences.upsert(LocalMessageFilterRule(pattern: "(")))
        XCTAssertFalse(preferences.upsert(LocalMessageFilterRule(pattern: "")))
        XCTAssertFalse(preferences.upsert(LocalMessageFilterRule(pattern: String(repeating: "a", count: 257))))
        XCTAssertTrue(preferences.rules.isEmpty)
    }

    func testMultilineUnicodeCaseAndReverse() throws {
        let evaluation = try XCTUnwrap(LocalMessageFilterEvaluation(milliseconds: 1000, comparisons: 16))
        evaluation.prepare([LocalMessageFilterRule(pattern: "^café$", isCaseInsensitive: true)])
        XCTAssertTrue(evaluation.shouldHide("before\nCAFÉ\nafter"))
        XCTAssertFalse(evaluation.shouldHide("CAFÉ au lait"))

        evaluation.prepare([LocalMessageFilterRule(pattern: "café", isReversed: true)])
        XCTAssertFalse(evaluation.shouldHide("café au lait"))
        XCTAssertTrue(evaluation.shouldHide("tea"))
        XCTAssertFalse(evaluation.shouldHide(""))
        XCTAssertFalse(evaluation.shouldHide(String(repeating: "a", count: 8193)))
    }

    func testPathologicalReversedPatternKeepsMessageVisibleOnFailure() throws {
        let evaluation = try XCTUnwrap(LocalMessageFilterEvaluation(milliseconds: 1000, comparisons: 4))
        evaluation.prepare([LocalMessageFilterRule(pattern: "^(a+)+$", isReversed: true)])
        XCTAssertFalse(evaluation.shouldHide(String(repeating: "a", count: 4096) + "!"))
        XCTAssertTrue(evaluation.shouldHide("!"))
    }

    func testBatchBudgetAndCancellationPreventFurtherMatches() throws {
        let evaluation = try XCTUnwrap(LocalMessageFilterEvaluation(milliseconds: 1000, comparisons: 1))
        evaluation.prepare([LocalMessageFilterRule(pattern: "spam")])
        XCTAssertTrue(evaluation.shouldHide("spam"))
        XCTAssertFalse(evaluation.canEvaluate)
        XCTAssertFalse(evaluation.shouldHide("spam"))

        evaluation.prepare([LocalMessageFilterRule(pattern: "spam")])
        evaluation.cancel()
        XCTAssertTrue(evaluation.isCancelled)
        XCTAssertFalse(evaluation.shouldHide("spam"))
    }

    func testExpiredDeadlineKeepsEvenAReversedRuleVisible() throws {
        let evaluation = try XCTUnwrap(LocalMessageFilterEvaluation(milliseconds: 0, comparisons: 16))
        evaluation.prepare([LocalMessageFilterRule(pattern: "spam", isReversed: true)])
        XCTAssertFalse(evaluation.canEvaluate)
        XCTAssertFalse(evaluation.shouldHide("other"))
    }

    func testEditingEquivalentUnicodeSpellingChangesTheStoredPattern() throws {
        let composed = LocalMessageFilterRule(pattern: "é")
        var decomposed = composed
        decomposed.pattern = "e\u{301}"
        XCTAssertNotEqual(composed, decomposed)
        var preferences = LocalMessageFilterPreferences()
        XCTAssertTrue(preferences.upsert(composed))
        let original = preferences
        XCTAssertTrue(preferences.upsert(decomposed))
        XCTAssertNotEqual(original, preferences)

        let evaluation = try XCTUnwrap(LocalMessageFilterEvaluation(milliseconds: 1000, comparisons: 8))
        evaluation.prepare(preferences.rules)
        XCTAssertTrue(evaluation.shouldHide(decomposed.pattern))
        XCTAssertFalse(evaluation.shouldHide(composed.pattern))
    }
}
