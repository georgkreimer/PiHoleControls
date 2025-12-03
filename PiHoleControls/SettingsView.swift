//
//  SettingsView.swift
//  PiHoleControls
//
//  Created by Georg Kreimer on 11/25/25.
//

import SwiftUI
import Combine
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: PiHoleStore
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle, loading, success, failure(String)
    }

    var body: some View {
        Form {
            Section("Pi-hole server") {
                TextField("Host or URL", text: $store.host)
                SecureField("API token", text: $store.token)
                Text("Example: pi.hole:8080 or http://192.168.1.2:8080")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Allow self-signed certificates", isOn: $store.allowSelfSignedCert)
                    .font(.caption)
            }

            Section {
                Button("Test connection") {
                    testState = .loading
                    Task { await runConnectionTest() }
                }
                .disabled(testState == .loading)

                // Feedback indicator
                switch testState {
                case .idle:
                    EmptyView()
                case .loading:
                    HStack {
                        ProgressView()
                        Text("Testing connection…")
                            .font(.caption)
                    }
                case .success:
                    Label("Connection successful", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .failure(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        ScrollView(.vertical, showsIndicators: true) {
                            Label {
                                Text(message)
                                    .font(.body)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(nil)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "xmark.octagon.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                        .frame(maxHeight: 120)

                        Button {
                            copyToPasteboard(message)
                        } label: {
                            Label("Copy error", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .frame(width: 350, height: 340)
        .onChange(of: store.host) {
            resetTestState()
        }
        .onChange(of: store.token) {
            resetTestState()
        }
        .onChange(of: store.allowSelfSignedCert) {
            resetTestState()
        }
    }
}

private extension SettingsView {
    @MainActor
    func runConnectionTest() async {
        let sanitizedHost = store.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedToken = store.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitizedHost != store.host { store.host = sanitizedHost }
        if sanitizedToken != store.token { store.token = sanitizedToken }

        guard let client = PiHoleClient(
            host: sanitizedHost,
            token: sanitizedToken,
            allowSelfSignedCert: store.allowSelfSignedCert
        ) else {
            testState = .failure("Enter a valid host and API token first.")
            return
        }
        do {
            _ = try await client.fetchStatus(allowLegacyFallback: false)
            testState = .success
        } catch {
            testState = .failure(friendlyMessage(for: error))
        }
    }

    func resetTestState() {
        if testState != .idle {
            testState = .idle
        }
    }

    func copyToPasteboard(_ message: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message, forType: .string)
    }
}

private func friendlyMessage(for error: Error) -> String {
    if let localized = (error as? LocalizedError)?.errorDescription {
        return localized
    }
    return error.localizedDescription
}

#Preview {
    SettingsView()
        .environmentObject(PiHoleStore())
}
