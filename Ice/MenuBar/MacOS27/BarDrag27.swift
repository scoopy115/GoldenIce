//
//  BarDrag27.swift
//  Ice
//

import Cocoa

/// Moves items on the macOS 27 menu bar the way the user does: with a Command-drag.
///
/// MenuBarAgent, not the item's application, handles the drag on macOS 27, and it honours
/// Command-drags posted through the HID event stream (measured on macOS 27.0.1, 2026-10-09).
/// Only drawn items can be dragged; callers make sure both ends are on the bar first.
@available(macOS 27.0, *)
@MainActor
enum BarDrag27 {
    /// Whether the item is folded into the system overflow, or otherwise not drawn.
    static func isFolded(_ item: MenuBarItem) -> Bool {
        guard item.bounds.width > 1 else {
            return true
        }
        // An item MenuBarAgent will not draw is parked off every bar, below the screen
        // (measured at y 970–986 on a 982 pt tall display).
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
    static func isDrawn(_ item: MenuBarItem) -> Bool {
        guard !isFolded(item), let screen = NSScreen.screenWithActiveMenuBar else {
            return false
        }
        return CGDisplayBounds(screen.displayID).intersects(item.bounds)
    }

    /// Waits for the user to let go of the mouse, then Command-drags from one point to another.
    static func commandDrag(from start: CGPoint, to end: CGPoint) async {
        for _ in 0..<40 where MouseHelpers.isButtonPressed() {
            try? await Task.sleep(for: .milliseconds(100))
        }
        await Task.detached(priority: .userInitiated) {
            postCommandDrag(from: start, to: end)
        }.value
    }

    /// Posts a Command-drag through the HID event stream.
    ///
    /// MenuBarAgent only follows events that arrive like the user's own: a press, a drag that
    /// crosses into the next item's slot at a human pace, and a release (the timing follows
    /// Thaw's measurements). The user's own mouse is detached meanwhile, and the pointer is put
    /// back afterwards.
    private nonisolated static func postCommandDrag(from start: CGPoint, to end: CGPoint) {
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
