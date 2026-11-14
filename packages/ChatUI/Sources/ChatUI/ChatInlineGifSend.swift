import SwiftSignalKit
import TelegramCore

func isInlineGifResult(_ result: ChatContextResult) -> Bool {
    guard result.type == "gif", case .auto = result.message else { return false }
    switch result {
    case .externalReference:
        return true
    case let .internalReference(reference):
        guard let file = reference.file else { return false }
        return !file.isSticker && !file.isAnimatedSticker && !file.isVideoSticker
            && !file.isInstantVideo && !file.isVoice && !file.isMusic
            && (file.isAnimated || file.mimeType == "image/gif")
    }
}

final class ChatInlineGifSend {
    final class Request {
        private enum Stage { case confirmation, payment, ready, finished }
        private var stage = Stage.confirmation
        private let lifetimeObservation = MetaDisposable()
        private let isCurrent: () -> Bool
        private let finish: () -> Void

        fileprivate init(isCurrent: @escaping () -> Bool, finish: @escaping () -> Void) {
            self.isCurrent = isCurrent
            self.finish = finish
        }

        func confirm() -> Bool {
            advance(from: .confirmation, to: .payment)
        }

        func observeLifetime(_ lifetime: Signal<Bool, NoError>) {
            guard stage == .payment else { return }
            lifetimeObservation.set((lifetime |> filter { !$0 } |> take(1) |> deliverOnMainQueue).start(next: { [weak self] _ in
                self?.cancel()
            }))
        }

        func acceptPayment() -> Bool {
            advance(from: .payment, to: .ready)
        }

        func canRespondToPayment() -> Bool {
            stage == .payment
        }

        func send() -> Bool {
            guard advance(from: .ready, to: .finished) else { return false }
            lifetimeObservation.dispose()
            finish()
            return true
        }

        func cancel() {
            guard stage != .finished else { return }
            stage = .finished
            lifetimeObservation.dispose()
            finish()
        }

        deinit {
            lifetimeObservation.dispose()
        }

        private func advance(from: Stage, to: Stage) -> Bool {
            guard isAt(from) else { return false }
            stage = to
            return true
        }

        private func isAt(_ expected: Stage) -> Bool {
            guard stage == expected else { return false }
            guard isCurrent() else {
                cancel()
                return false
            }
            return true
        }
    }

    private var pending: Request?

    var isPending: Bool {
        pending != nil
    }

    func begin(isCurrent: @escaping () -> Bool) -> Request? {
        guard pending == nil else { return nil }
        let request = Request(isCurrent: isCurrent, finish: { [weak self] in self?.pending = nil })
        pending = request
        return request
    }

    func cancel() {
        pending?.cancel()
    }
}
