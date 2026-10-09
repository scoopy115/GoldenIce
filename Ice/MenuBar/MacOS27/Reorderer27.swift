//
//  Reorderer27.swift
//  Ice
//

import Cocoa
import OSLog

/// Applies an order chosen in Menu Bar Layout to the macOS 27 menu bar.
///
/// MenuBarAgent keeps the order of the items itself, and the only way to change it is the
/// user's own: a Command-drag on the bar. Both items have to be drawn for that, which an item
/// in a hidden section is not, and an item on a full bar may be folded away. So for a moment
/// the bar shows only the section the item was dropped in — as the layout shows it — and Ice,
/// the item is dragged beside its new neighbour, and concealment goes back to what the layout
/// says. With only the two applications shown, MenuBarAgent placed them against items it was
/// not drawing, and the rest of the section came out in a different order (measured on
/// macOS 27.0.1, 2026-10-09).
@available(macOS 27.0, *)
@MainActor
enum Reorderer27 {
    private static let logger = Logger(category: "Reorderer27")

    /// How long the bar is given to lay itself out after concealment changes.
    private static let settle = Duration.milliseconds(700)

    /// Whether a reorder is under way; one at a time.
    private static var isReordering = false

    /// Moves `item` next to `neighbour` on the bar: before it, or after it if `after` is set.
    static func move(
        _ item: MenuBarItem,
        nextTo neighbour: MenuBarItem,
        after: Bool,
        section: [MenuBarItem],
        appState: AppState
    ) async {
        let concealer = appState.concealer27
        guard
            !isReordering,
            concealer.isolatedAllowlist == nil,
            item.tag != neighbour.tag,
            let itemBundleID = item.sourceApplication?.bundleIdentifier,
            let neighbourBundleID = neighbour.sourceApplication?.bundleIdentifier
        else {
            return
        }
        isReordering = true
        defer {
            isReordering = false
        }

        logger.notice("Moving \(item.logString, privacy: .public) \(after ? "after" : "before", privacy: .public) \(neighbour.logString, privacy: .public)")

        let sectionBundleIDs = section.compactMap { $0.sourceApplication?.bundleIdentifier }
        concealer.isolatedAllowlist = Set(sectionBundleIDs).union([Constants.bundleIdentifier, itemBundleID, neighbourBundleID])
        concealer.update()
        try? await Task.sleep(for: settle)

        var moved = false
        for attempt in 1...2 {
            let items = await MenuBarItemProvider27.items()
            guard
                let current = items.first(where: { $0.tag == item.tag && $0.ownerPID == item.ownerPID }),
                let target = items.first(where: { $0.tag == neighbour.tag && $0.ownerPID == neighbour.ownerPID }),
                BarDrag27.isDrawn(current),
                BarDrag27.isDrawn(target)
            else {
                logger.warning("The items to reorder were not drawn while the bar was cleared")
                break
            }
            // Applications concealed for the drag may sit between the two items, so being on
            // the right side of the neighbour is not yet being next to it: the first attempt
            // always drags, and a second one only follows if the item ended up on the wrong side.
            if attempt > 1, isInPlace(current, target: target, after: after) {
                moved = true
                break
            }
            // A drop on the near quarter of an item lands on that side of it, whichever way
            // the drag comes from: the item it crosses only moves over once the pointer passes
            // its middle.
            let endX = after
                ? target.bounds.maxX - target.bounds.width / 4
                : target.bounds.minX + target.bounds.width / 4
            await BarDrag27.commandDrag(
                from: CGPoint(x: current.bounds.midX, y: current.bounds.midY),
                to: CGPoint(x: endX, y: target.bounds.midY)
            )
            try? await Task.sleep(for: .milliseconds(400))
            logger.debug("Reorder attempt \(attempt, privacy: .public) done")
        }

        if !moved {
            let items = await MenuBarItemProvider27.items()
            if
                let current = items.first(where: { $0.tag == item.tag && $0.ownerPID == item.ownerPID }),
                let target = items.first(where: { $0.tag == neighbour.tag && $0.ownerPID == neighbour.ownerPID })
            {
                moved = isInPlace(current, target: target, after: after)
            }
        }
        if moved {
            logger.notice("\(item.logString, privacy: .public) is in its new place")
        } else {
            logger.warning("Could not move \(item.logString, privacy: .public)")
        }

        // The section is still drawn on its own, in its new order: photograph it now. Images
        // taken while the items were sliding into place could hold a piece of a neighbour, and
        // they would otherwise stay until the item was photographed again (measured on
        // macOS 27.0.1, 2026-10-09: Claude's tile kept half of Gnomon's glyph after a move).
        try? await Task.sleep(for: settle)
        await appState.itemImageStore27.captureActiveMenuBar(appState: appState, force: true)

        concealer.isolatedAllowlist = nil
        concealer.update()
        try? await Task.sleep(for: settle)
        await appState.itemManager.cacheItemsRegardless()
    }

    /// Whether `item` already sits on the requested side of `target`.
    private static func isInPlace(_ item: MenuBarItem, target: MenuBarItem, after: Bool) -> Bool {
        after ? item.bounds.minX > target.bounds.minX : item.bounds.minX < target.bounds.minX
    }
}
