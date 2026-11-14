extension ChatPresentationInterfaceState.BotMenu {
    func showsComposerButton(hidesBotCommands: Bool) -> Bool {
        guard !isEmpty else { return false }
        if case .commands = menuButton {
            return !hidesBotCommands
        }
        return true
    }

    var closingComposerCommands: Self {
        guard case .commands = menuButton, revealed else { return self }
        var menu = self
        menu.revealed = false
        return menu
    }
}
