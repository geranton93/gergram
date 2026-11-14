import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import PreviewSenderUI
import ImageCanvasUI
import EntertainmentUI
import ChatUI
import AlertsUI
import Localization
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils

extension EmojiesController: @retroactive PreviewSenderEmojiesController {

}

private func mapPreviewSenderEmojiSelectedItem(_ item: PreviewSenderEmojiSelectedItem) -> EmojiesSectionRowItem.SelectedItem {
    let source: EmojiesSectionRowItem.SelectedItem.Source
    switch item.source {
    case let .builtin(emoji):
        source = .builtin(emoji)
    case let .custom(fileId):
        source = .custom(fileId)
    }
    let type: EmojiesSectionRowItem.SelectedItem.Selection
    switch item.type {
    case .normal:
        type = .normal
    case .transparent:
        type = .transparent
    }
    return EmojiesSectionRowItem.SelectedItem(source: source, type: type)
}

func installPreviewSenderUIHooks() {
    PreviewSenderUIHooks.install(PreviewSenderUIHooks(makeEmojies: { context, presentation in
        let emojis = EmojiesController(context as! AccountContext, presentation: presentation)
        return emojis
    }, updateEmojies: { emoji, peerId, sendEmoji, sendAnimatedEmoji, chatInteraction in
        let interactions = EntertainmentInteractions(.emoji, peerId: peerId)

        interactions.sendEmoji = sendEmoji
        interactions.sendAnimatedEmoji = sendAnimatedEmoji

        (emoji as! EmojiesController).update(with: interactions, chatInteraction: chatInteraction)
    }, showMessageEffectsWindow: { context, peerId, selectedItems, react, view in
        let window = ReactionsWindowController(context as! AccountContext, peerId: peerId, selectedItems: selectedItems.map(mapPreviewSenderEmojiSelectedItem), react: react, moveTop: true, mode: .messageEffects)
        window.show(view)
    }))
}

private final class ImageCanvasEntertainment {
    private static var cached: ImageCanvasEntertainment?

    let entertainment: EntertainmentViewController
    let chatInteraction: ChatInteraction
    private weak var context: AccountContext?
    private let accountsDisposable = MetaDisposable()

    private init(context: AccountContext) {
        self.context = context
        self.chatInteraction = ChatInteraction(chatLocation: .peer(PeerId(0)), context: context)
        self.entertainment = EntertainmentViewController(size: NSMakeSize(350, 350), context: context, mode: .common)
        self.entertainment.update(with: chatInteraction)
    }

    deinit {
        accountsDisposable.dispose()
    }

    static func get(_ context: AccountContext) -> ImageCanvasEntertainment {
        if let cached = cached, cached.context === context {
            return cached
        }
        let value = ImageCanvasEntertainment(context: context)
        cached = value
        let accountId = context.account.id
        value.accountsDisposable.set((context.sharedContext.activeAccounts |> deliverOnMainQueue).start(next: { [weak value] accounts in
            if accounts.primary?.id != accountId, let value, cached === value {
                cached = nil
            }
        }))
        return value
    }
}

private final class ImageCanvasStickerPickerImpl: EditImageCanvasStickerPicker {
    private let context: AccountContext
    private let entertainment: EntertainmentViewController
    private let disposable = MetaDisposable()
    private let dragDisposable = MetaDisposable()
    private let visibilityDisposable = MetaDisposable()
    private weak var pickerInteractions: EntertainmentInteractions?
    private var pickerOwner: UUID?
    private var stopAcceptingDrags: (() -> Void)?
    private var dropDisposable: MetaDisposable?
    var visibilityChanged: ((Bool) -> Void)?

    init(context: AccountContext) {
        self.context = context
        self.entertainment = ImageCanvasEntertainment.get(context).entertainment
        visibilityDisposable.set((entertainment.viewOnStage |> deliverOnMainQueue).start(next: { [weak self] isShown in
            self?.updatePickerVisibility(isShown)
        }))
    }

    private func updatePickerVisibility(_ isShown: Bool) {
        guard let owner = pickerOwner, let interactions = pickerInteractions,
              entertainment.interactions === interactions, interactions.imageCanvasPickerOwner == owner else { return }
        if !isShown {
            invalidateDragRoutes(preservingDrop: true)
        }
        visibilityChanged?(isShown)
    }

    deinit {
        disposable.dispose()
        dragDisposable.dispose()
        dropDisposable?.dispose()
        visibilityDisposable.dispose()
        releasePickerOwnership()
    }

    func show(for control: Control, select: @escaping (EditImageCanvasStickerPick) -> Void, drag: @escaping (EditImageCanvasStickerDrag) -> Void) {
        guard let window = control.window as? Window, !window.inLiveSwiping, window.sheets.isEmpty else { return }
        guard let interactions = entertainment.interactions else { return }
        invalidateDragRoutes(preservingDrop: false)
        disposable.set(nil)
        let owner = claimPickerOwnership(on: interactions)
        installPickerRoutes(interactions: interactions, owner: owner, select: select, drag: drag)
        showPopover(for: control, with: entertainment)
    }

    private func installPickerRoutes(
        interactions: EntertainmentInteractions,
        owner: UUID,
        select: @escaping (EditImageCanvasStickerPick) -> Void,
        drag: @escaping (EditImageCanvasStickerDrag) -> Void
    ) {
        let selectItem = { [weak self, weak interactions] (item: EntertainmentDragItem) in
            guard let self, self.ownsPicker(owner, on: interactions) else { return }
            self.pick(item, disposable: self.disposable, select: { [weak self, weak interactions] pick in
                guard self?.ownsPicker(owner, on: interactions) == true else { return }
                select(pick)
            })
            if self.ownsPicker(owner, on: interactions) {
                self.entertainment.closePopover()
            }
        }
        interactions.sendSticker = { file, _, _, _ in selectItem(.file(file)) }
        interactions.sendAnimatedEmoji = { item, _, _, _, _ in selectItem(.file(item.file._parse())) }
        interactions.sendEmoji = { emoji, _ in selectItem(.emoji(emoji)) }
        interactions.sendGIF = { file, _, _ in selectItem(.file(file)) }
        var dragImage: CGImage?
        var isDragging = false
        var previewGeneration: UInt64 = 0
        let finishDrag = { [weak self] in
            guard isDragging else { return }
            isDragging = false
            dragImage = nil
            self?.dragDisposable.set(nil)
            drag(.ended)
        }
        interactions.cancelItemDrag = finishDrag
        var acceptsDrag = true
        stopAcceptingDrags = { [weak interactions] in
            acceptsDrag = false
            if interactions?.imageCanvasPickerOwner == owner {
                interactions?.dragItem = nil
                interactions?.cancelItemDrag = nil
            }
            finishDrag()
        }
        interactions.dragItem = { [weak self, weak interactions] item, image, phase in
            guard let self, self.ownsPicker(owner, on: interactions), acceptsDrag else {
                return
            }
            switch phase {
            case let .moved(point):
                if let image = image {
                    dragImage = image
                }
                if !isDragging {
                    isDragging = true
                    previewGeneration &+= 1
                    self.cancelPendingDrop()
                    let generation = previewGeneration
                    drag(.moved(dragImage, point))
                    guard self.ownsPicker(owner, on: interactions), isDragging, previewGeneration == generation else { return }
                    self.pick(item, disposable: self.dragDisposable, select: { [weak self, weak interactions] pick in
                        guard self?.ownsPicker(owner, on: interactions) == true, isDragging, previewGeneration == generation else { return }
                        dragImage = pick.image
                        drag(.preview(pick))
                    })
                } else {
                    drag(.moved(dragImage, point))
                }
            case let .ended(point):
                guard isDragging else { return }
                let generation = previewGeneration
                finishDrag()
                guard self.ownsPicker(owner, on: interactions), acceptsDrag, previewGeneration == generation else { return }
                let request = MetaDisposable()
                self.dropDisposable = request
                self.pick(item, disposable: request, select: { [weak self, weak interactions, weak request] pick in
                    guard let self, let request, self.dropDisposable === request else { return }
                    self.cancelPendingDrop()
                    guard self.ownsPicker(owner, on: interactions) else { return }
                    drag(.dropped(pick, point))
                })
            }
        }
    }

    private func ownsPicker(_ owner: UUID, on interactions: EntertainmentInteractions?) -> Bool {
        guard let interactions else { return false }
        return entertainment.interactions === interactions && interactions.imageCanvasPickerOwner == owner
    }

    private func claimPickerOwnership(on interactions: EntertainmentInteractions) -> UUID {
        interactions.retireImageCanvasPicker?()
        if interactions.imageCanvasPickerOwner != nil {
            entertainment.closePopover()
        }
        let owner = UUID()
        self.pickerOwner = owner
        self.pickerInteractions = interactions
        interactions.imageCanvasPickerOwner = owner
        interactions.retireImageCanvasPicker = { [weak self, weak interactions] in
            guard let self, self.pickerOwner == owner, interactions?.imageCanvasPickerOwner == owner else { return }
            self.invalidateDragRoutes(preservingDrop: false)
            self.disposable.set(nil)
        }
        return owner
    }

    private func releasePickerOwnership() {
        let owner = pickerOwner
        pickerOwner = nil
        guard let owner, let interactions = pickerInteractions, interactions.imageCanvasPickerOwner == owner else { return }
        interactions.imageCanvasPickerOwner = nil
        interactions.retireImageCanvasPicker = nil
        interactions.sendSticker = { _, _, _, _ in }
        interactions.sendAnimatedEmoji = { _, _, _, _, _ in }
        interactions.sendEmoji = { _, _ in }
        interactions.sendGIF = { _, _, _ in }
        interactions.dragItem = nil
        interactions.cancelItemDrag = nil
    }

    private func invalidateDragRoutes(preservingDrop: Bool) {
        let stopAcceptingDrags = self.stopAcceptingDrags
        self.stopAcceptingDrags = nil
        stopAcceptingDrags?()
        if !preservingDrop {
            cancelPendingDrop()
        }
    }

    private func cancelPendingDrop() {
        let disposable = dropDisposable
        dropDisposable = nil
        disposable?.dispose()
    }

    func close() {
        invalidateDragRoutes(preservingDrop: false)
        disposable.set(nil)
        guard let owner = pickerOwner, let interactions = pickerInteractions,
              interactions.imageCanvasPickerOwner == owner else { return }
        releasePickerOwnership()
        if entertainment.interactions === interactions {
            entertainment.closePopover()
            visibilityChanged?(false)
        }
    }

    private func pick(_ item: EntertainmentDragItem, disposable: MetaDisposable?, select: @escaping (EditImageCanvasStickerPick) -> Void) {
        switch item {
        case let .emoji(emoji):
            if let image = ImageCanvasUIHooks.emojiImage(emoji) {
                select(EditImageCanvasStickerPick(image: image, fileId: nil))
            }
        case let .file(file):
            if file.isAnimated && file.isVideo && !file.isVideoSticker {
                renderGif(file, disposable: disposable, select: select)
            } else {
                render(file, disposable: disposable, select: select)
            }
        }
    }

    private func renderGif(_ file: TelegramMediaFile, disposable: MetaDisposable?, select: @escaping (EditImageCanvasStickerPick) -> Void) {
        let fileId = file.fileId.id
        let fetch = freeMediaFileInteractiveFetched(context: context, fileReference: .standalone(media: file)).start()
        let signal = context.account.postbox.mediaBox.resourceData(file.resource) |> filter { $0.complete } |> take(1) |> deliverOn(resourcesQueue) |> map { data -> EditImageCanvasStickerPick? in
            guard let image = editImageCanvasVideoPreview(path: data.path) else {
                return nil
            }
            return EditImageCanvasStickerPick(image: image, fileId: fileId, animation: EditImageCanvasStickerAnimation(kind: .video, path: data.path))
        }
        let disposableSet = DisposableSet()
        disposableSet.add(fetch)
        disposableSet.add((signal |> deliverOnMainQueue).start(next: { pick in
            if let pick = pick {
                select(pick)
            }
        }))
        disposable?.set(disposableSet)
    }

    private func render(_ file: TelegramMediaFile, disposable: MetaDisposable?, select: @escaping (EditImageCanvasStickerPick) -> Void) {
        let size = NSMakeSize(1024, 1024)
        let aspectSize = file.dimensions?.size.aspectFitted(size) ?? size
        let reference = FileMediaReference.standalone(media: file)
        let signal: Signal<ImageDataTransformation, NoError>
        let isVideo = file.fileName == "webm-preview" || file.isVideoSticker
        let animationKind: EditImageCanvasStickerAnimation.Kind?
        if file.mimeType == "image/webp" {
            signal = chatMessageSticker(postbox: context.account.postbox, file: reference, small: false, scale: 1.0, fetched: true, onlyFullSize: true)
            animationKind = nil
        } else {
            signal = chatMessageAnimatedSticker(postbox: context.account.postbox, file: reference, small: false, scale: 1.0, size: aspectSize, fetched: true, onlyFullSize: true, thumbAtFrame: 0, isVideo: isVideo)
            animationKind = isVideo ? .webm : .lottie
        }
        let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: aspectSize, boundingSize: aspectSize, intrinsicInsets: NSEdgeInsets(), scale: 1.0)
        let fileId = file.fileId.id
        let image = signal |> filter { $0.data.fullSizeComplete } |> map { data -> CGImage? in
            return data.execute(arguments, data.data)?.generateImage()
        } |> filter { $0 != nil } |> take(1)
        let animation: Signal<EditImageCanvasStickerAnimation?, NoError>
        if let animationKind = animationKind {
            animation = context.account.postbox.mediaBox.resourceData(file.resource) |> filter { $0.complete } |> take(1) |> map { data in
                return EditImageCanvasStickerAnimation(kind: animationKind, path: data.path)
            }
        } else {
            animation = .single(nil)
        }
        disposable?.set((combineLatest(image, animation) |> take(1) |> deliverOnMainQueue).start(next: { image, animation in
            if let image = image {
                select(EditImageCanvasStickerPick(image: image, fileId: fileId, animation: animation))
            }
        }))
    }
}

func installImageCanvasUIHooks() {
    ImageCanvasUIHooks.install(ImageCanvasUIHooks(makeStickerPicker: { context in
        guard let context = context as? AccountContext else {
            return nil
        }
        return ImageCanvasStickerPickerImpl(context: context)
    }, confirm: { window, information, ok, action in
        verifyAlert(for: window, information: information, ok: ok, successHandler: { _ in
            action()
        }, presentation: TelegramThemeHooks.shared.darkAppearance())
    }))
}
