//
//  RulesSettingsPane.swift
//  Ice
//

import SwiftUI

/// Rules that show hidden items when something happens, rather than only on request.
struct RulesSettingsPane: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if #available(macOS 27.0, *) {
            RulesSettingsPane27(concealer: appState.concealer27)
        } else {
            IceForm {
                IceSection {
                    Text("Rules are available on macOS 27 and later.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                }
            }
        }
    }
}

@available(macOS 27.0, *)
private struct RulesSettingsPane27: View {
    @ObservedObject var concealer: Concealer27

    static func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    var body: some View {
        IceForm {
            IceSection {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Show while in front")
                        .font(.headline)
                    Text("A hidden app's items appear on the menu bar while you are using the app, and hide again when you switch away.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            let applications = concealer.hiddenApplications.sorted { lhs, rhs in
                Self.displayName(for: lhs.bundleID).localizedStandardCompare(Self.displayName(for: rhs.bundleID)) == .orderedAscending
            }
            if applications.isEmpty {
                IceSection {
                    VStack(spacing: 6) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                        Text("No hidden apps yet")
                            .font(.headline)
                        Text("Drag an item into Hidden in Menu Bar Layout, and it shows up here.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                }
            } else {
                IceSection("Hidden Apps") {
                    ForEach(applications, id: \.bundleID) { application in
                        ApplicationRuleRow(
                            bundleID: application.bundleID,
                            section: application.section,
                            isOn: Binding(
                                get: { concealer.showWhenFrontmost.contains(application.bundleID) },
                                set: { concealer.setShowWhenFrontmost($0, for: application.bundleID) }
                            )
                        )
                    }
                }
            }
        }
    }
}

/// One application with its rule switch.
@available(macOS 27.0, *)
private struct ApplicationRuleRow: View {
    let bundleID: String
    let section: MacOS27Section
    @Binding var isOn: Bool

    private var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private var name: String {
        if let applicationURL {
            return FileManager.default.displayName(atPath: applicationURL.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    private var sectionName: LocalizedStringKey {
        switch section {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always-Hidden"
        }
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Group {
                    if let applicationURL {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path))
                            .resizable()
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                    }
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                    Text(sectionName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
