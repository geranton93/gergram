struct StickerPackIdentifier {
    enum Kind: String {
        case stickerSet = "Gergram.StickerPack.CopyStickerSetID"
        case emojiSet = "Gergram.StickerPack.CopyEmojiSetID"
        case emoji = "Gergram.StickerPack.CopyEmojiID"
    }

    let kind: Kind
    let clipboardText: String

    init?(kind: Kind, id: Int64) {
        guard id != 0 else { return nil }
        self.kind = kind
        self.clipboardText = String(UInt64(bitPattern: id))
    }
}
