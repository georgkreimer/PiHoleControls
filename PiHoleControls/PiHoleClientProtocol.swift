//
//  PiHoleClientProtocol.swift
//  PiHoleControls
//
//  Protocol for Pi-hole API client to enable testing
//

import Foundation

/// A recently blocked DNS query
struct BlockedQuery: Identifiable, Equatable {
    let id = UUID()
    let domain: String
    let timestamp: Date
}

/// Protocol defining the Pi-hole API operations
protocol PiHoleClientProtocol {
    /// Fetch the current blocking status
    func fetchStatus(allowLegacyFallback: Bool) async throws -> Bool

    /// Enable ad blocking
    func enableBlocking() async throws

    /// Disable ad blocking
    func disableBlocking(durationSeconds: Int?) async throws

    /// Fetch recently blocked domains
    func fetchRecentBlocked(count: Int) async throws -> [BlockedQuery]

    /// Add a domain to the allowlist
    func allowDomain(_ domain: String) async throws

    /// Remove a domain from the allowlist
    func removeDomain(_ domain: String) async throws
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
