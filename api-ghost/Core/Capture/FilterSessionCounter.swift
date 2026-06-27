import Foundation

/// Thread-safe in-memory tally of dropped requests for the current session. Never backed by the DB.
nonisolated final class FilterSessionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    nonisolated var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    @discardableResult
    nonisolated func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    nonisolated func reset() {
        lock.lock()
        defer { lock.unlock() }
        count = 0
    }
}
