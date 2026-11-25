import Foundation

public struct PiHoleSummary: Sendable, Equatable {
    public let queriesToday: Int
    public let blockedToday: Int
    public let blockPercentage: Double
    public let topBlockedDomain: String?

    public init(queriesToday: Int, blockedToday: Int, blockPercentage: Double, topBlockedDomain: String? = nil) {
        self.queriesToday = queriesToday
        self.blockedToday = blockedToday
        self.blockPercentage = blockPercentage
        self.topBlockedDomain = topBlockedDomain
    }
}
