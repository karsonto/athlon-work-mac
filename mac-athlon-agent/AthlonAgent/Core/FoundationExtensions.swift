import Foundation
import os

// MARK: - Thread-Safe ISO8601DateFormatter Cache

/// Prevents repeated allocation of the *same* formatter across hot paths.
/// Access via `ISO8601DateFormatter.string(from:)` (static) which is lock-protected.
extension ISO8601DateFormatter {
    private static let _lock = NSLock()
    private static let _cached = ISO8601DateFormatter()

    /// Thread-safe convenience that reuses a single underlying formatter.
    /// Equivalent to `ISO8601DateFormatter().string(from: date)` but without the allocation.
    static func string(from date: Date) -> String {
        _lock.lock()
        let result = _cached.string(from: date)
        _lock.unlock()
        return result
    }
}

// MARK: - Thread-Safe DateFormatter Cache (audit day stamp)

extension DateFormatter {
    private static let _dayStampLock = NSLock()
    private static let _dayStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Thread-safe day-stamp generation: `"yyyy-MM-dd"`.
    static func dayStamp(from date: Date = Date()) -> String {
        _dayStampLock.lock()
        let result = _dayStampFormatter.string(from: date)
        _dayStampLock.unlock()
        return result
    }

    /// Pre-configured formatter for short time display (zh_CN locale).
    /// **Not thread-safe** – intended for use from `@MainActor` contexts only.
    /// Caller must set `dateFormat` before each use.
    static let shortTimeDisplay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()
}
