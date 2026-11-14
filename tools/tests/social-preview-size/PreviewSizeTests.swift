import Foundation

struct ImageRepresentation {
    var dimensions: Dimensions
}
struct Dimensions {
    var size: CGSize
    init(_ width: CGFloat, _ height: CGFloat) { size = CGSize(width: width, height: height) }
}
struct Image { var representations = [ImageRepresentation(dimensions: Dimensions(640, 480))] }
struct File { var isVideo = true; var dimensions: Dimensions? = Dimensions(640, 480) }
func largestImageRepresentation(_ images: [ImageRepresentation]) -> ImageRepresentation? {
    images.max { $0.dimensions.size.width < $1.dimensions.size.width }
}
extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct TelegramMediaWebpageLoadedContent {
    enum Attribute { case stickerPack, starGift, giftCollection, giftAuction, aiTextStyle, other }
    var url = "https://x.com/a/status/123"
    var image: Image? = Image()
    var file: File?
    var type: String? = "article"
    var story: Int?
    var attributes: [Attribute] = []
    var isMediaLargeByDefault: Bool?
    var text: String? = "A post"
    var websiteName: String? = "Other"
    var instantPage: Int?
}

__MEDIA_POLICY__

struct HistoryArticle {
    struct Parent {
        struct PreviewAttribute { var forceLargeMedia: Bool? }
        var webpagePreviewAttribute: PreviewAttribute?
    }

    var content: TelegramMediaWebpageLoadedContent
    var parent: Parent
    var imageSize: CGSize?
    var adAttribute: Int?
    var isLoadingStory = false
    var isSocialPost: Bool { SocialPostPreview.prefersLargeMedia(for: content) }

    init(_ content: TelegramMediaWebpageLoadedContent, explicitSize: Bool? = nil, adAttribute: Int? = nil) {
        self.content = content
        self.parent = Parent(webpagePreviewAttribute: .init(forceLargeMedia: explicitSize))
        self.imageSize = content.file?.dimensions?.size
            ?? content.image.flatMap { largestImageRepresentation($0.representations)?.dimensions.size }
        self.adAttribute = adAttribute
    }

    __HISTORY_SIZE__
}

struct Preview {
    enum Content { case Pending, Loaded(TelegramMediaWebpageLoadedContent) }
    var webpageId = 1
    var content: Content
}
struct Peer { var id = 1; var webUrlRestricted = false }
struct ChatPresentationInterfaceState {
    struct Interface {
        struct Edit {
            struct Message { var id = 1 }
            var message = Message()
        }
        var editState: Edit?
        var largeMedia: Bool?
        var composeDisableUrlPreview: String?
        var suggestPost: Int?

        func withUpdatedLargeMedia(_ largeMedia: Bool) -> Self {
            var updated = self
            updated.largeMedia = largeMedia
            return updated
        }
    }
    var peer: Peer? = Peer()
    var urlPreview: (String, Preview)?
    var interfaceState = Interface()

    func updatedInterfaceState(_ update: (Interface) -> Interface) -> Self {
        var updated = self
        updated.interfaceState = update(interfaceState)
        return updated
    }
}
final class ChatInteraction {
    var presentation: ChatPresentationInterfaceState
    init(_ presentation: ChatPresentationInterfaceState) { self.presentation = presentation }
    func update(_ update: (ChatPresentationInterfaceState) -> ChatPresentationInterfaceState) {
        presentation = update(presentation)
    }
}
final class Composer {
    let chatInteraction: ChatInteraction
    init(_ state: ChatPresentationInterfaceState) { chatInteraction = ChatInteraction(state) }

    func menu(for state: ChatPresentationInterfaceState) -> (selected: (ChatPresentationInterfaceState) -> Bool?, choose: (Bool) -> Void) {
        let urlPreview = state.urlPreview!
        __COMPOSER_SIZE__
        return (currentLinkSize, toggleLinkSize)
    }
}

func state(_ content: TelegramMediaWebpageLoadedContent) -> ChatPresentationInterfaceState {
    ChatPresentationInterfaceState(urlPreview: (content.url, Preview(content: .Loaded(content))))
}

for serverDefault: Bool? in [false, nil, true] {
    let article = TelegramMediaWebpageLoadedContent(isMediaLargeByDefault: serverDefault)
    let initial = state(article)
    let composer = Composer(initial)
    let menu = composer.menu(for: initial)
    precondition(menu.selected(initial) == true)
    precondition(HistoryArticle(article).isFullImageSize)
    menu.choose(false)
    precondition(menu.selected(composer.chatInteraction.presentation) == false)
    precondition(HistoryArticle(article, explicitSize: composer.chatInteraction.presentation.interfaceState.largeMedia).isFullImageSize == false)
    menu.choose(true)
    precondition(menu.selected(composer.chatInteraction.presentation) == true)
}
print("PASS composer and history agree on the social default and explicit compact override")

let ordinary = TelegramMediaWebpageLoadedContent(url: "https://example.org/article", isMediaLargeByDefault: false)
let small = TelegramMediaWebpageLoadedContent(image: Image(representations: [ImageRepresentation(dimensions: Dimensions(199, 800))]))
let empty = TelegramMediaWebpageLoadedContent(image: nil)
let invalid = TelegramMediaWebpageLoadedContent(image: nil, file: File(dimensions: Dimensions(400, 0)))
let infinite = TelegramMediaWebpageLoadedContent(image: nil, file: File(dimensions: Dimensions(.infinity, 800)))
let film = TelegramMediaWebpageLoadedContent(image: nil, file: File())
let poster = TelegramMediaWebpageLoadedContent(file: File(dimensions: nil))
let unusableFileWithPoster = TelegramMediaWebpageLoadedContent(file: File(dimensions: Dimensions(150, 800)))
for article in [small, empty, invalid, infinite, unusableFileWithPoster] {
    precondition(SocialPostPreview.selectedMediaSize(for: article, explicitSize: nil) == nil)
    precondition(!HistoryArticle(article).isFullImageSize)
}
for article in [film, poster] {
    precondition(SocialPostPreview.selectedMediaSize(for: article, explicitSize: nil) == true)
    precondition(HistoryArticle(article).isFullImageSize)
}
precondition(SocialPostPreview.selectedMediaSize(for: ordinary, explicitSize: nil) == false)
precondition(SocialPostPreview.selectedMediaSize(for: ordinary, explicitSize: true) == true)
precondition(!HistoryArticle(ordinary).isFullImageSize)
precondition(HistoryArticle(ordinary, explicitSize: true).isFullImageSize)
print("PASS ordinary previews, image/video dimensions, and missing media preserve native policy")

for article in [
    TelegramMediaWebpageLoadedContent(type: "telegram_user"),
    TelegramMediaWebpageLoadedContent(type: "telegram_ad"),
    TelegramMediaWebpageLoadedContent(story: 1),
    TelegramMediaWebpageLoadedContent(attributes: [.stickerPack]),
    TelegramMediaWebpageLoadedContent(attributes: [.giftAuction])
] {
    precondition(!SocialPostPreview.prefersLargeMedia(for: article))
}
precondition(!HistoryArticle(TelegramMediaWebpageLoadedContent(), adAttribute: 1).isFullImageSize)
print("PASS story, account, ad and special layouts do not inherit social sizing")

let initial = state(TelegramMediaWebpageLoadedContent())
for change in ["url", "webpage", "pending", "edit", "removed", "peer", "restricted", "suggestion"] {
    let composer = Composer(initial)
    let menu = composer.menu(for: initial)
    switch change {
    case "url": composer.chatInteraction.presentation.urlPreview?.0 = "https://x.com/a/status/456"
    case "webpage": composer.chatInteraction.presentation.urlPreview?.1.webpageId = 2
    case "pending": composer.chatInteraction.presentation.urlPreview?.1.content = .Pending
    case "edit": composer.chatInteraction.presentation.interfaceState.editState = .init()
    case "removed": composer.chatInteraction.presentation.interfaceState.composeDisableUrlPreview = initial.urlPreview?.0
    case "peer": composer.chatInteraction.presentation.peer?.id = 2
    case "restricted": composer.chatInteraction.presentation.peer?.webUrlRestricted = true
    case "suggestion": composer.chatInteraction.presentation.interfaceState.suggestPost = 1
    default: fatalError()
    }
    menu.choose(false)
    precondition(menu.selected(composer.chatInteraction.presentation) == nil)
    precondition(composer.chatInteraction.presentation.interfaceState.largeMedia == nil, change)
}
print("PASS retained menu cannot change a different or disabled preview")
