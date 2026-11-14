import Cocoa
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramTheme
import TelegramContext
import InAppSettings


public final class PeerInfoMusicView : View {
    public static func height(colorful: Bool) -> CGFloat {
        return colorful ? 24 : 20
    }
    private let textView: TextView = TextView()
    private var titleFont: NSFont = .semibold(.short)
    private let chevron = ImageView()
    private let imageView = ImageView()
    private let container = View()
    public let control = Control()

    private struct Appearance: Equatable {
        let title: String
        let performer: String
        let primary: NSColor
        let secondary: NSColor
        let background: NSColor
        let colorful: Bool
        let isDark: Bool
    }

    private struct ArtworkSource {
        let accountId: Int64
        let mediaBox: MediaBox
        let resources: [any MediaResource]
    }

    private struct ArtworkRequest: Equatable {
        let accountId: Int64
        let mediaBox: ObjectIdentifier
        let resourceIds: [String]
        let pixelSize: Int
        let isDark: Bool
        let colorful: Bool
    }

    private static let artworkQueue = Queue(name: "ProfileMusicCover", qos: .utility)
    private let preferenceDisposable = MetaDisposable()
    private let artworkDisposable = MetaDisposable()
    private var isAdaptive = ProfileMusicCoverPreferences.shared.isAdaptive
    private var appearance: Appearance?
    private var artworkSource: ArtworkSource?
    private var artworkRequest: ArtworkRequest?
    private var artworkGeneration = 0
    private var artwork: ProfileMusicCover?
    private var layoutWidth: CGFloat?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(control)
        control.addSubview(container)
        container.addSubview(textView)
        container.addSubview(chevron)
        container.addSubview(imageView)

        textView.userInteractionEnabled = false
        textView.isSelectable = false
        textView.isAccessibilityDecorative = true
        chevron.isAccessibilityDecorative = true
        imageView.isAccessibilityDecorative = true
        
        control.scaleOnClick = true
        preferenceDisposable.set((ProfileMusicCoverPreferences.shared.signal |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let self, self.isAdaptive != value else { return }
            self.isAdaptive = value
            self.updateArtwork()
        }))
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(file: TelegramMediaFile, primaryText: NSColor, secondaryText: NSColor, backgroundColor: NSColor, colorfull: Bool, context: any AccountContextProtocol) {
        var track = "Unknown Track"
        var artist = "Unknown Performer"
        for attribute in file.attributes {
            if case let .Audio(_, _, title, performer, _) = attribute {
                if let title {
                    track = title
                }
                if let performer {
                    artist = performer
                }
                break
            }
        }

        let updatedAppearance = Appearance(title: track, performer: artist, primary: primaryText, secondary: secondaryText,
                                           background: colorfull ? backgroundColor : .clear, colorful: colorfull, isDark: theme.colors.isDark)
        let appearanceChanged = appearance != updatedAppearance
        appearance = updatedAppearance
        let resources = file.previewRepresentations.lazy.filter { !$0.hasVideo }
            .prefix(ProfileMusicCover.maximumCandidates).map(\.resource)
        artworkSource = resources.isEmpty ? nil : ArtworkSource(
            accountId: context.account.id.int64, mediaBox: context.account.postbox.mediaBox, resources: Array(resources)
        )
        updateArtwork(appearanceChanged: appearanceChanged)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateArtwork(appearanceChanged: true)
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateArtwork()
    }

    private func updateArtwork(appearanceChanged: Bool = false) {
        guard isAdaptive, window != nil, let source = artworkSource, let appearance else {
            let wasShowingArtwork = artwork != nil
            clearArtworkRequest()
            if appearanceChanged || wasShowingArtwork {
                renderAppearance()
            }
            return
        }

        let request = ArtworkRequest(accountId: source.accountId, mediaBox: ObjectIdentifier(source.mediaBox),
                                     resourceIds: source.resources.map { $0.id.stringRepresentation },
                                     pixelSize: Int(ceil(Self.artworkSide(colorful: appearance.colorful) * backingScaleFactor)),
                                     isDark: appearance.isDark, colorful: appearance.colorful)
        guard artworkRequest != request else {
            if appearanceChanged {
                renderAppearance()
            }
            return
        }

        clearArtworkRequest()
        artworkRequest = request
        renderAppearance()
        let generation = artworkGeneration
        let candidates = zip(request.resourceIds, source.resources).map { id, resource in
            ProfileMusicCover.Candidate(
                resourceId: id,
                cachedPath: source.mediaBox.resourceData(resource)
                    |> filter { $0.complete && $0.offset == 0 && (1...Int64(ProfileMusicCover.maximumBytes)).contains($0.size) }
                    |> map(\.path)
            )
        }
        let signal = ProfileMusicCover.observeCached(
            candidates, accountId: request.accountId, pixelSize: request.pixelSize, isDark: request.isDark, on: Self.artworkQueue
        ) |> deliverOnMainQueue
        artworkDisposable.set(signal.start(next: { [weak self] artwork in
            guard let self, self.artworkGeneration == generation, self.artwork?.image !== artwork?.image else { return }
            self.artwork = artwork
            self.renderAppearance()
        }))
    }

    private func clearArtworkRequest() {
        guard artworkRequest != nil else { return }
        artworkGeneration &+= 1
        artworkRequest = nil
        artwork = nil
        artworkDisposable.set(nil)
    }

    private func renderAppearance() {
        guard let appearance else { return }
        let primary = artwork?.primary ?? appearance.primary
        let secondary = artwork?.secondary ?? appearance.secondary
        backgroundColor = artwork?.background ?? appearance.background

        titleFont = appearance.colorful ? .semibold(.short) : .semibold(.text)
        let secondaryFont: NSFont = appearance.colorful ? .normal(.short) : .normal(.text)
        let attributedTitle = NSMutableAttributedString()
        attributedTitle.append(string: appearance.title, color: primary, font: titleFont)
        attributedTitle.append(string: " - " + appearance.performer, color: secondary, font: secondaryFont)
        let textLayout = TextViewLayout(attributedTitle, maximumNumberOfLines: 1, alignment: .center)
        control.setAccessibilityLabel(attributedTitle.string)

        if let artwork {
            let side = Self.artworkSide(colorful: appearance.colorful)
            imageView.contentGravity = .resizeAspectFill
            imageView.layer?.cornerRadius = 3
            imageView.image = artwork.image
            imageView.setFrameSize(NSSize(width: side, height: side))
        } else {
            imageView.contentGravity = .center
            imageView.layer?.cornerRadius = 0
            imageView.image = TelegramThemeHooks.shared.image(.iconPeerMusicWaveform).precomposed(primary)
            imageView.sizeToFit()
        }

        chevron.image = TelegramThemeHooks.shared.image(.iconPeerMusicChevron).precomposed(secondary)
        chevron.sizeToFit()
        let textWidth = availableTextWidth
        textLayout.measure(width: textWidth)
        textView.update(textLayout)
        layoutWidth = textWidth
        needsLayout = true
    }

    private static func artworkSide(colorful: Bool) -> CGFloat {
        colorful ? 18 : 16
    }

    private var availableTextWidth: CGFloat {
        max(1, bounds.width - imageView.frame.width - chevron.frame.width - 22)
    }
    
    public override func layout() {
        super.layout()
        
        control.frame = bounds
        let textWidth = availableTextWidth
        if textWidth != layoutWidth {
            textView.resize(textWidth)
            layoutWidth = textWidth
        }
        
        container.setFrameSize(NSMakeSize(container.subviewsWidthSize.width + 6, frame.height))
        
        imageView.centerY(x: 0)
        textView.centerY(x: imageView.frame.maxX + 3)
        if let line = textView.textLayout?.lines.first {
            let glyphCenter = line.frame.minY - (titleFont.ascender + titleFont.descender) / 2
            textView.setFrameOrigin(NSMakePoint(textView.frame.minX, floorToScreenPixels(backingScaleFactor, frame.height / 2 - glyphCenter)))
        }
        chevron.centerY(x: textView.frame.maxX + 3)
        
        container.center()
    }

    deinit {
        preferenceDisposable.dispose()
        artworkDisposable.dispose()
    }
}
