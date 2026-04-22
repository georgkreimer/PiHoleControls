//
//  PiHoleSessionCacheTests.swift
//  PiHoleControlsTests
//

import Testing
import Foundation
@testable import PiHoleControls

@Suite("PiHoleSessionCache Tests")
struct PiHoleSessionCacheTests {

    private func makeCache() -> PiHoleSessionCache {
        PiHoleSessionCache()
    }

    @Test("Get returns nil for empty cache")
    func getEmptyCache() async {
        let cache = makeCache()
        let result = await cache.get(key: "test-key")
        #expect(result == nil)
    }

    @Test("Set and get returns stored session")
    func setAndGet() async {
        let cache = makeCache()
        let session = PiHoleSessionCache.Session(sid: "abc123", csrf: "csrf-token")

        await cache.set(session, key: "my-key")
        let result = await cache.get(key: "my-key")

        #expect(result?.sid == "abc123")
        #expect(result?.csrf == "csrf-token")
    }

    @Test("Get with wrong key returns nil")
    func getWrongKey() async {
        let cache = makeCache()
        let session = PiHoleSessionCache.Session(sid: "abc123", csrf: nil)

        await cache.set(session, key: "key-a")
        let result = await cache.get(key: "key-b")

        #expect(result == nil)
    }

    @Test("Set overwrites previous session")
    func setOverwrites() async {
        let cache = makeCache()
        let session1 = PiHoleSessionCache.Session(sid: "first", csrf: nil)
        let session2 = PiHoleSessionCache.Session(sid: "second", csrf: nil)

        await cache.set(session1, key: "key")
        await cache.set(session2, key: "key")
        let result = await cache.get(key: "key")

        #expect(result?.sid == "second")
    }

    @Test("Set with different key replaces previous entry")
    func setDifferentKey() async {
        let cache = makeCache()
        let session1 = PiHoleSessionCache.Session(sid: "first", csrf: nil)
        let session2 = PiHoleSessionCache.Session(sid: "second", csrf: nil)

        await cache.set(session1, key: "key-a")
        await cache.set(session2, key: "key-b")

        #expect(await cache.get(key: "key-a") == nil)
        #expect(await cache.get(key: "key-b")?.sid == "second")
    }

    @Test("Remove clears matching session")
    func removeMatchingKey() async {
        let cache = makeCache()
        let session = PiHoleSessionCache.Session(sid: "abc", csrf: nil)

        await cache.set(session, key: "my-key")
        await cache.remove(key: "my-key")
        let result = await cache.get(key: "my-key")

        #expect(result == nil)
    }

    @Test("Remove with wrong key does nothing")
    func removeWrongKey() async {
        let cache = makeCache()
        let session = PiHoleSessionCache.Session(sid: "abc", csrf: nil)

        await cache.set(session, key: "my-key")
        await cache.remove(key: "other-key")
        let result = await cache.get(key: "my-key")

        #expect(result?.sid == "abc")
    }

    @Test("Clear removes everything")
    func clearRemovesAll() async {
        let cache = makeCache()
        let session = PiHoleSessionCache.Session(sid: "abc", csrf: nil)

        await cache.set(session, key: "my-key")
        await cache.clear()
        let result = await cache.get(key: "my-key")

        #expect(result == nil)
    }

    @Test("Session with nil csrf is stored correctly")
    func nilCsrf() async {
        let cache = makeCache()
        let session = PiHoleSessionCache.Session(sid: "abc", csrf: nil)

        await cache.set(session, key: "key")
        let result = await cache.get(key: "key")

        #expect(result?.sid == "abc")
        #expect(result?.csrf == nil)
    }
}
