//
//  PiHoleControlsApp.swift
//  PiHoleControls
//
//  Created by Georg Kreimer on 11/25/25.
//

import SwiftUI

@main
struct PiHoleControlsApp: App {
    @StateObject private var store = PiHoleStore()

    var body: some Scene {
        MenuBarExtra("Pi-hole", systemImage: store.menuBarIconSystemName) {
            ContentView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
