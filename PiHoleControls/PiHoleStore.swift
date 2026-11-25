import Foundation
import SwiftUI
import Combine
import Network

@MainActor
final class PiHoleStore: ObservableObject {
    /// Factory closure type for creating Pi-hole clients
    typealias ClientFactory = (String, String, Bool) -> (any PiHoleClientProtocol)?

    @Published var host: String {
        didSet {
            defaults.set(host, forKey: "piholeHost")
            if oldValue != host { configurationDidChange() }
        }
    }
    @Published var allowSelfSignedCert: Bool {
        didSet {
            defaults.set(allowSelfSignedCert, forKey: "allowSelfSignedCert")
            if oldValue != allowSelfSignedCert { configurationDidChange() }
        }
    }
    @Published var defaultDisableMinutes: Int {
        didSet { defaults.set(defaultDisableMinutes, forKey: "defaultDisableMinutes") }
    }

    // Token with Keychain backing
    @Published var token: String = "" {
        didSet {
            if oldValue != token {
                configurationDidChange()
                do { try tokenStorage.save(token) }
                catch { lastError = "Could not save API token: \(error.localizedDescription)" }
            }
        }
    }

    // UI state
    @Published var isBlockingEnabled: Bool?
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    @Published var remainingDisableSeconds: Int?
    @Published var isNetworkAvailable: Bool = true

    struct TempAllowEntry: Codable, Identifiable, Equatable {
        let domain: String
        let expiresAt: Date
        // Nil for old entries: neither origin nor ownership was recorded.
        var server: String? = nil
        var id: String { "\(server ?? "unknown")|\(domain)" }
    }
    @Published var recentBlocked: [BlockedQuery] = []
    @Published private(set) var tempAllowList: [TempAllowEntry] = []
    @Published private(set) var cleanupError: String?
    private let cleanupStorage: CleanupStorage
    private var cleanupStorageReady = false
    private var cleanupInFlight: Set<String> = []
    private var tempAllowTimer: Timer?

    var cleanupServer: String? {
        PiHoleClient(host: host.trimmingCharacters(in: .whitespacesAndNewlines), token: "identity")?.baseURL.absoluteString
    }

    func tempAllowDomain(_ domain: String, durationSeconds: Int) {
        lastError = "New temporary exceptions are disabled until server-side expiry is available."
    }

    func confirmTempAllowRemoval(_ entry: TempAllowEntry, server: String) async {
        guard cleanupServer == server, isConfigured, tempAllowList.contains(entry),
              entry.server == nil || entry.server == server else {
            cleanupError = "Select the original server before confirming cleanup."
            return
        }
        let confirmed = TempAllowEntry(domain: entry.domain, expiresAt: now(), server: server)
        let updated = tempAllowList.map { $0 == entry ? confirmed : $0 }
        guard persistTempAllowList(updated) else { return }
        await retryTempAllowCleanup()
    }

    func retryTempAllowCleanup() async {
        guard cleanupStorageReady, isConfigured, let server = cleanupServer,
              let client = makeClient() else { return }
        // Capture the original client before suspension; never redirect a deletion after settings change.
        for entry in tempAllowList where entry.server == server && entry.expiresAt <= now() {
            guard cleanupInFlight.insert(entry.id).inserted else { continue }
            defer { cleanupInFlight.remove(entry.id) }
            do {
                try await client.removeDomain(entry.domain)
                if persistTempAllowList(tempAllowList.filter { $0.id != entry.id }) { cleanupError = nil }
            } catch {
                cleanupError = "Cleanup pending for \(entry.domain): \(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    private func persistTempAllowList(_ entries: [TempAllowEntry]) -> Bool {
        guard cleanupStorageReady else { return false }
        do {
            try cleanupStorage.save(JSONEncoder().encode(entries))
            tempAllowList = entries
            return true
        } catch {
            cleanupError = "Could not save cleanup records: \(error.localizedDescription)"
            return false
        }
    }

    private func restoreTempAllowList(automaticCleanup: Bool) {
        do {
            let saved = try cleanupStorage.load()
            let legacy = defaults.data(forKey: "tempAllowList")
            if let data = saved ?? legacy {
                tempAllowList = try JSONDecoder().decode([TempAllowEntry].self, from: data)
                // Migrate before removing the only copy, including expired legacy entries.
                if saved == nil { try cleanupStorage.save(data) }
            }
            cleanupStorageReady = true
            defaults.removeObject(forKey: "tempAllowList")
            if automaticCleanup && !tempAllowList.isEmpty {
                Task { [weak self] in await self?.retryTempAllowCleanup() }
                tempAllowTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in await self?.retryTempAllowCleanup() }
                }
            }
        } catch {
            cleanupError = "Could not load cleanup records. Existing records were preserved: \(error.localizedDescription)"
        }
    }

    func fetchRecentBlocked() {
        let context = configurationID
        guard let client = makeClient() else { return }
        Task {
            do {
                let queries = try await client.fetchRecentBlocked(count: 5)
                guard context == configurationID else { return }
                recentBlocked = queries
            } catch {
                guard context == configurationID else { return }
                lastError = error.localizedDescription
            }
        }
    }

    // Auto refresh
    private var refreshTask: Task<Void, Never>?
    private var followUpRefreshTask: Task<Void, Never>?
    private var countdownTimer: Timer?
    private var disableDeadline: Date?
    private let refreshIntervalSeconds: TimeInterval = 20

    // Retry configuration (baseRetryDelay injectable for testing)
    let baseRetryDelay: TimeInterval

    // Network monitoring
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "NetworkMonitor")
    private var networkDebounceTask: Task<Void, Never>?
    private let networkDebounceInterval: TimeInterval = 0.5

    // Dependency injection for testing
    private let makeClientFn: ClientFactory
    private let defaults: UserDefaults
    private let tokenStorage: TokenStorage
    private let now: () -> Date
    private var configurationID = UUID()

    var isConfigured: Bool { !host.isEmpty && !token.isEmpty }

    /// Default client factory that creates real PiHoleClient instances
    static let defaultClientFactory: ClientFactory = { host, token, allowSelfSigned in
        PiHoleClient(host: host, token: token, allowSelfSignedCert: allowSelfSigned)
    }

    init(clientFactory: ClientFactory? = nil, baseRetryDelay: TimeInterval = 1.0,
         defaults: UserDefaults = .standard, tokenStorage: TokenStorage? = nil,
         cleanupStorage: CleanupStorage? = nil, automaticCleanup: Bool = true,
         monitorNetwork: Bool = true, now: @escaping () -> Date = Date.init) {
        let tokenStorage = tokenStorage ?? .keychain
        self.makeClientFn = clientFactory ?? Self.defaultClientFactory
        self.baseRetryDelay = baseRetryDelay
        self.defaults = defaults
        self.tokenStorage = tokenStorage
        self.now = now
        self.cleanupStorage = cleanupStorage ?? .file
        host = defaults.string(forKey: "piholeHost") ?? ""
        allowSelfSignedCert = defaults.bool(forKey: "allowSelfSignedCert")
        defaultDisableMinutes = defaults.object(forKey: "defaultDisableMinutes") as? Int ?? 5

        // Load token from Keychain on init
        if let savedToken = tokenStorage.load() {
            token = savedToken
        }

        // Migrate from old AppStorage if exists
        migrateTokenFromAppStorage()

        restoreTempAllowList(automaticCleanup: automaticCleanup)

        // Start network monitoring
        if monitorNetwork { startNetworkMonitoring() }
    }

    deinit {
        networkMonitor.cancel()
    }

    // MARK: - Token Migration

    private func migrateTokenFromAppStorage() {
        // Skip if Keychain already has a token (already migrated or set via UI)
        if tokenStorage.load() != nil {
            // Clean up old AppStorage key if it exists
            defaults.removeObject(forKey: "piholeToken")
            return
        }

        let oldTokenKey = "piholeToken"
        if let oldToken = defaults.string(forKey: oldTokenKey), !oldToken.isEmpty {
            // Save to Keychain first, only remove from UserDefaults if save succeeds
            do {
                try tokenStorage.save(oldToken)
                token = oldToken
                defaults.removeObject(forKey: oldTokenKey)
            } catch {
                // Migration failed - keep old token in UserDefaults for next attempt
            }
        }
    }

    private func configurationDidChange() {
        configurationID = UUID()
        recentBlocked = []
        followUpRefreshTask?.cancel()
        stopDisableCountdown()
        isBlockingEnabled = nil
        isLoading = false
        lastError = nil
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
            _ = try await client.fetchStatus(allowLegacyFallback: true)
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

    @discardableResult
    func toggleBlocking() -> Task<Void, Never>? {
        guard !isLoading else { return nil }
        if isBlockingEnabled == true {
            return disableBlocking(durationSeconds: defaultDisableMinutes > 0 ? defaultDisableMinutes * 60 : nil)
        } else if isBlockingEnabled == false {
            return enableBlocking()
        } else {
            return refreshStatus()
        }
    }

    @discardableResult
    func enableBlocking() -> Task<Void, Never> {
        Task { await enableBlockingAsync() }
    }

    @discardableResult
    func disableBlocking(durationSeconds: Int? = nil) -> Task<Void, Never> {
        Task { await disableBlockingAsync(durationSeconds: durationSeconds) }
    }

    @discardableResult
    func refreshStatus() -> Task<Void, Never> {
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
            try Task.checkCancellation()
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Don't retry on configuration errors or if cancelled
                if error is CancellationError { throw error }
                if (error as? URLError)?.code == .cancelled { throw error }
                if case PiHoleClient.PiHoleError.notConfigured = error { throw error }
                if let apiError = error as? PiHoleClient.PiHoleError, apiError.isLegacyServerError {
                    throw error
                }
                
                // Last attempt, don't sleep
                if attempt == maxAttempts - 1 { break }
                
                // Exponential backoff: 1s, 2s, 4s...
                let delay = baseRetryDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw lastError ?? PiHoleClient.PiHoleError.invalidURL
    }

    func refreshStatusAsync() async {
        guard !isLoading else { return }
        guard let client = requireClientOrFail() else { return }
        let context = configurationID
        setLoading(true)
        defer { if context == configurationID { setLoading(false) } }

        do {
            let enabled = try await withRetry {
                guard context == self.configurationID else { throw CancellationError() }
                return try await client.fetchStatus()
            }
            guard context == configurationID else { return }
            isBlockingEnabled = enabled
            lastError = nil
            // If enabled, stop countdown; if disabled and we don't know remaining time, leave as is.
            if enabled { stopDisableCountdown() }
        } catch {
            guard context == configurationID, !Task.isCancelled else { return }
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func enableBlockingAsync() async {
        guard !isLoading else { return }
        guard let client = requireClientOrFail() else { return }
        let context = configurationID
        setLoading(true)
        defer { if context == configurationID { setLoading(false) } }
        do {
            try await withRetry {
                guard context == self.configurationID else { throw CancellationError() }
                try await client.enableBlocking()
            }
            guard context == configurationID else { return }
            isBlockingEnabled = true
            lastError = nil
            stopDisableCountdown()
            // Refresh after a brief delay to ensure status reflects server state.
            scheduleFollowUpRefresh()
        } catch {
            guard context == configurationID, !Task.isCancelled else { return }
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func disableBlockingAsync(durationSeconds: Int?) async {
        guard !isLoading else { return }
        guard let client = requireClientOrFail() else { return }
        let context = configurationID
        setLoading(true)
        defer { if context == configurationID { setLoading(false) } }
        do {
            try await withRetry {
                guard context == self.configurationID else { throw CancellationError() }
                try await client.disableBlocking(durationSeconds: durationSeconds)
            }
            guard context == configurationID else { return }
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
            guard context == configurationID, !Task.isCancelled else { return }
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
        disableDeadline = now().addingTimeInterval(TimeInterval(clampedSeconds))

        guard clampedSeconds > 0 else {
            handleDisableCountdownFinished()
            return
        }

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateDisableCountdown()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    func updateDisableCountdown() {
        guard let disableDeadline else { return }
        let remaining = max(0, Int(ceil(disableDeadline.timeIntervalSince(now()))))
        if remaining == 0 { handleDisableCountdownFinished() }
        else { remainingDisableSeconds = remaining }
    }

    private func handleDisableCountdownFinished() {
        // The server owns expiry. Never override another client's newer blocking decision.
        stopDisableCountdown()
        refreshStatus()
    }

    private func stopDisableCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        disableDeadline = nil
        remainingDisableSeconds = nil
    }
}
