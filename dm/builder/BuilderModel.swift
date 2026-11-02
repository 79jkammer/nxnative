// NXNative Builder's state and the run of the NSP script: one build at a time, its events applied to a BuildTranscript on the main thread. The script is started the way docs/frontends.md describes:
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

    // onLine and onExit are called on the main thread.
    func start(python: String, script: URL, arguments: [String], cwd: URL, onLine: @escaping (String) -> Void, onExit: @escaping (Int32, String) -> Void) throws {
        var env = Host.environment
        env["PYTHONUNBUFFERED"] = "1"
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [script.path] + arguments
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

    private enum Key { static let repo = "repoRoot", game = "gameFolder", keys = "keysFile", target = "target", python = "pythonPath", venv = "venvPath" }

    init() {
        repo = Self.findRepo(defaults.string(forKey: Key.repo))
        if let t = defaults.string(forKey: Key.target).flatMap(BuildTarget.init(rawValue:)) { options.target = t }
        if let k = defaults.string(forKey: Key.keys), FileManager.default.fileExists(atPath: k) { setKeys(URL(fileURLWithPath: k)) }
        if let g = defaults.string(forKey: Key.game), FileManager.default.fileExists(atPath: g) { setGame(URL(fileURLWithPath: g)) }
        checkEnvironment(force: true)
    }

    // The repository this app was built from (Info.plist NXRepoRoot, written by scripts/build_builder_app.py), unless another was chosen
    private static func findRepo(_ saved: String?) -> URL? {
        let fm = FileManager.default
        for p in [saved, Bundle.main.object(forInfoDictionaryKey: "NXRepoRoot") as? String] {
            guard let p, !p.isEmpty, fm.fileExists(atPath: p + "/scripts/build_ipa_from_nsp.py") else { continue }
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    var script: URL? { repo?.appendingPathComponent("scripts/build_ipa_from_nsp.py") }
    var isBuilding: Bool { phase == .building }
    var profile: GameProfile? {
        guard let repo, let t = selectedTitle else { return nil }
        return GameProfile.load(repo: repo, title: t)
    }
    var selectedTitle: UInt64? {
        if let v = UInt64(options.titleID, radix: 16) { return v }
        return game?.titles.first
    }
    var gameName: String {
        if let n = profile?.name, !n.isEmpty { return n }
        return game?.url.lastPathComponent ?? ""
    }
    var freeBytes: Int64? {
        let path = options.workDir.isEmpty ? game?.url : URL(fileURLWithPath: options.workDir).deletingLastPathComponent()
        return (try? path?.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity.map(Int64.init)
    }
    var spaceProblem: String? {
        guard let game, let free = freeBytes else { return nil }
        let need = GameScan.spaceNeeded(game)
        return need > free ? "The first build needs about \(formatBytes(Double(need))) free on this disk; it has \(formatBytes(Double(free)))." : nil
    }
    // What stops Build, in the order the player would fix it; the environment's own problems are shown with their fixes
    var blocker: String? {
        if repo == nil { return "Choose the nxnative folder." }
        guard let game else { return "Add your game." }
        if game.titles.count > 1, options.titleID.isEmpty { return "This folder holds several games: choose one." }
        if !game.isDump {
            if options.keys == nil { return "Add your prod.keys." }
            if keysProblem != nil { return "Choose a working prod.keys." }
        }
        if env?.python == nil { return checkingEnv ? "Checking this Mac…" : "Install Python first." }
        if env?.problems.isEmpty == false, !buildAnyway { return "Install what this Mac is missing." }
        return nil
    }

    var buildsFolder: URL? {
        if !options.workDir.isEmpty { return URL(fileURLWithPath: options.workDir) }
        guard let game, let t = selectedTitle else { return nil }
        return game.url.appendingPathComponent(GameScan.hex(t) + "_build")
    }

    var commandLine: String {
        guard let script else { return "" }
        return ([env?.python ?? "python3", script.path] + options.arguments()).map(shellQuote).joined(separator: " ")
    }

    // MARK: Files

    func accept(_ urls: [URL]) -> Bool {
        var used = false
        var folders = Set<URL>()
        for u in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue { folders.insert(u); used = true }
            else if GameScan.isPackage(u) { folders.insert(u.deletingLastPathComponent()); used = true }
            else if u.pathExtension.lowercased() == "keys" || u.lastPathComponent.lowercased().contains("keys") { setKeys(u); used = true }
        }
        if folders.count > 1 { notice = "Put one game's files in one folder, then add that folder: the update and DLC are found beside the game." }
        else if let f = folders.first { setGame(f) }
        if !used { notice = "Add a game folder, a .nsp, .nsz, .xci or .xcz file, or prod.keys." }
        return used
    }

    func setGame(_ folder: URL) {
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
                    self.options.titleID = g.titles.count > 1 ? "" : self.options.titleID
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
            notice = "\(url.lastPathComponent) is not an nxnative checkout: it has no scripts/build_ipa_from_nsp.py."
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
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/NXNative Builder/venv").path
    }

    func checkEnvironment(force: Bool = false) {
        guard let repo, !isBuilding else { return }
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

    // The fixes run in Terminal, where the player sees them and can answer a password prompt. Coming back to this app checks again.
    func runFixes() {
        guard let env, !env.fixes.isEmpty else { return }
        defaults.set(venvPath, forKey: Key.venv)
        let xcode = Host.xcodeOverride.map { "export DEVELOPER_DIR=\(shellQuote($0))\n" } ?? ""
        var s = "#!/bin/zsh\nexport PATH=\(Host.toolPaths.map(shellQuote).joined(separator: ":")):$PATH\n\(xcode)set -e\nclear\necho 'NXNative Builder: installing what this Mac is missing.'\necho\n"
        for fix in env.fixes { s += "echo \(shellQuote("$ " + fix))\n\(fix)\necho\n" }
        s += "echo 'Done. Return to NXNative Builder: it checks again by itself.'\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nxnative-setup-\(UUID().uuidString).command")
        do {
            try s.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            notice = "The setup script could not be written: \(error.localizedDescription)"
        }
    }

    // MARK: The build

    func startBuild() {
        guard blocker == nil, let script, let repo, let python = env?.python else { return }
        transcript = BuildTranscript()
        cancelling = false
        startedAt = Date()
        phase = .building
        let runner = BuildRunner()
        self.runner = runner
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Building a game")
        do {
            try runner.start(python: python, script: script, arguments: options.arguments(), cwd: repo,
                onLine: { [weak self] line in
                    guard let self, let e = BuildEvent.parse(line) else { return }
                    self.transcript.apply(e)
                },
                onExit: { [weak self] code, stderr in self?.finished(code, stderr) })
        } catch {
            finished(1, "\(python) did not start: \(error.localizedDescription)")
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
        case 0: phase = .finished
        case _ where cancelling: phase = .cancelled
        default: phase = .failed(transcript.lastError ?? (err.isEmpty ? "The build stopped with exit code \(code)." : err))
        }
        NSApp.requestUserAttention(.informationalRequest)
        exitWaiters.forEach { $0() }
        exitWaiters = []
    }

    func backToSetup() {
        phase = .setup
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
