// NXNative Builder's logic, without any UI: the NSP script's arguments and its JSON events (docs/frontends.md, Building: the NSP script), what a game folder holds, the check of a keys file.
// dm/builder/tests/builder_check.swift compiles this file alone and checks it. Game files and keys stay where the player keeps them: the app passes their paths to the script, copies nothing,
// and of a keys file reads only the key names, never showing a value.
import Foundation

enum BuildTarget: String, CaseIterable, Identifiable {
    case ios, device, macApp = "mac-app"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ios: return L("IPA file")
        case .device: return L("iPhone")
        case .macApp: return L("Mac")
        }
    }
    var platform: String { self == .macApp ? rawValue : "ios" }   // the script's --platform
}

func shellQuote(_ s: String) -> String {
    if !s.isEmpty, s.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "-_./=:@%+,".unicodeScalars.contains($0) }) { return s }
    return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

// MARK: - The script's arguments

struct BuildOptions {
    var gameFolder: URL?
    var keys: URL?
    var needsKeys = true   // false for a dump folder
    var target = BuildTarget.ios
    var titleID = ""       // only when the folder holds several games
    var package = ""       // v<N>; empty = the newest
    var language = ""
    var appName = ""
    var bundleID = ""
    var output = ""
    var workDir = ""
    var romfsSeparate = false
    var gpu = ""
    var macSign = ""
    var showFPS = true
    var motion = true
    var keepExtracted = true
    var allowDamaged = false
    var allowShaderRegressions = false
    var allowOtherMetal = false
    var provisional = false
    var teamID = ""        // .device: the Apple team that signs it
    var xcodeWorkspace = ""
    var envFile = ""       // the player's controls, baked into the app

    // What comes after the script's path. An option at the script's default is left out, so the script's own default holds and the command stays short.
    func arguments() -> [String] {
        var a: [String] = []
        if let gameFolder { a.append(gameFolder.path) }
        if needsKeys, let keys { a += ["-k", keys.path] }
        a += ["--platform", target.platform, "--progress", "json"]
        func text(_ flag: String, _ value: String) {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { a += [flag, v] }
        }
        text("--title-id", titleID)
        text("-p", package)
        text("-l", language)
        text("--app-name", appName)
        text("--bundle-id", bundleID)
        if target != .device { text("-o", output) }
        text("--work-dir", workDir)
        text("--gpu", gpu)
        text("--env-file", envFile)
        switch target {
        case .ios:
            if romfsSeparate { a += ["--romfs", "separate"] }
            if !showFPS { a.append("--no-show-fps") }
        case .device:   // an Xcode project, whose game files go to the phone once and stay there while the app is reinstalled (docs/development.md, Quick reinstalls)
            a += ["--prepare-xcode", "--romfs", "separate"]
            text("--team-id", teamID)
            text("--xcode-workspace", xcodeWorkspace)
            if !showFPS { a.append("--no-show-fps") }
        case .macApp:
            text("--mac-sign", macSign)
        }
        if !motion { a.append("--no-motion") }
        if !keepExtracted, target != .device { a.append("--no-keep-extracted") }
        if allowDamaged { a.append("--allow-damaged") }
        if allowShaderRegressions { a.append("--allow-shader-regressions") }
        if allowOtherMetal { a.append("--allow-other-metal") }
        if provisional { a.append("--provisional") }
        return a
    }
}

// MARK: - The script's events

struct LiveProgress: Equatable {
    var done = 0.0, total = 0.0
    var unit = "", note = ""
    var estimated = false
    var fraction: Double?   // nil when the work cannot be counted
    var eta: Double?
    var elapsed = 0.0
}

enum BuildEvent: Equatable {
    case stage(k: Int, n: Int, name: String, step: String)
    case step(k: Int, name: String, step: String)
    case progress(k: Int, name: String, step: String, LiveProgress)
    case stageEnd(k: Int, name: String, ok: Bool, summary: String, elapsed: Double)
    case shadersStale(reason: String, count: Int)
    case say(String)

    // One line of the script's stdout. A line that is no JSON object is kept as a message; an event this app does not know is dropped, as a newer script may add some.
    static func parse(_ line: String) -> BuildEvent? {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        guard let d = s.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let ev = o["ev"] as? String else { return .say(s) }
        func str(_ k: String) -> String { o[k] as? String ?? "" }
        func num(_ k: String) -> Double? { (o[k] as? NSNumber)?.doubleValue }
        func int(_ k: String) -> Int { Int(num(k) ?? 0) }
        switch ev {
        case "stage": return .stage(k: int("k"), n: int("n"), name: str("name"), step: str("step"))
        case "step": return .step(k: int("k"), name: str("name"), step: str("step"))
        case "progress":
            return .progress(k: int("k"), name: str("name"), step: str("step"), LiveProgress(
                done: num("done") ?? 0, total: num("total") ?? 0, unit: str("unit"), note: str("note"), estimated: (o["est"] as? Bool) ?? false,
                fraction: num("frac"), eta: num("eta"), elapsed: num("elapsed") ?? 0))
        case "stage_end": return .stageEnd(k: int("k"), name: str("name"), ok: (o["ok"] as? Bool) ?? false, summary: str("summary"), elapsed: num("elapsed") ?? 0)
        case "shaders_stale": return .shadersStale(reason: str("reason"), count: int("count"))
        case "say": return .say(str("msg"))
        default: return nil
        }
    }
}

struct StageRow: Identifiable, Equatable {
    enum State { case running, done, failed }
    let k: Int
    var name: String
    var step: String
    var state = State.running
    var summary = ""
    var elapsed = 0.0
    var fromScript = true   // false for the install's own stages, which are in words already
    var id: Int { k }
}

struct LogLine: Identifiable, Equatable {
    let id: Int
    let text: String
    let isError: Bool
}

// A build as its events tell it.
struct BuildTranscript {
    static let maxLines = 4000
    private(set) var stages: [StageRow] = []
    private(set) var stageCount = 0
    private(set) var live: LiveProgress?
    private(set) var lines: [LogLine] = []
    private(set) var output: String?      // the finished IPA or app, from the script's "done:" message
    private(set) var lastError: String?
    private(set) var project: String?     // --prepare-xcode: "game project: <path>"
    private(set) var bundleID: String?    // "bundle ID: <id>"
    private var nextLine = 0

    var current: StageRow? { stages.last { $0.state == .running } ?? stages.last }

    mutating func apply(_ e: BuildEvent) {
        switch e {
        case let .stage(k, n, name, step):
            stageCount = max(stageCount, n)
            live = nil
            upsert(k, name, step)
        case let .step(k, name, step):
            live = nil
            upsert(k, name, step)
        case let .progress(k, name, step, p):
            live = p
            upsert(k, name, step)
        case let .stageEnd(k, name, ok, summary, elapsed):
            upsert(k, name, nil)
            if let i = stages.firstIndex(where: { $0.k == k }) {
                stages[i].state = ok ? .done : .failed
                stages[i].summary = summary
                stages[i].elapsed = elapsed
            }
            live = nil
        case let .shadersStale(reason, count):
            add(reason == "chain" ? L("Shaders must be rebuilt (the translation chain changed): %@ libraries", "\(count)") : L("Shaders must be rebuilt (the game profile's shader inputs changed): %@ libraries", "\(count)"), false)
        case let .say(msg):
            if msg.hasPrefix("[RED] ") {
                let text = String(msg.dropFirst(6))
                lastError = text
                add(text, true)
            } else {
                add(msg, false)
                if let path = Self.donePath(msg) { output = path }
                if let r = msg.range(of: "game project: ") { project = String(msg[r.upperBound...]) }
                if let r = msg.range(of: "bundle ID: ") { bundleID = String(msg[r.upperBound...].prefix { $0 != ";" && !$0.isWhitespace }) }
            }
        }
    }

    mutating func addStderr(_ text: String) { add(text, true) }

    // A stage of the install, not of the script
    mutating func beginOwnStage(k: Int, n: Int, name: String, step: String) {
        apply(.stage(k: k, n: n, name: name, step: step))
        if let i = stages.firstIndex(where: { $0.k == k }) { stages[i].fromScript = false }
    }

    private mutating func upsert(_ k: Int, _ name: String, _ step: String?) {
        if let i = stages.firstIndex(where: { $0.k == k }) {
            if !name.isEmpty { stages[i].name = name }
            if let step { stages[i].step = step }
        } else {
            stages.append(StageRow(k: k, name: name, step: step ?? ""))
            stages.sort { $0.k < $1.k }
        }
    }

    private mutating func add(_ text: String, _ isError: Bool) {
        lines.append(LogLine(id: nextLine, text: text, isError: isError))
        nextLine += 1
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
    }

    // "[12:00:00] done: /path/Game.ipa (4.2 GB)", the same for a Mac app with more after the size
    static func donePath(_ msg: String) -> String? {
        guard let r = msg.range(of: #"done: (/.+?) \(\d+(\.\d+)? GB\)"#, options: .regularExpression) else { return nil }
        let m = msg[r].dropFirst("done: ".count)
        guard let size = m.range(of: " (", options: .backwards) else { return nil }
        return String(m[..<size.lowerBound])
    }
}

// MARK: - What a game folder holds

struct GamePackage: Identifiable, Equatable {
    enum Kind: String { case base = "Game", update = "Update", dlc = "DLC", unknown = "Package" }
    let name: String
    let size: Int64
    let titleID: UInt64?
    let version: Int?
    let holdsSeveral: Bool   // base game, update and DLC in one file
    var id: String { name }
    var kind: Kind {
        guard let titleID else { return .unknown }
        switch titleID & 0xFFF {
        case 0: return .base
        case 0x800: return .update
        default: return .dlc
        }
    }
    var baseTitle: UInt64? {
        guard let titleID else { return nil }
        return kind == .dlc ? (titleID & ~0xFFF) - 0x1000 : titleID & ~0xFFF
    }
}

struct GameFolder: Equatable {
    let url: URL
    let isDump: Bool
    let packages: [GamePackage]
    let titles: [UInt64]     // the base games found, one in the usual folder
    let versions: [Int]      // the versions that can be packed, oldest first
    let bytes: Int64
    let hasBuildFolder: Bool

    // One game of a folder that holds several (nil: the whole folder). A package the app cannot identify may belong to any of them.
    func packages(of title: UInt64?) -> [GamePackage] {
        guard let title else { return packages }
        return packages.filter { $0.baseTitle == nil || $0.baseTitle == title }
    }

    func versions(of title: UInt64?) -> [Int] {
        guard !isDump, title != nil else { return versions }
        return GameScan.versions(packages(of: title))
    }

    func bytes(of title: UInt64?) -> Int64 {
        guard !isDump, title != nil else { return bytes }
        return packages(of: title).reduce(0) { $0 + $1.size }
    }

    // The game's name as its files give it: "Game [0100…][v0].nsp" → "Game"
    func fileName(of title: UInt64?) -> String? {
        let own = packages(of: title)
        guard let p = own.first(where: { $0.kind == .base }) ?? own.first else { return nil }
        let name = (p.name as NSString).deletingPathExtension
        let cut = name.prefix { $0 != "[" }.trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? name : cut
    }
}

enum GameScanError: LocalizedError {
    case empty(String)
    var errorDescription: String? {
        switch self { case let .empty(m): return m }
    }
}

enum GameScan {
    static let extensions = ["nsp", "nsz", "xci", "xcz"]

    static func isPackage(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }
    static func hex(_ title: UInt64) -> String { String(format: "%016llX", title) }

    static func scan(_ folder: URL) throws -> GameFolder {
        let fm = FileManager.default
        let npdm = folder.appendingPathComponent("base/exefs/main.npdm")
        if fm.fileExists(atPath: npdm.path) { return dump(folder, npdm) }
        let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        let packages = items.filter(isPackage).map(package).sorted { ($0.kind.rawValue, $0.version ?? 0, $0.name) < ($1.kind.rawValue, $1.version ?? 0, $1.name) }
        if packages.isEmpty {
            throw GameScanError.empty(L("%@ holds no game: no .nsp, .nsz, .xci or .xcz file, and no base/exefs/main.npdm of a dump.", folder.lastPathComponent))
        }
        let titles = Array(Set(packages.compactMap(\.baseTitle))).sorted()
        return GameFolder(url: folder, isDump: false, packages: packages, titles: titles, versions: versions(packages),
                          bytes: packages.reduce(0) { $0 + $1.size }, hasBuildFolder: hasBuild(folder, titles))
    }

    static func versions(_ packages: [GamePackage]) -> [Int] {
        var found = Set(packages.filter { $0.kind == .update }.compactMap(\.version))
        if let base = packages.first(where: { $0.kind == .base }) { found.insert(base.version ?? 0) }
        return found.sorted()
    }

    private static func hasBuild(_ folder: URL, _ titles: [UInt64]) -> Bool {
        titles.contains { FileManager.default.fileExists(atPath: folder.appendingPathComponent(hex($0) + "_build").path) }
    }

    private static func package(_ url: URL) -> GamePackage {
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        let name = url.lastPathComponent
        let names = pfs0Names(url)
        // As the script's title_of: the ticket first, as a file name's tag can be wrong; a package with neither is identified by the script, with the keys
        var title: UInt64?
        for n in names where n.count == 36 && n.lowercased().hasSuffix(".tik") {
            if let v = UInt64(n.prefix(16), radix: 16) { title = v; break }
        }
        if title == nil, let v = tag(name, #"\[([0-9A-Fa-f]{16})\]"#) { title = UInt64(v, radix: 16) }
        let version = tag(name, #"\[v(\d+)\]"#).flatMap { Int($0) }
        return GamePackage(name: name, size: size, titleID: title, version: version, holdsSeveral: names.filter { $0.lowercased().hasSuffix(".cnmt.nca") }.count > 1)
    }

    private static func tag(_ name: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let r = Range(m.range(at: 1), in: name) else { return nil }
        return String(name[r])
    }

    // An NSP or NSZ is a PFS0: the file names inside are in its header. Empty for anything else (an XCI: its tag in the file name, or the script).
    static func pfs0Names(_ url: URL) -> [String] {
        guard let f = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? f.close() }
        guard let h = try? f.read(upToCount: 16), h.count == 16, h.prefix(4).elementsEqual("PFS0".utf8) else { return [] }
        let n = Int(u32(h, 4)), st = Int(u32(h, 8))
        guard n > 0, n < 100_000, st > 0, st < 16 << 20, let body = try? f.read(upToCount: n * 0x18 + st), body.count == n * 0x18 + st else { return [] }
        let strs = body.dropFirst(n * 0x18)
        return (0..<n).compactMap { i in
            let o = Int(u32(body, i * 0x18 + 0x10))
            guard o < st else { return nil }
            let start = strs.startIndex + o
            let end = strs[start...].firstIndex(of: 0) ?? strs.endIndex
            return String(decoding: strs[start..<end], as: UTF8.self)
        }
    }

    private static func u32(_ d: Data, _ at: Int) -> UInt32 {
        let i = d.startIndex + at
        return UInt32(d[i]) | UInt32(d[i + 1]) << 8 | UInt32(d[i + 2]) << 16 | UInt32(d[i + 3]) << 24
    }

    private static func dump(_ folder: URL, _ npdm: URL) -> GameFolder {
        let fm = FileManager.default
        let versions = ((try? fm.contentsOfDirectory(atPath: folder.appendingPathComponent("updates").path)) ?? []).compactMap { Int($0) }.sorted()
        let titles = programID(npdm).map { [$0] } ?? []
        var bytes: Int64 = 0
        if let e = fm.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let u as URL in e {
                if u.lastPathComponent.hasSuffix("_build") { e.skipDescendants(); continue }
                bytes += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
        }
        return GameFolder(url: folder, isDump: true, packages: [], titles: titles, versions: versions, bytes: bytes, hasBuildFolder: hasBuild(folder, titles))
    }

    // The ACI0 program ID of main.npdm, as pack_dump.py reads it
    static func programID(_ npdm: URL) -> UInt64? {
        guard let d = try? Data(contentsOf: npdm), d.count >= 0x78, d.prefix(4).elementsEqual("META".utf8) else { return nil }
        let off = Int(u32(d, 0x70)), size = Int(u32(d, 0x74))
        guard size >= 0x18, off + 0x18 <= d.count, d[off..<(off + 4)].elementsEqual("ACI0".utf8) else { return nil }
        return UInt64(u32(d, off + 0x10)) | UInt64(u32(d, off + 0x14)) << 32
    }

    // The first build needs about twice the game's size plus 10 GB (README.md). An existing build folder already holds most of it.
    static func spaceNeeded(_ game: GameFolder, title: UInt64? = nil) -> Int64 {
        let built = title.map { FileManager.default.fileExists(atPath: game.url.appendingPathComponent(hex($0) + "_build").path) } ?? game.hasBuildFolder
        return built ? 0 : game.bytes(of: title) * 2 + 10 << 30
    }
}

// dm/games/<title ID>/game.tsv: the game's name and the builds it was brought up on
struct GameProfile: Equatable {
    let name: String
    let displayVersions: [Int: String]

    static func load(repo: URL, title: UInt64) -> GameProfile? {
        let tsv = repo.appendingPathComponent("dm/games/\(GameScan.hex(title))/game.tsv")
        guard let text = try? String(contentsOf: tsv, encoding: .utf8) else { return nil }
        var name = "", versions: [Int: String] = [:]
        for line in text.split(separator: "\n") {
            let c = line.split(separator: "\t")
            if c.count >= 2, c[0] == "name" { name = String(c[1]) }
            if c.count >= 3, c[0] == "build", c[1].hasPrefix("v"), let v = Int(c[1].dropFirst()) { versions[v] = String(c[2]) }
        }
        return GameProfile(name: name, displayVersions: versions)
    }
}

// MARK: - A keys file

enum KeysCheck {
    // Whether the file looks like prod.keys: lines of name = hex, with the header key every package needs. Only names are looked at, and nothing read here leaves this function.
    static func problem(_ url: URL) -> String? {
        guard let d = try? Data(contentsOf: url, options: .mappedIfSafe) else { return L("The file cannot be read.") }
        if d.count > 1 << 20 { return L("This file is too big to be a keys file.") }
        guard let text = String(data: d, encoding: .utf8) else { return L("This is not a text keys file.") }
        let names = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            guard let eq = line.firstIndex(of: "=") else { return nil }
            return line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
        }
        return names.contains("header_key") ? nil : L("No header_key in this file: it is not a complete prod.keys.")
    }
}

// MARK: - Formatting

func formatBytes(_ n: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file) }

func formatDuration(_ s: Double) -> String {
    let t = Int(s.rounded())
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
}

func formatCount(_ p: LiveProgress) -> String {
    let e = p.estimated ? "~" : ""
    var s = ""
    if p.total > 0 {
        s = p.unit == "B" ? L("%@ of %@", formatBytes(p.done), e + formatBytes(p.total))
            : L("%@ of %@", Int(p.done).formatted(), e + Int(p.total).formatted()) + (p.unit.isEmpty ? "" : " \(p.unit)")
    } else if p.done > 0 {
        s = p.unit == "B" ? formatBytes(p.done) : Int(p.done).formatted() + (p.unit.isEmpty ? "" : " \(p.unit)")
    }
    if !p.note.isEmpty { s += s.isEmpty ? p.note : " · \(p.note)" }
    return s
}
