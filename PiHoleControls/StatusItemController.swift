//
//  StatusItemController.swift
//  PiHoleControls
//
//  Created by Georg Kreimer on 11/27/25.
//

import Foundation
import AppKit
import SwiftUI
import Combine

/// Manages the status bar item and routes clicks to toggle blocking or open the popover menu.
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let store: PiHoleStore
    private var cancellables = Set<AnyCancellable>()

    init(store: PiHoleStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.popover.behavior = .transient
        self.popover.contentViewController = NSHostingController(rootView: ContentView().environmentObject(store))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        store.$isBlockingEnabled
            .combineLatest(store.$remainingDisableSeconds, store.$isLoading)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.updateButton()
            }
            .store(in: &cancellables)

        updateButton()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        switch event.type {
        case .rightMouseUp:
            togglePopover()
        case .leftMouseUp:
            toggleBlocking()
        default:
            break
        }
    }

    private func toggleBlocking() {
        guard !store.isLoading else { return }
        store.toggleBlocking()
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: store.menuBarIconSystemName, accessibilityDescription: "Pi-hole")
        button.imagePosition = .imageLeading
        button.title = store.menuBarTitle
        button.toolTip = store.menuBarTitle
    }
}
