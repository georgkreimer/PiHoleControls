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

    var isConfigured: Bool { !host.isEmpty && !token.isEmpty }
    
    private var client: PiHoleClient? {
        PiHoleClient(host: host, token: token, allowSelfSignedCert: allowSelfSignedCert)
    }

    var menuBarIconSystemName: String {
        if isBlockingEnabled == nil { return "shield.slash" }
        return isBlockingEnabled == true ? "shield.lefthalf.filled" : "shield.slash"
    }

    func refreshStatus() {
        guard let client = client else {
            lastError = "Pi-hole not configured"
            return
        }
        isLoading = true
        lastError = nil
        Task {
            do {
                let enabled = try await client.fetchStatus()
                self.isBlockingEnabled = enabled
            } catch {
                self.lastError = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    func enableBlocking() {
        guard let client = client else {
            lastError = "Pi-hole not configured"
            return
        }
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
        isLoading = true
        lastError = nil
        Task {
            do {
                try await client.disableBlocking(durationSeconds: durationSeconds)
                self.isBlockingEnabled = false
            } catch {
                self.lastError = error.localizedDescription
            }
            self.isLoading = false
        }
    }
}
