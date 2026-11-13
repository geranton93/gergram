import Foundation

public protocol PostboxCoding {
    init(decoder: PostboxDecoder)
    func encode(_ encoder: PostboxEncoder)
}

public protocol MessageAttribute: PostboxCoding {}

public struct PostboxDecoder {
    private let data: Data
    init(buffer: MemoryBuffer) { self.data = buffer.makeData() }
    func decode<T: Decodable>(_ type: T.Type, forKey: String) -> T? {
        try? JSONDecoder().decode(type, from: self.data)
    }
    func decodeRootObject() -> PostboxCoding? { fatalError() }
    public func decodeInt32ForKey(_ key: String, orElse: Int32) -> Int32 { fatalError() }
    public func decodeInt64ForKey(_ key: String, orElse: Int64) -> Int64 { fatalError() }
    public func decodeOptionalStringForKey(_ key: String) -> String? { fatalError() }
    public func decodeOptionalInt32ForKey(_ key: String) -> Int32? { fatalError() }
    public func decodeStringForKey(_ key: String, orElse: String) -> String { fatalError() }
    public func decodeBoolForKey(_ key: String, orElse: Bool) -> Bool { fatalError() }
    public func decodeObjectForKey(_ key: String, decoder: (PostboxDecoder) -> Any) -> Any? { fatalError() }
    public func decodeObjectArrayWithDecoderForKey<T>(_ key: String) -> [T] { fatalError() }
}

public final class PostboxEncoder {
    private var data = Data()
    public init() {}
    func encode<T: Encodable>(_ value: T, forKey: String) { self.data = try! JSONEncoder().encode(value) }
    func encodeRootObject(_ value: PostboxCoding) { fatalError() }
    public func encodeInt32(_ value: Int32, forKey: String) { fatalError() }
    public func encodeInt64(_ value: Int64, forKey: String) { fatalError() }
    public func encodeString(_ value: String, forKey: String) { fatalError() }
    public func encodeBool(_ value: Bool, forKey: String) { fatalError() }
    public func encodeNil(forKey: String) { fatalError() }
    public func encodeObject(_ value: PostboxCoding, forKey: String) { fatalError() }
    public func encodeObjectArray<T>(_ value: [T], forKey: String) { fatalError() }
    public func makeData() -> Data { self.data }
}

struct StringCodingKey: CodingKey, ExpressibleByStringLiteral {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }

    init(stringLiteral value: String) {
        self.init(stringValue: value)
    }
}

public struct MediaId: Hashable {
    let namespace: Int32
    let id: Int64
}

public typealias MediaResourceId = String

public struct MediaResourceReference {
    let resource: Resource

    struct Resource {
        let id: MediaResourceId
    }
}

enum Namespaces {
    enum Message {
        static let Cloud: Int32 = 0
    }

    enum Peer {
        static let CloudUser = PeerId.Namespace._internalFromInt32Value(0)
        static let CloudGroup = PeerId.Namespace._internalFromInt32Value(1)
        static let CloudChannel = PeerId.Namespace._internalFromInt32Value(2)
    }

    enum Media {
        static let CloudFile: Int32 = 5
    }
}

protocol Peer {
    var id: PeerId { get }
    var isCopyProtectionEnabled: Bool { get }
}

struct RestrictionInfo {
    let rules = [1]
}

struct TelegramUser: Peer {
    let id: PeerId
    var botInfo: Bool? = nil
    var restrictionInfo: RestrictionInfo? = nil
    let isCopyProtectionEnabled = false
}

struct TelegramGroup: Peer {
    let id: PeerId
    var isCopyProtectionEnabled = false
}

struct TelegramChannel: Peer {
    let id: PeerId
    var isCopyProtectionEnabled = false
    var restrictionInfo: RestrictionInfo? = nil
}

struct CachedUserData {
    struct Flags: OptionSet {
        let rawValue: Int
        static let copyProtectionEnabled = Self(rawValue: 1)
        static let myCopyProtectionEnabled = Self(rawValue: 2)
    }

    var flags: Flags = []
}

protocol Media {}
struct TelegramMediaImage: Media {}
struct TelegramMediaFile: Media {}
struct TelegramMediaWebpage: Media {}
struct TelegramMediaPaidContent: Media {}

class Attribute: MessageAttribute {
    init() {}
    required init(decoder: PostboxDecoder) { fatalError() }
    func encode(_ encoder: PostboxEncoder) { fatalError() }
}

final class AutoclearTimeoutMessageAttribute: Attribute {}
final class AutoremoveTimeoutMessageAttribute: Attribute {}
final class EphemeralMessageAttribute: Attribute {}
final class EphemeralOutgoingMessageAttribute: Attribute {}
final class EphemeralReplacementMessageAttribute: Attribute {}
final class RestrictedContentMessageAttribute: Attribute {}
final class PaidStarsMessageAttribute: Attribute {}
final class RichTextMessageAttribute: Attribute {}
final class MediaSpoilerMessageAttribute: Attribute {}
final class PendingProcessingMessageAttribute: Attribute {}
final class ContentRequiresValidationMessageAttribute: Attribute {}
final class InlineBotMessageAttribute: Attribute {}
final class InlineBusinessBotMessageAttribute: Attribute {}

struct Message {
    struct Flags: OptionSet {
        let rawValue: Int
        static let Incoming = Self(rawValue: 1)
        static let CopyProtected = Self(rawValue: 2)
    }

    let id: MessageId
    var threadId: Int64? = nil
    var timestamp: Int32 = 100
    var flags: Flags = [.Incoming]
    var forwardInfo: Bool? = nil
    var author: Peer?
    var text: String = "before"
    var attributes: [MessageAttribute] = []
    var media: [Media] = []

    var textEntitiesAttribute: TextEntitiesMessageAttribute? {
        self.attributes.lazy.compactMap { $0 as? TextEntitiesMessageAttribute }.first
    }

    func isCopyProtected() -> Bool {
        self.flags.contains(.CopyProtected)
    }
}

struct StoreMessage {
    enum ID {
        case Id(MessageId)
        case Partial
    }

    let id: ID
    var flags: Message.Flags = [.Incoming]
    var forwardInfo: Bool? = nil
    var authorId: PeerId?
    var text: String = "after"
    var attributes: [MessageAttribute] = []
    var media: [Media] = []
}

public final class Transaction {
    var preferences: [ValueBoxKey: PreferencesEntry] = [:]
    var messages: [MessageId: Message] = [:]
    var globalIds: [Int32: MessageId] = [:]
    var peers: [PeerId: Peer] = [:]
    var cachedUsers: [PeerId: CachedUserData] = [:]
    var archiveWrites: [(account: Int64, messages: [LocalArchiveMessage])] = []
    var globalLookupCount = 0
    var messageLookupCount = 0

    func getPreferencesEntry(key: ValueBoxKey) -> PreferencesEntry? {
        preferences[key]
    }

    func updatePreferencesEntry(key: ValueBoxKey, _ update: (PreferencesEntry?) -> PreferencesEntry?) {
        preferences[key] = update(preferences[key])
    }

    func getMessage(_ id: MessageId) -> Message? {
        messageLookupCount += 1
        return messages[id]
    }

    func messageIdsForGlobalIds(_ ids: [Int32]) -> [MessageId] {
        globalLookupCount += 1
        return ids.compactMap { globalIds[$0] }
    }

    func getPeer(_ id: PeerId) -> Peer? {
        peers[id]
    }

    func getPeerCachedData(peerId: PeerId) -> Any? {
        cachedUsers[peerId]
    }

    func appendLocalArchiveMessages(accountId: Int64, messages: [LocalArchiveMessage], now: Int64) throws {
        archiveWrites.append((accountId, messages))
    }
}

final class ReplayContext {
    struct FinalState {
        struct State {
            var peers: [PeerId: Peer] = [:]
        }

        var state = State()
    }

    let accountPeerId: PeerId
    let transaction = Transaction()
    var finalState = FinalState()

    init(accountPeerId: PeerId) {
        self.accountPeerId = accountPeerId
    }
}
