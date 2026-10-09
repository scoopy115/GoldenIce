//
//  CaptureIndicatorPanel27.swift
//  Ice
//

import Cocoa
import Combine
import OSLog
import SwiftUI

/// Draws Ice's own camera and microphone indicator on the menu bar.
///
/// macOS has one of its own, but it belongs to Control Centre, and Control Centre's modules are
/// gone from the bar while any assessment assertion is live — which is to say, whenever Ice hides
/// anything. Nothing in the assertion can spare them (measured on macOS 27.0 against every system
/// item number up to 127, Control Centre's bundle identifier and the capturing application's), so
/// the only way to leave the user that indicator is to draw it.
///
/// It is a status item of Ice's own rather than a panel laid over the bar: a panel had to guess
/// at a free stretch of bar and landed on top of Ice's icon, and it could not be moved. As an
/// item it takes its own room, can be Command-dragged like any other, and MenuBarAgent remembers
/// where it was put. Ice's items stay on the bar while it conceals others, being Developer ID
/// signed. Between uses it collapses to no width rather than going away, so its place is kept.
///
/// Clicking it opens Control Centre, where the camera's own controls — Video Effects, Mic Mode —
/// live during a call.
@available(macOS 27.0, *)
@MainActor
final class CaptureIndicatorPanel27: NSObject {
    private let logger = Logger(category: "CaptureIndicatorPanel27")
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    private var shownKind: CaptureIndicator27.Kind?
    private var placement: CaptureIndicatorPlacement?

    /// The prefix of the item's autosave name, which Ice's item reader recognises it by.
    nonisolated static let autosaveNamePrefix = "Ice.CaptureIndicator"

    private static let frameLock = NSLock()
    nonisolated(unsafe) private static var shownFrame: CGRect?

    /// Where the indicator is drawn right now, for the hit tests that decide whether the pointer
    /// is over an empty stretch of the bar. Without this, hovering the indicator revealed the
    /// hidden items and clicking it did whatever a click on the bare bar does.
    nonisolated static func indicatorFrame() -> CGRect? {
        frameLock.withLock { shownFrame }
    }

    /// Records the item's frame as Ice's item reader last saw it.
    nonisolated static func setIndicatorFrame(_ frame: CGRect?) {
        frameLock.withLock { shownFrame = frame }
    }

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    /// Starts following what is in use, and where the user wants the indicator.
    func performSetup(watcher: CaptureWatcher27) {
        watcher.$kind
            .receive(on: DispatchQueue.main)
            .sink { [weak self] kind in
                MainActor.assumeIsolated {
                    self?.update(kind: kind)
                }
            }
            .store(in: &cancellables)
        appState?.settings.advanced.$captureIndicatorPlacement
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else {
                        return
                    }
                    // Placed anew: a fresh item, so MenuBarAgent takes the starting position.
                    self.removeItem()
                    self.update(kind: self.shownKind)
                }
            }
            .store(in: &cancellables)
    }

    /// Shows or collapses the indicator.
    private func update(kind: CaptureIndicator27.Kind?) {
        shownKind = kind
        guard
            let kind,
            let appState,
            appState.settings.advanced.showCaptureIndicator,
            appState.concealer27.isConcealing
        else {
            collapse()
            return
        }
        let item = item(for: appState.settings.advanced.captureIndicatorPlacement)
        item.length = NSStatusItem.variableLength
        if let button = item.button {
            button.image = Self.image(for: kind)
            button.toolTip = kind == .camera ? "The camera is in use" : "The microphone is in use"
            button.setAccessibilityLabel(button.toolTip)
        }
    }

    /// Shrinks the item to nothing, keeping its place on the bar.
    private func collapse() {
        guard let statusItem else {
            return
        }
        statusItem.button?.image = nil
        statusItem.length = 0
        Self.setIndicatorFrame(nil)
    }

    private func removeItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        Self.setIndicatorFrame(nil)
    }

    /// The status item, created at the starting position for the given placement.
    ///
    /// MenuBarAgent places an item it has not seen before by the legacy preferred position, the
    /// distance from the right end of the bar (measured on macOS 27.0.1: Ice's icon with 477 went
    /// to 477 points from the right). Each placement has an autosave name of its own, so choosing
    /// one gives a fresh item that MenuBarAgent places there; "where I drag it" keeps whatever
    /// MenuBarAgent remembers.
    private func item(for placement: CaptureIndicatorPlacement) -> NSStatusItem {
        if let statusItem, self.placement == placement {
            return statusItem
        }
        removeItem()
        let autosaveName = "\(Self.autosaveNamePrefix).\(placement)"
        let positionKey = "NSStatusItem Preferred Position \(autosaveName)"
        if let position = startingPosition(for: placement) {
            UserDefaults.standard.set(position, forKey: positionKey)
        }
        let item = NSStatusBar.system.statusItem(withLength: 0)
        item.autosaveName = autosaveName
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.imagePosition = .imageOnly
        statusItem = item
        self.placement = placement
        logger.debug("Created the capture indicator item, placed \(String(describing: placement), privacy: .public)")
        return item
    }

    /// The distance from the bar's right end to start the item at, or `nil` to leave it.
    private func startingPosition(for placement: CaptureIndicatorPlacement) -> Double? {
        guard let screen = NSScreen.screenWithActiveMenuBar else {
            return nil
        }
        let barRight = CGDisplayBounds(screen.displayID).maxX
        switch placement {
        case .trailing:
            // Just left of the system items (Wi-Fi, Control Centre, the clock).
            guard let systemLeft = MenuBarItemProvider27.systemItemFrames().map(\.minX).min() else {
                return 200
            }
            return Double(barRight - systemLeft + 2)
        case .leading:
            guard let leftEdge = MenuBarItemProvider27.leftEdge(for: screen.displayID) else {
                return nil
            }
            return Double(barRight - leftEdge + 2)
        case .custom:
            return nil
        }
    }

    @objc private func clicked() {
        openCaptureControls()
    }

    /// The indicator's image: a green camera or an orange microphone on a capsule, the way
    /// macOS draws its own.
    private static func image(for kind: CaptureIndicator27.Kind) -> NSImage {
        let size = NSSize(width: 30, height: 20)
        let colour: NSColor = switch kind {
        case .camera: NSColor(red: 0.16, green: 0.78, blue: 0.3, alpha: 1)
        case .microphone: NSColor(red: 0.98, green: 0.58, blue: 0.09, alpha: 1)
        }
        let symbolName = kind == .camera ? "video.fill" : "mic.fill"
        let image = NSImage(size: size, flipped: false) { rect in
            colour.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
            {
                let symbolRect = NSRect(
                    x: rect.midX - symbol.size.width / 2,
                    y: rect.midY - symbol.size.height / 2,
                    width: symbol.size.width,
                    height: symbol.size.height
                )
                symbol.draw(in: symbolRect)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Opens the camera and microphone controls, the ones the system's own indicator opens.
    ///
    /// The module those belong to is not drawn while anything is concealed, so there is nothing
    /// to press until the concealment is lifted — the same lift a click on the clock needs, and
    /// the same cost: the hidden items flash into view for a moment. Measured on macOS 27.0: with
    /// nothing concealed the module is a system item of its own,
    /// `com.apple.menuextra.audiovideo` ("Audio and Video Controls"), and it opens from an
    /// Accessibility press.
    ///
    /// If it does not appear, Control Centre is opened instead: the same controls are inside it
    /// during a call, and it opens with the concealment still in force.
    private func openCaptureControls() {
        guard let appState else {
            return
        }
        logger.notice("Opening the capture controls from the indicator")
        Task { [weak self] in
            await appState.concealer27.suspendReleased(for: .milliseconds(900))
            for _ in 0..<14 {
                _ = await MenuBarItemProvider27.items()
                if let element = MenuBarItemProvider27.systemItem(withIdentifier: Self.audioVideoItem) {
                    await Self.press(element)
                    // Hide the items again as soon as the controls are open, rather than letting
                    // the lift run its course: what the user sees of it is the whole cost.
                    try? await Task.sleep(for: .milliseconds(150))
                    appState.concealer27.resumeConcealing()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            self?.logger.warning("The audio and video item never appeared, so Control Centre was opened instead")
            if let element = MenuBarItemProvider27.systemItem(withIdentifier: Self.controlCentreItem) {
                await Self.press(element)
            }
            appState.concealer27.resumeConcealing()
        }
    }

    /// The system item the camera and microphone controls belong to.
    private static let audioVideoItem = "com.apple.menuextra.audiovideo"

    /// Control Centre's own item, which holds the same controls during a call.
    private static let controlCentreItem = "com.apple.menuextra.controlcenter"

    /// Presses an Accessibility element off the main thread, which the call can block.
    private static func press(_ element: AXUIElement) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
                continuation.resume()
            }
        }
    }
}
