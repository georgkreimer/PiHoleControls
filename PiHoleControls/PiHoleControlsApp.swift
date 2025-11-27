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
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
        } label: {
            Label(store.menuBarTitle, systemImage: store.menuBarIconSystemName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
