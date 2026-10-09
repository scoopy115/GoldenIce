//
//  ProfileManager27.swift
//  Ice
//

import Cocoa
import Combine
import OSLog
import UniformTypeIdentifiers

/// A named arrangement of the menu bar: which section each application is in.
///
/// The "show while in front" rules are not part of a profile; they apply whichever is active.
/// `showWhenFrontmost` is kept only so profiles saved by earlier builds still read.
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

    /// The symbols a profile's icon can be chosen from.
    static let symbols = [
        "square.stack.3d.up", "briefcase", "house", "display.2", "laptopcomputer",
        "person.2", "video", "music.note", "gamecontroller", "cup.and.saucer",
        "moon", "airplane", "graduationcap", "paintbrush", "hammer", "sparkles",
    ]

    var id = UUID()
    var name: String
    var symbol = LayoutProfile.symbols[0]
    var layout: [String: Int]
    var showWhenFrontmost: [String]
    var trigger: Trigger = .manual
    var hotkey: KeyCombination?

    var sections: [String: MacOS27Section] {
        layout.compactMapValues(MacOS27Section.init(rawValue:))
    }

    init(name: String, layout: [String: Int], showWhenFrontmost: [String]) {
        self.name = name
        self.layout = layout
        self.showWhenFrontmost = showWhenFrontmost
    }

    // Profiles saved before a field existed are read with its default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? LayoutProfile.symbols[0]
        layout = try container.decode([String: Int].self, forKey: .layout)
        showWhenFrontmost = try container.decodeIfPresent([String].self, forKey: .showWhenFrontmost) ?? []
        trigger = try container.decodeIfPresent(Trigger.self, forKey: .trigger) ?? .manual
        hotkey = try container.decodeIfPresent(KeyCombination.self, forKey: .hotkey)
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

    @Published private(set) var profiles = [LayoutProfile]() {
        didSet {
            if profiles.map(\.id) != oldValue.map(\.id) || profiles.map(\.hotkey) != oldValue.map(\.hotkey) {
                rebuildHotkeys()
            }
        }
    }
    @Published private(set) var activeProfileID: UUID?

    /// One hotkey per profile, which switches to it.
    @Published private(set) var hotkeys = [UUID: Hotkey]()
    private var hotkeyCancellables = Set<AnyCancellable>()

    /// What was in force before a profile was opened for editing, to go back to afterwards.
    private var stateBeforeEditing: (profileID: UUID?, layout: [String: MacOS27Section], rules: Set<String>)?

    func performSetup(with appState: AppState) {
        self.appState = appState
        if
            let data = Defaults.data(forKey: .layoutProfiles),
            let profiles = try? decoder.decode([LayoutProfile].self, from: data)
        {
            // One profile per trigger: the first keeps it, any later one switches by hand.
            var seen = Set<LayoutProfile.Trigger>()
            self.profiles = profiles.map { profile in
                var profile = profile
                if profile.trigger != .manual, !seen.insert(profile.trigger).inserted {
                    profile.trigger = .manual
                }
                return profile
            }
        }
        if let id = Defaults.string(forKey: .activeLayoutProfile) {
            activeProfileID = UUID(uuidString: id)
        }
        rebuildHotkeys()
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
            showWhenFrontmost: []
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

    /// Stops using profiles: the layout stays as it is, and changes are no longer saved to one.
    func deactivate() {
        activeProfileID = nil
        persist()
    }

    /// Switches to the profile after the active one, or to the first.
    func applyNext() {
        guard !profiles.isEmpty else {
            return
        }
        let index = profiles.firstIndex { $0.id == activeProfileID }.map { ($0 + 1) % profiles.count } ?? 0
        apply(profiles[index])
    }

    func setSymbol(_ symbol: String, for profile: LayoutProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }
        profiles[index].symbol = symbol
        persist()
    }

    // MARK: Editing

    /// Applies a profile so its layout can be edited, remembering what was in force before.
    func beginEditing(_ profile: LayoutProfile) {
        guard let concealer = appState?.concealer27 else {
            return
        }
        if stateBeforeEditing == nil {
            stateBeforeEditing = (activeProfileID, concealer.layoutSnapshot, concealer.showWhenFrontmost)
        }
        apply(profile)
    }

    /// Puts back what was in force before editing began. The edited profile keeps its changes,
    /// which were saved to it while it was active.
    func endEditing() {
        guard let previous = stateBeforeEditing, let concealer = appState?.concealer27 else {
            return
        }
        stateBeforeEditing = nil
        if let id = previous.profileID, let profile = profiles.first(where: { $0.id == id }) {
            apply(profile)
        } else {
            activeProfileID = nil
            persist()
            concealer.applyLayout(previous.layout)
        }
    }

    // MARK: Hotkeys

    private func rebuildHotkeys() {
        for hotkey in hotkeys.values {
            hotkey.disable()
        }
        hotkeyCancellables.removeAll()
        var built = [UUID: Hotkey]()
        for profile in profiles {
            let id = profile.id
            let hotkey = Hotkey(action: .nextProfile, keyCombination: profile.hotkey) { [weak self] in
                guard let self, let profile = profiles.first(where: { $0.id == id }) else {
                    return
                }
                apply(profile)
            }
            if let appState {
                hotkey.performSetup(with: appState)
            }
            hotkey.$keyCombination
                .dropFirst()
                .sink { [weak self] keyCombination in
                    guard let self, let index = profiles.firstIndex(where: { $0.id == id }) else {
                        return
                    }
                    profiles[index].hotkey = keyCombination
                    persist()
                }
                .store(in: &hotkeyCancellables)
            built[id] = hotkey
        }
        hotkeys = built
    }

    /// Switches to a profile.
    func apply(_ profile: LayoutProfile) {
        guard let concealer = appState?.concealer27 else {
            return
        }
        logger.notice("Applying profile \(profile.name, privacy: .public)")
        concealer.applyLayout(profile.sections)
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

    /// Sets when a profile switches in by itself. Only one profile can switch in for each
    /// situation, or the bar would not know which to pick, so another profile that had the
    /// same trigger goes back to switching by hand.
    func setTrigger(_ trigger: LayoutProfile.Trigger, for profile: LayoutProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }
        if trigger != .manual {
            for other in profiles.indices where other != index && profiles[other].trigger == trigger {
                profiles[other].trigger = .manual
            }
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
