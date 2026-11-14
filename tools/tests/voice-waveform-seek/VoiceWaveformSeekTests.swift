import Cocoa

struct PeerId: Equatable {
    var namespace = 0
}
struct MessageId: Equatable {
    var peerId = PeerId()
    var value = 1
}
struct Message {
    var id = MessageId()
    var autoclearTimeout: Int?
}
enum Namespaces {
    enum Peer {
        static let SecretChat = 1
    }
}

protocol AccountContextProtocol: AnyObject {}
final class AccountContext: AccountContextProtocol {}
protocol Media {}
struct Resource { var id = 1 }
struct TelegramMediaFile: Media { var resource = Resource() }

final class APSongItem {
    enum State {
        case playing, paused, waiting, fetching, stoped
    }
    struct Status { var duration: Double = 100 }
    struct Entry {
        var id = MessageId()
        func isEqual(to message: Message) -> Bool { message.id == id }
    }
    var state: State = .playing
    var status = Status()
    var entry = Entry()
}

final class APController {
    var currentSong: APSongItem? = APSongItem()
    var positions: [Float] = []
    var acceptSeek = true
    @discardableResult func set(trackProgress: Float) -> Bool {
        guard acceptSeek else { return false }
        positions.append(trackProgress)
        return true
    }
}

final class ChatMediaUIHooks {
    static let shared = ChatMediaUIHooks()
    var controller: APController? = APController()
    func getAudioPlayer(_ context: (any AccountContextProtocol)?) -> APController? { controller }
}

public class ChatAudioContentView: NSView {
    var parent: Message? = Message()
    var context: (any AccountContextProtocol)? = AccountContext()
    var media: (any Media)? = TelegramMediaFile()
    var userInteractionEnabled = true
    var forwardedEvents: [NSEvent.EventType] = []
    public override func mouseDown(with event: NSEvent) { forwardedEvents.append(event.type) }
    public override func mouseDragged(with event: NSEvent) { forwardedEvents.append(event.type) }
    public override func mouseUp(with event: NSEvent) { forwardedEvents.append(event.type) }
    public func willRemove() {}
}

final class AudioWaveformView: NSView {
    var isEventLess = false
}

final class ChatVoiceContentView: ChatAudioContentView {
    let waveformView = AudioWaveformView(frame: NSRect(x: 10, y: 10, width: 100, height: 10))
    __GESTURE_STATE__

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        __WAVEFORM_INIT__
        addSubview(waveformView)
    }

    required init?(coder: NSCoder) { fatalError() }

    __GESTURE_EVENTS__

    func rebind(with media: Media, context: any AccountContextProtocol, parent: Message?) {
        __WAVEFORM_REBIND__
        self.media = media
        self.context = context
        self.parent = parent
    }
}

func event(_ type: NSEvent.EventType, x: CGFloat = 35, flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 15), modifierFlags: flags,
                       timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                       clickCount: 1, pressure: 1)!
}

func fixture(_ state: APSongItem.State = .playing) -> (ChatVoiceContentView, APController) {
    let controller = APController()
    controller.currentSong?.state = state
    ChatMediaUIHooks.shared.controller = controller
    let view = ChatVoiceContentView(frame: NSRect(x: 0, y: 0, width: 130, height: 30))
    precondition(view.waveformView.isEventLess)
    return (view, controller)
}

for state: APSongItem.State in [.playing, .paused] {
    let (view, controller) = fixture(state)
    view.mouseDown(with: event(.leftMouseDown))
    view.mouseUp(with: event(.leftMouseUp))
    precondition(controller.positions == [0.25])
    precondition(controller.currentSong?.state == state && view.forwardedEvents.isEmpty)
}
print("PASS plain clicks seek playing and paused messages")

do {
    let (view, controller) = fixture()
    view.mouseDown(with: event(.leftMouseDown))
    view.mouseDragged(with: event(.leftMouseDragged, x: -10))
    view.mouseDragged(with: event(.leftMouseDragged, x: 60))
    view.mouseDragged(with: event(.leftMouseDragged, x: 60))
    view.mouseUp(with: event(.leftMouseUp, x: 120))
    precondition(controller.positions == [0, 0.5, 1] && view.forwardedEvents.isEmpty)
}
print("PASS drag clamps, coalesces duplicates, and consumes release")

for mode in ["outside", "control", "inactive", "disabled", "unavailable", "view-once"] {
    let (view, controller) = fixture()
    if mode == "inactive" { controller.currentSong?.entry.id.value = 2 }
    if mode == "disabled" { view.userInteractionEnabled = false }
    if mode == "unavailable" { controller.currentSong?.status.duration = 0 }
    if mode == "view-once" { view.parent?.autoclearTimeout = 1 }
    let flags: NSEvent.ModifierFlags = mode == "control" ? .control : []
    view.mouseDown(with: event(.leftMouseDown, x: mode == "outside" ? 5 : 35, flags: flags))
    view.mouseDragged(with: event(.leftMouseDragged, flags: flags))
    view.mouseUp(with: event(.leftMouseUp, flags: flags))
    precondition(controller.positions.isEmpty && view.forwardedEvents == [.leftMouseDown, .leftMouseDragged, .leftMouseUp], mode)
}
print("PASS non-seek gestures use original event handling")

for mode in ["new controller", "new song", "rebind", "new context", "new resource", "removal", "stop", "collapsed waveform"] {
    let (view, controller) = fixture()
    view.mouseDown(with: event(.leftMouseDown))
    switch mode {
    case "new controller": ChatMediaUIHooks.shared.controller = APController()
    case "new song": controller.currentSong = APSongItem()
    case "rebind": view.rebind(with: view.media!, context: view.context!, parent: Message(id: MessageId(value: 2)))
    case "new context": view.rebind(with: view.media!, context: AccountContext(), parent: view.parent)
    case "new resource": view.rebind(with: TelegramMediaFile(resource: Resource(id: 2)), context: view.context!, parent: view.parent)
    case "removal": view.willRemove()
    case "stop": controller.currentSong?.state = .stoped
    case "collapsed waveform": view.waveformView.setFrameSize(NSSize(width: 0, height: 10))
    default: fatalError()
    }
    view.mouseDragged(with: event(.leftMouseDragged))
    view.mouseUp(with: event(.leftMouseUp))
    precondition(controller.positions.isEmpty && view.forwardedEvents.isEmpty, mode)
    precondition(ChatMediaUIHooks.shared.controller?.positions.isEmpty == true, mode)
}
print("PASS owned gesture cannot seek or click through after losing its target")

do {
    let (view, controller) = fixture()
    view.rebind(with: view.media!, context: view.context!, parent: view.parent)
    view.mouseDown(with: event(.leftMouseDown))
    controller.acceptSeek = false
    view.mouseDragged(with: event(.leftMouseDragged))
    view.rebind(with: view.media!, context: view.context!, parent: view.parent)
    controller.acceptSeek = true
    view.mouseUp(with: event(.leftMouseUp))
    precondition(controller.positions == [0.25] && view.forwardedEvents.isEmpty)
}
print("PASS same binding survives updates and rejected targets can be retried")
