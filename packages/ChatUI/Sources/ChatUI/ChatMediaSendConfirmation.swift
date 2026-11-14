import Foundation
import SwiftSignalKit

final class ChatMediaSendConfirmation {
    typealias Present = (@escaping () -> Void, @escaping () -> Void, @escaping () -> Void) -> () -> Void

    private let lifetimeObservation = MetaDisposable()
    private var generation: UUID?
    private var dismiss: (() -> Void)?
    private var dismissed: (() -> Void)?

    deinit {
        let lifetimeObservation = self.lifetimeObservation
        let dismiss = self.dismiss
        let dismissed = self.dismissed
        Queue.mainQueue().async {
            lifetimeObservation.dispose()
            dismiss?()
            dismissed?()
        }
    }

    var isPending: Bool {
        generation != nil
    }

    func start(
        lifetime: Signal<Bool, NoError>,
        present: Present,
        accepted: @escaping () -> Void,
        cancelled: @escaping () -> Void,
        dismissed: @escaping () -> Void
    ) {
        guard !isPending else { return }
        let generation = UUID()
        self.generation = generation
        self.dismissed = dismissed

        let observation = MetaDisposable()
        lifetimeObservation.set(observation)
        observation.set((lifetime |> filter { !$0 } |> take(1) |> deliverOnMainQueue).start(next: { [weak self] _ in
            if self?.generation == generation {
                self?.cancel()
            }
        }))
        guard self.generation == generation else { return }

        let dismiss = present({ [weak self] in
            if self?.finish(generation) == true {
                accepted()
            }
        }, { [weak self] in
            if self?.finish(generation) == true {
                cancelled()
            }
        }, { [weak self] in
            Queue.mainQueue().justDispatch { [weak self] in
                if self?.finish(generation) == true {
                    dismissed()
                }
            }
        })
        if self.generation == generation {
            self.dismiss = dismiss
        } else {
            dismiss()
        }
    }

    func cancel() {
        guard let generation else { return }
        let dismiss = self.dismiss
        let dismissed = self.dismissed
        guard finish(generation) else { return }
        dismiss?()
        dismissed?()
    }

    private func finish(_ generation: UUID) -> Bool {
        guard self.generation == generation else { return false }
        self.generation = nil
        self.dismiss = nil
        self.dismissed = nil
        lifetimeObservation.set(nil)
        return true
    }
}
