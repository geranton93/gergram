struct ChatTextInputState: Equatable {
    var inputText = ""
    var selectionRange = 0..<0
    var attributes: [String] = []

    func textInputState() -> Self { self }
}

struct ComposerState: Equatable {
    var inputState = ChatTextInputState()
    var messageEffect: Int?

    func withUpdatedInputState(_ input: ChatTextInputState) -> Self {
        var state = self
        state.inputState = input
        return state
    }

    func withUpdatedMessageEffect(_ effect: Int?) -> Self {
        var state = self
        state.messageEffect = effect
        return state
    }
}

final class CaptionTextView {
    var interactions = Interactions()

    struct Interactions {
        var presentation = ChatTextInputState()
    }

    func set(_ input: ChatTextInputState) { interactions.presentation = input }
    func string() -> String { interactions.presentation.inputText }
}

struct CaptionStrings {
    let mediaSenderDiscardChangesHeader = "Discard changes?"
    let mediaSenderDiscardChangesText = "The caption will be discarded."
    let mediaSenderDiscardChangesOK = "Discard"
    let modalSend = "Send"
    let modalCancel = "Cancel"
}

func strings() -> CaptionStrings { CaptionStrings() }

func verifyAlert_button(for window: Window, header: String, information: String, ok: String, successHandler: (Bool) -> Void, cancelHandler: () -> Void, onDeinit: () -> Void) {}

final class CaptionTests: XCTestCase {
    private let original = ChatTextInputState(inputText: "Original", selectionRange: 2..<4, attributes: ["bold:0..<4"])
    private let edited = ChatTextInputState(inputText: "Edited", selectionRange: 5..<5, attributes: ["italic:0..<6", "link:0..<3"])

    private func borrowedDraft() -> Controller {
        let controller = Controller()
        controller.chatInteraction.state.interfaceState = ComposerState(inputState: original, messageEffect: 42)
        controller.borrowComposerDraft()
        return controller
    }

    func testExplicitCancelRestoresEditedCaptionWithAttributesSelectionAndEffect() {
        let controller = borrowedDraft()
        XCTAssertEqual(controller.chatInteraction.presentation.interfaceState, ComposerState())
        XCTAssertEqual(controller.genericView.textView.interactions.presentation, original)
        XCTAssertEqual(controller.contextChatInteraction.presentation.interfaceState.messageEffect, 42)

        controller.genericView.textView.set(edited)
        controller.contextChatInteraction.update { $0.updatedInterfaceState { $0.withUpdatedMessageEffect(88) } }
        controller.cancelPreview()
        controller.viewWillDisappear(true)

        XCTAssertEqual(controller.chatInteraction.presentation.interfaceState, ComposerState(inputState: edited, messageEffect: 88))
        let writes = controller.chatInteraction.preferenceWrites
        controller.viewWillDisappear(true)
        XCTAssertEqual(controller.chatInteraction.preferenceWrites, writes)
    }

    func testEscapeRestoresEditedCaptionWithoutDiscardConfirmation() {
        let controller = borrowedDraft()
        controller.genericView.textView.set(edited)
        controller.close(animationType: .common)
        controller.viewWillDisappear(true)

        XCTAssertEqual(controller.closes, [.common])
        XCTAssertFalse(controller.analyticsMediaJourney?.steps.contains(.openConfirmation) ?? true)
        XCTAssertEqual(controller.chatInteraction.presentation.interfaceState.inputState, edited)
    }

    func testEmptyCaptionAndProgrammaticDismissalRestoreOriginal() {
        let empty = borrowedDraft()
        empty.genericView.textView.set(ChatTextInputState())
        empty.cancelPreview()
        empty.viewWillDisappear(true)
        XCTAssertEqual(empty.chatInteraction.presentation.interfaceState.inputState, original)

        let programmatic = borrowedDraft()
        programmatic.genericView.textView.set(edited)
        programmatic.viewWillDisappear(true)
        XCTAssertEqual(programmatic.chatInteraction.presentation.interfaceState.inputState, original)
    }

    func testNewerComposerDraftWinsEvenWhenItHasBeenCleared() {
        for newer in [edited, ChatTextInputState()] {
            let controller = borrowedDraft()
            controller.genericView.textView.set(edited)
            controller.chatInteraction.update { $0.updatedInterfaceState { $0.withUpdatedInputState(self.original) } }
            controller.chatInteraction.update { $0.updatedInterfaceState { $0.withUpdatedInputState(newer) } }
            let writes = controller.chatInteraction.preferenceWrites

            controller.cancelPreview()
            controller.viewWillDisappear(true)

            XCTAssertEqual(controller.chatInteraction.presentation.interfaceState.inputState, newer)
            XCTAssertEqual(controller.chatInteraction.preferenceWrites, writes)
        }
    }

    func testDetachedComposeContextConsumesRestore() {
        let controller = borrowedDraft()
        var isCurrent = true
        XCTAssertTrue(controller.bindSendSourceValidation { isCurrent })
        controller.genericView.textView.set(edited)
        isCurrent = false
        controller.cancelPreview()
        controller.viewWillDisappear(true)
        XCTAssertEqual(controller.chatInteraction.presentation.interfaceState, ComposerState())

        isCurrent = true
        controller.viewWillDisappear(true)
        XCTAssertEqual(controller.chatInteraction.presentation.interfaceState, ComposerState())
    }

    func testSendConsumesBorrowedDraft() {
        let controller = borrowedDraft()
        controller.genericView.textView.set(edited)
        controller.makeSubmission()(nil)
        XCTAssertTrue(controller.sent)
        controller.viewWillDisappear(true)

        XCTAssertEqual(controller.chatInteraction.presentation.interfaceState, ComposerState())
    }

    func testSuppliedCaptionLeavesComposeDraftAndEffectIntact() {
        let controller = Controller()
        let composer = ComposerState(inputState: original, messageEffect: 42)
        controller.chatInteraction.state.interfaceState = composer
        controller.genericView.textView.set(edited)
        controller.cancelPreview()
        controller.viewWillDisappear(true)

        XCTAssertEqual(controller.chatInteraction.presentation.interfaceState, composer)
        XCTAssertEqual(controller.chatInteraction.preferenceWrites, 0)
    }
}
