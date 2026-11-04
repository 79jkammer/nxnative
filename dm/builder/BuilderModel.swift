// Slotless's state and the run of the NSP script: one build at a time, its events applied to a BuildTranscript on the main thread. The script is started the way docs/frontends.md describes:
// --progress json, the exit status (0 done, 1 stopped on an error, 2 invalid arguments, 130 interrupted) and stderr read as well as the events.
import AppKit
import Foundation
import SwiftUI

final class BuildRunner {
    private let process = Process()
    private var buffer = Data()
    private var errors = Data()
    private var graceful: DispatchWorkItem?
    private var forced: DispatchWorkItem?

    // onLine and onExit are called on the main thread. pathFirst: a folder to find tools in before any other.
    func start(tool: String, arguments: [String], cwd: URL, pathFirst: String? = nil, onLine: @escaping (String) -> Void, onExit: @escaping (Int32, String) -> Void) throws {
        var env = Host.environment
        env["PYTHONUNBUFFERED"] = "1"
        if let pathFirst { env["PATH"] = pathFirst + ":" + (env["PATH"] ?? "") }
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.environment = env
        process.currentDirectoryURL = cwd
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            DispatchQueue.main.async {
                guard let self else { return }
                self.buffer.append(d)
                while let nl = self.buffer.firstIndex(of: 10) {
                    onLine(String(decoding: self.buffer[self.buffer.startIndex..<nl], as: UTF8.self))
                    self.buffer.removeSubrange(self.buffer.startIndex...nl)
                }
            }
            if d.isEmpty { h.readabilityHandler = nil }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            DispatchQueue.main.async { self?.errors.append(d) }
            if d.isEmpty { h.readabilityHandler = nil }
        }
        process.terminationHandler = { [weak self] p in
            // What the pipes still hold comes first; a tool left running keeps them open, so the wait is short and bounded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let self else { return }
                self.graceful?.cancel()
                self.forced?.cancel()
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                if !self.buffer.isEmpty { onLine(String(decoding: self.buffer, as: UTF8.self)); self.buffer.removeAll() }
                onExit(p.terminationStatus, String(decoding: self.errors, as: UTF8.self))
            }
        }
        try process.run()
    }

    // As Ctrl-C in a terminal: SIGINT to the script's process group (a Process leads its own), so the tools it started stop too; it exits with 130. Then SIGTERM, then SIGKILL, for a tool that does not stop.
    func cancel() {
        guard process.isRunning, graceful == nil else { return }
        let group = -process.processIdentifier
        kill(group, SIGINT)
        let graceful = DispatchWorkItem { kill(group, SIGTERM) }, forced = DispatchWorkItem { kill(group, SIGKILL) }
        self.graceful = graceful
        self.forced = forced
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: graceful)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: forced)
    }
}

@MainActor
final class BuilderModel: ObservableObject {
    enum Phase: Equatable { case setup, building, finished, failed(String), cancelled }

    @Published var repo: URL?
    @Published var options = BuildOptions()
    @Published var game: GameFolder?
    @Published var gameError: String?
    @Published var scanning = false
    @Published var keysProblem: String?
    @Published var env: EnvReport?
    @Published var checkingEnv = false
    @Published var phase = Phase.setup
    @Published var transcript = BuildTranscript()
    @Published var startedAt = Date()
    @Published var cancelling = false
    @Published var notice: String?
    @Published var buildAnyway = false
    @Published var deviceID = ""
    @Published var installed: DeviceInstallRecord?     // the install that just finished
    @Published var language = AppLanguage.system
    @Published var advancedMode = false                // off: only what anyone can answer, in words; no commands, messages or build options
    @Published var installingStep: String?             // what Install Everything is doing now
    @Published var downloadingEngine = false
    @Published var engineFailed = false
    @Published var controls = Controls()
    @Published var showControls = false
    @Published var capturingAction: String?            // the keyboard action waiting for a key
    @Published var cleanup: [CleanupItem] = []
    @Published var cleanupDone = false
    // The window's own state, here because @State needs a macro plugin that the Command Line Tools do not have, and this app builds without Xcode
    @Published var dropping = false
    @Published var showAdvanced = false
    @Published var showInstalled = false
    @Published var showLog = false

    private var runner: BuildRunner?
    private var activity: NSObjectProtocol?
    private var lastEnvCheck = Date.distantPast
    private var envGeneration = 0
    private var scanGeneration = 0
    private var exitWaiters: [() -> Void] = []
    private let defaults = UserDefaults.standard

    private enum Key { static let repo = "repoRoot", game = "gameFolder", keys = "keysFile", target = "target", python = "pythonPath", venv = "venvPath", installs = "deviceInstalls", title = "titleID", language = "language", advanced = "advancedMode", controls = "controls" }

    init() {
        language = defaults.string(forKey: Key.language).flatMap(AppLanguage.init(rawValue:)) ?? .system
        Lang.selected = language
        advancedMode = defaults.bool(forKey: Key.advanced)
        if let d = defaults.data(forKey: Key.controls), let c = try? JSONDecoder().decode(Controls.self, from: d) { controls = c }
        repo = Self.findRepo(defaults.string(forKey: Key.repo))
        options.target = defaults.string(forKey: Key.target).flatMap(BuildTarget.init(rawValue:)) ?? .device
        if !advancedMode, options.target == .ios { options.target = .device }
        if let k = defaults.string(forKey: Key.keys), FileManager.default.fileExists(atPath: k) { setKeys(URL(fileURLWithPath: k)) }
        if let g = defaults.string(forKey: Key.game), FileManager.default.fileExists(atPath: g) { setGame(URL(fileURLWithPath: g), title: defaults.string(forKey: Key.title)) }
        checkEnvironment(force: true)
        if repo == nil, engineSource != nil { downloadEngine() }
    }

    // The repository this app was built from (Info.plist NXRepoRoot, written by scripts/build_builder_app.py), unless another was chosen
    private static func findRepo(_ saved: String?) -> URL? {
        let fm = FileManager.default
        for p in [saved, Bundle.main.object(forInfoDictionaryKey: "NXRepoRoot") as? String] {
            guard let p, !p.isEmpty, fm.fileExists(atPath: p + "/scripts/build_ipa_from_nsp.py") else { continue }
            return URL(fileURLWithPath: p)
        }
        if let commit = Bundle.main.object(forInfoDictionaryKey: "NXEngineCommit") as? String, Engine.isComplete(Engine.dir(commit: commit)) { return Engine.dir(commit: commit) }
        return nil
    }

    // MARK: The app's own copy of the project

    // Where a released app gets the project: the commit it was built from, as an archive on GitHub (scripts/build_builder_app.py --release)
    var engineSource: (url: String, commit: String)? {
        let info = Bundle.main.infoDictionary
        guard let url = defaults.string(forKey: "engineURL") ?? info?["NXEngineURL"] as? String, let commit = defaults.string(forKey: "engineCommit") ?? info?["NXEngineCommit"] as? String else { return nil }
        return (url, commit)
    }

    func downloadEngine() {
        guard let source = engineSource, !downloadingEngine else { return }
        downloadingEngine = true
        engineFailed = false
        Task {
            let fm = FileManager.default
            let dir = Engine.dir(commit: source.commit), partial = dir.appendingPathExtension("partial"), archive = dir.appendingPathExtension("tar.gz"), log = Engine.folder.appendingPathComponent("download.log")
            try? fm.createDirectory(at: Engine.folder, withIntermediateDirectories: true)
            try? fm.removeItem(at: partial)
            try? fm.createDirectory(at: partial, withIntermediateDirectories: true)
            let got = await runTool("/usr/bin/curl", ["-fL", "--retry", "3", "-sS", "-o", archive.path, source.url], cwd: Engine.folder, log: log)
            let unpacked = got.code == 0 ? await runTool("/usr/bin/tar", ["-xzf", archive.path, "-C", partial.path, "--strip-components=1"], cwd: Engine.folder, log: log) : got
            try? fm.removeItem(at: archive)
            var placed = false
            if unpacked.code == 0, Engine.isComplete(partial) {
                try? fm.removeItem(at: dir)
                placed = (try? fm.moveItem(at: partial, to: dir)) != nil
            }
            if placed {
                for old in Engine.oldVersions(keeping: source.commit) { try? fm.removeItem(at: old) }
                repo = dir
                downloadingEngine = false
                checkEnvironment(force: true)
            } else {
                try? fm.removeItem(at: partial)
                downloadingEngine = false
                engineFailed = true
            }
        }
    }

    var script: URL? { repo?.appendingPathComponent("scripts/build_ipa_from_nsp.py") }
    var targets: [BuildTarget] { advancedMode ? [.device, .macApp, .ios] : [.device, .macApp] }
    var isInstallingTools: Bool { installingStep != nil }
    func stageName(_ name: String) -> String { advancedMode ? name : friendlyStage(name) }

    func setLanguage(_ l: AppLanguage) {
        language = l
        Lang.selected = l
        defaults.set(l.rawValue, forKey: Key.language)
        if let keys = options.keys { keysProblem = KeysCheck.problem(keys) }
        checkEnvironment(force: true)   // its report is in words of the language it ran in
    }

    func setAdvancedMode(_ on: Bool) {
        advancedMode = on
        defaults.set(on, forKey: Key.advanced)
        if !on, options.target == .ios { setTarget(.device) }
    }
    var isBuilding: Bool { phase == .building }
    var profile: GameProfile? {
        guard let repo, let t = selectedTitle else { return nil }
        return GameProfile.load(repo: repo, title: t)
    }
    var selectedTitle: UInt64? {
        if let v = UInt64(options.titleID, radix: 16) { return v }
        return game?.titles.count == 1 ? game?.titles.first : nil
    }
    var needsGameChoice: Bool { (game?.titles.count ?? 0) > 1 && options.titleID.isEmpty }
    var gameName: String {
        if let n = profile?.name, !n.isEmpty { return n }
        if needsGameChoice { return L("Which game?") }
        return game?.fileName(of: selectedTitle) ?? game?.url.lastPathComponent ?? ""
    }
    func name(of title: UInt64) -> String {
        if let repo, let n = GameProfile.load(repo: repo, title: title)?.name, !n.isEmpty { return n }
        return game?.fileName(of: title) ?? GameScan.hex(title)
    }
    func chooseTitle(_ hex: String) {
        options.titleID = hex
        options.package = ""
        defaults.set(hex, forKey: Key.title)
        checkEnvironment()
    }
    var freeBytes: Int64? {
        let path = options.workDir.isEmpty ? game?.url : URL(fileURLWithPath: options.workDir).deletingLastPathComponent()
        return (try? path?.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity.map(Int64.init)
    }
    var spaceProblem: String? {
        guard let game, let free = freeBytes else { return nil }
        let need = GameScan.spaceNeeded(game, title: selectedTitle)
        return need > free ? L("The first build needs about %@ free on this disk; it has %@.", formatBytes(Double(need)), formatBytes(Double(free))) : nil
    }
    // What stops Build, in the order the player would fix it; the environment's own problems are shown with their fixes
    var blocker: String? {
        if isInstallingTools { return L("Installing…") }
        if downloadingEngine { return L("Downloading the app's components…") }
        if repo == nil { return engineSource != nil ? L("The app's components are not downloaded.") : L("Choose the nxnative folder.") }
        guard let game else { return L("Add your game.") }
        if needsGameChoice { return L("This folder holds several games: choose one under Game, on the left.") }
        if !game.isDump {
            if options.keys == nil { return L("Add your prod.keys.") }
            if keysProblem != nil { return L("Choose a working prod.keys.") }
        }
        if options.target == .device {
            if selectedDevice == nil { return checkingEnv ? L("Checking this Mac…") : L("Connect your iPhone.") }
            if team == nil { return env?.items.contains { $0.id == "apple-team" } == true ? L("Create your signing certificate in Xcode.") : L("Add your Apple ID in Xcode.") }
        }
        if env?.python == nil { return checkingEnv ? L("Checking this Mac…") : L("Install Python first.") }
        if env?.problems.isEmpty == false, !buildAnyway { return L("Install what this Mac is missing.") }
        return nil
    }

    var buildsFolder: URL? {
        if !options.workDir.isEmpty { return URL(fileURLWithPath: options.workDir) }
        guard let game, let t = selectedTitle else { return nil }
        return game.url.appendingPathComponent(GameScan.hex(t) + "_build")
    }

    var commandLine: String {
        guard let script else { return "" }
        return ([env?.python ?? "python3", script.path] + resolvedOptions.arguments()).map(shellQuote).joined(separator: " ")
    }

    // MARK: The install over a cable

    var selectedDevice: ConnectedDevice? { env?.devices.first { $0.id == deviceID } ?? env?.devices.first }
    var team: String? {
        let typed = options.teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? env?.teams.first?.id : typed
    }
    private var titleKey: String? { selectedTitle.map(GameScan.hex) }

    var installRecord: DeviceInstallRecord? {
        guard let titleKey else { return nil }
        return installs()[titleKey]
    }

    private func installs() -> [String: DeviceInstallRecord] {
        guard let d = defaults.data(forKey: Key.installs) else { return [:] }
        return (try? JSONDecoder().decode([String: DeviceInstallRecord].self, from: d)) ?? [:]
    }

    private func save(_ record: DeviceInstallRecord) {
        guard let titleKey else { return }
        var all = installs()
        all[titleKey] = record
        if let d = try? JSONEncoder().encode(all) { defaults.set(d, forKey: Key.installs) }
    }

    // What the script is given: for a device, the player's team, a bundle ID of their own, and the workspace inside the game's folder rather than beside it
    private var resolvedOptions: BuildOptions {
        var o = options
        if o.target != .macApp, !controls.envLines.isEmpty, o.envFile.isEmpty, let f = bakedControlsFile() { o.envFile = f }   // a Mac app reads the player's env.txt instead (saveControls)
        guard o.target == .device else { return o }
        o.teamID = team ?? ""
        if o.bundleID.isEmpty {
            if let saved = installRecord?.bundleID { o.bundleID = saved }
            else if let t = team, let title = selectedTitle { o.bundleID = XcodeInstall.bundleID(team: t, title: title) }
        }
        if let g = game?.url { o.xcodeWorkspace = g.appendingPathComponent("NxNative.xcworkspace").path }
        return o
    }

    // Runs one tool to its end, its output in a log file and its last lines kept for the reason it failed.
    private func runTool(_ tool: String, _ args: [String], cwd: URL, log: URL, pathFirst: String? = nil, onLine: ((String) -> Void)? = nil) async -> (code: Int32, tail: [String]) {
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let file = try? FileHandle(forWritingTo: log)
        defer { try? file?.close() }
        var tail: [String] = []
        let r = BuildRunner()
        runner = r
        let code: Int32 = await withCheckedContinuation { c in
            do {
                try r.start(tool: tool, arguments: args, cwd: cwd, pathFirst: pathFirst, onLine: { line in
                    try? file?.write(contentsOf: Data((line + "\n").utf8))
                    tail.append(line)
                    if tail.count > 400 { tail.removeFirst(100) }
                    onLine?(line)
                }, onExit: { code, err in
                    tail += err.split(separator: "\n").map(String.init)
                    try? file?.write(contentsOf: Data(err.utf8))
                    c.resume(returning: code)
                })
            } catch {
                tail.append(L("%@ did not start: %@", tool, error.localizedDescription))
                c.resume(returning: 1)
            }
        }
        return (code, tail)
    }

    // After the script prepared the project, or on its own for a reinstall: sign and build for this device, install, and copy the game files when the phone does not have these yet.
    // Nothing here runs unless the player pressed a button, and none of it touches a device other than the one chosen.
    private func installOnDevice(project: URL, bundleID: String, build: Bool, forceCopy: Bool, previous: DeviceInstallRecord?) async {
        guard let repo, let device = selectedDevice, let team else {
            return fail(L("The iPhone or the Apple team is gone: connect it and try again."))
        }
        let title = selectedTitle
        let root = project.deletingLastPathComponent().deletingLastPathComponent()   // <title ID>_build/xcode/DmIOS.xcodeproj
        let logs = root.appendingPathComponent("logs")
        let first = (transcript.stages.map(\.k).max() ?? 0) + 1
        let count = first + (build ? 1 : -1) + 1
        var record = previous ?? DeviceInstallRecord(project: project.path, scheme: "", bundleID: bundleID, deviceName: device.name, expires: nil, limitedMemory: false, imageStamp: nil)
        record.project = project.path
        record.bundleID = bundleID
        record.deviceName = device.name
        let started = Date()

        if build {
            transcript.beginOwnStage(k: first, n: count, name: L("Sign and build for %@", device.name), step: L("starting"))
            let list = await Host.detached(Host.tool("xcodebuild"), ["-list", "-json", "-project", project.path], cwd: repo)
            guard let scheme = list.flatMap({ XcodeInstall.scheme(listJSON: Data($0.out.utf8), title: title) }) else {
                return stageFailed(first, L("The prepared Xcode project lists no scheme: build the game again."))
            }
            record.scheme = scheme
            func args() -> [String] {
                XcodeInstall.arguments(project: project.path, scheme: scheme, device: device.id, team: team, derivedData: root.appendingPathComponent("xcode-derived-data").path, limitedMemory: record.limitedMemory)
            }
            var lines = 0
            let watch: (String) -> Void = { [weak self] line in
                lines += 1
                guard lines % 25 == 0 else { return }
                self?.transcript.apply(.progress(k: first, name: "", step: String(line.prefix(60)), LiveProgress(fraction: nil)))
            }
            var r = await runTool(Host.tool("xcodebuild"), args() + ["build"], cwd: repo, log: logs.appendingPathComponent("device_build.log"), onLine: watch)
            if r.code != 0, !cancelling, !record.limitedMemory, InstallFailure.classify(r.tail) == .memoryCapability {
                transcript.apply(.say(L("This Apple ID cannot give the app Increased Memory Limit: building without it. Bigger games may be closed by iOS.")))
                record.limitedMemory = true
                r = await runTool(Host.tool("xcodebuild"), args() + ["build"], cwd: repo, log: logs.appendingPathComponent("device_build.log"), onLine: watch)
            }
            if cancelling { return finished(130, "") }
            if r.code != 0 {
                return stageFailed(first, InstallFailure.classify(r.tail).message)
            }
            transcript.apply(.stageEnd(k: first, name: "", ok: true, summary: record.limitedMemory ? L("without Increased Memory Limit") : "", elapsed: Date().timeIntervalSince(started)))

            let installStart = Date()
            transcript.beginOwnStage(k: first + 1, n: count, name: L("Install on %@", device.name), step: L("sending the app"))
            let settings = await Host.detached(Host.tool("xcodebuild"), args() + ["-showBuildSettings", "-json"], cwd: repo)
            guard let app = settings.flatMap({ XcodeInstall.appPath(settingsJSON: Data($0.out.utf8)) }) else {
                return stageFailed(first + 1, L("Xcode does not say where it built the app."))
            }
            let i = await runTool(Host.tool("xcrun"), ["devicectl", "device", "install", "app", "--device", device.id, app], cwd: repo, log: logs.appendingPathComponent("device_install.log"))
            if cancelling { return finished(130, "") }
            if i.code != 0 { return stageFailed(first + 1, InstallFailure.classify(i.tail).message) }
            let profile = await Host.detached(Host.tool("security"), ["cms", "-D", "-i", app + "/embedded.mobileprovision"], cwd: repo)
            record.expires = profile.flatMap { XcodeInstall.expiry(profilePlist: Data($0.out.utf8)) }
            transcript.apply(.stageEnd(k: first + 1, name: "", ok: true, summary: "", elapsed: Date().timeIntervalSince(installStart)))
            save(record)   // the app is on the phone now, so a failed copy below can be repeated without building again
        }

        // The game files: once per game version, as they stay on the phone through reinstalls
        let copyStage = first + (build ? 2 : 0)
        let copyStart = Date()
        let resources = project.deletingLastPathComponent().appendingPathComponent("Gen/resources.env")
        let image = await Host.detached("/bin/bash", ["-c", "source \"$1\"; printf %s \"$DM_RESOURCE_ROMFS\"", "_", resources.path], cwd: repo)
        let stamp = image.flatMap { r -> String? in
            let a = try? FileManager.default.attributesOfItem(atPath: r.out)
            guard let size = a?[.size] as? NSNumber, let date = a?[.modificationDate] as? Date else { return nil }
            return "\(size)-\(date.timeIntervalSince1970)"
        }
        if !forceCopy, let stamp, stamp == record.imageStamp {
            transcript.beginOwnStage(k: copyStage, n: copyStage, name: L("Game files"), step: "")
            transcript.apply(.stageEnd(k: copyStage, name: "", ok: true, summary: L("already on the phone"), elapsed: 0))
        } else {
            transcript.beginOwnStage(k: copyStage, n: copyStage, name: L("Copy game files to %@", device.name), step: L("this can take minutes; keep the iPhone unlocked"))
            let c = await runTool("/bin/bash", [repo.appendingPathComponent("scripts/push_romfs.sh").path, device.id, record.bundleID, resources.path], cwd: repo,
                                  log: logs.appendingPathComponent("device_copy.log"), pathFirst: env?.python.map { ($0 as NSString).deletingLastPathComponent })
            if cancelling { return finished(130, "") }
            if c.code != 0 { return stageFailed(copyStage, InstallFailure.classify(c.tail).message) }
            transcript.apply(.stageEnd(k: copyStage, name: "", ok: true, summary: "", elapsed: Date().timeIntervalSince(copyStart)))
            record.imageStamp = stamp
        }
        save(record)
        installed = record
        finished(0, "")
    }

    private func stageFailed(_ k: Int, _ why: String) {
        transcript.apply(.stageEnd(k: k, name: "", ok: false, summary: "", elapsed: 0))
        fail(why)
    }

    private func fail(_ why: String) {
        transcript.apply(.say("[RED] " + why))
        finished(1, "")
    }

    // Signs again and installs (a free team's signature lasts 7 days); the saves and the game files stay on the phone.
    func reinstall() { startInstallOnly(build: true, forceCopy: false) }

    // For an app that was deleted and installed again, which took its game files with it.
    func copyGameFilesAgain() { startInstallOnly(build: false, forceCopy: true) }

    private func startInstallOnly(build: Bool, forceCopy: Bool) {
        guard let record = installRecord else { return }
        guard FileManager.default.fileExists(atPath: record.project) else { return notice = L("The prepared project is gone: press Build to make it again.") }
        beginRun()
        Task { await installOnDevice(project: URL(fileURLWithPath: record.project), bundleID: record.bundleID, build: build, forceCopy: forceCopy, previous: record) }
    }

    private func beginRun() {
        transcript = BuildTranscript()
        installed = nil
        cleanup = []
        cleanupDone = false
        cancelling = false
        startedAt = Date()
        phase = .building
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Building a game")
    }

    // MARK: Controls

    private func bakedControlsFile() -> String? {
        let url = Engine.folder.appendingPathComponent("controls.env")
        try? FileManager.default.createDirectory(at: Engine.folder, withIntermediateDirectories: true)
        return (try? controls.envLines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)) != nil ? url.path : nil
    }

    // Kept for every game; in a Mac app's own env.txt at once (docs/frontends.md, Starting a game), so no build is needed. An iPhone app gets them when it is built.
    func saveControls() {
        if let d = try? JSONEncoder().encode(controls) { defaults.set(d, forKey: Key.controls) }
        guard let titleKey else { return }
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/nxnative/\(titleKey)"), file = dir.appendingPathComponent("env.txt")
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let merged = controls.merged(into: text)
        if merged == text { return }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? merged.write(to: file, atomically: true, encoding: .utf8)
    }

    func assignKey(_ code: Int) {
        guard let action = capturingAction else { return }
        controls.assign(key: code, to: action)
        capturingAction = nil
        saveControls()
    }

    func resetControls() {
        controls.reset()
        capturingAction = nil
        saveControls()
    }

    // MARK: Cleaning up

    private func findCleanup() {
        cleanupDone = false
        let target = options.target, folder = buildsFolder, output = outputURL
        var gameFiles = game.map { g in g.isDump ? [URL]() : g.packages(of: selectedTitle).map { g.url.appendingPathComponent($0.name) } } ?? []
        gameFiles = gameFiles.filter { FileManager.default.fileExists(atPath: $0.path) }
        Task.detached(priority: .utility) {
            let items = Cleanup.items(target: target, buildFolder: folder, gameFiles: gameFiles, output: output)
            await MainActor.run { self.cleanup = items }
        }
    }

    // Moved to the Trash, not deleted: the player can still bring them back
    func moveCleanupToTrash() {
        var failed: String?
        for item in cleanup where item.selected {
            for url in item.urls {
                do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { failed = error.localizedDescription }
            }
        }
        if let failed { notice = L("Some files could not be moved to the Trash: %@", failed) }
        cleanupDone = cleanup.contains { $0.selected }
        cleanup = cleanup.filter { !$0.selected }
        if let g = game?.url, cleanupDone { setGame(g, title: options.titleID) }
    }

    // MARK: Files

    func accept(_ urls: [URL]) -> Bool {
        var used = false
        var folders = Set<URL>()
        var file: URL?
        for u in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue { folders.insert(u); used = true }
            else if GameScan.isPackage(u) { folders.insert(u.deletingLastPathComponent()); file = u; used = true }
            else if u.pathExtension.lowercased() == "keys" || u.lastPathComponent.lowercased().contains("keys") { setKeys(u); used = true }
        }
        if folders.count > 1 { notice = L("Put one game's files in one folder, then add that folder: the update and DLC are found beside the game.") }
        else if let f = folders.first { setGame(f, file: file) }
        if !used { notice = L("Add a game folder, a .nsp, .nsz, .xci or .xcz file, or prod.keys.") }
        return used
    }

    // file: the package the player chose, which says which game they mean when its folder holds several. title: the game chosen before.
    func setGame(_ folder: URL, file: URL? = nil, title: String? = nil) {
        scanGeneration += 1
        let generation = scanGeneration
        scanning = true
        gameError = nil
        Task.detached(priority: .userInitiated) {
            let result = Result { try GameScan.scan(folder) }
            await MainActor.run {
                guard generation == self.scanGeneration else { return }
                self.scanning = false
                switch result {
                case let .success(g):
                    self.game = g
                    self.options.gameFolder = folder
                    self.options.needsKeys = !g.isDump
                    let chosen = g.packages.first { $0.name == file?.lastPathComponent }?.baseTitle.map(GameScan.hex) ?? title ?? ""
                    self.options.titleID = g.titles.count > 1 && g.titles.contains(where: { GameScan.hex($0) == chosen }) ? chosen : ""
                    self.defaults.set(self.options.titleID, forKey: Key.title)
                    self.options.package = ""
                    self.defaults.set(folder.path, forKey: Key.game)
                    self.findKeysBeside(folder)
                    self.checkEnvironment(force: true)
                case let .failure(e):
                    self.gameError = e.localizedDescription
                }
            }
        }
    }

    func clearGame() {
        game = nil
        gameError = nil
        options.gameFolder = nil
        defaults.removeObject(forKey: Key.game)
    }

    func setKeys(_ url: URL) {
        options.keys = url
        keysProblem = KeysCheck.problem(url)
        if keysProblem == nil { defaults.set(url.path, forKey: Key.keys) }
    }

    private func findKeysBeside(_ folder: URL) {
        guard options.keys == nil else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for u in [folder.appendingPathComponent("prod.keys"), folder.deletingLastPathComponent().appendingPathComponent("prod.keys"), home.appendingPathComponent(".switch/prod.keys")]
        where FileManager.default.fileExists(atPath: u.path) && KeysCheck.problem(u) == nil {
            setKeys(u)
            return
        }
    }

    func setTarget(_ t: BuildTarget) {
        options.target = t
        defaults.set(t.rawValue, forKey: Key.target)
        checkEnvironment(force: true)
    }

    func setRepo(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("scripts/build_ipa_from_nsp.py").path) {
            repo = url
            defaults.set(url.path, forKey: Key.repo)
            checkEnvironment(force: true)
        } else {
            notice = L("%@ is not an nxnative checkout: it has no scripts/build_ipa_from_nsp.py.", url.lastPathComponent)
        }
    }

    func setPython(_ url: URL) {
        defaults.set(url.path, forKey: Key.python)
        checkEnvironment(force: true)
    }

    // MARK: This Mac

    // A virtual environment for the modules: Homebrew's Python refuses pip outside one. It goes beside the game folder, on the games' drive, as AGENTS.md asks of tool environments.
    private var venvPath: String {
        if let v = defaults.string(forKey: Key.venv), !v.isEmpty { return v }
        if let g = game?.url { return g.deletingLastPathComponent().appendingPathComponent(".nxnative-venv").path }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Slotless/venv").path
    }

    func checkEnvironment(force: Bool = false) {
        guard let repo, !isBuilding, !isInstallingTools else { return }
        if !force, Date().timeIntervalSince(lastEnvCheck) < 5 { return }
        lastEnvCheck = Date()
        envGeneration += 1
        let generation = envGeneration
        checkingEnv = true
        let target = options.target, venv = venvPath, metal = options.allowOtherMetal
        let preferred = [defaults.string(forKey: Key.python) ?? "", venv + "/bin/python"]
        let nsz = game?.packages.contains { ["nsz", "xcz"].contains(($0.name as NSString).pathExtension.lowercased()) } ?? false
        Task.detached(priority: .utility) {
            let report = EnvCheck.run(repo: repo, target: target, preferredPython: preferred, venv: venv, needsNsz: nsz, allowOtherMetal: metal)
            await MainActor.run {
                guard generation == self.envGeneration else { return }
                self.env = report
                self.checkingEnv = false
            }
        }
    }

    // What needs no password runs here, with one line of progress, so nobody has to see a terminal. Homebrew's own installer asks for a password, so it goes to Terminal first.
    func installEverything() {
        guard let env else { return }
        if env.needsTerminal { return runFixes() }
        let steps = env.fixSteps
        guard !steps.isEmpty, let repo else { return }
        defaults.set(venvPath, forKey: Key.venv)
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Slotless/setup.log")
        Task {
            for (i, step) in steps.enumerated() {
                installingStep = L("Installing %@ (%@ of %@)…", step.title, "\(i + 1)", "\(steps.count)")
                let r = await runTool("/bin/zsh", ["-c", "export NONINTERACTIVE=1 HOMEBREW_NO_INSTALL_CLEANUP=1; " + step.command], cwd: repo, log: log)
                if r.code != 0 {
                    if installingStep != nil { notice = L("%@ could not be installed: %@", step.title, r.tail.last(where: { !$0.isEmpty }) ?? "\(r.code)") }
                    break
                }
            }
            installingStep = nil
            checkEnvironment(force: true)
        }
    }

    func stopInstalling() {
        guard isInstallingTools else { return }
        installingStep = nil
        runner?.cancel()
    }

    // In Terminal, where the player sees them and can answer a password prompt. Coming back to this app checks again.
    func runFixes() {
        guard let env, !env.fixes.isEmpty else { return }
        defaults.set(venvPath, forKey: Key.venv)
        let xcode = Host.xcodeOverride.map { "export DEVELOPER_DIR=\(shellQuote($0))\n" } ?? ""
        let fixes = env.needsTerminal ? env.items.filter { !$0.ok && $0.terminal }.compactMap(\.fix) : env.fixes
        var s = "#!/bin/zsh\nexport PATH=\(Host.toolPaths.map(shellQuote).joined(separator: ":")):$PATH\nexport HOMEBREW_NO_INSTALL_CLEANUP=1\n\(xcode)set -e\nclear\necho 'Slotless'\necho\n"
        for fix in fixes { s += "echo \(shellQuote("$ " + fix))\n\(fix)\necho\n" }
        s += "echo 'Done. Return to Slotless: it checks again by itself.'\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nxnative-setup-\(UUID().uuidString).command")
        do {
            try s.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            notice = L("The setup script could not be written: %@", error.localizedDescription)
        }
    }

    // MARK: The build

    func startBuild() {
        guard blocker == nil, let script, let repo, let python = env?.python else { return }
        beginRun()
        let runner = BuildRunner()
        self.runner = runner
        let target = options.target
        do {
            try runner.start(tool: python, arguments: [script.path] + resolvedOptions.arguments(), cwd: repo,
                onLine: { [weak self] line in
                    guard let self, let e = BuildEvent.parse(line) else { return }
                    self.transcript.apply(e)
                },
                onExit: { [weak self] code, stderr in
                    guard let self else { return }
                    if code == 0, target == .device, !self.cancelling {
                        guard let project = self.transcript.project, let bundle = self.transcript.bundleID else { return self.fail(L("The script did not say which project it prepared.")) }
                        Task { await self.installOnDevice(project: URL(fileURLWithPath: project), bundleID: bundle, build: true, forceCopy: false, previous: self.installRecord) }
                    } else {
                        self.finished(code, stderr)
                    }
                })
        } catch {
            finished(1, L("%@ did not start: %@", python, error.localizedDescription))
        }
    }

    func cancelBuild() {
        cancelling = true
        runner?.cancel()
    }

    // Quitting during a build stops it first, so no tool is left running without anyone to see it.
    func cancelBuild(then done: @escaping () -> Void) {
        exitWaiters.append(done)
        cancelBuild()
    }

    private func finished(_ code: Int32, _ stderr: String) {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        runner = nil
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !err.isEmpty { transcript.addStderr(err) }
        switch code {
        case 0:
            phase = .finished
            saveControls()
            findCleanup()
        case _ where cancelling: phase = .cancelled
        default: phase = .failed(transcript.lastError ?? (err.isEmpty ? L("The build stopped with exit code %@.", "\(code)") : err))
        }
        NSApp.requestUserAttention(.informationalRequest)
        exitWaiters.forEach { $0() }
        exitWaiters = []
    }

    func backToSetup() {
        phase = .setup
        cleanup = []
        checkEnvironment(force: true)
    }

    // MARK: Finder

    var outputURL: URL? { transcript.output.map { URL(fileURLWithPath: $0) } }

    func revealOutput() {
        if let outputURL { NSWorkspace.shared.activateFileViewerSelecting([outputURL]) }
    }

    func openLogs() {
        let logs = buildsFolder?.appendingPathComponent("logs")
        if let logs, FileManager.default.fileExists(atPath: logs.path) { NSWorkspace.shared.open(logs) }
        else if let g = game?.url { NSWorkspace.shared.open(g) }
    }

    func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commandLine, forType: .string)
    }

    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript.lines.map(\.text).joined(separator: "\n"), forType: .string)
    }
}
