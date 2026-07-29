import AppKit
import Foundation

/// The independently importable categories in a Raycast export, so the user can pick a subset.
struct RaycastImportOptions: OptionSet, Sendable {
    let rawValue: Int
    static let shortcuts = RaycastImportOptions(rawValue: 1 << 0)
    static let favorites = RaycastImportOptions(rawValue: 1 << 1)
    static let emojiSkinTone = RaycastImportOptions(rawValue: 1 << 2)
    static let launchAtLogin = RaycastImportOptions(rawValue: 1 << 3)
    static let menuBarVisibility = RaycastImportOptions(rawValue: 1 << 4)
    static let clipboardHistory = RaycastImportOptions(rawValue: 1 << 5)
    static let popToRoot = RaycastImportOptions(rawValue: 1 << 6)
    static let compactMode = RaycastImportOptions(rawValue: 1 << 7)
    static let all: RaycastImportOptions = [
        .shortcuts, .favorites, .emojiSkinTone, .launchAtLogin, .menuBarVisibility, .clipboardHistory,
        .popToRoot, .compactMode,
    ]
}

/// Decrypts Raycast X and classic macOS `.rayconfig` exports and maps the subset Tinycast supports. Decrypt is CPU-heavy and runs off the main actor.
enum RaycastImport {
    struct Result {
        var backup: SettingsBackup
        var clipboard: [ClipboardItem]
        /// Image clips whose referenced file no longer exists on disk (reported so the UI can note them).
        var missingImages: Int

        /// A copy trimmed to the chosen categories; `apply()` is already per-field non-destructive, so dropping a field is enough to skip it.
        func selecting(_ options: RaycastImportOptions) -> Result {
            var trimmed = SettingsBackup()
            if options.contains(.shortcuts) { trimmed.hotkeys = backup.hotkeys }
            if options.contains(.favorites) { trimmed.favoriteApps = backup.favoriteApps }

            var settings = SettingsBackup.SettingsData()
            var hasSettings = false
            if options.contains(.emojiSkinTone), let tone = backup.settings?.emojiSkinTone {
                settings.emojiSkinTone = tone
                hasSettings = true
            }
            if options.contains(.launchAtLogin), let launch = backup.settings?.launchAtLogin {
                settings.launchAtLogin = launch
                hasSettings = true
            }
            if options.contains(.menuBarVisibility), let show = backup.settings?.showInMenuBar {
                settings.showInMenuBar = show
                hasSettings = true
            }
            if options.contains(.popToRoot), let secs = backup.settings?.popToRootSeconds {
                settings.popToRootSeconds = secs
                hasSettings = true
            }
            if options.contains(.compactMode) {
                if let compact = backup.settings?.compactMode {
                    settings.compactMode = compact
                    hasSettings = true
                }
                if let showFavorites = backup.settings?.showFavoritesInCompactMode {
                    settings.showFavoritesInCompactMode = showFavorites
                    hasSettings = true
                }
            }
            if options.contains(.shortcuts) {
                if let shift = backup.settings?.hyperKeyIncludesShift {
                    settings.hyperKeyIncludesShift = shift
                    hasSettings = true
                }
                if let key = backup.settings?.hyperKey {
                    settings.hyperKey = key
                    hasSettings = true
                }
                if let glyph = backup.settings?.hyperKeyReplacesGlyph {
                    settings.hyperKeyReplacesGlyph = glyph
                    hasSettings = true
                }
            }
            if hasSettings { trimmed.settings = settings }

            let keepClipboard = options.contains(.clipboardHistory)
            return Result(
                backup: trimmed,
                clipboard: keepClipboard ? clipboard : [],
                missingImages: keepClipboard ? missingImages : 0)
        }
    }

    // MARK: - Decrypt

    static func decrypt(file: URL, passphrase: String) throws -> Data {
        try RaycastExportDecoder.decrypt(Data(contentsOf: file), passphrase: passphrase)
    }

    // MARK: - Map

    static func parse(_ decrypted: Data) throws -> Result {
        guard let json = try? JSONSerialization.jsonObject(with: decrypted) as? [String: Any] else {
            throw RaycastImportError.corrupt
        }
        var backup = SettingsBackup()
        backup.settings = mapSettings(json)
        backup.hotkeys = mapHotkeys(json)
        backup.favoriteApps = mapFavorites(json)
        let (clipboard, missing) = mapClipboard(json)
        return Result(backup: backup, clipboard: clipboard, missingImages: missing)
    }

    /// Raycast `general.hyperKeyCode` → Tinycast physical key; unknown or absent values are skipped, and no value ever maps to `.none` (an export without a Hyper key must not disable one the user already configured).
    private static let hyperKeyCodes: [String: HyperKeyPhysicalKey] = [
        "caps_lock": .capsLock,
        "right_control": .rightControl,
        "right_shift": .rightShift,
        "right_option": .rightOption,
        "right_command": .rightCommand,
    ]

    private static func mapSettings(_ json: [String: Any]) -> SettingsBackup.SettingsData? {
        let general = (json["settings"] as? [String: Any])?["general"] as? [String: Any]
        var data = SettingsBackup.SettingsData()
        var mapped = false
        if let openAtLogin = general?["openAtLogin"] as? Bool {
            data.launchAtLogin = openAtLogin
            mapped = true
        }
        if let includeShift = general?["hyperKeyIncludeShift"] as? Bool {
            data.hyperKeyIncludesShift = includeShift
            mapped = true
        }
        // Without the physical Hyper key the imported ⌃⌥⇧⌘ shortcuts exist but can't be triggered from it.
        if let code = general?["hyperKeyCode"] as? String, let key = hyperKeyCodes[code] {
            data.hyperKey = key.rawValue
            mapped = true
        }
        if let display = general?["hyperKeyDisplayShortcut"] as? Bool {
            data.hyperKeyReplacesGlyph = display
            mapped = true
        }
        if let showInMenuBar = general?["showInMenuBar"] as? Bool {
            data.showInMenuBar = showInMenuBar
            mapped = true
        }
        if let tone = mapSkinTone(json) {
            data.emojiSkinTone = tone
            mapped = true
        }
        // Exact-match only: a Raycast timeout outside Tinycast's option set is skipped, not clamped.
        if let secs = general?["popToRootTimeout"] as? Int,
            let timeout = PopToRootTimeout(rawValue: secs)
        {
            data.popToRootSeconds = timeout.rawValue
            mapped = true
        }
        // Raycast's window mode is a string ("compact"/"advanced"/…); Tinycast only has the compact toggle.
        if let mode = general?["windowMode"] as? String {
            data.compactMode = (mode == "compact")
            mapped = true
        }
        if let showFavorites = general?["showFavoritesInCompactMode"] as? Bool {
            data.showFavoritesInCompactMode = showFavorites
            mapped = true
        }

        let classic = json["builtin_package_raycastPreferences"] as? [String: Any]
        let appearance = classic?["preferencesAppearance"] as? [String: Any]
        let advanced = classic?["preferencesAdvanced"] as? [String: Any]
        if let showInMenuBar = appearance?["statusBarIsVisible"] as? Bool {
            data.showInMenuBar = showInMenuBar
            mapped = true
        }
        if let secs = advanced?["popToRootTimeout"] as? Int,
            let timeout = PopToRootTimeout(rawValue: secs)
        {
            data.popToRootSeconds = timeout.rawValue
            mapped = true
        }
        if let mode = appearance?["raycastPreferredWindowMode"] as? String {
            data.compactMode = (mode == "compact")
            mapped = true
        }
        if let showFavorites = appearance?["showFavoritesInCompactMode"] as? Bool {
            data.showFavoritesInCompactMode = showFavorites
            mapped = true
        }
        if let useHyperKeyIcon = advanced?["useHyperKeyIcon"] as? Bool {
            data.hyperKeyReplacesGlyph = useHyperKeyIcon
            mapped = true
        }
        return mapped ? data : nil
    }

    /// Raycast X uses structured shortcuts; classic exports use `Modifier-…-CarbonKeyCode` strings.
    private static func mapHotkeys(_ json: [String: Any]) -> SettingsBackup.HotkeyBackup? {
        let settings = json["settings"] as? [String: Any]
        var hotkeys = SettingsBackup.HotkeyBackup()
        var apps: [String: KeyShortcut] = [:]
        var mapped = false

        if let general = settings?["general"] as? [String: Any],
            let shortcut = keyShortcut(from: general["globalHotkey"])
        {
            hotkeys.togglePalette = shortcut
            mapped = true
        }

        for command in settings?["commands"] as? [[String: Any]] ?? [] {
            guard let shortcut = keyShortcut(from: command["macosHotkey"]) else { continue }
            switch command["extensionId"] as? String {
            case "e:r:clipboard-history":
                hotkeys.toggleClipboard = shortcut
                mapped = true
            case "e:r:emoji-picker":
                hotkeys.toggleEmoji = shortcut
                mapped = true
            case "e:r:applications":
                if let path = appPath(fromCommandID: command["id"] as? String),
                    let bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
                {
                    apps[bundleID] = shortcut
                    mapped = true
                }
            default:
                break
            }
        }

        let classic = json["builtin_package_raycastPreferences"] as? [String: Any]
        let classicGeneral = classic?["preferencesGeneral"] as? [String: Any]
        if let shortcut = classicKeyShortcut(from: classicGeneral?["raycastGlobalHotkey"]) {
            hotkeys.togglePalette = shortcut
            mapped = true
        }
        let rootSearch = json["builtin_package_rootSearch"] as? [String: Any]
        for item in rootSearch?["rootSearch"] as? [[String: Any]] ?? [] {
            guard let shortcut = classicKeyShortcut(from: item["hotkey"]) else { continue }
            switch item["key"] as? String {
            case "builtin_command_clipboardHistory":
                hotkeys.toggleClipboard = shortcut
                mapped = true
            case "builtin_command_searchEmoji":
                hotkeys.toggleEmoji = shortcut
                mapped = true
            default:
                if let path = item["path"] as? String,
                    let bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
                {
                    apps[bundleID] = shortcut
                    mapped = true
                }
            }
        }
        if !apps.isEmpty { hotkeys.apps = apps }
        return mapped ? hotkeys : nil
    }

    /// Build a `KeyShortcut` from a Raycast hotkey object (`{ kind: { shortcut: { modifiers, key } } }`).
    private static func keyShortcut(from hotkey: Any?) -> KeyShortcut? {
        guard let dict = hotkey as? [String: Any],
            let shortcut = (dict["kind"] as? [String: Any])?["shortcut"] as? [String: Any],
            let key = shortcut["key"] as? [String: Any],
            (key["type"] as? String) == "LayoutIndependent",
            let code = key["code"] as? Int
        else { return nil }

        var flags: NSEvent.ModifierFlags = []
        for entry in (shortcut["modifiers"] as? [[String: Any]]) ?? [] {
            switch entry["modifier"] as? String {
            case "Meta": flags.insert(.command)
            case "Ctrl": flags.insert(.control)
            case "Alt": flags.insert(.option)
            case "Shift": flags.insert(.shift)
            default: break
            }
        }
        return KeyShortcut(
            carbonKeyCode: code, carbonModifiers: KeyShortcut.carbonModifiers(from: flags))
    }

    private static func classicKeyShortcut(from hotkey: Any?) -> KeyShortcut? {
        guard let raw = hotkey as? String else { return nil }
        var parts = raw.split(separator: "-").map(String.init)
        guard let keyCode = parts.popLast().flatMap(Int.init) else { return nil }
        var flags: NSEvent.ModifierFlags = []
        for part in parts {
            switch part.lowercased() {
            case "command", "cmd": flags.insert(.command)
            case "control", "ctrl": flags.insert(.control)
            case "option", "alt": flags.insert(.option)
            case "shift": flags.insert(.shift)
            default: return nil
            }
        }
        return KeyShortcut(
            carbonKeyCode: keyCode, carbonModifiers: KeyShortcut.carbonModifiers(from: flags))
    }

    /// Maps Raycast X `favoriteOrder` entries and classic pinned app items, preserving their order.
    private static func mapFavorites(_ json: [String: Any]) -> [String]? {
        let commands = (json["settings"] as? [String: Any])?["commands"] as? [[String: Any]] ?? []
        var favorites =
            commands
            .compactMap { command -> (order: Int, bundleID: String)? in
                guard let order = command["favoriteOrder"] as? Int,
                    command["extensionId"] as? String == "e:r:applications",
                    let path = appPath(fromCommandID: command["id"] as? String),
                    let bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
                else { return nil }
                return (order, bundleID)
            }
            .sorted { $0.order < $1.order }
            .map(\.bundleID)

        let rootSearch = (json["builtin_package_rootSearch"] as? [String: Any])?["rootSearch"]
            as? [[String: Any]] ?? []
        var pathsByKey: [String: String] = [:]
        for item in rootSearch {
            if let key = item["key"] as? String, let path = item["path"] as? String {
                pathsByKey[key] = path
            }
        }
        let pinned = (json["builtin_package_navigation"] as? [String: Any])?["pinnedMenuItems"]
            as? [Any] ?? []
        for item in pinned {
            let path: String?
            if let dict = item as? [String: Any] {
                path = dict["path"] as? String
            } else if let key = item as? String {
                path = key.hasSuffix(".app") ? key : pathsByKey[key]
            } else {
                path = nil
            }
            if let path, let bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier,
                !favorites.contains(bundleID)
            {
                favorites.append(bundleID)
            }
        }
        return favorites.isEmpty ? nil : favorites
    }

    /// The launched app's path is the tail of an applications command id: `c:r:applications::*::application::=::/Applications/Ghostty.app`.
    private static func appPath(fromCommandID id: String?) -> String? {
        guard let id, let range = id.range(of: "::=::") else { return nil }
        let path = String(id[range.upperBound...])
        return path.isEmpty ? nil : path
    }

    /// Raycast stores the tone under an emoji command's preferences; a recursive search avoids hard-coding a brittle path. Enum raw values line up (`light`…`dark`); Raycast's `default` maps to none.
    private static func mapSkinTone(_ json: [String: Any]) -> String? {
        guard let raw = firstValue(forKey: "skinTone", in: json) as? String else { return nil }
        if raw == "default" { return EmojiSkinTone.none.rawValue }
        return EmojiSkinTone(rawValue: raw)?.rawValue
    }

    // MARK: - Clipboard

    private static func mapClipboard(_ json: [String: Any]) -> (items: [ClipboardItem], missing: Int)
    {
        guard
            let entries = (json["clipboardHistory"] as? [String: Any])?["clipboardEntries"]
                as? [[String: Any]]
        else { return ([], 0) }

        let dateParser = ISO8601DateFormatter()
        dateParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var items: [ClipboardItem] = []
        var missing = 0
        for entry in entries {
            let createdAt = parseDate(entry["createdAt"] as? String, using: dateParser) ?? Date()
            let reps = (entry["items"] as? [[String: Any]] ?? [])
                .flatMap { ($0["representations"] as? [[String: Any]]) ?? [] }

            if let text = reps.first(where: {
                ($0["mimeType"] as? String)?.hasPrefix("text/plain") == true
            })?["content"] as? String, !text.isEmpty {
                items.append(
                    ClipboardItem(
                        id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: createdAt,
                        sourceBundleID: nil))
                continue
            }

            if let path = reps.first(where: {
                ($0["mimeType"] as? String)?.hasPrefix("image/") == true
                    && ($0["contentType"] as? String) == "url"
            })?["content"] as? String {
                guard FileManager.default.fileExists(atPath: path) else {
                    missing += 1
                    continue
                }
                items.append(
                    ClipboardItem(imagePath: path, createdAt: createdAt, sourceBundleID: nil))
            }
        }
        return (items, missing)
    }

    // MARK: - Helpers

    private static func parseDate(_ string: String?, using parser: ISO8601DateFormatter) -> Date? {
        guard let string else { return nil }
        // Fractional-seconds parser first; fall back to a whole-second timestamp.
        return parser.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    /// First value stored under `key` anywhere in a nested JSON object/array tree.
    private static func firstValue(forKey key: String, in object: Any) -> Any? {
        if let dict = object as? [String: Any] {
            if let hit = dict[key] { return hit }
            for value in dict.values {
                if let hit = firstValue(forKey: key, in: value) { return hit }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let hit = firstValue(forKey: key, in: value) { return hit }
            }
        }
        return nil
    }
}
