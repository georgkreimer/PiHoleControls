//
//  MockPiHoleClient.swift
//  PiHoleControlsTests
//
//  Mock implementation of PiHoleClientProtocol for testing
//

import Foundation
import PiHoleKit

/// Mock Pi-hole client for unit testing
@MainActor
final class MockPiHoleClient: PiHoleClientProtocol {
    // Configurable responses
    var statusToReturn: Bool = true
    var summaryToReturn: PiHoleSummary = PiHoleSummary(queriesToday: 0, blockedToday: 0, blockPercentage: 0)
    var errorToThrow: Error?
    var onFetch: (() async throws -> Bool)?
    private(set) var lastAllowLegacyFallback: Bool?

    // Call tracking
    private(set) var fetchStatusCallCount = 0
    private(set) var enableBlockingCallCount = 0
    private(set) var disableBlockingCallCount = 0
    private(set) var fetchSummaryCallCount = 0
    private(set) var lastDisableDuration: Int?

    func fetchStatus(allowLegacyFallback: Bool) async throws -> Bool {
        fetchStatusCallCount += 1
        lastAllowLegacyFallback = allowLegacyFallback
        if let onFetch { return try await onFetch() }
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

    func fetchSummary() async throws -> PiHoleSummary {
        fetchSummaryCallCount += 1
        if let error = errorToThrow {
            throw error
        }
        return summaryToReturn
    }

    // Helper to reset all tracking
    func reset() {
        statusToReturn = true
        summaryToReturn = PiHoleSummary(queriesToday: 0, blockedToday: 0, blockPercentage: 0)
        errorToThrow = nil
        fetchStatusCallCount = 0
        enableBlockingCallCount = 0
        disableBlockingCallCount = 0
        fetchSummaryCallCount = 0
        lastDisableDuration = nil
    }
}
