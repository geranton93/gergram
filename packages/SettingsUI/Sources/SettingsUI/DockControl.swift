import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import ApiCredentials
import InAppSettings
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import FoundationUtils
import InputDataUI
import TelegramIconsTheme
import AlertsUI
import TelegramMediaUtils

public extension TelegramApplicationIcons.Icon {
    var path: String {
        return iconsFolder + "/" + self.file.fileName!
    }
    
    func resourcePath(_ context: any AccountContextProtocol) -> String? {
        if self.file.fileName == TelegramApplicationIcons.Icon.defaultIconName {
            return nil
        } else {
            return context.account.postbox.mediaBox.resourcePath(self.file.resource)
        }
    }
    
    var isPremium: Bool {
        if let fileName = file.fileName, fileName.contains("Premium") {
            return true
        }
        return false
    }
    
    static let defaultIconName = "Default.icns"
}

private var iconsFolder: String {
    return ApiEnvironment.containerURL!.appendingPathComponent("icons").path
}

public final class DockControl {
    
    private let promise: ValuePromise<TelegramApplicationIcons> = .init()
    
    public var icons: Signal<TelegramApplicationIcons, NoError> {
        return promise.get()
    }
    
    private let disposable = MetaDisposable()
    
    private let fetch = DisposableDict<String>()
    private var fetchedResourceIds: Set<String> = []
    
    private let engine: TelegramEngine
    private let accountManager: AccountManager<TelegramAccountManagerTypes>
    private let update = MetaDisposable()
    private let applyResource = MetaDisposable()
    public init(_ engine: TelegramEngine, accountManager: AccountManager<TelegramAccountManagerTypes>) {
        self.engine = engine
        self.accountManager = accountManager
        loadResources()
        
        observeSelection()
    }
    
    private func loadResources() {
        disposable.set((engine.resources.applicationIcons() |> distinctUntilChanged |> deliverOnMainQueue).start(next: { [weak self] icons in
            self?.update(icons)
        }))
    }
    
    private func update(_ icons: TelegramApplicationIcons) {
        var resourceIds: Set<String> = []
        for icon in icons.icons where icon.file.fileName != TelegramApplicationIcons.Icon.defaultIconName {
            let id = icon.file.resource.id.stringRepresentation
            guard resourceIds.insert(id).inserted, !fetchedResourceIds.contains(id) else { continue }
            let reference = MediaResourceReference.media(media: AnyMediaReference.message(message: icon.reference, media: icon.file), resource: icon.file.resource)
            let fetchDisposable = fetchedMediaResource(mediaBox: engine.account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: reference).start()
            fetch.set(fetchDisposable, forKey: id)
        }
        for id in fetchedResourceIds.subtracting(resourceIds) {
            fetch.set(nil, forKey: id)
        }
        fetchedResourceIds = resourceIds
        promise.set(icons)
    }

    private enum Selection: Equatable {
        case defaultIcon
        case unavailable
        case resource(TelegramApplicationIcons.Icon)
    }

    private func observeSelection() {
        let signal = combineLatest(self.icons, dockSettings(accountManager: accountManager))
        |> map { icons, settings -> Selection in
            guard let selected = settings.iconSelected, selected != TelegramApplicationIcons.Icon.defaultIconName else {
                return .defaultIcon
            }
            guard let icon = icons.icons.first(where: { $0.file.fileName == selected }) else {
                return .unavailable
            }
            return .resource(icon)
        }
        |> distinctUntilChanged
        |> deliverOnMainQueue
        update.set(signal.start(next: { [weak self] selection in
            guard let self else { return }
            self.applyResource.set(nil)
            switch selection {
            case .defaultIcon:
                Dock.setCustomAppIcon(path: nil)
            case .unavailable:
                break
            case let .resource(icon):
                let resource = self.engine.account.postbox.mediaBox.resourceData(icon.file.resource) |> filter { $0.complete } |> take(1) |> deliverOnMainQueue
                self.applyResource.set(resource.start(next: { resource in
                    Dock.setCustomAppIcon(path: resource.path)
                }))
            }
        }))
    }
    public func clear() {
        update.dispose()
        fetch.dispose()
        disposable.dispose()
        applyResource.dispose()
    }
    
    deinit {
        clear()
    }
}

//
//private func moveIconToCache(path: String, icon: TelegramApplicationIcons.Icon) {
//    try? FileManager.default.createDirectory(at: URL(fileURLWithPath: iconsFolder), withIntermediateDirectories: true, attributes: nil)
//    
//    if let fileName = icon.file.fileName {
//        try? FileManager.default.copyItem(atPath: path, toPath: iconsFolder + "/" + fileName)
//    }
//}
