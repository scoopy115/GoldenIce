//
//  IconPlacer27.swift
//  Ice
//

import Cocoa
import OSLog

/// Keeps Ice's own icon on the menu bar on macOS 27.
///
/// MenuBarAgent puts a status item it has not placed before at the far left of the trailing
/// items, which is the first place it folds into the system overflow ("«") once the bar is
/// full — and on a notched display it usually is. Ice's icon then sits behind the overflow
/// button, and there is nothing left to click to show the hidden items.
///
/// A folded item cannot be dragged, so the placer conceals every other application for a
/// moment, except the one whose item is rightmost on the bar. That leaves room for Ice's icon
/// to be drawn, and a Command-drag puts it to the right of that item, which is the last place
/// MenuBarAgent folds. MenuBarAgent keeps the order it is given, so this is needed once rather
/// than on every launch (measured on macOS 27.0.1, 2026-10-09).
@available(macOS 27.0, *)
@MainActor
final class IconPlacer27 {
    /// Applications that are never concealed, not even while the icon is placed: they host the
    /// system items, which the assertion keeps by number anyway.
    nonisolated static let neverConcealed: Set<String> = [
        "com.apple.MenuBarAgent",
        "com.apple.controlcenter",
    ]

    /// The most attempts made in one launch, so a bar that will not take the icon is not
    /// shuffled over and over.
    private static let maxAttempts = 3

    /// The shortest time between two attempts.
    private static let attemptInterval = Duration.seconds(20)

    /// How long the bar is given to lay itself out after concealment changes.
    private static let settle = Duration.milliseconds(700)

    private unowned let concealer: Concealer27
    private let logger = Logger(category: "IconPlacer27")

    private var isPlacing = false
    private var attempts = 0
    private var lastAttemptAt: ContinuousClock.Instant?

    init(concealer: Concealer27) {
        self.concealer = concealer
    }

    /// Checks whether Ice's icon is folded into the overflow, and places it on the bar if it is.
    func checkPlacement() async {
        guard
            !isPlacing,
            attempts < Self.maxAttempts,
            let appState = concealer.appState,
            appState.settings.general.showIceIcon
        else {
            return
        }
        if let lastAttemptAt, ContinuousClock.now - lastAttemptAt < Self.attemptInterval {
            return
        }

        let items = await MenuBarItemProvider27.items()
        guard
            let icon = items.first(where: { $0.tag == .visibleControlItem }),
            isFolded(icon)
        else {
            return
        }
        guard let anchor = anchorItem(in: items, besides: icon) else {
            logger.notice("Ice's icon is folded, but there is no item on the bar to place it beside")
            return
        }
        guard let anchorBundleID = anchor.sourceApplication?.bundleIdentifier else {
            return
        }

        isPlacing = true
        attempts += 1
        lastAttemptAt = .now
        defer {
            isPlacing = false
        }

        logger.notice("Ice's icon is folded into the overflow; placing it beside \(anchor.logString, privacy: .public)")
        await place(anchorBundleID: anchorBundleID)

        try? await Task.sleep(for: Self.settle)
        let after = await MenuBarItemProvider27.items()
        if let icon = after.first(where: { $0.tag == .visibleControlItem }), !isFolded(icon) {
            logger.notice("Ice's icon is on the bar at \(icon.bounds.minX, privacy: .public)")
            attempts = 0
        } else {
            logger.warning("Ice's icon is still folded after placing it (attempt \(self.attempts, privacy: .public))")
        }
    }

    /// Conceals everything but Ice and the anchor's application, drags the icon beside the
    /// anchor, and puts concealment back the way it was.
    private func place(anchorBundleID: String) async {
        concealer.isolatedAllowlist = [Constants.bundleIdentifier, anchorBundleID]
        concealer.update()
        defer {
            concealer.isolatedAllowlist = nil
            concealer.update()
        }

        try? await Task.sleep(for: Self.settle)
        let items = await MenuBarItemProvider27.items()
        guard let icon = items.first(where: { $0.tag == .visibleControlItem }), !isFolded(icon) else {
            logger.warning("Ice's icon was not drawn while the bar was cleared")
            return
        }
        let anchors = items.filter { item in
            item.sourceApplication?.bundleIdentifier == anchorBundleID && isDrawn(item)
        }
        guard let anchor = anchors.max(by: { $0.bounds.minX < $1.bounds.minX }) else {
            logger.warning("The item to place Ice's icon beside was not drawn while the bar was cleared")
            return
        }
        guard icon.bounds.minX < anchor.bounds.minX else {
            // Already to the right of it: nothing will fold before the icon does.
            return
        }

        let start = CGPoint(x: icon.bounds.midX, y: icon.bounds.midY)
        // The right half of an item is where a drop lands after it.
        let end = CGPoint(x: anchor.bounds.maxX - anchor.bounds.width / 4, y: anchor.bounds.midY)
        await waitForUserToPauseInput()
        await Task.detached(priority: .userInitiated) {
            Self.commandDrag(from: start, to: end)
        }.value
    }

    /// Whether the item is folded into the system overflow, or otherwise not drawn.
    private func isFolded(_ item: MenuBarItem) -> Bool {
        guard item.bounds.width > 1 else {
            return true
        }
        // A new item MenuBarAgent has no room for can also be parked off every bar, below the
        // screen (measured at y 986 on a 982 pt tall display).
        let isOnABar = NSScreen.screens.contains { screen in
            let display = CGDisplayBounds(screen.displayID)
            let bar = CGRect(x: display.minX, y: display.minY, width: display.width, height: 50)
            return bar.intersects(item.bounds)
        }
        guard isOnABar else {
            return true
        }
        return OverflowDetection27.isInOverflow(
            itemFrame: item.bounds,
            chevronFrame: MenuBarItemProvider27.overflowButtonFrame()
        )
    }

    /// Whether the item is drawn on the bar of the display with the active menu bar.
    private func isDrawn(_ item: MenuBarItem) -> Bool {
        guard !isFolded(item), let screen = NSScreen.screenWithActiveMenuBar else {
            return false
        }
        return CGDisplayBounds(screen.displayID).intersects(item.bounds)
    }

    /// The rightmost drawn item of another application, left of the system items.
    private func anchorItem(in items: [MenuBarItem], besides icon: MenuBarItem) -> MenuBarItem? {
        let systemEdge = MenuBarItemProvider27.systemItemFrames().map(\.minX).min() ?? .infinity
        return items
            .filter { item in
                !item.isControlItem &&
                item.ownerPID != icon.ownerPID &&
                item.bounds.maxX <= systemEdge + 1 &&
                isDrawn(item) &&
                !Self.neverConcealed.contains(item.sourceApplication?.bundleIdentifier ?? "")
            }
            .max { $0.bounds.minX < $1.bounds.minX }
    }

    /// Waits, for a few seconds at most, until no mouse button is held.
    private func waitForUserToPauseInput() async {
        for _ in 0..<40 where MouseHelpers.isButtonPressed() {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Posts a Command-drag through the HID event stream.
    ///
    /// On macOS 27 MenuBarAgent, not the item's application, handles the drag, and it only
    /// follows events that arrive like the user's own: a press, a drag that crosses into the
    /// next item's slot at a human pace, and a release (the timing follows Thaw's measurements).
    /// The user's own mouse is detached meanwhile, and the pointer is put back afterwards.
    private nonisolated static func commandDrag(from start: CGPoint, to end: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let origin = MouseHelpers.locationCoreGraphics

        func post(_ type: CGEventType, at point: CGPoint, flags: CGEventFlags) {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else {
                return
            }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }

        CGAssociateMouseAndMouseCursorPosition(0)
        MouseHelpers.hideCursor()
        defer {
            if let origin {
                CGWarpMouseCursorPosition(origin)
            }
            CGAssociateMouseAndMouseCursorPosition(1)
            MouseHelpers.showCursor()
        }

        post(.mouseMoved, at: start, flags: [])
        usleep(200_000)
        post(.leftMouseDown, at: start, flags: .maskCommand)
        usleep(40_000)
        let steps = 48 // 800 ms at 60 Hz
        for step in 1...steps {
            let fraction = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
            post(.leftMouseDragged, at: point, flags: .maskCommand)
            usleep(16_667)
        }
        usleep(300_000)
        post(.leftMouseUp, at: end, flags: .maskCommand)
        usleep(50_000)
    }
}
