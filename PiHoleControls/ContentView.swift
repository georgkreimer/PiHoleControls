//
//  ContentView.swift
//  PiHoleControls
//
//  Created by Georg Kreimer on 11/25/25.
//

import SwiftUI
import AppKit

// MARK: - Main Container View

@MainActor
struct ContentView: View {
    @EnvironmentObject var store: PiHoleStore
    @Environment(\.dismissMenu) private var dismissMenu
    @State private var showSettings = false
    @State private var selectedDisableOption: DisableOption = .minutes(5)
    @State private var appearAnimation = false
    @State private var statusHeight: CGFloat = 0
    @State private var settingsHeight: CGFloat = 0

    private var containerHeight: CGFloat {
        let active = showSettings ? settingsHeight : statusHeight
        return max(active, 1)
    }


    var body: some View {
        ZStack(alignment: .topLeading) {
            // Status view
            StatusContentView(
                store: store,
                selectedDisableOption: $selectedDisableOption,
                appearAnimation: $appearAnimation,
                onSettingsTapped: { withAnimation(.easeOut(duration: 0.35)) { showSettings = true } },
                onDisable: { dismissMenu?() }
            )
            .frame(width: 300)
            .background(HeightReader { statusHeight = $0 })
            .offset(x: showSettings ? -300 : 0)
            .opacity(showSettings ? 0 : 1)

            // Settings view
            SettingsContentView(
                store: store,
                onBack: { withAnimation(.easeOut(duration: 0.35)) { showSettings = false } }
            )
            .frame(width: 300)
            .background(HeightReader { settingsHeight = $0 })
            .offset(x: showSettings ? 0 : 300)
            .opacity(showSettings ? 1 : 0)
        }
        .frame(width: 300, height: containerHeight)
        .background(.ultraThinMaterial)
        .clipped()
        .animation(.easeOut(duration: 0.35), value: showSettings)
        .onAppear {
            syncDefaultSelection()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appearAnimation = true
            }
        }
        .onChange(of: selectedDisableOption) {
            store.defaultDisableMinutes = selectedDisableOption.minutesValue
        }
        // Keyboard shortcuts
        .keyboardShortcut("e", modifiers: .command)
        .background {
            // Hidden buttons to capture keyboard shortcuts
            Group {
                Button("") {
                    if !store.isLoading && store.isBlockingEnabled == false {
                        store.enableBlocking()
                    }
                }
                .keyboardShortcut("e", modifiers: .command)
                .opacity(0)
                
                Button("") {
                    if !store.isLoading && store.isBlockingEnabled == true {
                        store.disableBlocking(durationSeconds: selectedDisableOption.durationSeconds)
                        dismissMenu?()
                    }
                }
                .keyboardShortcut("d", modifiers: .command)
                .opacity(0)
                
                Button("") {
                    store.refreshStatus()
                }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0)
            }
        }
    }

    private func syncDefaultSelection() {
        let minutes = max(store.defaultDisableMinutes, 0)
        if minutes == 0 {
            selectedDisableOption = .untilReenabled
        } else {
            selectedDisableOption = .minutes(minutes)
        }
    }
}

// MARK: - View Height Reader

private struct HeightReader: View {
    var onChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: ViewHeightKey.self, value: proxy.size.height)
        }
        .onPreferenceChange(ViewHeightKey.self, perform: onChange)
    }
}

private struct ViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Status Content View

private struct StatusContentView: View {
    @ObservedObject var store: PiHoleStore
    @Binding var selectedDisableOption: DisableOption
    @Binding var appearAnimation: Bool
    let onSettingsTapped: () -> Void
    let onDisable: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            statusCard
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 20)

            actionSection
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
 
            Spacer(minLength: 0)
 
            Divider()
                .opacity(0.5)
 
            footerButtons
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }

    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusGlowGradient)
                    .frame(width: 80, height: 80)
                    .blur(radius: 20)
                    .opacity(appearAnimation ? 0.6 : 0)

                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 64, height: 64)

                    Circle()
                        .strokeBorder(statusBorderGradient, lineWidth: 2)
                        .frame(width: 64, height: 64)

                    statusIcon
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(statusIconGradient)
                        .symbolEffect(.pulse, options: .repeating, isActive: store.isLoading)
                }
                .scaleEffect(appearAnimation ? 1 : 0.5)
                .opacity(appearAnimation ? 1 : 0)
            }

            VStack(spacing: 4) {
                Text(statusTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Group {
                    if let remaining = store.remainingDisableSeconds, remaining > 0 {
                        Text(formatTime(remaining))
                            .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(statusIconGradient)
                            .contentTransition(.numericText())
                    } else if store.isLoading {
                        Text("Checking status...")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else if let error = store.lastError {
                        Text(error)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    } else {
                        Text(" ")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                }
                .frame(height: 28)
                .animation(.easeOut(duration: 0.4), value: store.remainingDisableSeconds)
                .animation(.easeOut(duration: 0.4), value: store.isLoading)
            }
            .opacity(appearAnimation ? 1 : 0)
            .offset(y: appearAnimation ? 0 : 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        }
    }

    // MARK: - Action Section

    private var actionSection: some View {
        VStack(spacing: 10) {
            // Action button first
            ZStack {
                ActionButton(
                    title: "Enable Blocking",
                    icon: "shield.fill",
                    style: .primary,
                    isLoading: store.isLoading
                ) {
                    store.enableBlocking()
                }
                .opacity(store.isBlockingEnabled == false ? 1 : 0)
                .allowsHitTesting(store.isBlockingEnabled == false)

                ActionButton(
                    title: "Disable Blocking",
                    icon: "shield.slash.fill",
                    style: .destructive,
                    isLoading: store.isLoading
                ) {
                    store.disableBlocking(durationSeconds: selectedDisableOption.durationSeconds)
                    onDisable()
                }
                .opacity(store.isBlockingEnabled == true ? 1 : 0)
                .allowsHitTesting(store.isBlockingEnabled == true)

                ActionButton(
                    title: "Refresh Status",
                    icon: "arrow.clockwise",
                    style: .primary,
                    isLoading: store.isLoading
                ) {
                    store.refreshStatus()
                }
                .opacity(store.isBlockingEnabled == nil ? 1 : 0)
                .allowsHitTesting(store.isBlockingEnabled == nil)
            }

            // Duration picker below button
            HStack(spacing: 6) {
                ForEach(DisableOption.allCases, id: \.self) { option in
                    DurationPill(
                        label: option.shortLabel,
                        isSelected: selectedDisableOption == option,
                        action: { selectedDisableOption = option }
                    )
                    .disabled(store.isBlockingEnabled != true)
                }
            }
            .opacity(store.isBlockingEnabled == true ? 1 : 0.4)
        }
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 15)
        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: appearAnimation)
        .animation(.easeOut(duration: 0.4), value: store.isBlockingEnabled)
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack(spacing: 4) {
            FooterButton(title: "Settings", icon: "gearshape.fill", action: onSettingsTapped)
            Spacer()
            FooterButton(title: "Quit", icon: "power") {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Helpers

    private var statusIcon: Image {
        if store.isLoading {
            return Image(systemName: "arrow.trianglehead.2.counterclockwise.rotate.90")
        }
        guard let enabled = store.isBlockingEnabled else {
            return Image(systemName: "questionmark.circle.fill")
        }
        return Image(systemName: enabled ? "shield.fill" : "shield.slash.fill")
    }

    private var statusTitle: String {
        if store.isLoading { return "Checking" }
        guard let enabled = store.isBlockingEnabled else { return "Unknown" }
        return enabled ? "Protected" : "Unprotected"
    }

    private var statusGlowGradient: RadialGradient {
        let color = statusColor
        return RadialGradient(
            colors: [color, color.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: 50
        )
    }

    private var statusBorderGradient: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.3), .white.opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var statusIconGradient: LinearGradient {
        let color = statusColor
        return LinearGradient(
            colors: [color, color.opacity(0.7)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var statusColor: Color {
        if store.isLoading { return .blue }
        guard let enabled = store.isBlockingEnabled else { return .gray }
        return enabled ? .green : .orange
    }

    private func formatTime(_ seconds: Int) -> String {
        let min = seconds / 60
        let sec = seconds % 60
        return String(format: "%d:%02d", min, sec)
    }
}

// MARK: - Settings Content View

private struct SettingsContentView: View {
    @ObservedObject var store: PiHoleStore
    let onBack: () -> Void
    @State private var testState: TestState = .idle
    @State private var appearAnimation = false

    enum TestState: Equatable {
        case idle, loading, success, failure(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            settingsHeader
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)

            // Main content
            VStack(spacing: 14) {
                serverCard
                connectionCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .opacity(appearAnimation ? 1 : 0)
            .offset(y: appearAnimation ? 0 : 15)

            Spacer()

            Divider()
                .opacity(0.5)

            // Footer
            HStack {
                FooterButton(title: "Back", icon: "chevron.left", action: onBack)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appearAnimation = true
            }
        }
        .onChange(of: store.host) { _, _ in resetTestState() }
        .onChange(of: store.token) { _, _ in resetTestState() }
        .onChange(of: store.allowSelfSignedCert) { _, _ in resetTestState() }
    }

    // MARK: - Header

    private var settingsHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.blue, .blue.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 30
                        )
                    )
                    .frame(width: 50, height: 50)
                    .blur(radius: 12)
                    .opacity(appearAnimation ? 0.5 : 0)

                // Icon container
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)

                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .scaleEffect(appearAnimation ? 1 : 0.5)
                .opacity(appearAnimation ? 1 : 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Configure your Pi-hole")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        }
    }

    // MARK: - Server Card

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .purple.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 24, height: 24)

                    Image(systemName: "server.rack")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text("Server")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }

            VStack(spacing: 10) {
                SettingsTextField(
                    icon: "globe",
                    placeholder: "Host or URL",
                    hint: "pi.hole or 192.168.1.2:8080",
                    text: $store.host
                )

                SettingsSecureField(
                    icon: "key.fill",
                    placeholder: "API Token / Password",
                    text: $store.token
                )
            }

            // Toggle with better styling
            HStack {
                Toggle(isOn: $store.allowSelfSignedCert) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(store.allowSelfSignedCert ? .orange : .secondary)
                        Text("Allow self-signed certificates")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.8))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        }
    }

    // MARK: - Connection Card

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Section header
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [testStateColor, testStateColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 24, height: 24)

                        Image(systemName: testStateIcon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Text("Connection")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }

                Spacer()

                testButton
            }

            testResultView
                .frame(height: 36, alignment: .center)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: testState)
    }

    private var testStateColor: Color {
        switch testState {
        case .idle: return .cyan
        case .loading: return .blue
        case .success: return .green
        case .failure: return .red
        }
    }

    private var testStateIcon: String {
        switch testState {
        case .idle: return "antenna.radiowaves.left.and.right"
        case .loading: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark"
        case .failure: return "xmark"
        }
    }

    private var testButton: some View {
        Button {
            testState = .loading
            Task { await runConnectionTest() }
        } label: {
            HStack(spacing: 5) {
                if testState == .loading {
                    ProgressView()
                        .controlSize(.mini)
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
                    .shadow(color: .blue.opacity(0.3), radius: 4, y: 2)
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
                Text("Tap Test to verify your Pi-hole connection")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Authenticating...")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .frame(maxWidth: .infinity)

        case .success:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
                Text("Connection successful!")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.green.opacity(0.15))
            }

        case .failure(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.red.opacity(0.15))
            }
        }
    }

    // MARK: - Helpers

    @MainActor
    private func runConnectionTest() async {
        let sanitizedHost = store.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedToken = store.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitizedHost != store.host { store.host = sanitizedHost }
        if sanitizedToken != store.token { store.token = sanitizedToken }

        guard let client = PiHoleClient(
            host: sanitizedHost,
            token: sanitizedToken,
            allowSelfSignedCert: store.allowSelfSignedCert
        ) else {
            testState = .failure("Enter host and token first")
            return
        }
        do {
            _ = try await client.fetchStatus(allowLegacyFallback: false)
            testState = .success
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            testState = .failure(String(message.prefix(80)))
        }
    }

    private func resetTestState() {
        if testState != .idle {
            testState = .idle
        }
    }
}

// MARK: - Settings Text Field

private struct SettingsTextField: View {
    let icon: String
    let placeholder: String
    var hint: String? = nil
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isFocused ? Color.blue.opacity(0.15) : Color.primary.opacity(0.08))
                        .frame(width: 28, height: 28)

                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isFocused ? .blue : .primary.opacity(0.6))
                }

                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .focused($isFocused)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.8))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isFocused ? Color.blue.opacity(0.6) : Color.primary.opacity(0.15), lineWidth: 1)
            }
            .shadow(color: isFocused ? .blue.opacity(0.15) : .black.opacity(0.05), radius: 4, y: 2)

            if let hint = hint {
                Text(hint)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.leading, 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isFocused)
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
            ZStack {
                Circle()
                    .fill(isFocused ? Color.blue.opacity(0.15) : Color.primary.opacity(0.08))
                    .frame(width: 28, height: 28)

                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isFocused ? .blue : .primary.opacity(0.6))
            }

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
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 28, height: 28)

                    Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.8))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isFocused ? Color.blue.opacity(0.6) : Color.primary.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: isFocused ? .blue.opacity(0.15) : .black.opacity(0.05), radius: 4, y: 2)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - Duration Pill

private struct DurationPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(isHovering ? 0.1 : 0.05))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    enum Style { case primary, destructive }

    let title: String
    let icon: String
    let style: Style
    let isLoading: Bool
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    private var backgroundColor: Color {
        switch style {
        case .primary: return .green
        case .destructive: return .orange
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [backgroundColor, backgroundColor.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: backgroundColor.opacity(0.4), radius: isHovering ? 8 : 4, y: isHovering ? 4 : 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
            }
            .scaleEffect(isPressed ? 0.97 : 1)
            .opacity(isLoading ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
    }
}

// MARK: - Footer Button

private struct FooterButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .foregroundStyle(isHovering ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.1 : 0))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - Disable Option

private enum DisableOption: Hashable, CaseIterable {
    case minutes(Int)
    case untilReenabled

    var label: String {
        switch self {
        case .minutes(let m): return "\(m) minutes"
        case .untilReenabled: return "Until re-enabled"
        }
    }

    var shortLabel: String {
        switch self {
        case .minutes(let m): return "\(m)m"
        case .untilReenabled: return "∞"
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

    var minutesValue: Int {
        switch self {
        case .minutes(let m): return m
        case .untilReenabled: return 0
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PiHoleStore())
}
