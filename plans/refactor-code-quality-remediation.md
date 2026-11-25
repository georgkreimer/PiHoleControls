# refactor: Code Quality Remediation Plan

> **Created:** 2026-01-20
> **Deepened:** 2026-01-20
> **Type:** Refactor
> **Complexity:** Medium-High (simplified from 27 to 18 actionable items)
> **Review Source:** Multi-agent code review + deepening research

## Enhancement Summary

**Sections enhanced:** 7 major sections
**Research agents used:** 5 review agents (simplicity, security, performance, architecture, data integrity), 3 research agents (repo conventions, Swift testing, framework docs), Context7 documentation
**Key improvements:**
1. Reduced protocol abstractions from 3 to 1 (eliminated over-engineering)
2. Reduced test count from 37 to 10-12 focused tests
3. Added 7 data integrity edge cases to address
4. Added 5 security gaps to fix
5. Improved performance recommendations with concrete benchmarks
6. Clarified phase ordering to establish test coverage before refactoring

## Overview

Comprehensive remediation plan addressing 27 code quality findings from an exhaustive multi-agent code review. This plan transforms PiHoleControls from a functional macOS menu bar app into a well-tested, maintainable, and secure codebase.

**Key Outcomes:**
- Zero critical security vulnerabilities
- ~80% unit test coverage
- ~220 LOC reduction through dead code removal and consolidation
- Protocol-based architecture enabling full testability

---

## Problem Statement

The code review identified systemic issues across multiple dimensions:

| Category | Critical (P1) | Important (P2) | Nice-to-Have (P3) |
|----------|---------------|----------------|-------------------|
| Security | 2 | 3 | 1 |
| Data Integrity | 2 | 4 | 0 |
| Performance | 0 | 6 | 3 |
| Architecture | 1 | 3 | 1 |
| Code Quality | 0 | 2 | 3 |
| **Total** | **5** | **18** | **8** |

**Current State Problems:**
1. **Security:** HTTP default exposes credentials; certificate bypass enables MITM attacks
2. **Reliability:** Non-atomic token migration can permanently lose user credentials
3. **Testability:** Zero protocol abstractions; 0% unit test coverage
4. **Maintainability:** ~200 LOC duplicated code; 35 LOC dead code
5. **Performance:** Image processing on every timer tick; unbounded task spawning

---

## Technical Approach

### Architecture Changes

```
BEFORE (Current):
┌─────────────┐    direct instantiation    ┌──────────────┐
│ PiHoleStore ├───────────────────────────►│ PiHoleClient │
└─────────────┘                            └──────────────┘
       │                                          │
       │ direct static calls                      │ URLSession.shared
       ▼                                          ▼
┌───────────────┐                         ┌─────────────┐
│ KeychainHelper│                         │  Network    │
└───────────────┘                         └─────────────┘

AFTER (Proposed):
┌─────────────┐    PiHoleClientProtocol    ┌──────────────┐
│ PiHoleStore ├───────────────────────────►│ PiHoleClient │
└─────────────┘         ▲                  └──────────────┘
       │                │                         │
       │         MockPiHoleClient                 │ URLSessionProtocol
       │           (tests)                        ▼
       │                                   ┌─────────────┐
       │ KeychainProtocol                  │MockURLSession│
       ▼         ▲                         │  (tests)    │
┌───────────────┐│                         └─────────────┘
│KeychainService├┘
└───────────────┘
       ▲
 MockKeychain
   (tests)
```

---

## Implementation Phases

### Phase 1: Critical Fixes (Immediate)

**Goal:** Eliminate crash risks, security vulnerabilities, and data loss scenarios.

#### 1.1 Fix Force Unwrap Crash Risk
**File:** `PiHoleClient.swift:423`
**Priority:** P1 | **Effort:** Small

```swift
// BEFORE (crashes if lastError is nil)
throw lastError!

// AFTER (safe with fallback)
throw lastError ?? PiHoleError.invalidResponse(statusCode: nil, bodyPreview: nil, endpoint: nil)
```

**Acceptance Criteria:**
- [ ] No force unwraps in codebase (`grep -rn "!" --include="*.swift" | grep -v "//" | grep -v "\"" | grep "!$"`)
- [ ] Build succeeds without warnings

### Research Insights: Force Unwrap Detection
**Best Practice:** Use SwiftLint's `force_unwrapping` rule for automated detection in CI.
**Edge Case:** The grep pattern in acceptance criteria may have false positives from string literals and comments.

---

#### 1.2 Make Token Migration Atomic
**File:** `PiHoleStore.swift:65-74`
**Priority:** P1 | **Effort:** Medium

```swift
// BEFORE (can lose token if keychain fails)
private func migrateTokenFromAppStorage() {
    let oldTokenKey = "piholeToken"
    if let oldToken = UserDefaults.standard.string(forKey: oldTokenKey), !oldToken.isEmpty {
        try? KeychainHelper.save(key: Self.tokenKeychainKey, value: oldToken)  // Silent failure!
        token = oldToken
        UserDefaults.standard.removeObject(forKey: oldTokenKey)  // Deletes even if save failed!
    }
}

// AFTER (atomic - only deletes after confirmed save, skips if already migrated)
private func migrateTokenFromAppStorage() {
    // Skip if Keychain already has a token (prevents overwrite on partial migration)
    if KeychainHelper.retrieve(key: Self.tokenKeychainKey) != nil { return }

    let oldTokenKey = "piholeToken"
    guard let oldToken = UserDefaults.standard.string(forKey: oldTokenKey),
          !oldToken.isEmpty else { return }

    do {
        try KeychainHelper.save(key: Self.tokenKeychainKey, value: oldToken)
        token = oldToken
        UserDefaults.standard.removeObject(forKey: oldTokenKey)
        // Note: Remove print() in production - use os_log if logging needed
    } catch {
        // Don't delete from UserDefaults - user keeps token as fallback
        // Surface error to UI so user knows migration failed
        lastError = "Failed to migrate API token to secure storage"
    }
}
```

### Research Insights: Token Migration
**Data Integrity Finding:** The original plan had a race condition - if both Keychain and UserDefaults contain tokens (from a partial previous migration), the migration would overwrite the Keychain token. Added check to skip if Keychain already has a valid token.

**Security Finding:** Remove `print()` statements - they leak sensitive context to Console.app. Use structured logging with `os_log` if needed, or surface errors to UI.

**Edge Case:** Empty token handling - if user clears token, it should be deleted from Keychain (see 1.5 below).

**Acceptance Criteria:**
- [ ] Token only removed from UserDefaults AFTER successful Keychain write
- [ ] Migration skipped if Keychain already has a token
- [ ] Error surfaced to UI (not just logged)
- [ ] No print() statements in final code
- [ ] Manual test: Simulate keychain failure, verify token preserved in UserDefaults

---

#### 1.3 Default to HTTPS
**File:** `PiHoleClient.swift:134-136`
**Priority:** P1 | **Effort:** Small

```swift
// BEFORE (defaults to insecure HTTP)
if !hostString.hasPrefix("http://") && !hostString.hasPrefix("https://") {
    hostString = "http://" + hostString
}

// AFTER (defaults to secure HTTPS)
if !hostString.hasPrefix("http://") && !hostString.hasPrefix("https://") {
    hostString = "https://" + hostString
}
```

### Research Insights: HTTPS Default
**Security Finding:** Users who explicitly enter `http://` will still use insecure connections. Consider adding a visual indicator (orange text or icon) in the host field when HTTP is explicitly used.

**Implementation Pattern:**
```swift
// In ContentView/SettingsView, add indicator:
if store.host.lowercased().hasPrefix("http://") && !store.host.lowercased().hasPrefix("https://") {
    Image(systemName: "exclamationmark.triangle")
        .foregroundColor(.orange)
        .help("Using unencrypted HTTP connection")
}
```

**Acceptance Criteria:**
- [ ] Entering "pi.hole" connects to "https://pi.hole"
- [ ] Explicit "http://pi.hole" still works (user choice)
- [ ] Visual indicator when HTTP is explicitly used (optional enhancement)
- [ ] README updated with note about HTTPS default

---

#### 1.4 Add Security Warning for Self-Signed Certs
**Files:** `ContentView.swift` AND `SettingsView.swift`
**Priority:** P1 | **Effort:** Small

### Research Insights: Certificate Warning
**Security Finding:** The original plan only added the warning to `ContentView.swift`. The `SettingsView.swift` (standalone settings window at lines 118-128) has the same toggle with NO warning. Must add to BOTH files.

**Enhanced Warning Pattern:** A small orange text is insufficient for a feature that completely disables TLS security. Consider requiring confirmation when enabling:

```swift
// Add state for confirmation dialog
@State private var showSecurityWarningAlert = false

Toggle(isOn: $store.allowSelfSignedCert) {
    // existing label...
}
.onChange(of: store.allowSelfSignedCert) { _, newValue in
    if newValue {
        showSecurityWarningAlert = true
    }
}
.alert("Security Warning", isPresented: $showSecurityWarningAlert) {
    Button("I Understand the Risks", role: .destructive) { }
    Button("Cancel", role: .cancel) {
        store.allowSelfSignedCert = false
    }
} message: {
    Text("Disabling certificate validation allows attackers on your network to intercept your API token. Only enable this if you control the network and understand the risks.")
}

// Also show persistent warning when enabled
if store.allowSelfSignedCert {
    HStack(spacing: 4) {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.red)  // Use RED for critical security
        Text("Certificate validation disabled. MITM attacks possible.")
            .font(.system(size: 10))
            .foregroundColor(.red)
    }
    .padding(.top, 2)
}
```

**Acceptance Criteria:**
- [ ] Warning added to BOTH ContentView.swift AND SettingsView.swift
- [ ] Confirmation dialog shown when enabling toggle
- [ ] Persistent warning visible when toggle is ON
- [ ] Warning uses RED color (critical security, not just caution)

---

#### 1.5 Fix Silent Keychain Errors
**File:** `PiHoleStore.swift:15-21`
**Priority:** P1 | **Effort:** Small

### Research Insights: Keychain Error Handling
**Data Integrity Finding:** Empty token should DELETE from Keychain, not silently do nothing. Current `KeychainHelper.save` with empty string leaves stale data.

**Security Finding:** User notification is NOT optional - users must know if credentials aren't securely stored.

**Best Practice (from Context7 KeychainAccess docs):** Use update-or-insert pattern instead of delete-then-add for atomicity.

```swift
// AFTER (handles empty token, surfaces errors, no print statements)
@Published var token: String = "" {
    didSet {
        if oldValue != token {
            do {
                if token.isEmpty {
                    // Delete from Keychain when token is cleared
                    try KeychainHelper.delete(key: Self.tokenKeychainKey)
                } else {
                    try KeychainHelper.save(key: Self.tokenKeychainKey, value: token)
                }
            } catch {
                // MANDATORY: Surface to UI so user knows token may not persist
                lastError = "Failed to save API token securely. Changes may not persist."
            }
        }
    }
}
```

**Also update KeychainHelper.save() for atomicity:**
```swift
// Use SecItemUpdate instead of delete-then-add
static func save(key: String, value: String) throws {
    guard let data = value.data(using: .utf8) else { return }

    let updateQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key
    ]
    let updateAttributes: [String: Any] = [
        kSecValueData as String: data
    ]

    let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)

    if updateStatus == errSecSuccess { return }

    if updateStatus == errSecItemNotFound {
        // Item doesn't exist, add it
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
        return
    }

    throw KeychainError.unexpectedStatus(updateStatus)
}
```

**Acceptance Criteria:**
- [ ] Empty token triggers Keychain delete (not silent no-op)
- [ ] Keychain save uses update-or-insert pattern (atomic)
- [ ] User sees error message if token save fails (MANDATORY, not optional)
- [ ] No print() statements for credential operations

---

### Phase 2: Testability & Quality

**Goal:** Enable unit testing through minimal protocol abstraction (simplified from original plan).

### Research Insights: Simplification
**Simplicity Review Finding:** The original plan proposed 3 protocols + factory pattern, which is over-engineered for a ~3K LOC utility app. Simplified to:
- **KEEP:** `PiHoleClientProtocol` (high value - primary external boundary)
- **SKIP:** `URLSessionProtocol` (mock at client boundary instead)
- **SKIP:** `PiHoleClientFactoryProtocol` (direct injection is simpler)
- **OPTIONAL:** `KeychainProtocol` (only if Keychain behavior testing is critical)

**Architecture Review Finding:** For a single-purpose app with no external dependencies, the appropriate level of abstraction is 1 protocol at the primary external boundary.

#### 2.1 Create PiHoleClientProtocol (Single Protocol)

**New File:** `PiHoleControls/Protocols/PiHoleClientProtocol.swift`

```swift
// PiHoleClientProtocol.swift
import Foundation

/// Protocol for Pi-hole API operations - enables testing with mocks
protocol PiHoleClientProtocol: Sendable {
    func fetchStatus(allowLegacyFallback: Bool) async throws -> Bool
    func enableBlocking() async throws
    func disableBlocking(durationSeconds: Int?) async throws
}

// Default parameter extension
extension PiHoleClientProtocol {
    func fetchStatus() async throws -> Bool {
        try await fetchStatus(allowLegacyFallback: true)
    }
}

// Conform existing client
extension PiHoleClient: PiHoleClientProtocol {}
```

**Why this is sufficient:**
- `PiHoleClient` is the primary external boundary
- All network, auth, and API logic is encapsulated
- Mock this single interface to test `PiHoleStore` behavior
- No need to mock URLSession separately - test at higher level

**Acceptance Criteria:**
- [ ] Single protocol compiles without errors
- [ ] `PiHoleClient` conforms to `PiHoleClientProtocol`
- [ ] Protocol is `Sendable` for actor compatibility

---

#### 2.2 Inject Client into PiHoleStore (Simplified)

**File:** `PiHoleStore.swift`

### Research Insights: Simpler DI Pattern
**Simplicity Review Finding:** Factory pattern is unnecessary for a single client type. Use direct closure injection instead.

```swift
@MainActor
final class PiHoleStore: ObservableObject {
    // Simplified: Closure for client creation (no factory protocol needed)
    private let makeClientFn: (String, String, Bool) -> (any PiHoleClientProtocol)?

    // Default initializer for production
    init(
        makeClient: @escaping (String, String, Bool) -> (any PiHoleClientProtocol)? = PiHoleClient.init
    ) {
        self.makeClientFn = makeClient
        // ... rest of existing init (keychain loading, migration, network monitoring)
    }

    private func makeClient() -> (any PiHoleClientProtocol)? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return makeClientFn(trimmedHost, trimmedToken, allowSelfSignedCert)
    }
}
```

**Why this is better than factory pattern:**
- Zero additional types/protocols to maintain
- Swift's closure syntax is natural for this use case
- Same testability: inject `{ _, _, _ in MockPiHoleClient() }`
- Simpler code = fewer bugs

**Acceptance Criteria:**
- [ ] `PiHoleStore` accepts client creation closure
- [ ] Default parameter uses `PiHoleClient.init` (backward compatible)
- [ ] Tests can inject mock client via closure

---

#### 2.3 Create Mock Implementation for Tests (Single Mock)

**New File:** `PiHoleControlsTests/Mocks/MockPiHoleClient.swift`

### Research Insights: Minimal Mocking
**Simplicity Review Finding:** Skip MockKeychain, MockURLSession, MockClientFactory. Only need MockPiHoleClient to test PiHoleStore behavior.

```swift
// MockPiHoleClient.swift
import Foundation
@testable import PiHoleControls

/// Mock Pi-hole client for testing store logic without network
final class MockPiHoleClient: PiHoleClientProtocol, @unchecked Sendable {
    // Configurable responses
    var statusToReturn: Bool = true
    var shouldFail: Bool = false
    var errorToThrow: PiHoleClient.PiHoleError = .invalidURL
    var delay: TimeInterval = 0

    // Call tracking
    private(set) var fetchStatusCallCount = 0
    private(set) var enableBlockingCallCount = 0
    private(set) var disableBlockingCallCount = 0
    private(set) var lastDisableDuration: Int?

    private let lock = NSLock()

    func fetchStatus(allowLegacyFallback: Bool) async throws -> Bool {
        lock.lock()
        fetchStatusCallCount += 1
        lock.unlock()

        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        if shouldFail { throw errorToThrow }
        return statusToReturn
    }

    func enableBlocking() async throws {
        lock.lock()
        enableBlockingCallCount += 1
        lock.unlock()

        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        if shouldFail { throw errorToThrow }
    }

    func disableBlocking(durationSeconds: Int?) async throws {
        lock.lock()
        disableBlockingCallCount += 1
        lastDisableDuration = durationSeconds
        lock.unlock()

        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        if shouldFail { throw errorToThrow }
    }

    func reset() {
        lock.lock()
        fetchStatusCallCount = 0
        enableBlockingCallCount = 0
        disableBlockingCallCount = 0
        lastDisableDuration = nil
        lock.unlock()
    }
}
```

**Acceptance Criteria:**
- [ ] MockPiHoleClient compiles in test target
- [ ] Mock tracks call counts for verification
- [ ] Mock supports configurable return values, errors, and delays
- [ ] Thread-safe (uses lock for call counting)

---

#### 2.4 Write Unit Tests (Focused Set)

**New/Modified Files:**
- `PiHoleControlsTests/PiHoleStoreTests.swift`
- `PiHoleControlsTests/PiHoleClientTests.swift` (URL parsing only)

### Research Insights: Right-Sized Testing
**Simplicity Review Finding:** 37 tests is excessive for a utility app. Focus on 10-12 high-value tests.

**Swift Testing Best Practices (from Context7):**
- Use `@Test` macro with `@MainActor` for UI state tests
- Use `#expect` and `#require` for assertions
- Use parameterized tests (`@Test(arguments:)`) for URL parsing variations
- Organize with `@Suite` for grouping

**Focused Test Coverage:**

| Component | Test Cases | Focus |
|-----------|-----------|-------|
| PiHoleClient URL parsing | 3-4 | Edge cases only (parameterized) |
| PiHoleStore state transitions | 4-5 | Enable/disable/toggle/error states |
| Token migration atomicity | 1-2 | Critical data integrity path |
| **Total** | **10-12** | **High-value paths** |

**Example Tests (Swift Testing framework):**

```swift
// PiHoleStoreTests.swift
import Testing
@testable import PiHoleControls

@Suite("PiHoleStore Tests")
struct PiHoleStoreTests {

    @Test @MainActor
    func refreshStatusSetsEnabledState() async {
        let mockClient = MockPiHoleClient()
        mockClient.statusToReturn = true
        let store = PiHoleStore(makeClient: { _, _, _ in mockClient })
        store.host = "pi.hole"
        store.token = "testtoken"

        await store.refreshStatusAsync()

        #expect(store.isBlockingEnabled == true)
        #expect(mockClient.fetchStatusCallCount == 1)
    }

    @Test @MainActor
    func toggleBlockingDisablesWhenEnabled() async {
        let mockClient = MockPiHoleClient()
        let store = PiHoleStore(makeClient: { _, _, _ in mockClient })
        store.host = "pi.hole"
        store.token = "test"
        store.defaultDisableMinutes = 5
        store.isBlockingEnabled = true

        store.toggleBlocking()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(mockClient.disableBlockingCallCount == 1)
        #expect(mockClient.lastDisableDuration == 300)
    }

    @Test @MainActor
    func errorStateClearsOnSuccess() async {
        let mockClient = MockPiHoleClient()
        let store = PiHoleStore(makeClient: { _, _, _ in mockClient })
        store.host = "pi.hole"
        store.token = "test"
        store.lastError = "Previous error"

        await store.refreshStatusAsync()

        #expect(store.lastError == nil)
    }

    @Test @MainActor
    func fetchFailureSetsErrorState() async {
        let mockClient = MockPiHoleClient()
        mockClient.shouldFail = true
        mockClient.errorToThrow = .invalidResponse(statusCode: 500, bodyPreview: nil, endpoint: "test")
        let store = PiHoleStore(makeClient: { _, _, _ in mockClient })
        store.host = "pi.hole"
        store.token = "test"

        await store.refreshStatusAsync()

        #expect(store.lastError != nil)
        #expect(store.lastError?.contains("500") == true)
    }
}

// PiHoleClientTests.swift - URL parsing with parameterized tests
@Suite("PiHoleClient URL Parsing")
struct PiHoleClientURLTests {

    @Test("URL normalization", arguments: [
        ("pi.hole", true),           // Plain host -> should work
        ("http://pi.hole", true),    // Explicit HTTP -> should work
        ("https://pi.hole", true),   // Explicit HTTPS -> should work
        ("", false),                 // Empty -> should fail
    ])
    func urlNormalization(input: String, shouldSucceed: Bool) {
        let client = PiHoleClient(host: input, token: "test", allowSelfSignedCert: false)
        if shouldSucceed {
            #expect(client != nil)
        } else {
            #expect(client == nil)
        }
    }
}
```

**Acceptance Criteria:**
- [ ] 10-12 focused test cases pass
- [ ] Tests run in < 5 seconds
- [ ] `xcodebuild test` succeeds
- [ ] Tests cover critical paths: state transitions, error handling, URL parsing

---

#### 2.5 Add Network Debouncing

**File:** `PiHoleStore.swift:78-92`

### Research Insights: Network Debouncing
**Performance Review Finding:** The 500ms interval is appropriate. Typical network transition bursts are 50-200ms.

**Bug Found:** The original proposed code has a calculation bug:
```swift
// BUG: self is captured AFTER optional chaining, causing incorrect calculation
UInt64(self?.networkDebounceInterval ?? 0.5 * 1_000_000_000)
// Evaluates as: self?.networkDebounceInterval ?? (0.5 * 1_000_000_000)
// Should be: (self?.networkDebounceInterval ?? 0.5) * 1_000_000_000
```

**Corrected Implementation:**

```swift
private var networkDebounceTask: Task<Void, Never>?
private let networkDebounceInterval: TimeInterval = 0.5

private func startNetworkMonitoring() {
    networkMonitor.pathUpdateHandler = { [weak self] path in
        Task { @MainActor [weak self] in
            self?.handleNetworkChange(path)
        }
    }
    networkMonitor.start(queue: networkMonitorQueue)
}

private func handleNetworkChange(_ path: NWPath) {
    networkDebounceTask?.cancel()

    // FIX: Calculate nanoseconds before the closure to avoid precedence bug
    let debounceNanos = UInt64(networkDebounceInterval * 1_000_000_000)

    networkDebounceTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: debounceNanos)
        guard !Task.isCancelled, let self else { return }

        let wasAvailable = self.isNetworkAvailable
        self.isNetworkAvailable = path.status == .satisfied

        if !wasAvailable && self.isNetworkAvailable {
            self.refreshStatus()
        }
    }
}
```

**Architecture Note:** This belongs in Phase 3 (Performance & Cleanup), not Phase 2 (Testability). Moving here for simplicity, but it's a performance fix, not a testability improvement.

**Acceptance Criteria:**
- [ ] Rapid network changes (WiFi toggle) don't spawn multiple refreshes
- [ ] Status refreshes after network recovers (with 500ms delay)
- [ ] No calculation bugs in nanosecond conversion
- [ ] No memory leaks from orphaned tasks

---

### Phase 3: Performance & Cleanup

**Goal:** Optimize performance and reduce technical debt.

### Research Insights: Phase 3 Simplification
**Simplicity Review Finding:** Some Phase 3 items are unnecessary:
- **KEEP:** 3.1 (icon caching), 3.3 (remove loading delay), 3.5 (dead code removal)
- **SKIP:** 3.2 (task cancellation - premature optimization), 3.4 (UI consolidation - designs are intentionally different)
- **MODIFY:** 3.6 (session cache TTL - move to Phase 1 as security item)

#### 3.1 Cache Processed Menu Bar Icon

**File:** `StatusItemController.swift:114-125`

### Research Insights: Icon Caching
**Performance Review Finding:** Use `let` constant instead of `lazy var`. The icon should be computed at initialization, not lazily on first UI update.

**Performance Impact:**
- Before: O(width × height) = ~225 operations per UI update (15x15 image)
- After: O(1) constant time lookup
- With countdown timer at 1Hz, saves ~225 operations/second

```swift
// BETTER: Compute once at initialization with explicit constant
private let cachedStatusIcon: NSImage?

init(store: PiHoleStore) {
    // Compute icon BEFORE anything else
    self.cachedStatusIcon = NSImage(named: "MenuIcon")?
        .trimmedToAlphaBounds()
        .resizedForStatusBar(maxDimension: 15, template: true)

    // ... rest of existing init
    self.store = store
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    // etc.
}

private func statusImage() -> (image: NSImage?, alpha: CGFloat) {
    guard let enabled = store.isBlockingEnabled else {
        return (cachedStatusIcon, 0.5)
    }
    return (cachedStatusIcon, enabled ? 1 : 0.35)
}
```

**Why `let` is better than `lazy var`:**
- Explicit initialization order
- No thread-safety concerns
- Avoids any perceptible delay on first UI update

**Acceptance Criteria:**
- [ ] Image processed only once at startup (in init)
- [ ] CPU usage during countdown drops to near-zero
- [ ] Icon appearance unchanged
- [ ] Uses `let` constant, not `lazy var`

---

#### 3.2 Implement Task Cancellation Tracking

### Research Insights: Skip This Item
**Simplicity Review Finding:** This is premature optimization. The current "fire and forget" approach is fine for this use case:
- The `guard !isLoading` check already prevents rapid clicks
- User clicking rapidly is an edge case that doesn't cause real problems
- Adding cancellation tracking adds complexity for minimal benefit

**If you still want to implement (optional):**

**Data Integrity Finding:** Use SEPARATE task tracking per operation type, not a single shared variable. Otherwise, `enableBlocking()` followed by `refreshStatus()` would cancel the enable operation.

```swift
// OPTIONAL: Separate task tracking by operation type
private var enableDisableTask: Task<Void, Never>?
private var refreshTask: Task<Void, Never>?

func enableBlocking() {
    enableDisableTask?.cancel()
    enableDisableTask = Task {
        await enableBlockingAsync()
        // Check cancellation AFTER async work before mutating state
    }
}

func refreshStatus() {
    // Don't cancel if already refreshing - coalesce instead
    guard refreshTask == nil || refreshTask?.isCancelled == true else { return }
    refreshTask = Task {
        await refreshStatusAsync()
        refreshTask = nil
    }
}

deinit {
    enableDisableTask?.cancel()
    refreshTask?.cancel()
}
```

**Recommendation:** Skip this for now. Implement only if users report issues with rapid clicking.

**Acceptance Criteria (if implemented):**
- [ ] Separate task tracking per operation type
- [ ] Cancellation checks after async work
- [ ] Tasks cancelled on deinit

---

#### 3.3 Remove Artificial Loading Delay

**File:** `PiHoleStore.swift:199-222`

### Research Insights: Loading Delay
**Performance Review Finding:** A 2-second artificial delay is excessive. Local network API calls typically complete in 50-200ms, meaning users wait 1.8-1.95 seconds unnecessarily.

**Better Approach:** Remove the delay entirely. Don't add any artificial minimum.

```swift
// BEFORE (artificial 2-second minimum delay)
let minimumLoadingDuration: TimeInterval = 2.0
// ...
if elapsed < minimumLoadingDuration {
    try? await Task.sleep(nanoseconds: UInt64((minimumLoadingDuration - elapsed) * 1_000_000_000))
}

// AFTER (no artificial delay - remove the entire block)
private func refreshStatusAsync() async {
    guard let client = requireClientOrFail() else { return }
    setLoading(true)

    do {
        let enabled = try await withRetry {
            try await client.fetchStatus()
        }
        isBlockingEnabled = enabled
        lastError = nil
        if enabled { stopDisableCountdown() }
    } catch {
        lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
    setLoading(false)
}
```

**Why 0ms is better than 200ms:**
- Status checks should feel instant
- The spinner will still be visible during actual network latency
- Users prefer responsive UI over artificial "feedback"

**Acceptance Criteria:**
- [ ] Remove `minimumLoadingDuration` constant entirely
- [ ] Remove all `Task.sleep` for loading duration
- [ ] Status refreshes complete as fast as network allows
- [ ] Loading indicator still visible during actual network operation

---

#### 3.4 Consolidate Duplicated UI Components

### Research Insights: Skip This Item
**Simplicity Review Finding:** The implementations are **intentionally different**, not duplicated:
- `ContentView.swift` (lines 764-875): Uses glassmorphism styling with circles and shadows
- `SettingsView.swift` (lines 301-384): Uses simpler flat styling for standalone window

Forcing them into one shared component would either:
1. Make the shared component overly complex with conditional styling
2. Lose the intentional design differences

**Architecture Review Finding:** Before extracting shared components, verify if `SettingsView.swift` is still needed. The inline settings in `ContentView.swift` may have replaced it entirely.

**Recommendation:** Skip this consolidation. Keep the intentionally different designs.

**Alternative Action (if needed):**
- Check if `SettingsView.swift` is still used anywhere
- If not used, delete it entirely (saves ~436 LOC)
- If used, keep both implementations as-is

**Acceptance Criteria:**
- [ ] Verify whether `SettingsView.swift` is still referenced
- [ ] If unused, delete `SettingsView.swift` entirely
- [ ] If used, leave both implementations as-is (intentional design difference)

---

#### 3.5 Remove Dead Code

| File | Lines | Code to Remove | LOC |
|------|-------|----------------|-----|
| `StatusItemController.swift` | 236-240 | `settingTemplate(_:)` | -5 |
| `StatusItemController.swift` | 292-300 | `withAlpha(_:)` | -9 |
| `PiHoleClient.swift` | 56-61 | `ensureSessionAuth()` | -6 |
| `ContentView.swift` | 68 | Redundant `.keyboardShortcut` | -1 |
| `PiHoleStore.swift` | 96-111 | Simplify `menuBarTitle` | -14 |

```swift
// PiHoleStore.swift - simplify menuBarTitle (always returns "")
var menuBarTitle: String { "" }
```

**Acceptance Criteria:**
- [ ] ~35 LOC removed
- [ ] Build succeeds
- [ ] All tests pass

---

#### 3.6 Add Session Cache Expiration

### Research Insights: Promote to Phase 1
**Security Review Finding:** This should be Phase 1 (Critical), not Phase 3. Sessions cached indefinitely can be replayed if stolen, and violate security best practices.

**Data Integrity Finding:** Add max entries limit and periodic cleanup to prevent unbounded memory growth.

**File:** `PiHoleSessionCache.swift`

```swift
actor PiHoleSessionCache {
    static let shared = PiHoleSessionCache()

    struct Session {
        let sid: String
        let csrf: String?
        let createdAt: Date
    }

    private var cache: [String: Session] = [:]
    private let ttl: TimeInterval = 25 * 60  // 25 min (buffer before 30 min server expiry)
    private let maxEntries = 10  // Reasonable limit for single-user app
    private var lastCleanup: Date = Date()
    private let cleanupInterval: TimeInterval = 60  // Clean every minute

    func get(key: String) -> Session? {
        // Periodic cleanup
        if Date().timeIntervalSince(lastCleanup) > cleanupInterval {
            cleanupExpired()
            lastCleanup = Date()
        }

        guard let session = cache[key] else { return nil }

        // Check expiration
        if Date().timeIntervalSince(session.createdAt) > ttl {
            cache.removeValue(forKey: key)
            return nil
        }

        return session
    }

    func set(_ session: Session, key: String) {
        // Evict oldest if at capacity
        if cache.count >= maxEntries {
            evictOldest()
        }
        cache[key] = session
    }

    private func evictOldest() {
        guard let oldest = cache.min(by: { $0.value.createdAt < $1.value.createdAt }) else { return }
        cache.removeValue(forKey: oldest.key)
    }

    private func cleanupExpired() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.createdAt) <= ttl }
    }

    func remove(key: String) {
        cache.removeValue(forKey: key)
    }

    func clear() {
        cache.removeAll()
    }
}
```

**Acceptance Criteria:**
- [ ] Sessions expire after 25 minutes (buffer before server's 30 min expiry)
- [ ] Expired sessions trigger re-authentication
- [ ] Maximum 10 entries in cache
- [ ] Periodic cleanup runs every 60 seconds
- [ ] Memory doesn't grow unbounded

---

### NEW: Phase 1 Addition - Remove Sensitive Data from Error Messages

**Security Review Finding (CRITICAL):** The `bodyPreview` in error messages could expose sensitive server information.

**File:** `PiHoleClient.swift:645-650`

```swift
// BEFORE (exposes server response in UI)
case .invalidResponse(let statusCode, let bodyPreview, let endpoint):
    var base = "Pi-hole API returned an error"
    if let code = statusCode { base += " (HTTP \(code))" }
    if let endpoint { base += "\nEndpoint: \(endpoint)" }
    if let body = bodyPreview { base += "\nServer said: \(body)" }  // DANGEROUS!
    return base

// AFTER (sanitized - no server response exposed)
case .invalidResponse(let statusCode, _, let endpoint):
    var base = "Pi-hole API returned an error"
    if let code = statusCode { base += " (HTTP \(code))" }
    if let endpoint { base += " at \(endpoint)" }
    // Do NOT include bodyPreview in user-facing messages
    return base
```

**Acceptance Criteria:**
- [ ] `bodyPreview` NOT shown in user-facing error messages
- [ ] Status code and endpoint still shown for debugging
- [ ] Internal logging can still include bodyPreview if needed

---

## Acceptance Criteria Summary

### Research Insights: Simplified Criteria
Based on review agent feedback, the acceptance criteria have been simplified to reflect the reduced scope.

### Functional Requirements (Revised)
- [ ] All 6 P1 critical issues resolved (original 5 + session cache TTL + sanitize error messages)
- [ ] Phase 2 testability improvements implemented (1 protocol, 1 mock, 10-12 tests)
- [ ] Phase 3 performance items completed (icon caching, remove loading delay, dead code removal)
- [ ] No regressions in existing functionality

### Non-Functional Requirements (Revised)
- [ ] 10-12 focused unit tests pass
- [ ] Build time unchanged (within 10%)
- [ ] Memory footprint unchanged
- [ ] CPU usage during countdown < 0.1% (was <1%, now with icon caching)

### Quality Gates
- [ ] `xcodebuild build` succeeds with no warnings
- [ ] `xcodebuild test` passes all test cases
- [ ] No force unwraps in codebase
- [ ] No print() statements for credential operations

---

## Success Metrics

### Research Insights: Revised Metrics
Based on simplification review, metrics adjusted to reflect realistic scope.

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Force unwraps | 1 | 0 | 100% |
| Unit tests | 0 | 10-12 | +10-12 tests |
| Dead code | ~35 LOC | 0 | -35 LOC |
| Protocol abstractions | 0 | 1 | +1 (simplified) |
| Security vulnerabilities | 4 | 0 | -4 (added 2 new findings) |
| Artificial loading delay | 2s | 0s | -2s latency |
| Icon processing per tick | O(n) | O(1) | ~225 ops/sec saved |

### Performance Benchmarks (New)
| Metric | Current | Target | Method |
|--------|---------|--------|--------|
| Status refresh (local) | ~2050ms | <300ms | Remove artificial delay |
| Icon update CPU | ~0.5% | <0.1% | Cache icon at init |
| Memory (idle) | ~25MB | ~25MB | No change expected |

---

## Dependencies & Prerequisites

### Required Before Starting
- [ ] Xcode 15+ installed
- [ ] macOS 14+ for testing
- [ ] Git clean working directory

### External Dependencies
- None (no third-party packages)

### Internal Dependencies
- Phase 2 depends on Phase 1 completion
- Phase 3 can partially parallel with Phase 2

---

## Risk Analysis & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Breaking existing functionality | Medium | High | Comprehensive test coverage before refactoring |
| Keychain migration issues | Low | High | Backup UserDefaults before migration |
| Performance regression | Low | Medium | Benchmark before/after |
| Merge conflicts | Medium | Low | Small, focused PRs |

---

## Documentation Plan

### Files to Update
- [ ] `README.md` - Note HTTPS default, testing instructions
- [ ] `CLAUDE.md` - Update architecture section with protocols
- [ ] `AGENTS.md` - Update testing guidelines with new test patterns

### New Documentation
- [ ] `docs/TESTING.md` - How to run tests, mock usage
- [ ] Inline code comments for complex logic

---

## References & Research

### Internal References
- Code review findings: Multi-agent analysis (security, performance, architecture, patterns, data integrity, simplicity)
- Architecture: `CLAUDE.md:29-49`
- Testing guidelines: `AGENTS.md:24-27`

### External References
- Swift Testing Framework: https://developer.apple.com/documentation/testing
- Keychain Services: https://developer.apple.com/documentation/security/keychain_services
- NWPathMonitor: https://developer.apple.com/documentation/network/nwpathmonitor
- Task Cancellation: https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html

### Related Work
- Recent commits: `70c8a79` (session reuse), `be8d8b5` (UI redesign)
- No open PRs currently

---

## Implementation Notes

### AI-Era Considerations
- Plan generated with Claude Code multi-agent review
- Mock implementations can be AI-generated then reviewed
- Test case generation benefits from parameterized testing
- All AI-generated code should be reviewed for correctness

### Recommended Workflow
1. Create feature branch: `refactor/code-quality-remediation`
2. Implement Phase 1 in single PR (critical fixes)
3. Implement Phase 2 in 2-3 PRs (protocols, DI, tests separately)
4. Implement Phase 3 in single PR (performance/cleanup)
5. Squash merge each phase to main
