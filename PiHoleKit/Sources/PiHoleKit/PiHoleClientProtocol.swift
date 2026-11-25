import Foundation

public protocol PiHoleClientProtocol: Sendable {
    func fetchStatus(allowLegacyFallback: Bool) async throws -> Bool
    func enableBlocking() async throws
    func disableBlocking(durationSeconds: Int?) async throws
    func fetchSummary() async throws -> PiHoleSummary
}

extension PiHoleClientProtocol {
    public func fetchStatus() async throws -> Bool {
        try await fetchStatus(allowLegacyFallback: true)
    }

    public func disableBlocking() async throws {
        try await disableBlocking(durationSeconds: nil)
    }
}

extension PiHoleClient: PiHoleClientProtocol {}
