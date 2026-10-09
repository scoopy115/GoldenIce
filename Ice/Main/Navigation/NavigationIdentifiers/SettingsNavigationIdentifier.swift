//
//  SettingsNavigationIdentifier.swift
//  Ice
//

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
}
