import Foundation
import SwiftUI
import Combine
import Network

@MainActor
final class PiHoleStore: ObservableObject {
    /// Factory closure type for creating Pi-hole clients
    typealias ClientFactory = (String, String, Bool) -> (any PiHoleClientProtocol)?

    // Settings (host stays in AppStorage, token moves to Keychain)
    @AppStorage("piholeHost") var host: String = ""
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

    // Retry configuration (baseRetryDelay injectable for testing)
    private let maxRetryAttempts = 3
    let baseRetryDelay: TimeInterval

    // Network monitoring
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "NetworkMonitor")
    private var networkDebounceTask: Task<Void, Never>?
    private let networkDebounceInterval: TimeInterval = 0.5

    // Dependency injection for testing
    private let makeClientFn: ClientFactory

    var isConfigured: Bool { !host.isEmpty && !token.isEmpty }

    /// Default client factory that creates real PiHoleClient instances
    static let defaultClientFactory: ClientFactory = { host, token, allowSelfSigned in
        PiHoleClient(host: host, token: token, allowSelfSignedCert: allowSelfSigned)
    }

    init(clientFactory: ClientFactory? = nil, baseRetryDelay: TimeInterval = 1.0) {
        self.makeClientFn = clientFactory ?? Self.defaultClientFactory
        self.baseRetryDelay = baseRetryDelay

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
        // Skip if Keychain already has a token (already migrated or set via UI)
        if KeychainHelper.retrieve(key: Self.tokenKeychainKey) != nil {
            // Clean up old AppStorage key if it exists
            UserDefaults.standard.removeObject(forKey: "piholeToken")
            return
        }

        let oldTokenKey = "piholeToken"
        if let oldToken = UserDefaults.standard.string(forKey: oldTokenKey), !oldToken.isEmpty {
            // Save to Keychain first, only remove from UserDefaults if save succeeds
            do {
                try KeychainHelper.save(key: Self.tokenKeychainKey, value: oldToken)
                token = oldToken
                UserDefaults.standard.removeObject(forKey: oldTokenKey)
            } catch {
                // Migration failed - keep old token in UserDefaults for next attempt
            }
        }
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasAvailable = self.isNetworkAvailable
                self.isNetworkAvailable = path.status == .satisfied

                // If network became available, trigger a debounced refresh
                if !wasAvailable && self.isNetworkAvailable {
                    self.scheduleNetworkRefresh()
                }
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    private func scheduleNetworkRefresh() {
        networkDebounceTask?.cancel()
        let debounceNanos = UInt64(networkDebounceInterval * 1_000_000_000)
        networkDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled, let self else { return }
            self.refreshStatus()
        }
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

    private func makeClient() -> (any PiHoleClientProtocol)? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return makeClientFn(trimmedHost, trimmedToken, allowSelfSignedCert)
    }

    // MARK: - Connection test (used by settings UI)

    enum ConnectionTestResult {
        case success
        case failure(String)
    }

    func testConnection() async -> ConnectionTestResult {
        let sanitizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitizedHost != host { host = sanitizedHost }
        if sanitizedToken != token { token = sanitizedToken }

        guard let client = makeClient() else {
            return .failure("Enter a valid host and API token first.")
        }
        do {
            _ = try await client.fetchStatus(allowLegacyFallback: false)
            return .success
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .failure(message)
        }
    }

    var isHttpHost: Bool {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("http://")
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

    private func requireClientOrFail() -> (any PiHoleClientProtocol)? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedHost.isEmpty && trimmedToken.isEmpty {
            lastError = "Enter host and API token in Settings first."
            return nil
        }
        if trimmedHost.isEmpty {
            lastError = "Enter host in Settings first."
            return nil
        }
        if trimmedToken.isEmpty {
            lastError = "Enter API token in Settings first."
            return nil
        }

        guard let client = makeClient() else {
            lastError = "Invalid host. Include http:// or https:// and avoid extra paths."
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
                if let apiError = error as? PiHoleClient.PiHoleError, apiError.isLegacyServerError {
                    throw error
                }
                
                // Last attempt, don't sleep
                if attempt == maxAttempts - 1 { break }
                
                // Exponential backoff: 1s, 2s, 4s...
                let delay = baseRetryDelay * pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw lastError ?? PiHoleClient.PiHoleError.invalidURL
    }

    func refreshStatusAsync() async {
        guard let client = requireClientOrFail() else { return }
        setLoading(true)
        defer { setLoading(false) }

        do {
            let enabled = try await withRetry {
                try await client.fetchStatus()
            }
            isBlockingEnabled = enabled
            lastError = nil
            // If enabled, stop countdown; if disabled and we don't know remaining time, leave as is.
            if enabled { stopDisableCountdown() }
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func enableBlockingAsync() async {
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

    func disableBlockingAsync(durationSeconds: Int?) async {
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
            MainActor.assumeIsolated {
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
