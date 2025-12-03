import Foundation
import SwiftUI
import Combine

@MainActor
final class PiHoleStore: ObservableObject {
    // Settings
    @AppStorage("piholeHost") var host: String = "pi.hole"
    @AppStorage("piholeToken") var token: String = ""
    @AppStorage("allowSelfSignedCert") var allowSelfSignedCert: Bool = false
    @AppStorage("defaultDisableMinutes") var defaultDisableMinutes: Int = 5

    // UI state
    @Published var isBlockingEnabled: Bool?
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    @Published var remainingDisableSeconds: Int?

    // Auto refresh
    private var refreshTask: Task<Void, Never>?
    private var countdownTimer: Timer?
    private let refreshIntervalSeconds: TimeInterval = 20

    var isConfigured: Bool { !host.isEmpty && !token.isEmpty }

    // MARK: - Menu bar helpers

    var menuBarTitle: String {
        if let remaining = remainingDisableSeconds, remaining > 0, isBlockingEnabled == false {
            let min = remaining / 60
            let sec = remaining % 60
            return String(format: "%d:%02d", min, sec)
        }
        return ""
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

    // MARK: - Async implementations

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

    private func refreshStatusAsync() async {
        guard let client = requireClientOrFail() else { return }
        setLoading(true)
        defer { setLoading(false) }
        do {
            let enabled = try await client.fetchStatus()
            isBlockingEnabled = enabled
            lastError = nil
            // If enabled, stop countdown; if disabled and we don't know remaining time, leave as is.
            if enabled { stopDisableCountdown() }
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func enableBlockingAsync() async {
        guard let client = requireClientOrFail() else { return }
        setLoading(true)
        defer { setLoading(false) }
        do {
            try await client.enableBlocking()
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
            try await client.disableBlocking(durationSeconds: durationSeconds)
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
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            await refreshStatusAsync()
        }
    }

    // MARK: - Auto refresh

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshStatusAsync()
                try? await Task.sleep(nanoseconds: UInt64(refreshIntervalSeconds * 1_000_000_000))
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

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Ensure mutations happen on the main actor
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
        RunLoop.main.add(countdownTimer!, forMode: .common)
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
