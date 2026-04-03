//
//  KeychainHelperTests.swift
//  PiHoleControlsTests
//
//  Tests for KeychainHelper using a test-specific key prefix to avoid
//  interfering with real app data.
//

import Testing
import Foundation
@testable import PiHoleControls

@Suite("KeychainHelper Tests")
struct KeychainHelperTests {

    /// Unique key prefix per test run to avoid collisions
    private let testKeyPrefix = "test-\(UUID().uuidString.prefix(8))"

    private func testKey(_ name: String) -> String {
        "\(testKeyPrefix)-\(name)"
    }

    private func cleanup(_ keys: String...) {
        for key in keys {
            try? KeychainHelper.delete(key: key)
        }
    }

    @Test("Save and retrieve a value")
    func saveAndRetrieve() throws {
        let key = testKey("save-retrieve")
        defer { cleanup(key) }

        try KeychainHelper.save(key: key, value: "test-token-123")
        let result = KeychainHelper.retrieve(key: key)

        #expect(result == "test-token-123")
    }

    @Test("Retrieve returns nil for nonexistent key")
    func retrieveNonexistent() {
        let key = testKey("nonexistent")
        let result = KeychainHelper.retrieve(key: key)
        #expect(result == nil)
    }

    @Test("Save overwrites existing value")
    func saveOverwrites() throws {
        let key = testKey("overwrite")
        defer { cleanup(key) }

        try KeychainHelper.save(key: key, value: "first-value")
        try KeychainHelper.save(key: key, value: "second-value")
        let result = KeychainHelper.retrieve(key: key)

        #expect(result == "second-value")
    }

    @Test("Delete removes value")
    func deleteRemoves() throws {
        let key = testKey("delete")

        try KeychainHelper.save(key: key, value: "to-delete")
        try KeychainHelper.delete(key: key)
        let result = KeychainHelper.retrieve(key: key)

        #expect(result == nil)
    }

    @Test("Delete nonexistent key does not throw")
    func deleteNonexistent() throws {
        let key = testKey("delete-nope")
        try KeychainHelper.delete(key: key)
    }

    @Test("Saving empty string deletes the key")
    func saveEmptyDeletesKey() throws {
        let key = testKey("empty-delete")
        defer { cleanup(key) }

        try KeychainHelper.save(key: key, value: "some-value")
        try KeychainHelper.save(key: key, value: "")
        let result = KeychainHelper.retrieve(key: key)

        #expect(result == nil)
    }

    @Test("Save and retrieve unicode value")
    func unicodeValue() throws {
        let key = testKey("unicode")
        defer { cleanup(key) }

        try KeychainHelper.save(key: key, value: "token-with-emoji-and-unicode")
        let result = KeychainHelper.retrieve(key: key)

        #expect(result == "token-with-emoji-and-unicode")
    }

    @Test("Save and retrieve long value")
    func longValue() throws {
        let key = testKey("long")
        defer { cleanup(key) }

        let longToken = String(repeating: "a", count: 1000)
        try KeychainHelper.save(key: key, value: longToken)
        let result = KeychainHelper.retrieve(key: key)

        #expect(result == longToken)
    }
}
