import Foundation

public actor PiHoleSessionCache {
    public static let shared = PiHoleSessionCache()

    public struct Session: Sendable {
        public let sid: String
        public let csrf: String?

        public init(sid: String, csrf: String?) {
            self.sid = sid
            self.csrf = csrf
        }
    }

    private struct CachedSession {
        let session: Session
        let createdAt: Date
    }

    private var cache: [String: CachedSession] = [:]
    private let ttl: TimeInterval = 25 * 60

    public func get(key: String) -> Session? {
        guard let entry = cache[key] else { return nil }
        if Date().timeIntervalSince(entry.createdAt) > ttl {
            cache[key] = nil
            return nil
        }
        return entry.session
    }

    public func set(_ session: Session, key: String) {
        cache[key] = CachedSession(session: session, createdAt: Date())
    }

    public func remove(key: String) {
        cache[key] = nil
    }

    public func clear() {
        cache.removeAll()
    }
}
