import Darwin
import Foundation
import SwiftSignalKit

public let crashReportsBotUsername = "macos_stable_updater_bot"

public struct CrashReport: Equatable {
    public let url: URL
    public let date: Date
    public let incidentId: String
    public let appVersion: String
    public let buildVersion: String
}

public final class CrashReportStore {
    private static let rescanDelays: [Double] = [0, 15, 45, 120, 300]
    private static let maxReports = 5
    static let maxCandidates = 64
    static let maxReportBytes = 8 * 1024 * 1024

    private struct Candidate {
        let name: String
        let date: Date
        let metadata: stat
    }

    private let directory: URL
    private let executablePath: String
    private let anonymizedExecutablePath: String
    private let processName: String
    private let handledKey: String
    private let defaults: UserDefaults
    private let queue = Queue(name: "org.telegram.crashReports")
    private let reportsPromise = ValuePromise<[CrashReport]>([], ignoreRepeated: true)
    private var started = false

    public init(handledKey: String, directory: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/DiagnosticReports"), executablePath: String = Bundle.main.executablePath ?? "", homeDirectory: String = NSHomeDirectory(), defaults: UserDefaults = .standard, now: Date = Date()) {
        self.directory = directory
        self.executablePath = executablePath
        if !homeDirectory.isEmpty, executablePath.hasPrefix(homeDirectory + "/") {
            self.anonymizedExecutablePath = "/Users/USER" + executablePath.dropFirst(homeDirectory.count)
        } else {
            self.anonymizedExecutablePath = executablePath
        }
        self.processName = URL(fileURLWithPath: executablePath).lastPathComponent
        self.handledKey = handledKey
        self.defaults = defaults
        if defaults.object(forKey: handledKey) == nil {
            defaults.set(now.timeIntervalSince1970, forKey: handledKey)
        }
    }

    public var reports: Signal<[CrashReport], NoError> {
        self.queue.async { [weak self] in
            guard let self, !self.started else {
                return
            }
            self.started = true
            for delay in CrashReportStore.rescanDelays {
                self.queue.after(delay, { [weak self] in
                    self?.rescan()
                })
            }
        }
        return self.reportsPromise.get()
    }

    public func markHandled(_ reports: [CrashReport]) {
        guard let newest = reports.map({ $0.date }).max() else {
            return
        }
        self.queue.async {
            let handled = self.defaults.double(forKey: self.handledKey)
            self.defaults.set(max(handled, newest.timeIntervalSince1970), forKey: self.handledKey)
            self.rescan()
        }
    }

    public func rescan() {
        self.reportsPromise.set(self.scan())
    }

    public func scan() -> [CrashReport] {
        let handled = self.defaults.double(forKey: self.handledKey)
        guard directory.isFileURL else { return [] }
        let descriptor = directory.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW) } ?? -1
        }
        guard descriptor >= 0 else { return [] }
        guard let entries = fdopendir(descriptor) else {
            close(descriptor)
            return []
        }
        defer { closedir(entries) }

        let prefix = self.processName + "-"
        var candidates: [Candidate] = []
        while let entry = readdir(entries) {
            let name = withUnsafeBytes(of: &entry.pointee.d_name) { bytes in
                bytes.bindMemory(to: CChar.self).baseAddress.flatMap(String.init(validatingUTF8:))
            }
            guard let name, !name.hasPrefix("."), name.hasPrefix(prefix), name.hasSuffix(".ips") else { continue }
            var metadata = stat()
            guard fstatat(descriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0,
                  (metadata.st_mode & S_IFMT) == S_IFREG, metadata.st_nlink == 1,
                  metadata.st_size > 0, metadata.st_size <= Self.maxReportBytes else { continue }
            let date = Date(timeIntervalSince1970: Double(metadata.st_mtimespec.tv_sec) + Double(metadata.st_mtimespec.tv_nsec) / 1_000_000_000)
            guard date.timeIntervalSince1970 > handled else { continue }
            let index = candidates.firstIndex { $0.date < date || ($0.date == date && $0.name > name) } ?? candidates.count
            if index < Self.maxCandidates {
                candidates.insert(Candidate(name: name, date: date, metadata: metadata), at: index)
                if candidates.count > Self.maxCandidates { candidates.removeLast() }
            }
        }

        var reports: [CrashReport] = []
        for candidate in candidates {
            if let report = read(candidate, from: descriptor) {
                reports.append(report)
                if reports.count == Self.maxReports { break }
            }
        }
        var openedDirectory = stat()
        var namedDirectory = stat()
        guard fstat(descriptor, &openedDirectory) == 0,
              directory.withUnsafeFileSystemRepresentation({ path in path.map { lstat($0, &namedDirectory) } ?? -1 }) == 0,
              openedDirectory.st_dev == namedDirectory.st_dev, openedDirectory.st_ino == namedDirectory.st_ino else { return [] }
        return reports
    }

    private static func sameFile(_ lhs: stat, _ rhs: stat) -> Bool {
        return lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && lhs.st_size == rhs.st_size
            && lhs.st_mode == rhs.st_mode && lhs.st_nlink == rhs.st_nlink
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    private func read(_ candidate: Candidate, from directoryDescriptor: Int32) -> CrashReport? {
        let descriptor = openat(directoryDescriptor, candidate.name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var opened = stat()
        guard fstat(descriptor, &opened) == 0, Self.sameFile(opened, candidate.metadata) else { return nil }
        let size = Int(opened.st_size)
        var data = Data()
        data.reserveCapacity(size)
        var buffer = [UInt8](repeating: 0, count: min(size + 1, 64 * 1024))
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, min(bytes.count, size - data.count + 1))
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0, count <= size - data.count else { return nil }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        let url = directory.appendingPathComponent(candidate.name)
        guard data.count == size, let report = parse(data, url: url, date: candidate.date) else { return nil }
        var current = stat()
        guard fstatat(directoryDescriptor, candidate.name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              Self.sameFile(opened, current) else { return nil }
        return report
    }

    private func parse(_ data: Data, url: URL, date: Date) -> CrashReport? {
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")) else {
            return nil
        }
        guard let header = (try? JSONSerialization.jsonObject(with: data[data.startIndex ..< newline])) as? [String: Any], header["bug_type"] as? String == "309" else {
            return nil
        }
        guard let body = (try? JSONSerialization.jsonObject(with: data[data.index(after: newline)...])) as? [String: Any], let procPath = body["procPath"] as? String else {
            return nil
        }
        guard procPath == self.executablePath || procPath == self.anonymizedExecutablePath else {
            return nil
        }
        return CrashReport(url: url, date: date, incidentId: header["incident_id"] as? String ?? url.lastPathComponent, appVersion: header["app_version"] as? String ?? "", buildVersion: header["build_version"] as? String ?? "")
    }
}
