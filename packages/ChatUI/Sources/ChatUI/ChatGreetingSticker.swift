import SwiftSignalKit

enum ChatGreetingSticker {
    static func suggestions<Sticker>(hidden: Signal<Bool, NoError>, load: @escaping () -> Signal<Sticker?, NoError>) -> Signal<(isHidden: Bool, sticker: Sticker?), NoError> {
        hidden |> mapToSignal { hidden -> Signal<(isHidden: Bool, sticker: Sticker?), NoError> in
            if hidden {
                return .single((true, nil))
            }
            return .single((false, nil)) |> then(load() |> map { (false, $0) })
        }
    }
}
