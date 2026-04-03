import Foundation

actor PiHoleSessionCache {
    static let shared = PiHoleSessionCache()

    struct Session {
        let sid: String
        let csrf: String?
    }

    private var cached: (session: Session, key: String, createdAt: Date)?
    private let ttl: TimeInterval = 25 * 60 // 25 minutes

    func get(key: String) -> Session? {
        guard let cached, cached.key == key else { return nil }
        if Date().timeIntervalSince(cached.createdAt) > ttl {
            self.cached = nil
            return nil
        }
        return cached.session
    }

    func set(_ session: Session, key: String) {
        cached = (session: session, key: key, createdAt: Date())
    }

    func remove(key: String) {
        if cached?.key == key {
            cached = nil
        }
    }

    func clear() {
        cached = nil
    }
}
