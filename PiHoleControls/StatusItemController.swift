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
    private let statusView: StatusItemView
    private let popover: NSPopover
    private let store: PiHoleStore
    private var cancellables = Set<AnyCancellable>()
    private var disableAfterAction: (() -> Void)?

    init(store: PiHoleStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusView = StatusItemView()
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

        statusView.onLeftClick = { [weak self] in self?.toggleBlocking() }
        statusView.onRightClick = { [weak self] in self?.togglePopover() }
        statusItem.view = statusView

        store.$isBlockingEnabled
            .combineLatest(store.$remainingDisableSeconds, store.$isLoading)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.updateButton()
            }
            .store(in: &cancellables)

        updateButton()
    }

    private func toggleBlocking() {
        guard !store.isLoading else { return }
        store.toggleBlocking()
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let view = statusItem.view {
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateButton() {
        let title = store.menuBarTitle
        let timerText = store.remainingDisableSeconds.map { remaining -> String in
            let min = remaining / 60
            let sec = remaining % 60
            return String(format: "%d:%02d", min, sec)
        }
        statusView.update(image: statusImage(), timerText: timerText)
        let size = statusView.intrinsicContentSize
        statusView.frame = NSRect(origin: .zero, size: size)
        statusItem.length = size.width
        statusView.toolTip = title.isEmpty ? nil : title
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
                .resizedForStatusBar(maxDimension: 16, template: false)
        } else {
            return NSImage(named: "MenuIconInactive")?
                .trimmedToAlphaBounds()
                .resizedForStatusBar(maxDimension: 16, template: true)
        }
    }
}

private final class StatusItemView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    private let horizontalInset: CGFloat = 4
    private let topInset: CGFloat = 2
    private let bottomInset: CGFloat = 2

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.required, for: .vertical)
        imageView.setContentHuggingPriority(.required, for: .horizontal)

        label.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.textColor = .white
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        label.shadow = shadow
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        addSubview(label)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: topInset),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: horizontalInset),
            imageView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -horizontalInset),

            label.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: horizontalInset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -horizontalInset),

            bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: bottomInset)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(image: NSImage?, timerText: String?) {
        imageView.image = image
        label.stringValue = timerText ?? ""
        label.isHidden = (timerText ?? "").isEmpty
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        let imageSize = imageView.intrinsicContentSize
        let labelSize = label.intrinsicContentSize
        let width = max(imageSize.width, labelSize.width) + (horizontalInset * 2)
        let height = max(imageSize.height, labelSize.height) + topInset + bottomInset
        return NSSize(width: max(width, 28), height: height)
    }

    override func mouseUp(with event: NSEvent) {
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            onRightClick?()
        } else {
            onLeftClick?()
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        onRightClick?()
    }
}

private extension NSImage {
    func resizedForStatusBar(maxDimension: CGFloat = 14, template: Bool) -> NSImage {
        let copy = self.copy() as? NSImage ?? self
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
