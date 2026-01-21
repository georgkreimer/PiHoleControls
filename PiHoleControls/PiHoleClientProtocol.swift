//
//  PiHoleClientProtocol.swift
//  PiHoleControls
//
//  Protocol for Pi-hole API client to enable testing
//

import Foundation

/// Protocol defining the Pi-hole API operations
protocol PiHoleClientProtocol {
    /// Fetch the current blocking status
    /// - Parameter allowLegacyFallback: Whether to fall back to v5 API if v6 fails
    /// - Returns: true if blocking is enabled, false if disabled
    func fetchStatus(allowLegacyFallback: Bool) async throws -> Bool

    /// Enable ad blocking
    func enableBlocking() async throws

    /// Disable ad blocking
    /// - Parameter durationSeconds: Optional duration in seconds, nil for indefinite
    func disableBlocking(durationSeconds: Int?) async throws
}

// Default parameter value for protocol extension
extension PiHoleClientProtocol {
    func fetchStatus() async throws -> Bool {
        try await fetchStatus(allowLegacyFallback: true)
    }

    func disableBlocking() async throws {
        try await disableBlocking(durationSeconds: nil)
    }
}

// MARK: - PiHoleClient Conformance
extension PiHoleClient: PiHoleClientProtocol {}
