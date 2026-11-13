import AppKit
import InAppSettings
import TGUIKit

enum ChatCodeFont {
    static func resolve(_ choice: ChatMonospaceFont, size: CGFloat, find: (String, CGFloat) -> NSFont? = { NSFont(name: $0, size: $1) }) -> NSFont {
        let name: String
        switch choice {
        case .system: return .code(size)
        case .menlo: name = "Menlo-Regular"
        case .monaco: name = "Monaco"
        }
        guard let font = find(name, size), font.isFixedPitch else {
            return .code(size)
        }
        return font
    }
}
