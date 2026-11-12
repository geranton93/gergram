import AppKit

enum ChatMessageContextMenuModifier {
    static func isExtended(_ modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let flags = modifierFlags.intersection([.shift, .command, .option, .control])
        return flags == .shift || flags == .command
    }
}
