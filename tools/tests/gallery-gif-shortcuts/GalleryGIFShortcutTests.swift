import AppKit

enum KeyboardKey: UInt16 {
    case K = 40
    case Space = 49

    var character: String { self == .K ? "k" : " " }
}

enum KeyHandlerResult {
    case invoked, rejected
}

enum HandlerPriority {
    case low
}

final class TestWindow {
    var hasModal = false
    var handlers: [KeyboardKey: (NSEvent) -> KeyHandlerResult] = [:]

    func set(handler: @escaping (NSEvent) -> KeyHandlerResult, with object: NSObject, for key: KeyboardKey, priority: HandlerPriority, modifierFlags: NSEvent.ModifierFlags?) {
        handlers[key] = handler
    }

    func send(_ key: KeyboardKey, flags: NSEvent.ModifierFlags = [], repeating: Bool = false) -> KeyHandlerResult {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: key.character, charactersIgnoringModifiers: key.character, isARepeat: repeating, keyCode: key.rawValue)!
        return handlers[key]!(event)
    }
}

func hasModals(_ window: TestWindow) -> Bool { window.hasModal }

__KEYBOARD__

struct Message {
    var autoclearTimeout: Int?
    func isCopyProtected(cachedData: Bool) -> Bool { cachedData }
}

struct Entry {
    var isProtected = false
    var message: Message? = Message()
}

struct File {
    var isVideo = true
    var isAnimated = true
}

class MGalleryItem {
    var entry = Entry()
    private(set) var toggles = 0
    func togglePlayerOrPause() { toggles += 1 }
}

final class MediaPlayer {
    private(set) var toggles = 0
    func togglePlayPause() { toggles += 1 }
}

final class MGalleryGIFItem: MGalleryItem {
    let mediaPlayer = MediaPlayer()
    var file = File()
    private(set) var mediaReads = 0
    var media: File {
        mediaReads += 1
        return file
    }
    __TOGGLE__
}

final class MGalleryVideoItem: MGalleryItem {}
final class MGalleryExternalVideoItem: MGalleryItem {}
final class Pager { var selectedItem: MGalleryItem? }
final class Interactions {
    private(set) var dismissals = 0
    func dismiss(_ event: NSEvent) -> KeyHandlerResult {
        dismissals += 1
        return .invoked
    }
}

final class Gallery: NSObject {
    enum GalleryType { case history, secret }
    let window = TestWindow()
    let pager = Pager()
    let interactions = Interactions()
    var type = GalleryType.history
    var cachedPeerData = false

    override init() {
        super.init()
        __REGISTRATION__
    }

    __SHORTCUT__
}

let gallery = Gallery()
let gif = MGalleryGIFItem()
gallery.pager.selectedItem = gif

for key: KeyboardKey in [.Space, .K] {
    let count = gif.mediaPlayer.toggles
    precondition(gallery.window.send(key) == .invoked)
    precondition(gallery.window.send(key, repeating: true) == .invoked)
    precondition(gif.mediaPlayer.toggles == count + 1)
}
precondition(gallery.interactions.dismissals == 0)

for flag: NSEvent.ModifierFlags in [.command, .option, .control, .shift, .function] {
    precondition(gallery.window.send(.K, flags: flag) == .rejected)
}
precondition(gif.mediaPlayer.toggles == 2)

gallery.window.hasModal = true
for key: KeyboardKey in [.Space, .K] {
    precondition(gallery.window.send(key) == .rejected)
}
precondition(gif.mediaPlayer.toggles == 2 && gallery.interactions.dismissals == 0)
gallery.window.hasModal = false

let reads = gif.mediaReads
gif.entry.isProtected = true
precondition(gallery.window.send(.K) == .rejected)
gif.entry.isProtected = false
gallery.cachedPeerData = true
precondition(gallery.window.send(.K) == .rejected)
gallery.cachedPeerData = false
gif.entry.message = Message(autoclearTimeout: 1)
precondition(gallery.window.send(.K) == .rejected)
gif.entry.message = Message()
gallery.type = .secret
precondition(gallery.window.send(.K) == .rejected)
gallery.type = .history
precondition(gif.mediaReads == reads && gif.mediaPlayer.toggles == 2)

gif.file.isAnimated = false
precondition(gallery.window.send(.K) == .rejected)
precondition(gallery.window.send(.Space) == .invoked)
precondition(gallery.interactions.dismissals == 1 && gif.mediaPlayer.toggles == 2)

gallery.pager.selectedItem = MGalleryItem()
precondition(gallery.window.send(.K, flags: .command) == .rejected)
precondition(gallery.window.send(.Space) == .invoked)
precondition(gallery.interactions.dismissals == 2)

for video in [MGalleryVideoItem(), MGalleryExternalVideoItem()] as [MGalleryItem] {
    gallery.pager.selectedItem = video
    precondition(gallery.window.send(.K) == .rejected)
    precondition(gallery.window.send(.Space) == .invoked)
    precondition(video.toggles == 1 && gallery.interactions.dismissals == 2)
}
precondition(gif.mediaPlayer.toggles == 2)

print("17 gallery GIF keyboard cases passed")
