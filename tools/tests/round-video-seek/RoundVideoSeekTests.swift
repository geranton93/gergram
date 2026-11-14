import Cocoa

struct Message {
    var id = 1
    var autoclearTimeout: Int?
}
protocol AccountContextProtocol: AnyObject {}
final class AccountContext: AccountContextProtocol {}
protocol Media {}
struct Resource { var id = 1 }
struct TelegramMediaFile: Media {
    var resource = Resource()
    var isInstantVideo = true
}

final class APSongItem {
    enum State { case playing, paused, waiting, fetching, stoped }
    enum Entry { case song(Message), single }
    struct Status { var duration: Double = 100 }
    var state: State = .playing
    var status = Status()
    var entry: Entry = .song(Message())
    var resource = Resource()
}

final class APController {
    var currentSong: APSongItem? = APSongItem()
    var positions: [Float] = []
    @discardableResult func set(trackProgress: Float) -> Bool {
        positions.append(trackProgress)
        return true
    }
}

final class ChatMediaUIHooks {
    static let shared = ChatMediaUIHooks()
    var controller: APController? = APController()
    func getAudioPlayer(_ context: (any AccountContextProtocol)?) -> APController? { controller }
}

public class ChatMediaContentView: NSView {
    enum FetchStatus { case Local, Remote }
    var parent: Message? = Message()
    var context: (any AccountContextProtocol)? = AccountContext()
    var media: (any Media)? = TelegramMediaFile()
    var userInteractionEnabled = true
    var isEnabled = true
    var hasFetchStatusForCurrentMedia = true
    var fetchStatus = FetchStatus.Local
    var forwardedEvents: [NSEvent.EventType] = []
    public override func mouseDown(with event: NSEvent) { forwardedEvents.append(event.type) }
    public override func mouseDragged(with event: NSEvent) { forwardedEvents.append(event.type) }
    public override func mouseUp(with event: NSEvent) { forwardedEvents.append(event.type) }
    public func willRemove() {}
}

final class RadialProgressView: NSView {
    enum State { case ImpossibleFetching(progress: Float, force: Bool) }
    struct Theme { var lineWidth: CGFloat = 3 }
    var state: State?
    var theme = Theme()
    var isEventLess = false
    var userInteractionEnabled = true
    override var isFlipped: Bool { testFlipped }
    var testFlipped = false
}

final class ChatVideoMessageContentView: ChatMediaContentView {
    let playingProgressView = RadialProgressView(frame: NSRect(x: 2, y: 2, width: 96, height: 96))
    let durationView = NSView()
    var transcribeControl: NSView?
    var progressView: NSView?
    var inkView: NSView?
    var stateUpdates = 0
    __GESTURE_STATE__

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        __ROUND_VIEW_INIT__
        addSubview(playingProgressView)
    }

    required init?(coder: NSCoder) { fatalError() }

    __GESTURE_EVENTS__

    func rebind(with media: Media, context: any AccountContextProtocol, parent: Message?) {
        __ROUND_VIEW_REBIND__
        self.media = media
        self.context = context
        self.parent = parent
    }

    func updateSongState() { stateUpdates += 1 }
}

func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat, flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: flags,
                       timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                       clickCount: 1, pressure: 1)!
}

func fixture(_ state: APSongItem.State = .playing) -> (ChatVideoMessageContentView, APController) {
    let controller = APController()
    controller.currentSong?.state = state
    ChatMediaUIHooks.shared.controller = controller
    let view = ChatVideoMessageContentView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    precondition(view.playingProgressView.isEventLess && !view.playingProgressView.userInteractionEnabled)
    return (view, controller)
}

for flipped in [false, true] {
    for (x, y, expected): (CGFloat, CGFloat, Float) in [(50, 97, 0), (97, 50, 0.25), (50, 3, 0.5), (3, 50, 0.75)] {
        let (view, controller) = fixture(.paused)
        view.playingProgressView.testFlipped = flipped
        view.mouseDown(with: event(.leftMouseDown, x, y))
        view.mouseUp(with: event(.leftMouseUp, x, y))
        precondition(controller.positions == [expected] && view.forwardedEvents.isEmpty)
        precondition(controller.currentSong?.state == .paused && view.stateUpdates == 1)
    }
}
print("PASS ring seeks clockwise from top in flipped and unflipped AppKit coordinates")

do {
    let (view, controller) = fixture()
    view.mouseDown(with: event(.leftMouseDown, 97, 50))
    view.mouseDragged(with: event(.leftMouseDragged, 50, 3))
    if case let .ImpossibleFetching(progress, force) = view.playingProgressView.state {
        precondition(progress == 0.5 && force)
    } else {
        fatalError("ring did not preview")
    }
    precondition(controller.positions.isEmpty)
    view.mouseUp(with: event(.leftMouseUp, 50, 50))
    precondition(controller.positions == [0.5] && view.forwardedEvents.isEmpty)
    precondition(controller.currentSong?.state == .playing && view.stateUpdates == 1)
}
print("PASS drag previews without a media seek and commits the last valid angle")

for mode in ["center", "outside", "control", "view-once", "duration", "transcribe", "ink", "fetch overlay", "remote", "stale fetch", "different message", "different resource", "single resource", "not instant", "disabled", "loading", "invalid duration"] {
    let (view, controller) = fixture()
    switch mode {
    case "view-once": view.parent?.autoclearTimeout = 1
    case "duration": view.durationView.frame = NSRect(x: 92, y: 45, width: 8, height: 10)
    case "transcribe": view.transcribeControl = NSView(frame: NSRect(x: 92, y: 45, width: 8, height: 10))
    case "ink": view.inkView = NSView()
    case "fetch overlay": view.progressView = NSView()
    case "remote": view.fetchStatus = .Remote
    case "stale fetch": view.hasFetchStatusForCurrentMedia = false
    case "different message": controller.currentSong?.entry = .song(Message(id: 2))
    case "different resource": controller.currentSong?.resource.id = 2
    case "single resource": controller.currentSong?.entry = .single
    case "not instant": view.media = TelegramMediaFile(isInstantVideo: false)
    case "disabled": view.isEnabled = false
    case "loading": controller.currentSong?.state = .waiting
    case "invalid duration": controller.currentSong?.status.duration = .infinity
    default: break
    }
    let x: CGFloat = mode == "center" ? 50 : mode == "outside" ? 110 : 97
    let flags: NSEvent.ModifierFlags = mode == "control" ? .control : []
    view.mouseDown(with: event(.leftMouseDown, x, 50, flags: flags))
    view.mouseDragged(with: event(.leftMouseDragged, 3, 50, flags: flags))
    view.mouseUp(with: event(.leftMouseUp, 3, 50, flags: flags))
    precondition(controller.positions.isEmpty && view.forwardedEvents == [.leftMouseDown, .leftMouseDragged, .leftMouseUp], mode)
}
print("PASS other gestures retain normal media handling")

for mode in ["new controller", "new song", "rebind", "remove", "disable", "end playback"] {
    let (view, controller) = fixture()
    view.mouseDown(with: event(.leftMouseDown, 97, 50))
    switch mode {
    case "new controller": ChatMediaUIHooks.shared.controller = APController()
    case "new song": controller.currentSong = APSongItem()
    case "rebind": view.rebind(with: view.media!, context: view.context!, parent: Message(id: 2))
    case "remove": view.willRemove()
    case "disable": view.isEnabled = false
    case "end playback": controller.currentSong?.state = .stoped
    default: fatalError()
    }
    view.mouseDragged(with: event(.leftMouseDragged, 3, 50))
    view.mouseUp(with: event(.leftMouseUp, 3, 50))
    precondition(controller.positions.isEmpty && view.forwardedEvents.isEmpty && view.stateUpdates == 1, mode)
    precondition(ChatMediaUIHooks.shared.controller?.positions.isEmpty == true, mode)
}
print("PASS owned gestures cannot seek or click through after losing the original song")
