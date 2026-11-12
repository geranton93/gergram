import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import InAppSettings
import TGUIKit
import FilePanels
import TelegramTheme
import TelegramUtils
import FoundationUtils
import Localization
import TelegramContext

public func saveAs(_ file: TelegramMediaFile, account: Account) {
    let name = account.postbox.mediaBox.resourceData(file.resource) |> take(1) |> mapToSignal { data -> Signal<(String, String), NoError> in
        guard data.complete else {
            return .complete()
        }
        if let ext = file.fileName?.nsstring.pathExtension {
            return .single((data.path, ext))
        }
        let ext = data.path.nsstring.pathExtension
        return resourceType(mimeType: file.mimeType) |> map { type in
            return (data.path, type == "*" || type == nil ? (ext.isEmpty ? "file" : ext) : type!)
        }
    } |> deliverOnMainQueue

    _ = name.start(next: { path, ext in
        savePanel(file: path, ext: ext, for: mainWindow, defaultName: file.fileName)
    })
}

public func saveAs(_ file: TelegramMediaFile, context: any AccountContextProtocol, message: Message) {
    _ = (saveFileExtension(file) |> take(1) |> deliverOnMainQueue).start(next: { ext in
        saveMediaAs(resource: file.resource, reference: .message(message: MessageReference(message), media: file), context: context, userLocation: .peer(message.id.peerId), ext: ext, defaultName: file.fileName, contentType: .init(file: file), statsCategory: statsCategoryForFileWithAttributes(file.attributes))
    })
}

public func saveImageAs(_ image: TelegramMediaImage, context: any AccountContextProtocol, message: Message) {
    guard let resource = image.representations.last?.resource else {
        return
    }
    saveMediaAs(resource: resource, reference: .message(message: MessageReference(message), media: image), context: context, userLocation: .peer(message.id.peerId), ext: "jpg", contentType: .image, statsCategory: .image)
}

public func saveStoryMediaAs(_ media: Media, context: any AccountContextProtocol, peer: Peer, storyId: Int32, defaultPhotoName: String, canSave: @escaping () -> Bool, completion: @escaping () -> Void) {
    guard canSave() else {
        completion()
        return
    }
    let reference = PeerReference(peer).map { AnyMediaReference.story(peer: $0, id: storyId, media: media) }
    let userLocation = MediaResourceUserLocation.peer(peer.id)
    if let image = media as? TelegramMediaImage, let resource = image.representations.last?.resource {
        saveMediaAs(resource: resource, reference: reference, context: context, userLocation: userLocation, ext: "jpeg", defaultName: defaultPhotoName, contentType: .story, statsCategory: .image, canSave: canSave, completion: completion)
    } else if let file = media as? TelegramMediaFile {
        _ = (saveFileExtension(file) |> take(1) |> deliverOnMainQueue).start(next: { ext in
            saveMediaAs(resource: file.resource, reference: reference, context: context, userLocation: userLocation, ext: ext, defaultName: file.fileName, contentType: .story, statsCategory: statsCategoryForFileWithAttributes(file.attributes), canSave: canSave, completion: completion)
        })
    } else {
        completion()
    }
}

private func saveFileExtension(_ file: TelegramMediaFile) -> Signal<String, NoError> {
    if let ext = file.fileName?.nsstring.pathExtension, !ext.isEmpty {
        return .single(ext)
    }
    return resourceType(mimeType: file.mimeType) |> map { type in
        guard let type, type != "*" else { return "file" }
        return type
    }
}

private func fetchedSaveMediaData(data: Signal<MediaResourceData, NoError>, status: Signal<MediaResourceStatus, NoError>, fetch: Signal<FetchResourceSourceType, FetchResourceError>) -> Signal<MediaResourceData, FetchResourceError> {
    return Signal { subscriber in
        let disposables = DisposableSet()
        let statusDisposable = MetaDisposable()
        disposables.add(statusDisposable)
        var started = false
        var fetching = false
        var fetchCompleted = false
        var finished = false

        func finish(_ value: MediaResourceData? = nil, error: FetchResourceError? = nil) {
            guard !finished else {
                return
            }
            finished = true
            disposables.dispose()
            if let value = value {
                subscriber.putNext(value)
            }
            if let error = error {
                subscriber.putError(error)
            } else {
                subscriber.putCompletion()
            }
        }

        statusDisposable.set((status |> deliverOnMainQueue).start(next: { value in
            guard !finished else {
                return
            }
            switch value {
            case .Fetching:
                fetching = true
            case .Remote, .Paused:
                if fetching {
                    finish()
                    return
                }
            case .Local:
                if started {
                    Queue.mainQueue().justDispatch {
                        if !fetchCompleted {
                            finish()
                        }
                    }
                }
            }
            if !started {
                started = true
                disposables.add((fetch |> deliverOnMainQueue).start(error: { error in
                    finish(error: error)
                }, completed: {
                    guard !finished else {
                        return
                    }
                    fetchCompleted = true
                    statusDisposable.dispose()
                    disposables.add((data |> take(1) |> deliverOnMainQueue).start(next: { data in
                        if data.complete {
                            finish(data)
                        } else {
                            finish(error: .generic)
                        }
                    }, completed: {
                        if !finished {
                            finish(error: .generic)
                        }
                    }))
                }))
            }
        }))
        return ActionDisposable {
            finished = true
            disposables.dispose()
        }
    } |> runOn(.mainQueue())
}

private struct SaveMediaDestination {
    let url: URL
    private let attributes: NSDictionary?

    init(url: URL) throws {
        self.url = url
        self.attributes = try SaveMediaDestination.attributes(at: url)
    }

    private static func attributes(at url: URL) throws -> NSDictionary? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path) as NSDictionary
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
    }

    func copy(from path: String) throws {
        let manager = FileManager.default
        let directory = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: self.url, create: true)
        defer {
            try? manager.removeItem(at: directory)
        }
        let temporary = directory.appendingPathComponent(self.url.lastPathComponent)
        try manager.copyItem(atPath: path, toPath: temporary.path)
        guard self.attributes == (try SaveMediaDestination.attributes(at: self.url)) else {
            throw CocoaError(.fileWriteFileExists)
        }
        if self.attributes != nil {
            _ = try manager.replaceItemAt(self.url, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: self.url)
        }
    }
}

private func saveMediaAs(resource: MediaResource, reference: AnyMediaReference?, context: any AccountContextProtocol, userLocation: MediaResourceUserLocation, ext: String, defaultName: String? = nil, contentType: MediaResourceUserContentType, statsCategory: MediaResourceStatsCategory, canSave: @escaping () -> Bool = { true }, completion: @escaping () -> Void = {}) {
    guard canSave() else {
        completion()
        return
    }
    let panel = NSSavePanel()
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    panel.nameFieldStringValue = defaultName ?? "\(dateFormatter.string(from: Date())).\(ext)"
    let window = context.window
    let level = window.level
    window.level = .normal

    panel.begin { result in
        window.level = level
        guard result == .OK, let url = panel.url, canSave() else {
            completion()
            return
        }
        let destination: SaveMediaDestination
        do {
            destination = try SaveMediaDestination(url: url)
        } catch {
            showModalText(for: window, text: strings().unknownError)
            completion()
            return
        }
        let mediaBox = context.account.postbox.mediaBox
        let disposable = MetaDisposable()
        var completed = false
        let finish = {
            guard !completed else { return }
            completed = true
            completion()
        }
        let signal = mediaBox.resourceData(resource) |> take(1) |> castError(FetchResourceError.self) |> deliverOnMainQueue |> mapToSignal { data -> Signal<MediaResourceData, FetchResourceError> in
            guard canSave() else { return .complete() }
            if data.complete {
                return .single(data)
            }
            guard let reference else { return .fail(.generic) }
            showModalText(for: window, text: strings().appUpdateDownloading, button: strings().modalCancel, callback: { _ in
                disposable.dispose()
                finish()
            })
            return fetchedSaveMediaData(data: mediaBox.resourceData(resource), status: mediaBox.resourceStatus(resource), fetch: fetchedMediaResource(mediaBox: mediaBox, userLocation: userLocation, userContentType: contentType, reference: reference.resourceReference(resource), statsCategory: statsCategory))
        } |> deliverOnMainQueue
        disposable.set(signal.start(next: { data in
            guard canSave() else { return }
            do {
                try destination.copy(from: data.path)
                delay(0.3, closure: {
                    FilePanelsHooks.shared?.showSavedPathSuccess(url.path)
                })
            } catch {
                showModalText(for: window, text: strings().unknownError)
            }
        }, error: { _ in
            if canSave() {
                showModalText(for: window, text: strings().unknownError)
            }
            finish()
        }, completed: finish))
    }
}

public func showInFinder(_ file:TelegramMediaFile, account:Account)  {
    let path = downloadFilePath(file, account.postbox) |> deliverOnMainQueue
    
    _ = combineLatest(queue: .mainQueue(), path, downloadedFilePaths(account.postbox)).start(next: { (expanded, paths) in
        
        guard let (boxPath, adopted) = expanded else {
            return
        }
        if let id = file.id {
            do {
                
                if let path = paths.path(for: id) {
                    let lastModified = Int32(FileManager.default.modificationDateForFileAtPath(path: path.downloadedPath)?.timeIntervalSince1970 ?? 0)
                    if fileSize(path.downloadedPath) == Int64(path.size), lastModified == path.lastModified {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path.downloadedPath)])
                        return
                    }
                
                }
                
                var adopted = adopted
                var i:Int = 1
                let deletedPathExt = adopted.nsstring.deletingPathExtension
                while FileManager.default.fileExists(atPath: adopted, isDirectory: nil) {
                    let ext = adopted.nsstring.pathExtension
                    adopted = "\(deletedPathExt) (\(i)).\(ext)"
                    i += 1
                }
                
                try? FileManager.default.copyItem(atPath: boxPath, toPath: adopted)
           
                let quarantineData = "does not really matter what is here".cString(using: String.Encoding.utf8)!
                _ = Int(strlen(quarantineData))
                
//                setxattr(adopted.cString(using: .utf8), "com.apple.quarantine", quarantineData, quarantineDataLength, 0, XATTR_CREATE)

                    // removexattr(adopted.cString(using: .utf8), "com.apple.quarantine", 0)

                
                let lastModified = FileManager.default.modificationDateForFileAtPath(path: adopted)?.timeIntervalSince1970 ?? FileManager.default.creationDateForFileAtPath(path: adopted)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
                
                let fs = fileSize(boxPath)
                let fileSize = fs ?? file.size ?? 0
                let path = DownloadedPath(id: id, downloadedPath: adopted, size: Int64(fileSize), lastModified: Int32(lastModified))
                
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: adopted)])
                _ = updateDownloadedFilePaths(account.postbox, {
                    $0.withAddedPath(path)
                }).start()
                
            }
        }
    })
}
