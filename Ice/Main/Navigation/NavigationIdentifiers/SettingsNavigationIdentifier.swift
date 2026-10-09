//
//  SettingsNavigationIdentifier.swift
//  Ice
//

import SwiftUI

/// The navigation identifier type for the "Settings" interface.
enum SettingsNavigationIdentifier: String, NavigationIdentifier {
    case general = "General"
    case menuBarLayout = "Menu Bar Layout"
    case rules = "Rules"
    case profiles = "Profiles"
    case menuBarAppearance = "Menu Bar Appearance"
    case hotkeys = "Hotkeys"
    case advanced = "Advanced"
    case about = "About"

    var iconResource: IconResource {
        switch self {
        case .general: .systemSymbol("gearshape")
        case .menuBarLayout: .systemSymbol("rectangle.topthird.inset.filled")
        case .rules: .systemSymbol("wand.and.sparkles")
        case .profiles: .systemSymbol("square.stack.3d.up")
        case .menuBarAppearance: .systemSymbol("swatchpalette")
        case .hotkeys: .systemSymbol("keyboard")
        case .advanced: .systemSymbol("gearshape.2")
        case .about: .assetCatalog(.iceCubeStroke)
        }
    }

    /// The tile colour of the identifier's icon in the sidebar.
    var tileColor: Color {
        switch self {
        case .general: .gray
        case .menuBarLayout: GoldenIceBrand.gold
        case .rules: .purple
        case .profiles: .indigo
        case .menuBarAppearance: .pink
        case .hotkeys: .blue
        case .advanced: .teal
        case .about: GoldenIceBrand.ice
        }
    }

    /// One line on what the pane is for.
    var subtitle: LocalizedStringKey {
        switch self {
        case .general: "How GoldenIce looks and behaves in your menu bar."
        case .menuBarLayout: "Decide what's always in view, and what waits until you ask."
        case .rules: "Let items step forward on their own, when you need them."
        case .profiles: "One menu bar for work, another for home — switch in a click."
        case .menuBarAppearance: "Tint, shape and shadow, made yours."
        case .hotkeys: "Keyboard shortcuts for the things you do most."
        case .advanced: "Fine-tuning, indicators and permissions."
        case .about: "A golden fork of Ice, made for macOS 27."
        }
    }
}
