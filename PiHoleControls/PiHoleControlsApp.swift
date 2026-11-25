//
//  PiHoleControlsApp.swift
//  PiHoleControls
//
//  Created by Georg Kreimer on 11/25/25.
//

import SwiftUI

@main
struct PiHoleControlsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isTesting: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    let store: PiHoleStore = {
        if isTesting {
            return PiHoleStore(defaults: UserDefaults(suiteName: "PiHoleControls.TestHost.\(UUID())")!,
                               tokenStorage: TokenStorage(load: { nil }, save: { _ in }),
                               monitorNetwork: false)
        }
        return PiHoleStore()
    }()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isTesting else { return }
        // LSUIElement=YES hides dock icon by default. Show it only if user opted in.
        if UserDefaults.standard.bool(forKey: "showDockIcon") {
            NSApp.setActivationPolicy(.regular)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        statusItemController = StatusItemController(store: store)
        store.startAutoRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopAutoRefresh()
    }
}
