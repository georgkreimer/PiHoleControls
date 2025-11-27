//
//  PiHoleStore.swift
//  PiHoleControls
//
//  Created by Georg Kreimer on 11/25/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class PiHoleStore: ObservableObject {
    @AppStorage("piholeHost") var host: String = "pi.hole"
    @AppStorage("piholeToken") var token: String = ""
    @AppStorage("allowSelfSignedCert") var allowSelfSignedCert: Bool = false
    @Published var isBlockingEnabled: Bool?
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    @Published var remainingDisableSeconds: Int?

    private var refreshTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?

    var isConfigured: Bool { !host.isEmpty && !token.isEmpty }
    
    private var client: PiHoleClient? {
        PiHoleClient(host: host, token: token, allowSelfSignedCert: allowSelfSignedCert)
    }

    var menuBarIconSystemName: String {
        if isBlockingEnabled == nil { return "shield.slash" }
        return isBlockingEnabled == true ? "shield.lefthalf.filled" : "shield.slash"
    }

    var menuBarTitle: String {
        if let remaining = remainingFormatted, isBlockingEnabled == false {
            return "Pi-hole (\(remaining))"
        }
        return "Pi-hole"
    }

    var remainingFormatted: String? {
        guard let remaining = remainingDisableSeconds else { return nil }
        let minutes = remaining / 60
        let secs = remaining % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    func refreshStatus() {
        Task { await performStatusFetch(showLoading: true) }
    }

    func startAutoRefresh(intervalSeconds: UInt64 = 5) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self {
                    await self.performStatusFetch(showLoading: false)
                } else {
                    return
                }
                try? await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func performStatusFetch(showLoading: Bool) async {
        guard let client = client else {
            lastError = "Pi-hole not configured"
            return
        }
        if showLoading { isLoading = true; lastError = nil }
        do {
            let enabled = try await client.fetchStatus()
            self.isBlockingEnabled = enabled
            self.lastError = nil
            if enabled { resetCountdown() }
        } catch {
            self.lastError = error.localizedDescription
        }
        if showLoading { isLoading = false }
    }

    func enableBlocking() {
        guard let client = client else {
            lastError = "Pi-hole not configured"
            return
        }
        resetCountdown()
        isLoading = true
        lastError = nil
        Task {
            do {
                try await client.enableBlocking()
                self.isBlockingEnabled = true
            } catch {
                self.lastError = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    func disableBlocking(durationSeconds: Int? = nil) {
        guard let client = client else {
            lastError = "Pi-hole not configured"
            return
        }
        resetCountdown()
        isLoading = true
        lastError = nil
        Task {
            do {
                try await client.disableBlocking(durationSeconds: durationSeconds)
                self.isBlockingEnabled = false
                if let durationSeconds {
                    startCountdown(from: durationSeconds)
                }
            } catch {
                self.lastError = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    private func resetCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        remainingDisableSeconds = nil
    }

    private func startCountdown(from seconds: Int) {
        remainingDisableSeconds = seconds
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while let self, let remaining = self.remainingDisableSeconds, remaining > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                await MainActor.run {
                    if let current = self.remainingDisableSeconds, current > 0 {
                        self.remainingDisableSeconds = current - 1
                    }
                }
            }
            guard !Task.isCancelled, let self else { return }
            await self.enableBlocking()
        }
    }
}
