import Foundation
import Postbox
import TelegramCore

final class ChatNetworkSpeedNotice {
    private struct Timestamp {
        weak var network: NSObject?
        let value: TimeInterval

        init(network: NSObject, value: TimeInterval) {
            self.network = network
            self.value = value
        }
    }

    static let shared = ChatNetworkSpeedNotice()
    static let defaultPeriod: TimeInterval = 3_600

    private var timestamps: [ObjectIdentifier: Timestamp] = [:]

    func claim(network: NSObject, configuredPeriod: TimeInterval, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        precondition(Thread.isMainThread)
        let period = configuredPeriod.isFinite && configuredPeriod >= 0 ? configuredPeriod : Self.defaultPeriod
        timestamps = timestamps.filter { $0.value.network != nil }
        let id = ObjectIdentifier(network)
        if let last = timestamps[id], last.network === network, now - last.value <= period {
            return false
        }
        timestamps[id] = Timestamp(network: network, value: now)
        return true
    }

    static func isEligible(_ event: NetworkSpeedLimitedEvent, isMessageVisible: (MessageId) -> Bool) -> Bool {
        switch event {
        case .upload:
            return true
        case let .download(.message(messageId)):
            return isMessageVisible(messageId)
        }
    }

    static func speedFactor(_ configured: Double) -> Int {
        guard configured.isFinite, configured >= 1, configured <= Double(Int32.max) else { return 10 }
        return Int(configured)
    }
}
