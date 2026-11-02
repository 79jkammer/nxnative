// NXNative Builder's control maps, without any UI: the player's keys and controller buttons as DM_KEYMAP and DM_PAD_MAP (dm/host/input_map.h has their format and the keys' defaults), and what can be
// moved to the Trash when a build is done.
import Foundation

struct Controls: Codable, Equatable {
    var keys: [String: Int] = [:]     // action -> macOS key code; only what the player moved
    var pad: [String: String] = [:]   // the controller's button -> the Switch button it presses; only what the player moved

    static let keyActions: [(id: String, code: Int?)] = [
        ("A", 38), ("B", 40), ("X", 32), ("Y", 34), ("L", 12), ("R", 14), ("ZL", 6), ("ZR", 8), ("PLUS", 36), ("MINUS", 48), ("UP", 126), ("DOWN", 125), ("LEFT", 123), ("RIGHT", 124), ("LS", 3), ("RS", 5),
        ("LSU", 13), ("LSD", 1), ("LSL", 0), ("LSR", 2), ("RSU", nil), ("RSD", nil), ("RSL", nil), ("RSR", nil), ("SHAKE", 49),
    ]
    static let padButtons = ["A", "B", "X", "Y", "L", "R", "ZL", "ZR", "PLUS", "MINUS", "UP", "DOWN", "LEFT", "RIGHT", "LS", "RS"]

    // The key an action has now. A default key another action took leaves it without one, as the host's key_map_parse does.
    func key(of action: String) -> Int? {
        if let k = keys[action] { return k }
        guard let d = Self.keyActions.first(where: { $0.id == action })?.code else { return nil }
        return keys.values.contains(d) ? nil : d
    }

    mutating func assign(key: Int, to action: String) {
        // The action that had this key loses it: a default of its own would otherwise come back with the moved key's own default
        for other in Self.keyActions where other.id != action {
            if keys[other.id] == key { keys[other.id] = nil }
        }
        keys[action] = key == Self.keyActions.first { $0.id == action }?.code && !keys.values.contains(key) ? nil : key
    }

    func padTarget(of button: String) -> String { pad[button] ?? button }
    mutating func assign(pad button: String, to game: String) { pad[button] = game == button ? nil : game }
    mutating func reset() { keys = [:]; pad = [:] }

    // An env file's lines: empty for what is at its default.
    var envLines: [String] {
        var lines: [String] = []
        if !keys.isEmpty { lines.append("DM_KEYMAP=" + keys.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")) }
        if !pad.isEmpty { lines.append("DM_PAD_MAP=" + pad.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")) }
        return lines
    }

    // An env.txt with these maps in place of any old ones; the player's other lines stay.
    func merged(into text: String) -> String {
        let kept = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.hasPrefix("DM_KEYMAP=") && !$0.hasPrefix("DM_PAD_MAP=") && !$0.isEmpty }
        let all = kept + envLines
        return all.isEmpty ? "" : all.joined(separator: "\n") + "\n"
    }

    static func label(_ id: String) -> String {
        switch id {
        case "PLUS": return "+"
        case "MINUS": return "−"
        case "UP": return L("D-pad up")
        case "DOWN": return L("D-pad down")
        case "LEFT": return L("D-pad left")
        case "RIGHT": return L("D-pad right")
        case "LS": return L("Press the left stick")
        case "RS": return L("Press the right stick")
        case "LSU": return L("Left stick up")
        case "LSD": return L("Left stick down")
        case "LSL": return L("Left stick left")
        case "LSR": return L("Left stick right")
        case "RSU": return L("Right stick up")
        case "RSD": return L("Right stick down")
        case "RSL": return L("Right stick left")
        case "RSR": return L("Right stick right")
        case "SHAKE": return L("Shake")
        default: return id
        }
    }

    static func keyName(_ code: Int?) -> String {
        guard let code else { return L("No key") }
        let names: [Int: String] = [0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        return names[code] ?? "#\(code)"
    }
}

// What a finished build leaves that the game no longer needs. Nothing is ever deleted: it goes to the Trash when the player asks, and they empty it.
struct CleanupItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let urls: [URL]
    var bytes: Int64 = 0
    var selected: Bool
}

enum Cleanup {
    static func size(of url: URL) -> Int64 {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        if let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true { return Int64(v.totalFileAllocatedSize ?? 0) }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: []) else { return 0 }
        for case let u as URL in e {
            if let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true { total += Int64(v.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    // output: the finished IPA or app, never offered and never inside what is offered.
    static func items(target: BuildTarget, buildFolder: URL?, gameFiles: [URL], output: URL?) -> [CleanupItem] {
        var items: [CleanupItem] = []
        let fm = FileManager.default
        if let buildFolder, fm.fileExists(atPath: buildFolder.path), output.map({ !$0.path.hasPrefix(buildFolder.path + "/") }) ?? true {
            if target == .device {
                let derived = buildFolder.appendingPathComponent("xcode-derived-data")
                if fm.fileExists(atPath: derived.path) {
                    items.append(CleanupItem(id: "derived", title: L("Temporary build files"), detail: L("Safe to remove. Reinstall makes them again."), urls: [derived], selected: true))
                }
                items.append(CleanupItem(id: "build", title: L("All build files"), detail: L("The game stays on the iPhone, but Reinstall will not work: after 7 days you would build it again from the game files."), urls: [buildFolder], selected: false))
            } else {
                items.append(CleanupItem(id: "build", title: L("Build files"), detail: L("The finished game does not need them. Building it again takes longer."), urls: [buildFolder], selected: true))
            }
        }
        if !gameFiles.isEmpty {
            items.append(CleanupItem(id: "game", title: L("The game's original files"), detail: L("Keep them if you may build this game again: without them you would need to copy them from your console again."), urls: gameFiles, selected: false))
        }
        return items.map { i in var i = i; i.bytes = i.urls.reduce(0) { $0 + size(of: $1) }; return i }.filter { $0.bytes > 0 }
    }
}

// The app's own copy of the project, for an app that was not built from a checkout: the build script names the exact commit it was made from.
enum Engine {
    static var folder: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/NXNative Builder") }
    static func dir(commit: String) -> URL { folder.appendingPathComponent("engine-\(commit)") }
    static func isComplete(_ dir: URL) -> Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent("scripts/build_ipa_from_nsp.py").path) }

    // Other versions' folders, which an updated app no longer reads
    static func oldVersions(keeping commit: String) -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.lastPathComponent.hasPrefix("engine-") && $0.lastPathComponent != "engine-\(commit)" }
    }
}
