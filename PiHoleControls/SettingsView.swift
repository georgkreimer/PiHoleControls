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
    @State private var appearAnimation = false

    enum TestState: Equatable {
        case idle, loading, success, failure(String)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            header
                .opacity(appearAnimation ? 1 : 0)
                .offset(y: appearAnimation ? 0 : -10)

            // Server settings card
            serverCard
                .opacity(appearAnimation ? 1 : 0)
                .offset(y: appearAnimation ? 0 : 15)

            // Connection test card
            connectionCard
                .opacity(appearAnimation ? 1 : 0)
                .offset(y: appearAnimation ? 0 : 15)

            Spacer()
        }
        .padding(24)
        .frame(width: 400, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appearAnimation = true
            }
        }
        .onChange(of: store.host) { resetTestState() }
        .onChange(of: store.token) { resetTestState() }
        .onChange(of: store.allowSelfSignedCert) { resetTestState() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: "shield.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Pi-hole Controls")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("Configure your Pi-hole connection")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Server Card

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Server Configuration")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            } icon: {
                Image(systemName: "server.rack")
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 12) {
                SettingsTextField(
                    icon: "globe",
                    placeholder: "Host or URL",
                    text: $store.host
                )

                SettingsSecureField(
                    icon: "key.fill",
                    placeholder: "API Token",
                    text: $store.token
                )
            }

            Text("Example: pi.hole or 192.168.1.2:8080")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Divider()
                .opacity(0.5)

            Toggle(isOn: $store.allowSelfSignedCert) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Allow self-signed certificates")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }

    // MARK: - Connection Card

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text("Connection Test")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                } icon: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                }

                Spacer()

                testButton
            }

            // Fixed height container to prevent layout shifts
            testResultView
                .frame(height: 80, alignment: .top)
                .clipped()
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: testState)
    }

    private var testButton: some View {
        Button {
            testState = .loading
            Task { await runConnectionTest() }
        } label: {
            HStack(spacing: 6) {
                if testState == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(testState == .loading ? "Testing..." : "Test")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(testState == .loading)
    }

    @ViewBuilder
    private var testResultView: some View {
        switch testState {
        case .idle:
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("Click Test to verify your connection")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            }

        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting to Pi-hole...")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .success:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
                Text("Connection successful!")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.green.opacity(0.1))
            }

        case .failure(let message):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.red)
                    Text("Connection failed")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                }

                ScrollView(.vertical, showsIndicators: true) {
                    Text(message)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 60)

                Button {
                    copyToPasteboard(message)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                        Text("Copy error")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.red.opacity(0.1))
            }
        }
    }
}

// MARK: - Settings Text Field

private struct SettingsTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isFocused ? .blue : .secondary)
                .frame(width: 16)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .focused($isFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFocused ? Color.blue.opacity(0.5) : Color.primary.opacity(0.1), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Settings Secure Field

private struct SettingsSecureField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isFocused ? .blue : .secondary)
                .frame(width: 16)

            ZStack {
                if isRevealed {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .focused($isFocused)
                } else {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .focused($isFocused)
                }
            }

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFocused ? Color.blue.opacity(0.5) : Color.primary.opacity(0.1), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Helpers

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
