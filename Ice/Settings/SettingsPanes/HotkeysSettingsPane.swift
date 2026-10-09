//
//  HotkeysSettingsPane.swift
//  Ice
//

import SwiftUI

struct HotkeysSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: HotkeysSettings

    var body: some View {
        IceForm {
            IceSection("Menu Bar Sections") {
                hotkeyRecorder(forSection: .hidden)
                hotkeyRecorder(forSection: .alwaysHidden)
            }
            IceSection("Menu Bar Items") {
                hotkeyRecorder(forAction: .searchMenuBarItems)
            }
            if #available(macOS 27.0, *) {
                ProfileHotkeys(manager: appState.profileManager27) {
                    hotkeyRecorder(forAction: .nextProfile)
                }
            }
            IceSection("Other") {
                hotkeyRecorder(forAction: .enableIceBar)
                hotkeyRecorder(forAction: .toggleApplicationMenus)
            }
        }
    }

    @ViewBuilder
    private func hotkeyRecorder(forAction action: HotkeyAction) -> some View {
        if let hotkey = settings.hotkey(withAction: action) {
            HotkeyRecorder(hotkey: hotkey) {
                switch action {
                case .toggleHiddenSection:
                    Text("Toggle the hidden section")
                case .toggleAlwaysHiddenSection:
                    Text("Toggle the always-hidden section")
                case .searchMenuBarItems:
                    Text("Search menu bar items")
                case .nextProfile:
                    Text("Switch to the next profile")
                case .enableIceBar:
                    Text("Enable the Ice Bar")
                case .toggleApplicationMenus:
                    Text("Toggle application menus")
                }
            }
        }
    }

    @ViewBuilder
    private func hotkeyRecorder(forSection name: MenuBarSection.Name) -> some View {
        if appState.menuBarManager.section(withName: name)?.isEnabled == true {
            if case .hidden = name {
                hotkeyRecorder(forAction: .toggleHiddenSection)
            } else if case .alwaysHidden = name {
                hotkeyRecorder(forAction: .toggleAlwaysHiddenSection)
            }
        }
    }
}

/// A hotkey for each profile, and one that steps through them.
@available(macOS 27.0, *)
private struct ProfileHotkeys<NextProfile: View>: View {
    @ObservedObject var manager: ProfileManager27
    @ViewBuilder var nextProfile: NextProfile

    var body: some View {
        IceSection("Profiles") {
            nextProfile
            ForEach(manager.profiles) { profile in
                if let hotkey = manager.hotkeys[profile.id] {
                    HotkeyRecorder(hotkey: hotkey) {
                        Label("Switch to \(profile.name)", systemImage: profile.symbol)
                    }
                }
            }
        }
    }
}
