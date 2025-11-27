//
//  ContentView.swift
//  PiHoleControls
//
//  Created by Georg Kreimer on 11/25/25.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: PiHoleStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .frame(width: 10, height: 10)
                    .foregroundStyle(statusColor)
                Text(statusText)
                    .font(.headline)
            }

            if store.isLoading {
                Text("Working…")
                    .font(.caption)
            } else if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            if store.isBlockingEnabled == false {
                Button("Enable blocking") {
                    store.enableBlocking()
                }
                .disabled(store.isLoading)
            } else {
                Menu("Disable blocking") {
                    Button("5 minutes") { store.disableBlocking(durationSeconds: 5 * 60) }
                    Button("30 minutes") { store.disableBlocking(durationSeconds: 30 * 60) }
                    Button("1 hour") { store.disableBlocking(durationSeconds: 60 * 60) }
                    Divider()
                    Button("Until re-enabled") { store.disableBlocking(durationSeconds: nil) }
                }
                .disabled(store.isLoading)
            }

            Divider()

            Button("Settings…") {
                openSettings()
            }

            Divider()

            Button("Quit PiHoleControls") {
                NSApp.terminate(nil)
            }
        }
        .padding(8)
        .onAppear {
            store.refreshStatus()
            store.startAutoRefresh()
        }
        .onDisappear {
            store.stopAutoRefresh()
        }
    }

    private var statusText: String {
        guard let enabled = store.isBlockingEnabled else { return "Unknown status" }
        if !enabled, let remaining = store.remainingFormatted {
            return "Blocking: Disabled (\(remaining))"
        }
        return enabled ? "Blocking: Enabled" : "Blocking: Disabled"
    }

    private var statusColor: Color {
        guard let enabled = store.isBlockingEnabled else { return .gray }
        return enabled ? .green : .orange
    }

}

#Preview {
    ContentView()
        .environmentObject(PiHoleStore())
}
