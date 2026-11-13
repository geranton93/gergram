import AlertsUI
import AppKit
import LocalAnimations
import Localization
import MessageUtils
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramCore
import TelegramMediaUtils
import TelegramUtils
import TGUIKit

final class ChatReceivedAudioTranscriptionAction {
    private typealias Failure = ChatReceivedAudioTranscription.Failure

    private struct Source {
        let message: Message
        let file: TelegramMediaFile
        let size: Int64?
    }

    private let operation = MetaDisposable()
    private var generation: UUID?
    private weak var transcriptSheet: NSWindow?

    deinit {
        operation.dispose()
    }

    func cancel() {
        generation = nil
        operation.set(nil)
        if let sheet = transcriptSheet, let parent = sheet.sheetParent {
            parent.endSheet(sheet)
        }
        transcriptSheet = nil
    }

    static func menuItem(for message: Message, cachedData: CachedPeerData?, interaction: ChatInteraction) -> ContextMenuItem? {
        guard #available(macOS 10.15, *), supportsChat(interaction),
              !interaction.presentation.searchMode.inSearch,
              message.id.peerId == interaction.peerId,
              let peer = message.peers[message.id.peerId] ?? interaction.peer,
              let source = source(for: message, peer: peer, cachedData: cachedData, accountPeerId: interaction.interactionContext.peerId) else {
            return nil
        }
        let id = message.id
        let location = interaction.chatLocation
        let mode = interaction.mode
        let resourceId = source.file.resource.id
        return ContextMenuItem(localizedString("Gergram.Chat.LocalSpeech.Action"), handler: { [weak interaction] in
            guard let interaction, interaction.chatLocation == location, interaction.mode == mode,
                  !interaction.presentation.searchMode.inSearch,
                  supportsChat(interaction) else { return }
            interaction.receivedAudioTranscription.start(id: id, resourceId: resourceId, interaction: interaction)
        }, itemImage: MenuAnimation.menu_voice.value)
    }

    private static func supportsChat(_ interaction: ChatInteraction) -> Bool {
        return interaction.supportsLocalMessageVisibility && interaction.canAnimateUpdates()
            && !interaction.interactionContext.isFrozen
            && interaction.presentation.state != .selecting && interaction.presentation.reportMode == nil
            && !interaction.presentation.isNotAccessible
    }

    private static func source(for message: Message, peer: Peer, cachedData: CachedPeerData?, accountPeerId: PeerId) -> Source? {
        let id = message.id
        guard id.namespace == Namespaces.Message.Cloud, id.id > 0, id.peerId == peer.id,
              id.peerId.namespace != Namespaces.Peer.SecretChat, id.peerId != accountPeerId,
              id.peerId.namespace != Namespaces.Peer.CloudUser || cachedData is CachedUserData,
              message.effectivelyIncoming(accountPeerId), message.adAttribute == nil,
              !message.flags.contains(.Sending), !message.flags.contains(.Unsent), !message.flags.contains(.Failed),
              !message.isCopyProtected(cachedData: cachedData), !peer.isCopyProtectionEnabled,
              !peer.isCopyProtected(cachedData: cachedData), !message.containsSecretMedia,
              message.autoclearTimeout == nil, message.autoremoveAttribute == nil,
              message.activeEphemeralReplacementMessage == nil, message.paidContent == nil,
              !message.attributes.contains(where: { $0 is EphemeralMessageAttribute || $0 is RestrictedContentMessageAttribute }),
              let file = message.media.first as? TelegramMediaFile, file.isVoice || file.isInstantVideo,
              let resource = file.resource as? CloudDocumentMediaResource else { return nil }
        let size = [file.size, resource.size].compactMap { $0 }.max()
        return Source(message: message, file: file, size: size)
    }

    @available(macOS 10.15, *)
    private func start(id: MessageId, resourceId: MediaResourceId, interaction: ChatInteraction) {
        let context = interaction.interactionContext
        let window = context.window
        guard window.isVisible, window.attachedSheet == nil || window.attachedSheet === transcriptSheet else { return }
        cancel()
        let generation = UUID()
        self.generation = generation
        let location = interaction.chatLocation
        let mode = interaction.mode
        let isCurrent: () -> Bool = { [weak self, weak interaction, weak window] in
            guard let self, let interaction, let window else { return false }
            return self.generation == generation && context.window === window && window.isVisible
                && interaction.chatLocation == location && interaction.mode == mode && Self.supportsChat(interaction)
        }
        let source = context.account.postbox.transaction { transaction -> Source? in
            guard let current = transaction.getMessage(id), let peer = transaction.getPeer(id.peerId),
                  let source = Self.source(for: current, peer: peer, cachedData: transaction.getPeerCachedData(peerId: id.peerId), accountPeerId: context.peerId),
                  source.file.resource.id == resourceId else { return nil }
            return source
        } |> deliverOnMainQueue
        let currentSource: Signal<Source, Failure> = source |> castError(Failure.self) |> mapToSignal { source in
            guard isCurrent() else { return .fail(.cancelled) }
            guard let source else { return .fail(.mediaUnavailable) }
            do {
                try ChatReceivedAudioTranscription.validateMetadata(size: source.size, duration: source.file.duration.map { Double($0) })
                return .single(source)
            } catch {
                return .fail(error as? Failure ?? .mediaUnavailable)
            }
        }

        let signal = currentSource
        |> mapToSignal { _ -> Signal<String, Failure> in
            let preferences = Locale.preferredLanguages + [Locale.current.identifier]
            guard let recognizer = ChatReceivedAudioTranscription.recognizer(selection: ChatInputDictationLanguage.selected, preferredLanguages: preferences) else {
                return .fail(.unavailable)
            }
            return requestSpeechRecognitionPermission()
            |> castError(Failure.self)
            |> mapToSignal { allowed -> Signal<String, Failure> in
                guard isCurrent() else { return .fail(.cancelled) }
                guard allowed else { return .fail(.denied) }
                return currentSource |> mapToSignal { current -> Signal<String, Failure> in
                    return Self.path(for: current, account: context.account)
                    |> mapToSignal { path -> Signal<String, Failure> in
                        return currentSource |> mapToSignal { _ -> Signal<String, Failure> in
                            return ChatReceivedAudioTranscription.recognize(path: path, using: recognizer)
                        }
                    }
                }
            }
        }
        |> mapToSignal { text -> Signal<String, Failure> in
            return currentSource |> map { _ in text }
        }
        |> SwiftSignalKit.timeout(120, queue: Queue.mainQueue(), alternate: .fail(.timedOut))

        let request = MetaDisposable()
        operation.set(request)
        request.set(showModalProgress(signal: signal, for: window, shouldPresent: {
            isCurrent() && window.attachedSheet == nil
        }).start(next: { [weak self] text in
            DispatchQueue.main.async { [weak self] in
                guard let self, isCurrent() else { return }
                self.showTranscript(text, for: window)
            }
        }, error: { error in
            guard isCurrent(), let text = Self.errorText(error) else { return }
            alert(for: window, header: localizedString("Gergram.Chat.LocalSpeech.Title"), info: text)
        }))
    }

    private static func path(for source: Source, account: Account) -> Signal<String, Failure> {
        let mediaBox = account.postbox.mediaBox
        let file = source.file
        let data = mediaBox.resourceData(file.resource)
        return data |> take(1) |> castError(Failure.self) |> mapToSignal { initial -> Signal<String, Failure> in
            if initial.complete {
                return checkedPath(initial)
            }
            guard let size = source.size, size > 0, size <= ChatReceivedAudioTranscription.maximumBytes else {
                return .fail(.tooLong)
            }
            return Signal { subscriber in
                let disposables = DisposableSet()
                let reference = FileMediaReference.message(message: MessageReference(source.message), media: file)
                let fetch = fetchedMediaResource(mediaBox: mediaBox, userLocation: reference.userLocation, userContentType: reference.userContentType,
                    reference: reference.resourceReference(file.resource), range: (0..<size, .default), statsCategory: file.isInstantVideo ? .video : .audio)
                disposables.add(fetch.start(error: { _ in subscriber.putError(.mediaUnavailable) }, completed: {
                    disposables.add((data |> take(1)).start(next: { final in
                        if !final.complete {
                            subscriber.putError(.mediaUnavailable)
                        }
                    }))
                }))
                disposables.add((data |> filter { $0.complete } |> take(1) |> castError(Failure.self) |> mapToSignal(checkedPath)).start(
                    next: subscriber.putNext, error: subscriber.putError, completed: subscriber.putCompletion
                ))
                return disposables
            }
        }
    }

    private static func checkedPath(_ data: MediaResourceData) -> Signal<String, Failure> {
        do {
            try ChatReceivedAudioTranscription.validateMetadata(size: data.size, duration: nil)
            return .single(data.path)
        } catch {
            return .fail(error as? Failure ?? .mediaUnavailable)
        }
    }

    private func showTranscript(_ text: String, for window: Window) {
        guard window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = localizedString("Gergram.Chat.LocalSpeech.Title")
        alert.addButton(withTitle: strings().modalOK)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.string = text
        scrollView.documentView = textView
        alert.accessoryView = scrollView

        let sheet = alert.window
        transcriptSheet = sheet
        alert.beginSheetModal(for: window) { [weak self, weak sheet] _ in
            if self?.transcriptSheet === sheet {
                self?.transcriptSheet = nil
            }
        }
    }

    private static func errorText(_ error: Failure) -> String? {
        let key: String
        switch error {
        case .unavailable: key = "Unavailable"
        case .denied: key = "Denied"
        case .mediaUnavailable: key = "MediaUnavailable"
        case .tooLong: key = "TooLong"
        case .failed: key = "Failed"
        case .timedOut: key = "TimedOut"
        case .cancelled: return nil
        }
        return localizedString("Gergram.Chat.LocalSpeech." + key)
    }
}
