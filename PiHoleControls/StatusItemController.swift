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
    private var statusViewWidthConstraint: NSLayoutConstraint?
    private var statusViewHeightConstraint: NSLayoutConstraint?
    private let statusViewVerticalOffset: CGFloat = -2

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

        if let button = statusItem.button {
            button.title = ""
            button.image = nil
            button.isBordered = false
            button.target = self
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            button.addSubview(statusView)
            statusView.translatesAutoresizingMaskIntoConstraints = false
            let centerX = statusView.centerXAnchor.constraint(equalTo: button.centerXAnchor)
            let centerY = statusView.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: statusViewVerticalOffset)

            let width = statusView.widthAnchor.constraint(equalToConstant: 0)
            let height = statusView.heightAnchor.constraint(equalToConstant: 0)
            statusViewWidthConstraint = width
            statusViewHeightConstraint = height

            NSLayoutConstraint.activate([centerX, centerY, width, height])
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

    private func toggleBlocking() {
        guard !store.isLoading else { return }
        store.toggleBlocking()
    }

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            togglePopover()
        } else {
            toggleBlocking()
        }
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
        let title = store.menuBarTitle
        let timerText = store.remainingDisableSeconds.map { remaining -> String in
            let min = remaining / 60
            let sec = remaining % 60
            return String(format: "%d:%02d", min, sec)
        }
        let statusImage = statusImage()
        statusView.update(image: statusImage.image, imageAlpha: statusImage.alpha, timerText: timerText)

        // Size the status item to our view’s intrinsic width.
        let size = statusView.intrinsicContentSize
        statusViewWidthConstraint?.constant = size.width
        statusViewHeightConstraint?.constant = size.height
        statusItem.length = size.width

        statusView.toolTip = title.isEmpty ? nil : title
    }

    private func statusImage() -> (image: NSImage?, alpha: CGFloat) {
        // Keep unknown state icon if we truly do not know.
        guard let enabled = store.isBlockingEnabled else {
            return (NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Pi-hole")?.settingTemplate(true), 1)
        }

        let baseImage = NSImage(named: "MenuIconInactive")?
            .trimmedToAlphaBounds()
            .resizedForStatusBar(maxDimension: 15, template: true)

        return (baseImage, enabled ? 1 : 0.35)
    }
}

private final class StatusItemView: NSView {
    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var labelHeightConstraint: NSLayoutConstraint?
    private var labelWidthConstraint: NSLayoutConstraint?
    private let placeholderLabelWidth: CGFloat
    private let placeholderLabelHeight: CGFloat

    private let horizontalInset: CGFloat = 0
    private let topInset: CGFloat = 4
    private let bottomInset: CGFloat = 1

    override init(frame frameRect: NSRect) {
        let placeholderSize = "00:00".size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)])
        self.placeholderLabelWidth = placeholderSize.width
        self.placeholderLabelHeight = placeholderSize.height
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
        shadow.shadowOffset = NSSize(width: 0, height: 0)
        shadow.shadowBlurRadius = 2
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
        label.shadow = shadow
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.translatesAutoresizingMaskIntoConstraints = false
        labelHeightConstraint = label.heightAnchor.constraint(equalToConstant: max(placeholderLabelHeight, label.intrinsicContentSize.height))
        labelWidthConstraint = label.widthAnchor.constraint(equalToConstant: placeholderLabelWidth)

        addSubview(imageView)
        addSubview(label)

        var constraints: [NSLayoutConstraint] = [
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: topInset),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: horizontalInset),
            imageView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -horizontalInset),

            label.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: horizontalInset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -horizontalInset),

            bottomAnchor.constraint(greaterThanOrEqualTo: imageView.bottomAnchor, constant: bottomInset),
            bottomAnchor.constraint(greaterThanOrEqualTo: label.bottomAnchor, constant: bottomInset)
        ]
        if let labelHeightConstraint {
            constraints.append(labelHeightConstraint)
        }
        if let labelWidthConstraint {
            constraints.append(labelWidthConstraint)
        }
        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) {
        self.placeholderLabelWidth = 0
        self.placeholderLabelHeight = 0
        fatalError("init(coder:) has not been implemented")
    }

    func update(image: NSImage?, imageAlpha: CGFloat = 1, timerText: String?) {
        imageView.image = image
        imageView.alphaValue = max(0, min(1, imageAlpha))
        label.stringValue = timerText ?? ""
        let hasText = !(timerText ?? "").isEmpty
        label.alphaValue = hasText ? 1 : 0
        let intrinsicSize = label.intrinsicContentSize
        labelHeightConstraint?.constant = max(placeholderLabelHeight, intrinsicSize.height)
        labelWidthConstraint?.constant = max(placeholderLabelWidth, intrinsicSize.width)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        let imageSize = imageView.intrinsicContentSize
        let labelIntrinsic = label.intrinsicContentSize
        let labelSize = NSSize(width: max(placeholderLabelWidth, labelIntrinsic.width),
                               height: max(placeholderLabelHeight, labelIntrinsic.height))
        let width = max(imageSize.width, labelSize.width) + (horizontalInset * 2)
        let height = max(imageSize.height, labelSize.height) + topInset + bottomInset
        return NSSize(width: width, height: height)
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

    func withAlpha(_ alpha: CGFloat) -> NSImage {
        let clampedAlpha = max(0, min(1, alpha))
        let result = NSImage(size: size)
        result.isTemplate = false
        result.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        draw(in: rect, from: .zero, operation: .sourceOver, fraction: clampedAlpha)
        result.unlockFocus()
        return result
    }
}
