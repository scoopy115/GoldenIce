//
//  AdvancedSettingsPane.swift
//  Ice
//

import SwiftUI

struct AdvancedSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: AdvancedSettings
    @State private var maxSliderLabelWidth: CGFloat = 0

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    private func formattedToSeconds(_ interval: TimeInterval) -> LocalizedStringKey {
        let formatted = interval.formatted()
        return if interval == 1 {
            LocalizedStringKey(formatted + " second")
        } else {
            LocalizedStringKey(formatted + " seconds")
        }
    }

    var body: some View {
        IceForm {
            IceSection("Menu Bar Sections") {
                enableAlwaysHiddenSection
                showAllSectionsOnUserDrag
                // Ice's dividers are collapsed on macOS 27, so they have no style.
                if #unavailable(macOS 27.0) {
                    sectionDividerStyle
                }
            }
            IceSection("Other") {
                // macOS 27 folds the items that do not fit behind its own overflow button,
                // and opens hidden items without moving them, so neither option applies.
                if #unavailable(macOS 27.0) {
                    hideApplicationMenus
                }
                enableSecondaryContextMenu
                showOnHoverDelay
                if #unavailable(macOS 27.0) {
                    tempShowInterval
                }
            }
            if #available(macOS 27.0, *) {
                IceSection("Menu Bar Indicators") {
                    showCaptureIndicator
                }
                IceSection("Arranging") {
                    ReorderWithoutPointerSetting()
                }
            }
            IceSection("Permissions") {
                allPermissions
            }
        }
    }

    @ViewBuilder
    private var showCaptureIndicator: some View {
        Toggle(isOn: $settings.showCaptureIndicator) {
            Text("Show a camera and microphone indicator")
            Text("macOS draws none of its own while Ice is hiding items. Click Ice's to open Control Centre.")
        }
        if settings.showCaptureIndicator {
            Picker(selection: $settings.captureIndicatorPlacement) {
                ForEach(CaptureIndicatorPlacement.allCases) { placement in
                    Text(placement.localized).tag(placement)
                }
            } label: {
                Text("Position")
                Text("It is a real menu bar item: you can also ⌘ Command + drag it.")
            }
        }
    }

    @ViewBuilder
    private var enableAlwaysHiddenSection: some View {
        Toggle(
            "Enable the always-hidden section",
            isOn: $settings.enableAlwaysHiddenSection
        )
    }

    @ViewBuilder
    private var showAllSectionsOnUserDrag: some View {
        Toggle(
            "Show all sections when ⌘ Command + dragging menu bar items",
            isOn: $settings.showAllSectionsOnUserDrag
        )
    }

    @ViewBuilder
    private var sectionDividerStyle: some View {
        IcePicker("Section divider style", selection: $settings.sectionDividerStyle) {
            ForEach(SectionDividerStyle.allCases) { style in
                Text(style.localized).tag(style)
            }
        }
    }

    @ViewBuilder
    private var hideApplicationMenus: some View {
        Toggle(
            "Hide app menus when showing menu bar items",
            isOn: $settings.hideApplicationMenus
        )
        .annotation {
            Text(
                """
                Make more room in the menu bar by hiding the current app menus if \
                needed. macOS requires Ice to make itself visible in the Dock while \
                this setting is in effect.
                """
            )
            .padding(.trailing, 75)
        }
    }

    @ViewBuilder
    private var enableSecondaryContextMenu: some View {
        Toggle(
            "Enable secondary context menu",
            isOn: $settings.enableSecondaryContextMenu
        )
        .annotation {
            Text(
                """
                Right-click in an empty area of the menu bar to display a minimal \
                version of Ice's menu. Disable this setting if you encounter conflicts \
                with other apps.
                """
            )
            .padding(.trailing, 75)
        }
    }

    @ViewBuilder
    private var showOnHoverDelay: some View {
        LabeledContent {
            IceSlider(
                formattedToSeconds(settings.showOnHoverDelay),
                value: $settings.showOnHoverDelay,
                in: 0...1,
                step: 0.1
            )
        } label: {
            Text("Show on hover delay")
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation("The amount of time to wait before showing on hover.")
    }

    @ViewBuilder
    private var tempShowInterval: some View {
        LabeledContent {
            IceSlider(
                formattedToSeconds(settings.tempShowInterval),
                value: $settings.tempShowInterval,
                in: 0...60,
                step: 1
            )
        } label: {
            Text("Temporarily shown item delay")
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation("The amount of time to wait before hiding temporarily shown menu bar items.")
    }

    @ViewBuilder
    private var allPermissions: some View {
        ForEach(appState.permissions.allPermissions) { permission in
            LabeledContent {
                if permission.hasPermission {
                    Label {
                        Text("Permission Granted")
                    } icon: {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                } else {
                    Button("Grant Permission") {
                        permission.performRequest()
                    }
                }
            } label: {
                Text(permission.title)
            }
            .frame(height: 22)
        }
    }
}

/// The switch for reordering through MenuBarAgent's position table, with what it needs.
@available(macOS 27.0, *)
private struct ReorderWithoutPointerSetting: View {
    @State private var isOn = Defaults.object(forKey: .reorderWithoutPointer) as? Bool ?? true
    @State private var hasAccess = PositionTable27.hasAccess

    var body: some View {
        Toggle(isOn: $isOn) {
            Text("Reorder without moving the pointer")
            Text("Ice writes the new order straight into macOS's own menu bar table, so your pointer stays put and hidden items don't flash. When that fails, Ice drags the item instead.")
        }
        .onChange(of: isOn) { _, newValue in
            Defaults.set(newValue, forKey: .reorderWithoutPointer)
        }
        if isOn {
            HStack(spacing: 8) {
                Image(systemName: hasAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(hasAccess ? .green : .orange)
                Text(hasAccess ? "Ice can read the menu bar table." : "Ice needs access to the menu bar table.")
                    .font(.system(size: 12))
                Spacer()
                if !hasAccess {
                    Button("Choose File…") {
                        hasAccess = PositionTable27.requestAccess()
                    }
                    Button("Full Disk Access…") {
                        PositionTable27.openFullDiskAccessSettings()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                hasAccess = PositionTable27.hasAccess
            }
        }
    }
}
