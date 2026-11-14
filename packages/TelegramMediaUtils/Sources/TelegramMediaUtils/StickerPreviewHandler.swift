import Cocoa
import TelegramCore

import TGUIKit
import SwiftSignalKit
import TelegramContext


public enum QuickPreviewMedia : Equatable {
    case file(FileMediaReference, ModalPreviewControllerView.Type)
    case image(ImageMediaReference, ModalPreviewControllerView.Type)
    
    public static func ==(lhs: QuickPreviewMedia, rhs: QuickPreviewMedia) -> Bool {
        switch lhs {
        case let .file(lhsReference, _):
            if case let .file(rhsReference, _) = rhs {
                return lhsReference.media.isEqual(to: rhsReference.media)
            } else {
                return false
            }
        case let .image(lhsReference, _):
            if case let .image(rhsReference, _) = rhs {
                return lhsReference.media.isEqual(to: rhsReference.media)
            } else {
                return false
            }
        }
    }
    
    public var fileReference: FileMediaReference? {
        switch self {
        case let .file(reference, _):
            return reference
        default:
            return nil
        }
    }
    public var imageReference: ImageMediaReference? {
        switch self {
        case let .image(reference, _):
            return reference
        default:
            return nil
        }
    }
    
    public var viewType: ModalPreviewControllerView.Type {
        switch self {
        case let .file(_, type), let .image(_, type):
            return type
        }
    }
}

extension TableView : ModalPreviewProtocol {
    public func fileAtLocationInWindow(_ point: NSPoint) -> (QuickPreviewMedia, NSView?)? {
        guard let documentView, let item = self.optionalItem(at: self.row(at: documentView.convert(point, from: nil))),
              let view = self.viewNecessary(at: item.index), let previewRow = view as? ModalPreviewRowViewProtocol else {
            return nil
        }
        return previewRow.fileAtPoint(view.convert(point, from: nil))
    }
}

public protocol ModalPreviewRowViewProtocol {
    func fileAtPoint(_ point:NSPoint) -> (QuickPreviewMedia, NSView?)?
}

public protocol ModalPreviewProtocol: AnyObject {
    func fileAtLocationInWindow(_ point:NSPoint) -> (QuickPreviewMedia, NSView?)?
    
}

public protocol ModalPreviewControllerView : NSView {
    func updateModalPreview(with reference: QuickPreviewMedia, context: any AccountContextProtocol, animated: Bool)
    func getContentView() -> NSView
}

private var activePreviewHandler: ModalPreviewHandler?

@discardableResult
public func startModalPreviewHandle(_ global: ModalPreviewProtocol, window: Window, context: any AccountContextProtocol) -> Disposable? {
    guard window.isKeyWindow, let initial = global.fileAtLocationInWindow(window.mouseLocationOutsideOfEventStream) else {
        return nil
    }
    return startModalPreviewHandle(global, window: window, context: context, initial: initial)
}

@discardableResult
public func startModalPreviewHandle(_ global: ModalPreviewProtocol, window: Window, context: any AccountContextProtocol, initial: (QuickPreviewMedia, NSView?)) -> Disposable? {
    guard window.isKeyWindow else { return nil }
    activePreviewHandler?.stopHandler()
    let handler = ModalPreviewHandler(global, window: window, context: context)
    activePreviewHandler = handler
    handler.startHandler(initial: initial)
    return ActionDisposable { [weak handler] in handler?.stopHandler() }
}

@discardableResult
public func showModalPreview(_ reference: QuickPreviewMedia, window: Window, context: any AccountContextProtocol, dismissTitle: String) -> Disposable? {
    guard window.isKeyWindow else { return nil }
    activePreviewHandler?.stopHandler()
    let handler = ModalPreviewHandler(nil, window: window, context: context, dismissTitle: dismissTitle)
    activePreviewHandler = handler
    handler.startHandler(initial: (reference, nil))
    return ActionDisposable { [weak handler] in handler?.stopHandler() }
}

private final class ModalPreviewHandler: NSObject {
    private weak var global: ModalPreviewProtocol?
    private weak var sourceWindow: Window?
    private let modal: PreviewModalController
    private let visibilityObservation = MetaDisposable()
    private weak var eventWindow: Window?

    init(_ global: ModalPreviewProtocol?, window: Window, context: any AccountContextProtocol, dismissTitle: String? = nil) {
        self.global = global
        self.sourceWindow = window
        self.modal = PreviewModalController(context, dismissTitle: dismissTitle)
    }

    func startHandler(initial: (QuickPreviewMedia, NSView?)) {
        guard let sourceWindow else {
            removeHandlers()
            return
        }
        modal.update(with: initial.0)
        let animation: ModalAnimationType
        if let view = initial.1, let content = sourceWindow.contentView {
            var rect = view.convert(view.bounds, to: nil)
            rect.origin.y = content.frame.maxY - rect.maxY
            animation = .scaleFrom(rect)
        } else {
            animation = .bottomToCenter
        }
        modal.onClose = { [weak self] in self?.removeHandlers() }
        showModal(with: modal, for: sourceWindow, animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, animationType: animation)
        guard activePreviewHandler === self else { return }
        let eventWindow = modal.modal?.window ?? sourceWindow
        self.eventWindow = eventWindow
        let center = NotificationCenter.default
        if global != nil {
            installPointerHandlers(in: eventWindow)
            if eventWindow !== sourceWindow {
                installPointerHandlers(in: sourceWindow)
            }
            eventWindow.set(escape: { [weak self] _ in
                guard let self else { return .rejected }
                self.stopHandler()
                return .invoked
            }, with: self, priority: .supreme)
            center.addObserver(self, selector: #selector(previewWindowDidClose), name: NSWindow.didResignKeyNotification, object: eventWindow)
        }
        center.addObserver(self, selector: #selector(previewWindowDidClose), name: NSWindow.willCloseNotification, object: sourceWindow)
        if eventWindow !== sourceWindow {
            center.addObserver(self, selector: #selector(previewWindowDidClose), name: NSWindow.willCloseNotification, object: eventWindow)
        }
        let visibility = eventWindow === sourceWindow
            ? sourceWindow.visibility
            : combineLatest(sourceWindow.visibility, eventWindow.visibility) |> map { $0.0 && $0.1 }
        visibilityObservation.set((visibility |> filter { !$0 } |> take(1) |> deliverOnMainQueue).start(next: { [weak self] _ in
            self?.previewWindowDidClose()
        }))
    }

    private func installPointerHandlers(in window: Window) {
        window.set(mouseHandler: { [weak self] event in
            guard let self else { return .rejected }
            if let reference = self.preview(at: event) {
                self.modal.update(with: reference.0)
            }
            return .invoked
        }, with: self, for: .leftMouseDragged, priority: .supreme)
        window.set(mouseHandler: { [weak self] event in
            guard let self else { return .rejected }
            self.stopHandler(returningTo: self.preview(at: event)?.1)
            return .invoked
        }, with: self, for: .leftMouseUp, priority: .supreme)
        window.set(mouseHandler: { [weak self] _ in
            self?.stopHandler()
            return .rejected
        }, with: self, for: .scrollWheel, priority: .supreme)
    }

    private func preview(at event: NSEvent) -> (QuickPreviewMedia, NSView?)? {
        guard let window = event.window, let sourceWindow, let global else { return nil }
        let point = window === sourceWindow
            ? event.locationInWindow
            : sourceWindow.convertPoint(fromScreen: window.convertPoint(toScreen: event.locationInWindow))
        return global.fileAtLocationInWindow(point)
    }

    @objc private func previewWindowDidClose() {
        stopHandler(immediately: true)
    }

    func stopHandler(returningTo view: NSView? = nil, immediately: Bool = false) {
        guard activePreviewHandler === self else { return }
        removeHandlers()
        if immediately {
            modal.close(animationType: .noneDelayed(duration: 0))
        } else if let view, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let content = modal.genericView.contentView?.getContentView() ?? modal.genericView
            let rect = view.convert(view.bounds, to: modal.genericView.superview?.superview?.superview)
            modal.close(animationType: .scaleToRect(rect, content))
        } else {
            modal.closePreview()
        }
    }

    private func removeHandlers() {
        visibilityObservation.dispose()
        eventWindow?.removeAllHandlers(for: self)
        if eventWindow !== sourceWindow {
            sourceWindow?.removeAllHandlers(for: self)
        }
        NotificationCenter.default.removeObserver(self)
        if activePreviewHandler === self {
            activePreviewHandler = nil
        }
    }
}

private final class PreviewModalView: View {
    fileprivate var contentView: ModalPreviewControllerView?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
    
    override func layout() {
        super.layout()
    }
    
    func update(with preview: QuickPreviewMedia, context: any AccountContextProtocol, animated: Bool) {
        
        let viewType = preview.viewType
        var changed = false
        if contentView == nil || !contentView!.isKind(of: viewType)  {
            if animated {
                let current = self.contentView
                self.contentView = nil
                current?.layer?.animateScaleSpring(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak current] completed in
                    if completed {
                        current?.removeFromSuperview()
                    }
                })
            } else {
                self.contentView?.removeFromSuperview()
            }
            
            self.contentView = viewType.init(frame:NSZeroRect)
            self.addSubview(self.contentView!)
            changed = true
        }
        contentView?.frame = bounds
        contentView?.updateModalPreview(with: preview, context: context, animated: animated && !changed)
        
        if animated {
            contentView?.layer?.animateScaleSpring(from: 0.5, to: 1.0, duration: 0.2)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class PreviewModalController: ModalViewController {
    fileprivate let context:any AccountContextProtocol
    fileprivate var reference:QuickPreviewMedia?
    private let dismissTitle: String?
    fileprivate var onClose: (() -> Void)?

    init(_ context: any AccountContextProtocol, dismissTitle: String? = nil) {
        self.context = context
        self.dismissTitle = dismissTitle
        
        super.init(frame: NSMakeRect(0, 0, min(context.window.frame.width - 50, 500), min(500, context.window.frame.height - 50)))
        bar = .init(height: 0)
    }
    
    override var hasOwnTouchbar: Bool {
        return false
    }
    
    override var containerBackground: NSColor {
        return .clear
    }
    
    override func becomeFirstResponder() -> Bool? {
        return nil
    }
    
    override var handleEvents: Bool {
        return dismissTitle != nil
    }

    override var modalInteractions: ModalInteractions? {
        guard let dismissTitle else { return nil }
        return ModalInteractions(acceptTitle: dismissTitle, accept: { [weak self] in self?.closePreview() }, singleButton: true)
    }

    override func escapeKeyAction() -> KeyHandlerResult {
        closePreview()
        return .invoked
    }

    override func returnKeyAction() -> KeyHandlerResult {
        closePreview()
        return .invoked
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        onClose?()
        onClose = nil
    }

    fileprivate func closePreview() {
        close(animationType: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .noneDelayed(duration: 0) : .noMorph)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if let reference = reference {
            genericView.update(with: reference, context: context, animated: false)
        }
        readyOnce()
    }
    
    func update(with reference:QuickPreviewMedia?) {
        if self.reference != reference {
            self.reference = reference
            if isLoaded(), let reference = reference {
                genericView.update(with: reference, context: context, animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            }
        }
    }
    
    fileprivate var genericView:PreviewModalView {
        return view as! PreviewModalView
    }
    
    override func viewClass() -> AnyClass {
        return PreviewModalView.self
    }
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
    
}
