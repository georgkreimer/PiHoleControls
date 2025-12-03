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
    private var disableAfterAction: (() -> Void)?

    init(store: PiHoleStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.popover.behavior = .transient
        // Inject a callback so menu actions can close the popover.
        self.disableAfterAction = { [weak popover] in
            popover?.performClose(nil)
        }
        let contentView = ContentView()
            .environmentObject(store)
            .environment(\.dismissMenu, { [weak self] in self?.disableAfterAction?() })
        self.popover.contentViewController = NSHostingController(rootView: contentView)

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
        button.image = statusImage()
        button.imagePosition = .imageLeading
        button.title = store.menuBarTitle
        button.toolTip = store.menuBarTitle
    }

    private func statusImage() -> NSImage? {
        // Keep system symbols for loading and unknown states to surface feedback.
        if store.isLoading {
            return NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Pi-hole")?.settingTemplate(true)
        }
        guard let enabled = store.isBlockingEnabled else {
            return NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Pi-hole")?.settingTemplate(true)
        }

        if enabled {
            return NSImage(named: "MenuIconActive")?
                .trimmedToAlphaBounds()
                .resizedForStatusBar(template: false)
        } else {
            return NSImage(named: "MenuIconInactive")?
                .trimmedToAlphaBounds()
                .resizedForStatusBar(template: true)
        }
    }
}

private extension NSImage {
    func resizedForStatusBar(template: Bool) -> NSImage {
        let copy = self.copy() as? NSImage ?? self
        let maxDimension: CGFloat = 18
        let originalSize = copy.size
        if originalSize.width > 0, originalSize.height > 0 {
            let scale = min(maxDimension / originalSize.width, maxDimension / originalSize.height)
            copy.size = NSSize(width: originalSize.width * scale, height: originalSize.height * scale)
        } else {
            copy.size = NSSize(width: maxDimension, height: maxDimension)
        }
        copy.isTemplate = template
        return copy
    }

    func settingTemplate(_ isTemplate: Bool) -> NSImage {
        let copy = self.copy() as? NSImage ?? self
        copy.isTemplate = isTemplate
        return copy
    }

    func trimmedToAlphaBounds() -> NSImage {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = cgImage.dataProvider?.data else { return self }

        let alphaInfo = cgImage.alphaInfo
        let alphaOffset: Int
        switch alphaInfo {
        case .premultipliedLast, .last, .noneSkipLast:
            alphaOffset = cgImage.bitsPerPixel / 8 - 1
        case .premultipliedFirst, .first, .noneSkipFirst:
            alphaOffset = 0
        default:
            return self
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        guard bytesPerPixel >= 4, let ptr = CFDataGetBytePtr(data) else { return self }

        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0

        for y in 0..<height {
            let row = ptr + y * bytesPerRow
            for x in 0..<width {
                let pixel = row + x * bytesPerPixel
                let alpha = pixel[alphaOffset]
                if alpha > 0 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }

        if minX > maxX || minY > maxY { return self }

        let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cropped = cgImage.cropping(to: rect) else { return self }

        let trimmed = NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
        trimmed.isTemplate = self.isTemplate
        return trimmed
    }
}
