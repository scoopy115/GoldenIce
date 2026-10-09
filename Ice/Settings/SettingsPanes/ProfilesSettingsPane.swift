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
    @ObservedObject var manager: ProfileManager27
    @State private var newProfileName = ""

    var body: some View {
        IceForm {
            IceSection {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Profiles")
                        .font(.headline)
                    Text("Save how your menu bar is arranged — which apps are hidden and which show while in front — and switch between arrangements, by hand or when a display comes and goes.")
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
                        ProfileRow(profile: profile, manager: manager)
                    }
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

    private var isActive: Bool {
        manager.activeProfileID == profile.id
    }

    private var hiddenCount: Int {
        profile.layout.values.filter { $0 != MacOS27Section.visible.rawValue }.count
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .fontWeight(isActive ? .semibold : .regular)
                Text("\(hiddenCount) hidden apps · \(profile.showWhenFrontmost.count) rules")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { profile.trigger },
                set: { manager.setTrigger($0, for: profile) }
            )) {
                Text("Manually").tag(LayoutProfile.Trigger.manual)
                Text("With an external display").tag(LayoutProfile.Trigger.externalDisplay)
                Text("On the built-in display only").tag(LayoutProfile.Trigger.builtInDisplayOnly)
            }
            .labelsHidden()
            .fixedSize()
            Button(isActive ? "Active" : "Apply") {
                manager.apply(profile)
            }
            .disabled(isActive)
            Menu {
                Button("Update from Current Layout") {
                    manager.updateFromCurrent(profile)
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
        .padding(.vertical, 2)
    }
}
