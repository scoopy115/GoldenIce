//
//  PositionTable27.swift
//  Ice
//

import Cocoa
import OSLog

/// Reads and writes MenuBarAgent's table of item positions on macOS 27.
///
/// The table lives in MenuBarAgent's group container, which needs Full Disk Access — or the
/// user picking the file once in an open panel, which Ice keeps a bookmark to. Writing a weight
/// there moves an item without the Command-drag that otherwise takes over the pointer, and it
/// works while the item is concealed. MenuBarAgent rewrites the table all the time, so it is
/// read again right before every write, and only Ice's own change is made to what was read.
@available(macOS 27.0, *)
enum PositionTable27 {
    private static let logger = Logger(category: "PositionTable27")

    /// The table's key in MenuBarAgent's preferences.
    static let key = "TrailingItemPreferredPositions"

    /// The preferences file.
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist")

    /// The folder the file is in, for the open panel.
    static var directoryURL: URL {
        fileURL.deletingLastPathComponent()
    }

    // MARK: Access

    /// Whether Ice can read the table right now.
    static var hasAccess: Bool {
        withAccess { (try? Data(contentsOf: fileURL)) != nil } ?? false
    }

    /// Asks the user to pick the table file, and keeps a bookmark to it.
    @MainActor
    static func requestAccess() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Allow GoldenIce to Arrange the Menu Bar"
        panel.message = "Choose “com.apple.MenuBar.plist” to let GoldenIce reorder items without moving the pointer."
        panel.prompt = "Allow"
        panel.directoryURL = directoryURL
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            Defaults.set(bookmark, forKey: .positionTableBookmark)
        } catch {
            logger.error("Could not keep a bookmark to the position table: \(error, privacy: .public)")
        }
        return hasAccess
    }

    /// Opens Full Disk Access in System Settings, the other way to grant access.
    @MainActor
    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Runs the body with the bookmarked file's security scope, if there is a bookmark.
    private static func withAccess<T>(_ body: () -> T) -> T? {
        guard let bookmark = Defaults.data(forKey: .positionTableBookmark) else {
            return body()
        }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return body()
        }
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return body()
    }

    // MARK: Reading and Writing

    /// The table as it stands, or `nil` if it cannot be read.
    static func read() -> [String: Int]? {
        withAccess {
            guard
                let data = try? Data(contentsOf: fileURL),
                let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                let table = plist[key] as? [String: Any]
            else {
                return nil
            }
            return table.compactMapValues { ($0 as? NSNumber)?.intValue }
        } ?? nil
    }

    /// Sets one entry in a fresh read of the table, and writes it back.
    @discardableResult
    static func write(weight: Int, forKey entryKey: String) -> Bool {
        withAccess {
            guard
                let data = try? Data(contentsOf: fileURL),
                var plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                var table = plist[key] as? [String: Any],
                !table.isEmpty
            else {
                // An empty read may be a failed one; writing it back would wipe the order.
                logger.warning("Not writing the position table: it could not be read")
                return false
            }
            table[entryKey] = weight
            plist[key] = table
            // Through preferences first, so cfprefsd and MenuBarAgent see the change.
            let domain = fileURL.deletingPathExtension().path as CFString
            CFPreferencesSetValue(key as CFString, table as CFDictionary, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            if CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) {
                return true
            }
            logger.notice("Preferences did not take the position table; writing the file directly")
            guard let output = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) else {
                return false
            }
            return (try? output.write(to: fileURL, options: .atomic)) != nil
        } ?? false
    }

    // MARK: Keys

    /// The table's key for an item, among those already in the table.
    ///
    /// Keys read `status:<owner>::<identifier>`, where the owner is the application's bundle
    /// identifier or its name, and the identifier the status item's autosave name. Only keys
    /// MenuBarAgent wrote itself are used: a key it never wrote would move nothing.
    static func entryKey(for item: MenuBarItem, in table: [String: Int]) -> String? {
        let application = item.sourceApplication
        var owners = [String]()
        if case .string(let bundleID) = item.tag.namespace {
            owners.append(bundleID)
        }
        if let name = application?.localizedName {
            owners.append(name)
        }
        if let executable = application?.executableURL?.lastPathComponent {
            owners.append(executable)
        }
        if item.isControlItem {
            owners.append(ProcessInfo.processInfo.processName)
        }
        for owner in owners {
            let candidate = "status:\(owner)::\(item.tag.title)"
            if table[candidate] != nil {
                return candidate
            }
        }
        // The item's title is read through Accessibility and is not always the autosave name.
        // An application with a single entry in the table can only mean that one.
        for owner in owners {
            let entries = table.keys.filter { $0.hasPrefix("status:\(owner)::") }
            if entries.count == 1 {
                return entries[0]
            }
        }
        return nil
    }
}
