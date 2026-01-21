import Foundation

actor PiHoleSessionCache {
    static let shared = PiHoleSessionCache()

    struct Session {
        let sid: String
        let csrf: String?
    }

    private struct CachedSession {
        let session: Session
        let createdAt: Date
    }

    private var cache: [String: CachedSession] = [:]
    private let ttl: TimeInterval = 25 * 60 // 25 minutes
    private let maxEntries = 10

    func get(key: String) -> Session? {
        cleanupExpired()
        guard let cached = cache[key] else { return nil }

        // Check if expired
        if Date().timeIntervalSince(cached.createdAt) > ttl {
            cache.removeValue(forKey: key)
            return nil
        }

        return cached.session
    }

    func set(_ session: Session, key: String) {
        cleanupExpired()

        // Enforce max entries by removing oldest if at capacity
        if cache.count >= maxEntries && cache[key] == nil {
            if let oldestKey = cache.min(by: { $0.value.createdAt < $1.value.createdAt })?.key {
                cache.removeValue(forKey: oldestKey)
            }
        }

        cache[key] = CachedSession(session: session, createdAt: Date())
    }

    func remove(key: String) {
        cache.removeValue(forKey: key)
    }

    func clear() {
        cache.removeAll()
    }

    private func cleanupExpired() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.createdAt) <= ttl }
    }
}
