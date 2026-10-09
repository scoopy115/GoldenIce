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
                    Text("Save how your menu bar is arranged — which apps are visible and which are hidden — and switch between arrangements, by hand, with a hotkey, or when a display comes and goes. While a profile is active, changes you make in Menu Bar Layout are saved to it. Rules apply to every profile.")
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
            ProfileEditor(profileID: profile.id, manager: manager) {
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

    private var isActive: Bool {
        manager.activeProfileID == profile.id
    }

    private var triggerSummary: LocalizedStringKey? {
        switch profile.trigger {
        case .manual: nil
        case .externalDisplay: "Switches in when you connect a display"
        case .builtInDisplayOnly: "Switches in when you're on the built-in display alone"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
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

            Image(systemName: profile.symbol)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .fontWeight(isActive ? .semibold : .regular)
                if let triggerSummary {
                    Text(triggerSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Edit Profile…", action: onEdit)
                .fixedSize()
        }
        .padding(.vertical, 3)
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

/// Everything about a profile, edited in a sheet over the Profiles pane: its name, icon,
/// when it switches in by itself, and its menu bar layout.
///
/// The profile is applied while the sheet is open, so the layout bars show its arrangement and
/// whatever is dragged is saved to it. Closing the sheet puts back what was in force before.
@available(macOS 27.0, *)
private struct ProfileEditor: View {
    @EnvironmentObject var appState: AppState
    let profileID: UUID
    @ObservedObject var manager: ProfileManager27
    let done: () -> Void

    @State private var name = ""
    @State private var isConfirmingDelete = false

    private var profile: LayoutProfile? {
        manager.profiles.first { $0.id == profileID }
    }

    private let iconColumns = Array(repeating: GridItem(.fixed(34), spacing: 6), count: 16)

    var body: some View {
        if let profile {
            VStack(alignment: .leading, spacing: 18) {
                Text("Edit Profile")
                    .font(.title2.bold())

                LabeledContent("Name") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .onSubmit(commitName)
                }

                LabeledContent("Icon") {
                    LazyVGrid(columns: iconColumns, alignment: .leading, spacing: 6) {
                        ForEach(LayoutProfile.symbols, id: \.self) { symbol in
                            Button {
                                manager.setSymbol(symbol, for: profile)
                            } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 14))
                                    .frame(width: 30, height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(symbol == profile.symbol ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(symbol == profile.symbol ? Color.accentColor : .clear, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                LabeledContent {
                    Picker("", selection: Binding(
                        get: { profile.trigger },
                        set: { manager.setTrigger($0, for: profile) }
                    )) {
                        Text("Never").tag(LayoutProfile.Trigger.manual)
                        Text("When an external display is connected").tag(LayoutProfile.Trigger.externalDisplay)
                        Text("When only the built-in display is used").tag(LayoutProfile.Trigger.builtInDisplayOnly)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Switch automatically")
                    Text("Every display shows the same menu bar; this decides when GoldenIce switches to this profile by itself.")
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Layout")
                        .font(.headline)
                    Text("Drag items between sections. Changes are saved to this profile.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    ForEach(MenuBarSection.Name.allCases, id: \.self) { name in
                        if let section = appState.menuBarManager.section(withName: name), section.isEnabled {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name.localized)
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.leading, 8)
                                LayoutBar(imageCache: appState.imageCache, section: name)
                            }
                        }
                    }
                    DisabledItemsBar(concealer: appState.concealer27)
                }

                HStack {
                    Button("Delete Profile…", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    Spacer()
                    Button("Done") {
                        commitName()
                        done()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 780)
            .onAppear {
                name = profile.name
            }
            .confirmationDialog("Delete “\(profile.name)”?", isPresented: $isConfirmingDelete) {
                Button("Delete Profile", role: .destructive) {
                    done()
                    manager.delete(profile)
                }
            } message: {
                Text("Your menu bar stays as it is now.")
            }
        }
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let profile, !trimmed.isEmpty, trimmed != profile.name else {
            return
        }
        manager.rename(profile, to: trimmed)
    }
}
