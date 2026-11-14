import AppKit
import CoreMedia

enum KeyboardKey: UInt16 {
    case J = 38
    case K = 40
    case L = 37
    case Space = 49

    var character: String {
        switch self {
        case .J: return "j"
        case .K: return "k"
        case .L: return "l"
        case .Space: return " "
        }
    }
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

enum MediaPlayerPlaybackAction: Equatable { case play, pause }

struct MediaPlayerLoadedState {
    struct Timebase {
        let timebase: CMTimebase

        init(timestamp: Double) {
            var timebase: CMTimebase?
            precondition(CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase) == noErr)
            self.timebase = timebase!
            precondition(CMTimebaseSetTime(self.timebase, time: CMTime(seconds: timestamp, preferredTimescale: 1000)) == noErr)
        }
    }

    struct Buffers {
        struct VideoBuffer { var duration: CMTime }
        var videoBuffer: VideoBuffer?
    }

    let controlTimebase: Timebase
    var mediaBuffers: Buffers
    var relativeVideoSeek = true

    init(timestamp: Double, duration: CMTime?) {
        self.controlTimebase = Timebase(timestamp: timestamp)
        self.mediaBuffers = Buffers(videoBuffer: duration.map { Buffers.VideoBuffer(duration: $0) })
    }
}

enum MediaPlayerState {
    case empty
    case seeking(Any?, Double, Any?, Any?, MediaPlayerPlaybackAction, Bool)
    case paused(MediaPlayerLoadedState)
    case playing(MediaPlayerLoadedState)
}

enum MediaPlayerActionAtEnd {
    case loop((() -> Void)?), stop
}

struct PlayerSeek: Equatable {
    let timestamp: Double
    let action: MediaPlayerPlaybackAction
}

struct MediaFrameSourceSeekResult {
    struct Frame { let position: CMTime }
    var buffers: MediaPlayerLoadedState.Buffers
    var extraDecodedVideoFrames: [Frame]
    var timestamp: CMTime
}

final class PlayerContextRef {
    let context = PlayerContext()
    private(set) var pending: [(PlayerContext) -> Void] = []

    func with(_ action: @escaping (PlayerContext) -> Void) { pending.append(action) }

    func drain() {
        let actions = pending
        pending.removeAll()
        for action in actions {
            context.queue.sync {
                action(context)
            }
        }
    }
}

final class PlayerQueue {
    private let queue = DispatchQueue(label: "gallery-gif-test-player")
    private let key = DispatchSpecificKey<Void>()

    init() { queue.setSpecific(key: key, value: ()) }
    func isCurrent() -> Bool { DispatchQueue.getSpecific(key: key) != nil }
    func sync(_ action: () -> Void) { queue.sync(execute: action) }
}

final class PlayerContext {
    let queue = PlayerQueue()
    var isSeekable = true
    var state = MediaPlayerState.empty
    var stoppedAtEnd = false
    private(set) var seeks: [PlayerSeek] = []

    __PLAYER_CONTEXT_SEEK__

    fileprivate func seek(timestamp: Double, action: MediaPlayerPlaybackAction, relativeVideoSeek: Bool = false) {
        precondition(queue.isCurrent())
        precondition(relativeVideoSeek || timestamp == 0)
        seeks.append(PlayerSeek(timestamp: timestamp, action: action))
        state = .seeking(nil, timestamp, nil, nil, action, false)
    }

    __RESTORE_TIMESTAMP__

    func restoreTimestamp(for result: MediaFrameSourceSeekResult, atPausedEnd: Bool) -> CMTime {
        Self.videoRestoreTimestamp(for: result, atPausedEnd: atPausedEnd)
    }

    func atLoopEnd(_ loop: @escaping () -> Void) {
        queue.sync {
            let loadedState: MediaPlayerLoadedState
            switch state {
            case let .paused(state), let .playing(state):
                loadedState = state
            default:
                preconditionFailure("Expected a loaded player")
            }
            switch MediaPlayerActionAtEnd.loop(loop) {
                __LOOP_FINISH__
            case .stop:
                break
            }
        }
    }
}

final class MediaPlayer {
    let contextRef = PlayerContextRef()
    private(set) var toggles = 0
    func togglePlayPause() { toggles += 1 }
    __PLAYER_SEEK__
}

final class MGalleryGIFItem: MGalleryItem {
    let mediaPlayer = MediaPlayer()
    var file = File()
    private(set) var mediaReads = 0
    var media: File {
        mediaReads += 1
        return file
    }
    __GIF_CONTROLS__
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
    for key: KeyboardKey in [.J, .K, .L] {
        precondition(gallery.window.send(key, flags: flag) == .rejected)
    }
}
precondition(gif.mediaPlayer.toggles == 2)
let player = gif.mediaPlayer.contextRef
precondition(player.pending.isEmpty)

gallery.window.hasModal = true
for key: KeyboardKey in [.Space, .J, .K, .L] {
    precondition(gallery.window.send(key) == .rejected)
}
precondition(player.pending.isEmpty && gif.mediaPlayer.toggles == 2 && gallery.interactions.dismissals == 0)
gallery.window.hasModal = false

let reads = gif.mediaReads
gif.entry.isProtected = true
precondition(gallery.window.send(.K) == .rejected && gallery.window.send(.J) == .rejected)
gif.entry.isProtected = false
gallery.cachedPeerData = true
precondition(gallery.window.send(.K) == .rejected && gallery.window.send(.L) == .rejected)
gallery.cachedPeerData = false
gif.entry.message = Message(autoclearTimeout: 1)
precondition(gallery.window.send(.K) == .rejected && gallery.window.send(.J) == .rejected)
gif.entry.message = Message()
gallery.type = .secret
precondition(gallery.window.send(.K) == .rejected && gallery.window.send(.L) == .rejected)
gallery.type = .history
precondition(player.pending.isEmpty && gif.mediaReads == reads && gif.mediaPlayer.toggles == 2)

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
    for key: KeyboardKey in [.J, .K, .L] {
        precondition(gallery.window.send(key) == .rejected)
    }
    precondition(gallery.window.send(.Space) == .invoked)
    precondition(video.toggles == 1 && gallery.interactions.dismissals == 2)
}
precondition(gif.mediaPlayer.toggles == 2)

gallery.pager.selectedItem = gif
gif.file.isAnimated = true

func loaded(_ timestamp: Double, duration: Double = 30) -> MediaPlayerLoadedState {
    MediaPlayerLoadedState(timestamp: timestamp, duration: CMTime(seconds: duration, preferredTimescale: 1000))
}

player.context.state = .paused(loaded(17))
precondition(gallery.window.send(.J) == .invoked)
precondition(gallery.window.send(.J, repeating: true) == .invoked)
precondition(player.pending.count == 1 && player.context.seeks.isEmpty)
player.drain()
precondition(player.context.seeks.last == PlayerSeek(timestamp: 7, action: .pause))

precondition(gallery.window.send(.L) == .invoked)
player.drain()
precondition(player.context.seeks.count == 1)

player.context.state = .playing(loaded(4))
precondition(gallery.window.send(.L) == .invoked)
player.drain()
precondition(player.context.seeks.last == PlayerSeek(timestamp: 14, action: .play))

player.context.state = .playing(loaded(3))
precondition(gallery.window.send(.J) == .invoked)
player.drain()
precondition(player.context.seeks.last == PlayerSeek(timestamp: 0, action: .play))

player.context.state = .paused(loaded(3, duration: 6))
precondition(gallery.window.send(.L) == .invoked)
player.drain()
precondition(player.context.seeks.last == PlayerSeek(timestamp: 6, action: .pause))

let seekCount = player.context.seeks.count
var loopCount = 0
player.context.state = .paused(loaded(6, duration: 6))
player.context.atLoopEnd { loopCount += 1 }
precondition(player.context.seeks.count == seekCount && loopCount == 0)
precondition(gallery.window.send(.L) == .invoked)
player.drain()
precondition(player.context.seeks.count == seekCount)

player.context.state = .playing(loaded(6, duration: 6))
player.context.atLoopEnd { loopCount += 1 }
precondition(player.context.seeks.last == PlayerSeek(timestamp: 0, action: .play) && loopCount == 1)

for state: MediaPlayerState in [
    .empty,
    .paused(MediaPlayerLoadedState(timestamp: 0, duration: nil)),
    .paused(MediaPlayerLoadedState(timestamp: 0, duration: .indefinite)),
    .playing(loaded(0, duration: 0)),
] {
    player.context.state = state
    precondition(gallery.window.send(.L) == .invoked)
    player.drain()
}
precondition(player.context.seeks.count == seekCount + 1)

player.context.state = .paused(loaded(10))
for offset in [Double.nan, .infinity, -.infinity, 0] {
    gif.mediaPlayer.seekVideo(by: offset)
}
player.drain()
precondition(player.context.seeks.count == seekCount + 1)

player.context.isSeekable = false
precondition(gallery.window.send(.L) == .invoked)
player.drain()
precondition(player.context.seeks.count == seekCount + 1)

var absoluteSeekState = loaded(6, duration: 6)
absoluteSeekState.relativeVideoSeek = false
player.context.state = .paused(absoluteSeekState)
player.context.atLoopEnd { loopCount += 1 }
precondition(player.context.seeks.count == seekCount + 2 && loopCount == 2)

let frameTime = CMTime(value: 5_900, timescale: 1000)
let endTime = CMTime(value: 6_000, timescale: 1000)
let earlierTime = CMTime(value: 5_500, timescale: 1000)
var restoreResult = MediaFrameSourceSeekResult(
    buffers: loaded(0, duration: 6).mediaBuffers,
    extraDecodedVideoFrames: [.init(position: frameTime), .init(position: .invalid), .init(position: earlierTime)],
    timestamp: endTime
)
precondition(player.context.restoreTimestamp(for: restoreResult, atPausedEnd: true) == frameTime)
precondition(player.context.restoreTimestamp(for: restoreResult, atPausedEnd: false) == endTime)
restoreResult.timestamp = earlierTime
precondition(player.context.restoreTimestamp(for: restoreResult, atPausedEnd: true) == earlierTime)
restoreResult.timestamp = endTime
restoreResult.extraDecodedVideoFrames = []
precondition(player.context.restoreTimestamp(for: restoreResult, atPausedEnd: true) == endTime)

print("Gallery GIF keyboard dispatch, queued seek, and paused endpoint cases passed")
