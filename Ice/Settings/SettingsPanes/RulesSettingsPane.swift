//
//  RulesSettingsPane.swift
//  Ice
//

import SwiftUI

/// Rules that bring hidden items forward when something happens, rather than only on request.
struct RulesSettingsPane: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if #available(macOS 27.0, *) {
            RulesSettingsPane27(concealer: appState.concealer27, itemManager: appState.itemManager)
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
    @ObservedObject var itemManager: MenuBarItemManager

    /// Applications whose items macOS will not draw.
    private var blocked: Set<String> {
        Set(concealer.disabledItems.compactMap(Self.bundleID))
    }

    /// Every application with an item on the menu bar, or with a rule.
    private var applications: [String] {
        let fromBar = (itemManager.itemCache.managedItems + concealer.disabledItems).compactMap(Self.bundleID)
        return Array(Set(fromBar).union(concealer.showWhenFrontmost))
            .sorted { Self.name(for: $0).localizedStandardCompare(Self.name(for: $1)) == .orderedAscending }
    }

    var body: some View {
        let blocked = blocked
        let applications = applications
        let inFront = applications.filter { concealer.showWhenFrontmost.contains($0) }
        let others = applications.filter { !concealer.showWhenFrontmost.contains($0) && !blocked.contains($0) }
        let blockedOthers = applications.filter { !concealer.showWhenFrontmost.contains($0) && blocked.contains($0) }

        IceForm {
            IceSection {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Show while in front")
                        .font(.headline)
                    Text("Apps in this list appear on the menu bar while you are using them, and go back to how your layout has them when you switch away. An app your layout already shows stays visible either way. Rules apply to every profile.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            IceSection("Show While in Front") {
                if inFront.isEmpty {
                    Text("No apps yet. Add them from the list below.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ForEach(inFront, id: \.self) { bundleID in
                        ApplicationRow(bundleID: bundleID, isBlocked: blocked.contains(bundleID)) {
                            Button {
                                concealer.setShowWhenFrontmost(false, for: bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(.system(size: 16))
                            }
                            .buttonStyle(.plain)
                            .help("Remove from this list")
                        }
                    }
                }
            }

            if !others.isEmpty {
                IceSection("Other Apps") {
                    ForEach(others, id: \.self) { bundleID in
                        ApplicationRow(bundleID: bundleID, isBlocked: false) {
                            Button {
                                concealer.setShowWhenFrontmost(true, for: bundleID)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 16))
                            }
                            .buttonStyle(.plain)
                            .help("Show while in front")
                        }
                    }
                }
            }

            if !blockedOthers.isEmpty {
                IceSection("Blocked by System Settings") {
                    Text("macOS never shows these apps' items, so a rule can't bring them forward. Turn them on under Allow in the Menu Bar first.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                    ForEach(blockedOthers, id: \.self) { bundleID in
                        ApplicationRow(bundleID: bundleID, isBlocked: false) {
                            EmptyView()
                        }
                        .opacity(0.6)
                    }
                    HStack {
                        Spacer()
                        Button("Open Menu Bar Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
    }

    static func bundleID(of item: MenuBarItem) -> String? {
        guard !item.isControlItem, case .string(let bundleID) = item.tag.namespace else {
            return nil
        }
        // MenuBarAgent hosts the system items, which no rule can hide or show.
        return bundleID == "com.apple.MenuBarAgent" ? nil : bundleID
    }

    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// An application with an action button at the end.
@available(macOS 27.0, *)
private struct ApplicationRow<Action: View>: View {
    let bundleID: String
    let isBlocked: Bool
    @ViewBuilder var action: Action

    private var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let applicationURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path))
                        .resizable()
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(RulesSettingsPane27.name(for: bundleID))
                if isBlocked {
                    Label("Blocked by System Settings — macOS won't show it", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            action
        }
        .padding(.vertical, 2)
    }
}
