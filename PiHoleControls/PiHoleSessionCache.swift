import Foundation

actor PiHoleSessionCache {
    static let shared = PiHoleSessionCache()

    struct Session {
        let sid: String
        let csrf: String?
    }

    private var cache: [String: Session] = [:]

    func get(key: String) -> Session? {
        cache[key]
    }

    func set(_ session: Session, key: String) {
        cache[key] = session
    }

    func remove(key: String) {
        cache.removeValue(forKey: key)
    }

    func clear() {
        cache.removeAll()
    }
}
