import Foundation
import Postbox
import TelegramCore

final class ChatNetworkSpeedNotice {
    struct Download: Equatable {
        let messageId: MessageId
        let resourceId: MediaResourceId

        init(messageId: MessageId, resourceId: MediaResourceId) {
            self.messageId = messageId
            self.resourceId = resourceId
        }

        init?(event: NetworkSpeedLimitedEvent, resourceId: MediaResourceId?) {
            guard case let .download(.message(messageId)) = event, let resourceId else { return nil }
            self.init(messageId: messageId, resourceId: resourceId)
        }

        func matches(media: Media?) -> Bool {
            if let file = media as? TelegramMediaFile {
                return file.resource.id == resourceId
            }
            if let image = media as? TelegramMediaImage {
                return image.video?.resource.id == resourceId
                    || image.videoRepresentations.contains { $0.resource.id == resourceId }
                    || image.representations.contains { $0.resource.id == resourceId }
            }
            return false
        }
    }

    private struct AccountState {
        weak var network: NSObject?
        var lastPresentedAt: TimeInterval?
        var pending: [PendingDownload] = []
    }

    private struct PendingDownload {
        let download: Download
        let receivedAt: TimeInterval
    }

    static let shared = ChatNetworkSpeedNotice()
    static let defaultPeriod: TimeInterval = 3_600
    private static let pendingDownloadLifetime: TimeInterval = 300
    private static let maximumPendingDownloads = 16

    private var accounts: [ObjectIdentifier: AccountState] = [:]

    func claim(network: NSObject, configuredPeriod: TimeInterval, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        precondition(Thread.isMainThread)
        accounts = accounts.filter { $0.value.network != nil }
        let id = ObjectIdentifier(network)
        var account = accounts[id] ?? AccountState(network: network)
        if Self.isCoolingDown(account, configuredPeriod: configuredPeriod, now: now) {
            return false
        }
        account.lastPresentedAt = now
        account.pending.removeAll()
        accounts[id] = account
        return true
    }

    func enqueue(_ download: Download, network: NSObject, configuredPeriod: TimeInterval = defaultPeriod, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        precondition(Thread.isMainThread)
        let id = ObjectIdentifier(network)
        accounts = accounts.filter { $0.value.network != nil }
        var account = accounts[id] ?? AccountState(network: network)
        if Self.isCoolingDown(account, configuredPeriod: configuredPeriod, now: now) {
            return
        }
        account.pending.removeAll { !Self.isCurrent($0, now: now) }
        if !account.pending.contains(where: { $0.download == download }) {
            if account.pending.count == Self.maximumPendingDownloads {
                account.pending.removeFirst()
            }
            account.pending.append(PendingDownload(download: download, receivedAt: now))
        }
        accounts[id] = account
    }

    func pendingDownloads(network: NSObject, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [Download] {
        precondition(Thread.isMainThread)
        let id = ObjectIdentifier(network)
        guard var account = accounts[id], account.network === network, !account.pending.isEmpty else { return [] }
        let previousCount = account.pending.count
        account.pending.removeAll { !Self.isCurrent($0, now: now) }
        if account.pending.count != previousCount {
            accounts[id] = account
        }
        return account.pending.map(\.download)
    }

    func discardPendingDownloads(network: NSObject) {
        precondition(Thread.isMainThread)
        accounts[ObjectIdentifier(network)]?.pending.removeAll()
    }

    private static func isCurrent(_ pending: PendingDownload, now: TimeInterval) -> Bool {
        return now - pending.receivedAt < pendingDownloadLifetime
    }

    private static func isCoolingDown(_ account: AccountState, configuredPeriod: TimeInterval, now: TimeInterval) -> Bool {
        guard let lastPresentedAt = account.lastPresentedAt else { return false }
        let period = configuredPeriod.isFinite && configuredPeriod >= 0 ? configuredPeriod : defaultPeriod
        return now - lastPresentedAt <= period
    }

    static func speedFactor(_ configured: Double) -> Int {
        guard configured.isFinite, configured >= 1, configured <= Double(Int32.max) else { return 10 }
        return Int(configured)
    }
}
