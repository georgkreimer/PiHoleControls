import Foundation
import SwiftUI
import Combine
import Network

@MainActor
final class PiHoleStore: ObservableObject {
    // Settings (host stays in AppStorage, token moves to Keychain)
    @AppStorage("piholeHost") var host: String = "pi.hole"
    @AppStorage("allowSelfSignedCert") var allowSelfSignedCert: Bool = false
    @AppStorage("defaultDisableMinutes") var defaultDisableMinutes: Int = 5

    // Token with Keychain backing
    private static let tokenKeychainKey = "piholeAPIToken"
    @Published var token: String = "" {
        didSet {
            if oldValue != token {
                try? KeychainHelper.save(key: Self.tokenKeychainKey, value: token)
            }
        }
    }

    // UI state
    @Published var isBlockingEnabled: Bool?
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    @Published var remainingDisableSeconds: Int?
    @Published var isNetworkAvailable: Bool = true

    // Auto refresh
    private var refreshTask: Task<Void, Never>?
    private var followUpRefreshTask: Task<Void, Never>?
    private var countdownTimer: Timer?
    private let refreshIntervalSeconds: TimeInterval = 20

    // Retry configuration
    private let maxRetryAttempts = 3
    private let baseRetryDelay: TimeInterval = 1.0

    // Network monitoring
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "NetworkMonitor")

    var isConfigured: Bool { !host.isEmpty && !token.isEmpty }

    init() {
        // Load token from Keychain on init
        if let savedToken = KeychainHelper.retrieve(key: Self.tokenKeychainKey) {
            token = savedToken
        }
        
        // Migrate from old AppStorage if exists
        migrateTokenFromAppStorage()
        
        // Start network monitoring
        startNetworkMonitoring()
    }

    deinit {
        networkMonitor.cancel()
    }

    // MARK: - Token Migration

    private func migrateTokenFromAppStorage() {
        let oldTokenKey = "piholeToken"
        if let oldToken = UserDefaults.standard.string(forKey: oldTokenKey), !oldToken.isEmpty {
            // Save to Keychain
            try? KeychainHelper.save(key: Self.tokenKeychainKey, value: oldToken)
            token = oldToken
            // Remove from UserDefaults
            UserDefaults.standard.removeObject(forKey: oldTokenKey)
        }
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasAvailable = self.isNetworkAvailable
                self.isNetworkAvailable = path.status == .satisfied
                
                // If network became available, trigger a refresh
                if !wasAvailable && self.isNetworkAvailable {
                    self.refreshStatus()
                }
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    // MARK: - Menu bar helpers

    var menuBarTitle: String {
        if isLoading { return "" }
        switch isBlockingEnabled {
        case .some(true):
            return ""
        case .some(false):
            if let remaining = remainingDisableSeconds, remaining > 0 {
                let min = remaining / 60
                let sec = remaining % 60
                return String(format: "%d:%02d", min, sec)
            }
            return ""
        case .none:
            return ""
        }
    }

    var menuBarIconSystemName: String {
        if isLoading { return "arrow.triangle.2.circlepath" }
        guard let enabled = isBlockingEnabled else { return "questionmark.circle" }
        return enabled ? "shield.lefthalf.filled" : "shield.slash"
    }

    // MARK: - Client factory

    private func makeClient() -> PiHoleClient? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return PiHoleClient(host: trimmedHost, token: trimmedToken, allowSelfSignedCert: allowSelfSignedCert)
    }

    // MARK: - Public operations (fire-and-forget wrappers for UI)

    func toggleBlocking() {
        guard !isLoading else { return }
        if isBlockingEnabled == true {
            disableBlocking(durationSeconds: defaultDisableMinutes > 0 ? defaultDisableMinutes * 60 : nil)
        } else if isBlockingEnabled == false {
            enableBlocking()
        } else {
            refreshStatus()
        }
    }

    func enableBlocking() {
        Task { await enableBlockingAsync() }
    }

    func disableBlocking(durationSeconds: Int? = nil) {
        Task { await disableBlockingAsync(durationSeconds: durationSeconds) }
    }

    func refreshStatus() {
        Task { await refreshStatusAsync() }
    }

    // MARK: - Async implementations with retry

    private func setLoading(_ loading: Bool) {
        isLoading = loading
        if loading { lastError = nil }
    }

    private func requireClientOrFail() -> PiHoleClient? {
        guard let client = makeClient() else {
            lastError = PiHoleClient.PiHoleError.notConfigured.localizedDescription
            return nil
        }
        return client
    }

    /// Execute an async operation with exponential backoff retry
    private func withRetry<T>(
        maxAttempts: Int = 3,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Don't retry on configuration errors or if cancelled
                if error is CancellationError { throw error }
                if case PiHoleClient.PiHoleError.notConfigured = error { throw error }
                
                // Last attempt, don't sleep
                if attempt == maxAttempts - 1 { break }
                
                // Exponential backoff: 1s, 2s, 4s...
                let delay = baseRetryDelay * pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw lastError ?? PiHoleClient.PiHoleError.invalidURL
    }

    private func refreshStatusAsync() async {
        guard let client = requireClientOrFail() else { return }
        setLoading(true)
        let startTime = Date()
        let minimumLoadingDuration: TimeInterval = 2.0
        
        do {
            let enabled = try await withRetry {
                try await client.fetchStatus()
            }
            
            // Ensure loading state is visible for at least minimumLoadingDuration
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < minimumLoadingDuration {
                try? await Task.sleep(nanoseconds: UInt64((minimumLoadingDuration - elapsed) * 1_000_000_000))
            }
            
            isBlockingEnabled = enabled
            lastError = nil
            // If enabled, stop countdown; if disabled and we don't know remaining time, leave as is.
            if enabled { stopDisableCountdown() }
        } catch {
            // Ensure loading state is visible for at least minimumLoadingDuration even on error
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < minimumLoadingDuration {
                try? await Task.sleep(nanoseconds: UInt64((minimumLoadingDuration - elapsed) * 1_000_000_000))
            }
            
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        setLoading(false)
    }

    private func enableBlockingAsync() async {
        guard let client = requireClientOrFail() else { return }
        setLoading(true)
        defer { setLoading(false) }
        do {
            try await withRetry {
                try await client.enableBlocking()
            }
            isBlockingEnabled = true
            lastError = nil
            stopDisableCountdown()
            // Refresh after a brief delay to ensure status reflects server state.
            scheduleFollowUpRefresh()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func disableBlockingAsync(durationSeconds: Int?) async {
        guard let client = requireClientOrFail() else { return }
        setLoading(true)
        defer { setLoading(false) }
        do {
            try await withRetry {
                try await client.disableBlocking(durationSeconds: durationSeconds)
            }
            isBlockingEnabled = false
            lastError = nil
            if let seconds = durationSeconds {
                startDisableCountdown(from: seconds)
            } else {
                remainingDisableSeconds = nil
                stopDisableCountdown()
            }
            scheduleFollowUpRefresh()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func scheduleFollowUpRefresh() {
        followUpRefreshTask?.cancel()
        followUpRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            guard let self, !Task.isCancelled else { return }
            await self.refreshStatusAsync()
        }
    }

    // MARK: - Auto refresh

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshStatusAsync()
                try? await Task.sleep(nanoseconds: UInt64(self.refreshIntervalSeconds * 1_000_000_000))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Disable countdown

    private func startDisableCountdown(from seconds: Int) {
        stopDisableCountdown()
        let clampedSeconds = max(0, seconds)
        remainingDisableSeconds = clampedSeconds

        guard clampedSeconds > 0 else {
            handleDisableCountdownFinished()
            return
        }

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let remaining = self.remainingDisableSeconds else {
                    self.stopDisableCountdown()
                    return
                }

                if remaining > 1 {
                    self.remainingDisableSeconds = remaining - 1
                } else {
                    self.handleDisableCountdownFinished()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func handleDisableCountdownFinished() {
        stopDisableCountdown()
        if isBlockingEnabled != true {
            enableBlocking()
        } else {
            refreshStatus()
        }
    }

    private func stopDisableCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        remainingDisableSeconds = nil
    }
}
