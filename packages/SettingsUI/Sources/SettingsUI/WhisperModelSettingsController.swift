import AlertsUI
import ApiCredentials
import AppKit
import GeneralRows
import InputDataUI
import Localization
import SpeechModelSupport
import SwiftSignalKit
import TelegramTheme
import TGUIKit

private typealias Model = SpeechModelArtifact.Model

private let supportedModels: [Model] = [.whisperTiny, .whisperBase, .whisperSmall]

private func modelTitle(_ model: Model) -> String {
    switch model {
    case .whisperTiny: return localizedString("Gergram.WhisperModels.Tiny")
    case .whisperBase: return localizedString("Gergram.WhisperModels.Base")
    case .whisperSmall: return localizedString("Gergram.WhisperModels.Small")
    }
}

@available(macOS 10.15, *)
private final class WhisperModelSettingsSession {
    enum Operation: Equatable {
        case check
        case install(Model)
        case remove(Model)
    }

    struct State: Equatable {
        var statuses: [Model: WhisperModelAcquisition.Status] = [:]
        var operation: Operation?
        var isCancelling = false

        func canImport(_ model: Model) -> Bool {
            statuses[model] == .missing || statuses[model] == .unverified
        }

        func canRemove(_ model: Model) -> Bool {
            statuses[model] == .verified || statuses[model] == .unverified
        }
    }

    private let acquisition: WhisperModelAcquisition
    private(set) var state = State()
    private(set) lazy var updates = ValuePromise(state, ignoreRepeated: true)
    private weak var window: Window?
    private var picker: NSOpenPanel?
    private var confirmation: UUID?
    private var dismissConfirmation: (() -> Void)?
    private var cancelWork: WhisperModelAcquisition.Cancel?
    private var needsRefresh = false

    init(acquisition: WhisperModelAcquisition) {
        self.acquisition = acquisition
    }

    deinit {
        cancelWork?()
    }

    func appear(in window: Window?) {
        self.window = window
        needsRefresh = window != nil
        refresh()
    }

    func disappear() {
        window = nil
        needsRefresh = false
        confirmation = nil
        let dismiss = dismissConfirmation
        dismissConfirmation = nil
        dismiss?()
        let panel = picker
        picker = nil
        panel?.cancel(nil)
        cancel()
    }

    func chooseFile(for model: Model) {
        guard canBegin, let window, state.canImport(model) else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = false
        panel.appearance = theme.appearance
        panel.prompt = localizedString("Gergram.WhisperModels.Import")
        if let artifact = try? WhisperModelCatalog.artifact(for: model) {
            panel.message = translate(key: "Gergram.WhisperModels.ChooseFile", [artifact.sourceURL.lastPathComponent])
        }
        picker = panel
        panel.beginSheetModal(for: window) { [weak self, weak panel, weak window] response in
            guard let self, let panel, self.picker === panel else { return }
            self.picker = nil
            guard response == .OK, let file = panel.url, let window, self.window === window, self.canBegin else { return }
            self.mutate(.install(model), model: model) { completion in
                self.acquisition.importModel(from: file, for: model, completion: completion)
            }
        }
    }

    func confirmRemoval(of model: Model) {
        guard canBegin, let window, state.canRemove(model) else { return }
        let identifier = UUID()
        confirmation = identifier
        let data = ModalAlertData(title: translate(key: "Gergram.WhisperModels.ConfirmRemoval", [modelTitle(model)]),
                                  info: localizedString("Gergram.WhisperModels.RemoveInfo"),
                                  ok: localizedString("Gergram.WhisperModels.Remove"),
                                  mode: .confirm(text: strings().alertCancel, isThird: false))
        dismissConfirmation = showDismissableModalAlert(for: window, data: data, completion: { [weak self] _ in
            guard let self, self.confirmation == identifier else { return }
            self.confirmation = nil
            self.dismissConfirmation = nil
            guard self.canBegin, self.state.canRemove(model) else { return }
            self.mutate(.remove(model), model: model) { completion in
                self.acquisition.removeModel(model, completion: completion)
            }
        }, onDeinit: { [weak self] in
            if self?.confirmation == identifier {
                self?.confirmation = nil
                self?.dismissConfirmation = nil
            }
        })
    }

    func cancel() {
        guard let cancelWork, !state.isCancelling else { return }
        state.isCancelling = true
        updates.set(state)
        cancelWork()
    }

    func retryStatusCheck() {
        needsRefresh = true
        refresh()
    }

    private var canBegin: Bool {
        window != nil && picker == nil && confirmation == nil && state.operation == nil
    }

    private func begin(_ operation: Operation) {
        state.operation = operation
        updates.set(state)
    }

    private func finish() -> Bool {
        let wasCancelling = state.isCancelling
        cancelWork = nil
        state.operation = nil
        state.isCancelling = false
        return wasCancelling
    }

    private func refresh() {
        guard needsRefresh, canBegin else { return }
        needsRefresh = false
        begin(.check)
        cancelWork = acquisition.modelStatuses(supportedModels) { [weak self] result in
            guard let self else { return }
            _ = self.finish()
            switch result {
            case let .success(statuses):
                self.state.statuses = statuses
            case .failure(.cancelled):
                break
            case .failure:
                self.state.statuses = Dictionary(uniqueKeysWithValues: supportedModels.map { ($0, .unavailable) })
            }
            self.updates.set(self.state)
            self.refresh()
        }
    }

    private func mutate(
        _ operation: Operation, model: Model,
        run: (@escaping WhisperModelAcquisition.Completion) -> WhisperModelAcquisition.Cancel
    ) {
        begin(operation)
        cancelWork = run { [weak self] result in
            guard let self else { return }
            let wasCancelling = self.finish()
            switch result {
            case .success:
                self.state.statuses[model] = operation == .install(model) ? .verified : .missing
            case .failure(.cancelled):
                break
            case let .failure(error):
                if let window = self.window, !wasCancelling {
                    showModalText(for: window, text: localizedString(Self.errorKey(error)))
                }
            }
            self.updates.set(self.state)
            self.refresh()
        }
    }

    private static func errorKey(_ error: WhisperModelAcquisition.Failure) -> String {
        switch error {
        case .busy: return "Gergram.WhisperModels.Error.Busy"
        case .modelDoesNotMatch: return "Gergram.WhisperModels.Error.Mismatch"
        case .fileChanged: return "Gergram.WhisperModels.Error.Changed"
        case .invalidFile, .unableToAccessFile: return "Gergram.WhisperModels.Error.File"
        case .insufficientStorage: return "Gergram.WhisperModels.Error.Storage"
        case .cancelled, .unableToUseCache: return "Gergram.WhisperModels.Error.Cache"
        }
    }
}

@available(macOS 10.15, *)
private func statusTitle(_ model: Model, state: WhisperModelSettingsSession.State) -> String {
    if state.operation == .check { return localizedString("Gergram.WhisperModels.Checking") }
    if state.operation == .install(model) || state.operation == .remove(model) {
        if state.isCancelling { return localizedString("Gergram.WhisperModels.Cancelling") }
        return localizedString(state.operation == .install(model) ? "Gergram.WhisperModels.Verifying" : "Gergram.WhisperModels.Removing")
    }
    switch state.statuses[model] {
    case .verified: return localizedString("Gergram.WhisperModels.Verified")
    case .missing: return localizedString("Gergram.WhisperModels.Missing")
    case .unverified: return localizedString("Gergram.WhisperModels.Unverified")
    case .unavailable: return localizedString("Gergram.WhisperModels.Unavailable")
    case nil: return localizedString("Gergram.WhisperModels.Checking")
    }
}

func whisperModelSettingsController() -> InputDataController? {
    guard #available(macOS 10.15, *), let container = ApiEnvironment.containerURL else { return nil }
    let session = WhisperModelSettingsSession(acquisition: WhisperModelAcquisition(appContainer: container))
    let signal = combineLatest(queue: prepareQueue, session.updates.get(), appearanceSignal)
    |> map { [weak session] state, appearance in
        let colors = appearance.presentation.colors
        var section: Int32 = 1
        var entries: [InputDataEntry] = [.sectionId(0, type: .normal)]
        entries.append(.desc(sectionId: section, index: Int32(entries.count), text: .plain(localizedString("Gergram.WhisperModels.Hint")),
                             data: .init(color: colors.listGrayText, viewType: .textTopItem)))
        for model in supportedModels {
            let identifier = model.rawValue
            let status = statusTitle(model, state: state)
            let byteCount = (try? WhisperModelCatalog.artifact(for: model))?.byteCount
            let size = byteCount.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            let canImport = state.canImport(model)
            let canRemove = state.canRemove(model)
            let enabled = state.operation == nil

            entries.append(.general(sectionId: section, index: Int32(entries.count), value: .none, error: nil, identifier: .init(identifier),
                                    data: .init(name: modelTitle(model), color: colors.text, type: .context(status), viewType: canImport || canRemove ? .firstItem : .singleItem,
                                                enabled: false, description: size)))
            if canImport {
                entries.append(.general(sectionId: section, index: Int32(entries.count), value: .none, error: nil, identifier: .init(identifier + "-import"),
                                        data: .init(name: localizedString("Gergram.WhisperModels.Import"), color: colors.accent, viewType: canRemove ? .innerItem : .lastItem,
                                                    enabled: enabled, action: { [weak session] in session?.chooseFile(for: model) })))
            }
            if canRemove {
                entries.append(.general(sectionId: section, index: Int32(entries.count), value: .none, error: nil, identifier: .init(identifier + "-remove"),
                                        data: .init(name: localizedString("Gergram.WhisperModels.Remove"), color: colors.redUI, viewType: .lastItem,
                                                    enabled: enabled, action: { [weak session] in session?.confirmRemoval(of: model) })))
            }
            entries.append(.sectionId(section, type: .normal))
            section += 1
        }
        if let operation = state.operation, operation != .check {
            entries.append(.general(sectionId: section, index: Int32(entries.count), value: .none, error: nil, identifier: .init("whisper-model-cancel"),
                                    data: .init(name: localizedString("Gergram.WhisperModels.CancelOperation"), color: colors.accent, viewType: .singleItem,
                                                enabled: !state.isCancelling, action: { [weak session] in session?.cancel() })))
        } else if state.operation == nil, state.statuses.values.contains(.unavailable) {
            entries.append(.general(sectionId: section, index: Int32(entries.count), value: .none, error: nil, identifier: .init("whisper-model-retry"),
                                    data: .init(name: localizedString("Gergram.WhisperModels.Retry"), color: colors.accent, viewType: .singleItem,
                                                action: { [weak session] in session?.retryStatusCheck() })))
        }
        return InputDataSignalValue(entries: entries, animated: false)
    }
    let controller = InputDataController(dataSignal: signal, title: localizedString("Gergram.WhisperModels"), hasDone: false)
    controller.contextObject = session
    controller.didAppear = { [weak session] controller in session?.appear(in: controller.window) }
    controller.willDisappear = { [weak session] _ in session?.disappear() }
    return controller
}
