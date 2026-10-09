//
//  ProfilesSettingsPane.swift
//  Ice
//

import SwiftUI

/// Named menu bar arrangements to switch between, and backups of them.
struct ProfilesSettingsPane: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if #available(macOS 27.0, *) {
            ProfilesSettingsPane27(manager: appState.profileManager27)
        } else {
            IceForm {
                IceSection {
                    Text("Profiles are available on macOS 27 and later.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                }
            }
        }
    }
}

@available(macOS 27.0, *)
private struct ProfilesSettingsPane27: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var manager: ProfileManager27
    @State private var newProfileName = ""
    @State private var editingProfile: LayoutProfile?

    var body: some View {
        IceForm {
            IceSection {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Profiles")
                        .font(.headline)
                    Text("Save how your menu bar is arranged — which apps are hidden and which show while in front — and switch between arrangements, by hand, with a hotkey, or when a display comes and goes. While a profile is active, changes you make in Menu Bar Layout and Rules are saved to it.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            IceSection("Save Current Layout") {
                HStack {
                    TextField("Name, e.g. Work or Home", text: $newProfileName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if manager.profiles.isEmpty {
                IceSection {
                    VStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                        Text("No profiles yet")
                            .font(.headline)
                        Text("Arrange your menu bar the way you like it, then save it above.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                }
            } else {
                IceSection("Your Profiles") {
                    ForEach(manager.profiles) { profile in
                        ProfileRow(profile: profile, manager: manager) {
                            manager.beginEditing(profile)
                            editingProfile = profile
                        }
                    }
                    NoProfileRow(manager: manager)
                }
            }

            IceSection("Backup") {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Layout backup")
                        Text("Your sections, rules and profiles in one file.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Import…") {
                        manager.importBackup()
                    }
                    Button("Export…") {
                        manager.exportBackup()
                    }
                }
            }
        }
        .sheet(item: $editingProfile, onDismiss: manager.endEditing) { profile in
            ProfileLayoutEditor(profile: profile, manager: manager) {
                editingProfile = nil
            }
            .environmentObject(appState)
        }
    }

    private func save() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            return
        }
        manager.saveCurrent(named: name)
        newProfileName = ""
    }
}

@available(macOS 27.0, *)
private struct ProfileRow: View {
    let profile: LayoutProfile
    @ObservedObject var manager: ProfileManager27
    let onEdit: () -> Void
    @State private var isRenaming = false
    @State private var newName = ""

    private var isActive: Bool {
        manager.activeProfileID == profile.id
    }

    /// The applications this profile hides, the ones that tell profiles apart.
    private var hiddenBundleIDs: [String] {
        profile.layout
            .filter { $0.value != MacOS27Section.visible.rawValue }
            .map(\.key)
            .sorted()
    }

    private func title(for trigger: LayoutProfile.Trigger) -> LocalizedStringKey {
        switch trigger {
        case .manual: "Manually"
        case .externalDisplay: "With an external display"
        case .builtInDisplayOnly: "On the built-in display only"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    if isActive {
                        manager.deactivate()
                    } else {
                        manager.apply(profile)
                    }
                } label: {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                        .font(.system(size: 17))
                }
                .buttonStyle(.plain)
                .help(isActive ? "Stop using this profile" : "Switch to this profile")

                Menu {
                    ForEach(LayoutProfile.symbols, id: \.self) { symbol in
                        Button {
                            manager.setSymbol(symbol, for: profile)
                        } label: {
                            Label(symbol, systemImage: symbol)
                                .labelStyle(.iconOnly)
                        }
                    }
                } label: {
                    Image(systemName: profile.symbol)
                        .font(.system(size: 14))
                        .frame(width: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Choose an icon")

                Text(profile.name)
                    .fontWeight(isActive ? .semibold : .regular)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Edit Layout…", action: onEdit)
                    .fixedSize()

                Menu {
                    Button("Rename…") {
                        newName = profile.name
                        isRenaming = true
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        manager.delete(profile)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            HStack(spacing: 4) {
                Text(hiddenBundleIDs.isEmpty ? "Hides nothing" : "Hides")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ForEach(hiddenBundleIDs.prefix(14), id: \.self) { bundleID in
                    ApplicationIcon(bundleID: bundleID)
                }
                if hiddenBundleIDs.count > 14 {
                    Text("+\(hiddenBundleIDs.count - 14)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Menu {
                    ForEach(LayoutProfile.Trigger.allCases, id: \.self) { trigger in
                        Button {
                            manager.setTrigger(trigger, for: profile)
                        } label: {
                            if trigger == profile.trigger {
                                Label(title(for: trigger), systemImage: "checkmark")
                            } else {
                                Text(title(for: trigger))
                            }
                        }
                    }
                } label: {
                    Text(title(for: profile.trigger))
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("When this profile switches in by itself")
            }
            .padding(.leading, 53)
        }
        .padding(.vertical, 4)
        .alert("Rename Profile", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Rename") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    manager.rename(profile, to: name)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

/// An application's icon, small, with its name on hover.
private struct ApplicationIcon: View {
    let bundleID: String

    private var url: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    var body: some View {
        Group {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 16, height: 16)
        .help(url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID)
    }
}

/// The choice not to use any profile.
@available(macOS 27.0, *)
private struct NoProfileRow: View {
    @ObservedObject var manager: ProfileManager27

    var body: some View {
        HStack(spacing: 8) {
            Button {
                manager.deactivate()
            } label: {
                Image(systemName: manager.activeProfileID == nil ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(manager.activeProfileID == nil ? Color.accentColor : .secondary)
                    .font(.system(size: 17))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text("No Profile")
                    .fontWeight(manager.activeProfileID == nil ? .semibold : .regular)
                Text("Arrange the menu bar freely; nothing is saved to a profile.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

/// A profile's layout, edited in a sheet over the Profiles pane.
///
/// The profile is applied while the sheet is open, so the bars show its arrangement and
/// whatever is dragged is saved to it. Closing the sheet puts back what was in force before.
@available(macOS 27.0, *)
private struct ProfileLayoutEditor: View {
    @EnvironmentObject var appState: AppState
    let profile: LayoutProfile
    @ObservedObject var manager: ProfileManager27
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: profile.symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit “\(profile.name)”")
                        .font(.title2.bold())
                    Text("Drag items between sections. Changes are saved to this profile.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
            ForEach(MenuBarSection.Name.allCases, id: \.self) { name in
                if let section = appState.menuBarManager.section(withName: name), section.isEnabled {
                    VStack(alignment: .leading) {
                        Text(name.localized)
                            .font(.headline)
                            .padding(.leading, 8)
                        LayoutBar(imageCache: appState.imageCache, section: name)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 760)
    }
}
