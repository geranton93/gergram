import Foundation
import InAppSettings
import SwiftSignalKit
import XCTest
@testable import ChatUI

final class ChatMediaSendConfirmationTests: XCTestCase {
    private final class Prompt {
        var accepted: (() -> Void)?
        var cancelled: (() -> Void)?
        var dismissed: (() -> Void)?
        var presentationCount = 0
        var closeCount = 0

        func present(accepted: @escaping () -> Void, cancelled: @escaping () -> Void, dismissed: @escaping () -> Void) -> () -> Void {
            presentationCount += 1
            self.accepted = accepted
            self.cancelled = cancelled
            self.dismissed = dismissed
            return { [weak self] in self?.closeCount += 1 }
        }
    }

    func testDuplicateActivationAndCallbacksSendOnlyOnce() {
        let gate = ChatMediaSendConfirmation()
        let prompt = Prompt()
        var sends = 0
        func start() {
            gate.start(lifetime: .single(true), present: prompt.present, accepted: { sends += 1 }, cancelled: {}, dismissed: {})
        }

        start()
        start()
        XCTAssertTrue(gate.isPending)
        XCTAssertEqual(prompt.presentationCount, 1)
        prompt.accepted?()
        prompt.accepted?()
        prompt.cancelled?()
        XCTAssertEqual(sends, 1)
        XCTAssertFalse(gate.isPending)
    }

    func testCancelDoesNotSendAndOldCallbackCannotConsumeNewPrompt() {
        let gate = ChatMediaSendConfirmation()
        let prompt = Prompt()
        var sends = 0
        var cancellations = 0
        func start() {
            gate.start(lifetime: .single(true), present: prompt.present, accepted: { sends += 1 },
                cancelled: { cancellations += 1 }, dismissed: {})
        }

        start()
        let oldAccept = prompt.accepted
        prompt.cancelled?()
        prompt.cancelled?()
        XCTAssertEqual(cancellations, 1)
        start()
        oldAccept?()
        XCTAssertTrue(gate.isPending)
        XCTAssertEqual(sends, 0)
        prompt.accepted?()
        XCTAssertEqual(sends, 1)
    }

    func testNavigationDismissesAndDisposesLifetimeBeforeCallback() {
        let gate = ChatMediaSendConfirmation()
        let prompt = Prompt()
        var unsubscribed = false
        let lifetime = Signal<Bool, NoError> { subscriber in
            subscriber.putNext(true)
            return ActionDisposable { unsubscribed = true }
        }
        var sends = 0
        var dismissals = 0
        gate.start(lifetime: lifetime, present: prompt.present, accepted: { sends += 1 },
            cancelled: {}, dismissed: { dismissals += 1 })
        gate.cancel()
        gate.cancel()
        prompt.accepted?()
        XCTAssertTrue(unsubscribed)
        XCTAssertEqual(prompt.closeCount, 1)
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(sends, 0)
    }

    func testInitiallyInvalidLifetimeDoesNotPresent() {
        let gate = ChatMediaSendConfirmation()
        let prompt = Prompt()
        var dismissals = 0
        gate.start(lifetime: .single(false), present: prompt.present, accepted: { XCTFail("Unexpected send") },
            cancelled: {}, dismissed: { dismissals += 1 })
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(prompt.presentationCount, 0)
        XCTAssertFalse(gate.isPending)
    }

    func testLostWindowOrAccountDismissesActivePrompt() {
        let gate = ChatMediaSendConfirmation()
        let prompt = Prompt()
        let lifetime = ValuePromise(true, ignoreRepeated: true)
        gate.start(lifetime: lifetime.get(), present: prompt.present, accepted: { XCTFail("Unexpected send") },
            cancelled: {}, dismissed: {})
        lifetime.set(false)
        prompt.accepted?()
        XCTAssertEqual(prompt.closeCount, 1)
        XCTAssertFalse(gate.isPending)
    }

    func testPromptCannotRetainItsOwner() {
        var gate: ChatMediaSendConfirmation? = ChatMediaSendConfirmation()
        weak var weakGate = gate
        let prompt = Prompt()
        gate?.start(lifetime: .single(true), present: prompt.present, accepted: { XCTFail("Unexpected send") },
            cancelled: {}, dismissed: {})
        gate = nil
        prompt.accepted?()
        XCTAssertNil(weakGate)
        XCTAssertEqual(prompt.closeCount, 1)
    }

    func testPreferencesDefaultOffPersistIndependentlyAndEmitOnlyChanges() {
        let suite = "gergram-media-send-confirmation-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Failed to create isolated UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ChatMediaSendConfirmationPreferences(defaults: defaults)
        var changes: [(Bool, Bool)] = []
        let disposable = preferences.signal.start(next: { changes.append(($0.stickers, $0.gifs)) })
        defer { disposable.dispose() }

        XCTAssertFalse(preferences.isEnabled(for: .sticker))
        XCTAssertFalse(preferences.isEnabled(for: .gif))
        preferences.set(true, for: .sticker)
        preferences.set(true, for: .sticker)
        preferences.set(true, for: .gif)
        preferences.set(false, for: .sticker)
        XCTAssertEqual(changes.map(\.0), [false, true, true, false])
        XCTAssertEqual(changes.map(\.1), [false, false, true, true])

        let reopened = ChatMediaSendConfirmationPreferences(defaults: defaults)
        XCTAssertFalse(reopened.isEnabled(for: .sticker))
        XCTAssertTrue(reopened.isEnabled(for: .gif))
    }
}
