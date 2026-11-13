enum ChatMediaSpoilerPresentation: Equatable {
    case visible
    case covered
    case previewOnly

    init(
        hasSpoiler: Bool, requiresCover: Bool, isExplicitlyRevealed: Bool?,
        revealsOrdinarySpoilers: Bool, isEligibleForPreview: Bool
    ) {
        guard isExplicitlyRevealed == false, hasSpoiler || requiresCover else {
            self = .visible
            return
        }
        if revealsOrdinarySpoilers, isEligibleForPreview, !requiresCover {
            self = .previewOnly
        } else {
            self = .covered
        }
    }
}
