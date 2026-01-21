//
//  MockPiHoleClient.swift
//  PiHoleControlsTests
//
//  Mock implementation of PiHoleClientProtocol for testing
//

import Foundation
@testable import PiHoleControls

/// Mock Pi-hole client for unit testing
final class MockPiHoleClient: PiHoleClientProtocol {
    // Configurable responses
    var statusToReturn: Bool = true
    var errorToThrow: Error?

    // Call tracking
    private(set) var fetchStatusCallCount = 0
    private(set) var enableBlockingCallCount = 0
    private(set) var disableBlockingCallCount = 0
    private(set) var lastDisableDuration: Int?

    func fetchStatus(allowLegacyFallback: Bool) async throws -> Bool {
        fetchStatusCallCount += 1
        if let error = errorToThrow {
            throw error
        }
        return statusToReturn
    }

    func enableBlocking() async throws {
        enableBlockingCallCount += 1
        if let error = errorToThrow {
            throw error
        }
    }

    func disableBlocking(durationSeconds: Int?) async throws {
        disableBlockingCallCount += 1
        lastDisableDuration = durationSeconds
        if let error = errorToThrow {
            throw error
        }
    }

    // Helper to reset all tracking
    func reset() {
        statusToReturn = true
        errorToThrow = nil
        fetchStatusCallCount = 0
        enableBlockingCallCount = 0
        disableBlockingCallCount = 0
        lastDisableDuration = nil
    }
}
