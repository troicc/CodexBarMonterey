import Foundation
import Dispatch

/// Back-deploys the small subset of Swift Clock/Duration functionality used by
/// CodexBarCore to macOS 12. Swift's native Duration and ContinuousClock are
/// runtime-gated to macOS 13, so merely lowering Package.swift is not sufficient.
public struct MontereyDuration: Sendable, Hashable, Comparable, Codable, AdditiveArithmetic {
    public struct Components: Sendable, Hashable, Codable {
        public let seconds: Int64
        public let attoseconds: Int64
    }

    public let timeInterval: TimeInterval

    public init(timeInterval: TimeInterval) {
        self.timeInterval = timeInterval.isFinite ? timeInterval : 0
    }

    public static let zero = MontereyDuration(timeInterval: 0)

    public static func seconds(_ value: TimeInterval) -> MontereyDuration {
        MontereyDuration(timeInterval: value)
    }

    public static func seconds<T: BinaryInteger>(_ value: T) -> MontereyDuration {
        MontereyDuration(timeInterval: TimeInterval(value))
    }

    public static func milliseconds(_ value: TimeInterval) -> MontereyDuration {
        MontereyDuration(timeInterval: value / 1_000)
    }

    public static func milliseconds<T: BinaryInteger>(_ value: T) -> MontereyDuration {
        MontereyDuration(timeInterval: TimeInterval(value) / 1_000)
    }

    public var components: Components {
        let whole = self.timeInterval.rounded(.towardZero)
        let fractional = self.timeInterval - whole
        return Components(
            seconds: Int64(whole),
            attoseconds: Int64((fractional * 1_000_000_000_000_000_000).rounded()))
    }

    public static func < (lhs: MontereyDuration, rhs: MontereyDuration) -> Bool {
        lhs.timeInterval < rhs.timeInterval
    }

    public static func + (lhs: MontereyDuration, rhs: MontereyDuration) -> MontereyDuration {
        MontereyDuration(timeInterval: lhs.timeInterval + rhs.timeInterval)
    }

    public static func - (lhs: MontereyDuration, rhs: MontereyDuration) -> MontereyDuration {
        MontereyDuration(timeInterval: lhs.timeInterval - rhs.timeInterval)
    }
}

public struct MontereyContinuousClock: Sendable {
    public struct Instant: Sendable, Hashable, Comparable, Codable {
        fileprivate let uptimeNanoseconds: UInt64

        public static var now: Instant {
            Instant(uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds)
        }

        public func advanced(by duration: MontereyDuration) -> Instant {
            let delta = duration.timeInterval * 1_000_000_000
            if delta >= 0 {
                let amount = UInt64(min(delta, Double(UInt64.max)))
                let result = self.uptimeNanoseconds.addingReportingOverflow(amount)
                return Instant(uptimeNanoseconds: result.overflow ? UInt64.max : result.partialValue)
            }
            let amount = UInt64(min(-delta, Double(UInt64.max)))
            return Instant(uptimeNanoseconds: self.uptimeNanoseconds > amount ? self.uptimeNanoseconds - amount : 0)
        }

        public func duration(to other: Instant) -> MontereyDuration {
            if other.uptimeNanoseconds >= self.uptimeNanoseconds {
                return MontereyDuration(
                    timeInterval: TimeInterval(other.uptimeNanoseconds - self.uptimeNanoseconds) / 1_000_000_000)
            }
            return MontereyDuration(
                timeInterval: -TimeInterval(self.uptimeNanoseconds - other.uptimeNanoseconds) / 1_000_000_000)
        }

        public static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.uptimeNanoseconds < rhs.uptimeNanoseconds
        }
    }

    public init() {}
    public var now: Instant { Instant.now }
    public static var now: Instant { Instant.now }
}

/// NSLock-backed replacement for OSAllocatedUnfairLock, which starts at macOS 13.
public final class MontereyStateLock<State>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State

    public init(initialState: State) {
        self.state = initialState
    }

    @discardableResult
    public func withLock<Result>(_ body: (inout State) throws -> Result) rethrows -> Result {
        self.lock.lock()
        defer { self.lock.unlock() }
        return try body(&self.state)
    }
}

extension Task where Success == Never, Failure == Never {
    public static func sleep(for duration: MontereyDuration) async throws {
        let seconds = max(0, duration.timeInterval)
        let nanoseconds = min(seconds * 1_000_000_000, TimeInterval(UInt64.max))
        try await Task.sleep(nanoseconds: UInt64(nanoseconds))
    }
}

extension URL {
    func montereyHost(percentEncoded: Bool) -> String? {
        if percentEncoded {
            return URLComponents(url: self, resolvingAgainstBaseURL: false)?.percentEncodedHost
        }
        return self.host
    }

    func montereyAppending(queryItems: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.queryItems = (components.queryItems ?? []) + queryItems
        return components.url ?? self
    }
}

extension String {
    func montereySplit(
        separator: String,
        maxSplits: Int = Int.max,
        omittingEmptySubsequences: Bool = true) -> [Substring]
    {
        guard !separator.isEmpty else { return [self[...]] }
        var result: [Substring] = []
        var cursor = self.startIndex
        var remaining = maxSplits
        while remaining > 0,
              let range = self.range(of: separator, range: cursor..<self.endIndex)
        {
            let piece = self[cursor..<range.lowerBound]
            if !omittingEmptySubsequences || !piece.isEmpty { result.append(piece) }
            cursor = range.upperBound
            remaining -= 1
        }
        let tail = self[cursor..<self.endIndex]
        if !omittingEmptySubsequences || !tail.isEmpty { result.append(tail) }
        return result
    }

    func montereyTrimmingPrefix(_ prefix: String) -> String {
        self.hasPrefix(prefix) ? String(self.dropFirst(prefix.count)) : self
    }

    func montereyRegexCaptures(_ pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let fullRange = NSRange(self.startIndex..<self.endIndex, in: self)
        return regex.matches(in: self, range: fullRange).map { match in
            (0..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                guard range.location != NSNotFound, let swiftRange = Range(range, in: self) else { return "" }
                return String(self[swiftRange])
            }
        }
    }

    func montereyFirstRegexCaptures(_ pattern: String) -> [String]? {
        self.montereyRegexCaptures(pattern).first
    }
}
