import Foundation

private let kib: Int64 = 1024
private let mib = 1024 * kib
private let fileSize = 256 * mib
private let readSize = 64 * kib

enum FetchLocation: String, CaseIterable {
    case datacenter = "master"
    case cdn

    var workerLimit: Int { self == .datacenter ? 4 * 3 : 8 * 4 }
}

final class FetchingState {
    let fetchLocation: FetchLocation
    let minPartSize: Int64
    let maxPartSize: Int64
    let maxPendingParts: Int
    var window = fastDownloadInitialWindow
    var partSize = fastDownloadSmallPartSize
    var lastWindowDecrease = 0.0
    var recentParts: [(time: Double, bytes: Int64)] = []

    init(_ location: FetchLocation) {
        fetchLocation = location
        minPartSize = location == .datacenter ? 4 * kib : 128 * kib
        maxPartSize = location == .datacenter ? mib : 256 * kib
        maxPendingParts = location == .datacenter ? fastDownloadMasterPendingParts : fastDownloadCdnPendingParts
    }
}

private typealias Window = (Int64, Int64, Range<Int64>?, (Range<Int64>) -> Bool) -> Range<Int64>?

private struct Arrival {
    let range: Range<Int64>
    let issuedAt: Double
    let finish: Double
}

private struct Result {
    let goodput: Double
    let firstBytesMilliseconds: Double
    let requests: Int
    let peakPending: Int
}

private func simulate(location: FetchLocation, rate: Double, roundTrip: Double, window: Window) -> Result {
    let state = FetchingState(location)
    var now = 0.0
    var linkFreeAt = 0.0
    var cached = RangeSet<Int64>()
    var arrivals: [Arrival] = []
    var consumed: Int64 = 0
    var firstBytes: Double?
    var requests = 0
    var peakPending = 0
    func isCached(_ range: Range<Int64>) -> Bool { cached.isSuperset(of: RangeSet(range)) }
    var current = window(consumed, fileSize, nil, isCached)

    while consumed < fileSize {
        var excluded = cached
        for arrival in arrivals {
            excluded.insert(contentsOf: arrival.range)
        }
        let required = current.map { [(range: $0, priority: 2)] } ?? []
        var remaining = fetchV2PriorityRanges(required: required, knownSize: fileSize, excluded: excluded)
        let slots = min(state.window, state.maxPendingParts, location.workerLimit)
        while arrivals.count < slots, let (_, range) = fetchV2TakeNextPart(
            ranges: &remaining, partSize: state.partSize, minPartSize: state.minPartSize,
            maxPartSize: state.maxPartSize, alignment: state.minPartSize, boundaryLimit: mib
        ) {
            let begin = max(now + roundTrip, linkFreeAt)
            linkFreeAt = begin + 8 * Double(range.count) / rate
            arrivals.append(Arrival(range: range, issuedAt: now, finish: linkFreeAt))
            requests += 1
        }

        peakPending = max(peakPending, arrivals.count)
        precondition(!arrivals.isEmpty, "No queued range for an unfinished read at offset \(consumed)")
        let next = arrivals.removeFirst()
        now = next.finish
        cached.insert(contentsOf: next.range)
        adaptWindow(state: state, now: now, latency: now - next.issuedAt, bytes: Int64(next.range.count))
        if firstBytes == nil, isCached(0..<(512 * kib)) {
            firstBytes = now * 1000
        }
        while consumed < fileSize {
            let readEnd = min(consumed + readSize, fileSize)
            guard isCached(consumed..<readEnd) else { break }
            consumed = readEnd
            current = window(consumed, fileSize, current, isCached)
        }
    }

    let bitsPerSecond = Double(fileSize) * 8 / now
    guard let firstBytes else { preconditionFailure("The first 512 KiB never arrived") }
    precondition(bitsPerSecond <= rate + 1)
    return Result(goodput: bitsPerSecond / 1_000_000, firstBytesMilliseconds: firstBytes, requests: requests, peakPending: peakPending)
}

@main
private enum ReadAheadSweep {
    static func main() {
        let policies: [(name: String, window: Window)] = [
            ("baseline-2", BaselineDirectMediaReadAhead.window),
            ("baseline-4", BaselineReadAhead4.window),
            ("baseline-6", BaselineReadAhead6.window),
            ("baseline-8", BaselineReadAhead8.window),
            ("current-2", { DirectMediaReadAhead.window(at: $0, fileSize: $1, current: $2, replenishAfterRead: true, isCached: $3) }),
            ("current-4", { CurrentReadAhead4.window(at: $0, fileSize: $1, current: $2, replenishAfterRead: true, isCached: $3) }),
            ("current-6", { CurrentReadAhead6.window(at: $0, fileSize: $1, current: $2, replenishAfterRead: true, isCached: $3) }),
            ("current-8", { CurrentReadAhead8.window(at: $0, fileSize: $1, current: $2, replenishAfterRead: true, isCached: $3) }),
            ("whole", { _, size, _, _ in 0..<size }),
        ]
        let profiles = [(50, 20), (200, 100), (500, 100), (1000, 20), (1000, 100), (1000, 250)]
        print("target,link_mbit_s,rtt_ms,policy,goodput_mbit_s,first_512kib_ms,requests,peak_executing_rpcs")
        for location in FetchLocation.allCases {
            for (rate, roundTrip) in profiles {
                for (name, window) in policies {
                    let result = simulate(location: location, rate: Double(rate) * 1_000_000, roundTrip: Double(roundTrip) / 1000, window: window)
                    let goodput = String(format: "%.2f", result.goodput)
                    let firstBytes = String(format: "%.2f", result.firstBytesMilliseconds)
                    print("\(location.rawValue),\(rate),\(roundTrip),\(name),\(goodput),\(firstBytes),\(result.requests),\(result.peakPending)")
                }
            }
        }
    }
}
