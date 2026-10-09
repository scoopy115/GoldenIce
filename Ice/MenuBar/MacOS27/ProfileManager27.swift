//
//  ProfileManager27.swift
//  Ice
//

import Cocoa
import Combine
import OSLog
import UniformTypeIdentifiers

/// A named arrangement of the menu bar: which section each application is in, and which
/// applications are shown while they are in front.
struct LayoutProfile: Codable, Identifiable, Equatable {
    /// When a profile switches in by itself.
    enum Trigger: String, Codable, CaseIterable {
        /// Only when the user picks it.
        case manual
        /// When a display other than the built-in one is connected.
        case externalDisplay
        /// When the built-in display is the only one.
        case builtInDisplayOnly
    }

    var id = UUID()
    var name: String
    var layout: [String: Int]
    var showWhenFrontmost: [String]
    var trigger: Trigger = .manual

    var sections: [String: MacOS27Section] {
        layout.compactMapValues(MacOS27Section.init(rawValue:))
    }
}

/// A backup of everything that makes up the arrangement, written to a file.
struct LayoutBackup: Codable {
    static let currentVersion = 1

    var version = currentVersion
    var createdAt = Date()
    var layout: [String: Int]
    var showWhenFrontmost: [String]
    var profiles: [LayoutProfile]
}

/// Keeps the user's layout profiles, switches between them, and writes and reads backups.
@available(macOS 27.0, *)
@MainActor
final class ProfileManager27: ObservableObject {
    private let logger = Logger(category: "ProfileManager27")
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @Published private(set) var profiles = [LayoutProfile]()
    @Published private(set) var activeProfileID: UUID?

    func performSetup(with appState: AppState) {
        self.appState = appState
        if
            let data = Defaults.data(forKey: .layoutProfiles),
            let profiles = try? decoder.decode([LayoutProfile].self, from: data)
        {
            self.profiles = profiles
        }
        if let id = Defaults.string(forKey: .activeLayoutProfile) {
            activeProfileID = UUID(uuidString: id)
        }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            // Displays arrive one after another; act once they have settled.
            .debounce(for: 1.5, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.applyDisplayTrigger()
                }
            }
            .store(in: &cancellables)
        applyDisplayTrigger()
    }

    // MARK: Profiles

    /// Saves the current arrangement as a new profile.
    @discardableResult
    func saveCurrent(named name: String) -> LayoutProfile? {
        guard let concealer = appState?.concealer27 else {
            return nil
        }
        let profile = LayoutProfile(
            name: name,
            layout: concealer.layoutSnapshot.mapValues(\.rawValue),
            showWhenFrontmost: concealer.showWhenFrontmost.sorted()
        )
        profiles.append(profile)
        activeProfileID = profile.id
        persist()
        logger.notice("Saved profile \(name, privacy: .public)")
        return profile
    }

    /// Overwrites a profile with the current arrangement.
    func updateFromCurrent(_ profile: LayoutProfile) {
        guard let concealer = appState?.concealer27, let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }
        profiles[index].layout = concealer.layoutSnapshot.mapValues(\.rawValue)
        profiles[index].showWhenFrontmost = concealer.showWhenFrontmost.sorted()
        persist()
    }

    /// Keeps the active profile in step with the layout and the rules, as they are edited.
    ///
    /// A profile is edited by switching to it and arranging the menu bar as usual, so every
    /// change made while it is active belongs to it.
    func activeLayoutDidChange() {
        guard let activeProfileID, let profile = profiles.first(where: { $0.id == activeProfileID }) else {
            return
        }
        updateFromCurrent(profile)
    }

    /// The active profile, if one is.
    var activeProfile: LayoutProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    /// Switches to a profile.
    func apply(_ profile: LayoutProfile) {
        guard let concealer = appState?.concealer27 else {
            return
        }
        logger.notice("Applying profile \(profile.name, privacy: .public)")
        concealer.applySnapshot(layout: profile.sections, showWhenFrontmost: Set(profile.showWhenFrontmost))
        activeProfileID = profile.id
        persist()
    }

    func rename(_ profile: LayoutProfile, to name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }
        profiles[index].name = name
        persist()
    }

    func setTrigger(_ trigger: LayoutProfile.Trigger, for profile: LayoutProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }
        profiles[index].trigger = trigger
        persist()
        applyDisplayTrigger()
    }

    func delete(_ profile: LayoutProfile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfileID == profile.id {
            activeProfileID = nil
        }
        persist()
    }

    /// Switches to the profile whose display trigger matches the displays connected now.
    private func applyDisplayTrigger() {
        let hasExternal = NSScreen.screens.contains { CGDisplayIsBuiltin($0.displayID) == 0 }
        let wanted: LayoutProfile.Trigger = hasExternal ? .externalDisplay : .builtInDisplayOnly
        guard
            let profile = profiles.first(where: { $0.trigger == wanted }),
            profile.id != activeProfileID
        else {
            return
        }
        logger.notice("Displays changed; switching to \(profile.name, privacy: .public)")
        apply(profile)
    }

    private func persist() {
        if let data = try? encoder.encode(profiles) {
            Defaults.set(data, forKey: .layoutProfiles)
        }
        Defaults.set(activeProfileID?.uuidString, forKey: .activeLayoutProfile)
    }

    // MARK: Backups

    /// Asks where to save a backup and writes it there.
    func exportBackup() {
        guard let concealer = appState?.concealer27 else {
            return
        }
        let backup = LayoutBackup(
            layout: concealer.layoutSnapshot.mapValues(\.rawValue),
            showWhenFrontmost: concealer.showWhenFrontmost.sorted(),
            profiles: profiles
        )
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let date = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "GoldenIce Layout \(date).json"
        panel.message = "Save a backup of your menu bar layout, rules and profiles."
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            try encoder.encode(backup).write(to: url, options: .atomic)
            logger.notice("Exported a backup")
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Asks for a backup file and restores it.
    func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a GoldenIce layout backup to restore."
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            let backup = try decoder.decode(LayoutBackup.self, from: Data(contentsOf: url))
            guard backup.version <= LayoutBackup.currentVersion else {
                throw CocoaError(.fileReadCorruptFile)
            }
            profiles = backup.profiles
            activeProfileID = nil
            persist()
            appState?.concealer27.applySnapshot(
                layout: backup.layout.compactMapValues(MacOS27Section.init(rawValue:)),
                showWhenFrontmost: Set(backup.showWhenFrontmost)
            )
            logger.notice("Restored a backup")
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
