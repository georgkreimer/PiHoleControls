//
//  ContentView.swift
//  PiHoleControls
//
//  Created by Georg Kreimer on 11/25/25.
//

import SwiftUI
import AppKit

@MainActor
struct ContentView: View {
    @EnvironmentObject var store: PiHoleStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismissMenu) private var dismissMenu
    @State private var selectedDisableOption: DisableOption = .minutes(5)

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
            } else if store.isBlockingEnabled == true {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Disable for", selection: $selectedDisableOption) {
                        ForEach(DisableOption.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    Button("Disable") {
                        store.disableBlocking(durationSeconds: selectedDisableOption.durationSeconds)
                        dismissMenu?()
                    }
                    .disabled(store.isLoading)
                }
            } else {
                Text("Status unknown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    }

    private var statusText: String {
        guard let enabled = store.isBlockingEnabled else { return "Unknown status" }
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

private enum DisableOption: Hashable, CaseIterable {
    case minutes(Int)
    case untilReenabled

    var label: String {
        switch self {
        case .minutes(let m): return "\(m) minutes"
        case .untilReenabled: return "Until re-enabled"
        }
    }

    var durationSeconds: Int? {
        switch self {
        case .minutes(let m): return m * 60
        case .untilReenabled: return nil
        }
    }

    static var allCases: [DisableOption] {
        [.minutes(5), .minutes(30), .minutes(60), .untilReenabled]
    }
}
