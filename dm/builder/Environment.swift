// What a build needs on this Mac (README.md, Build from the command line; the script's check_prereqs and check_metal say the same when it starts), checked before the player waits for a build
// to stop on it. A missing piece carries the command that installs it, which the app runs in Terminal for the player to see (some ask for a password), or the page to get it from.
import Foundation

enum Host {
    static let toolPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/local/share/dotnet", NSHomeDirectory() + "/.dotnet"]   // a GUI app does not get the shell's PATH; the script's TOOL_PATHS

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (toolPaths + [env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        if env["DEVELOPER_DIR"] == nil, let dev = xcodeOverride { env["DEVELOPER_DIR"] = dev }
        return env
    }

    // The Xcode a build uses, when it is not the Mac's selected one: DEVELOPER_DIR picks it for the build alone, with no password and nothing changed on the Mac (own_compilers.py names the same way).
    static var xcodeOverride: String? {
        let selected = (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link")) ?? ""
        let dir = "/Applications"
        let apps = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }.sorted().map { app -> (path: String, version: String) in
            let info = NSDictionary(contentsOfFile: "\(dir)/\(app)/Contents/Info.plist")
            return ("\(dir)/\(app)/Contents/Developer", info?["CFBundleShortVersionString"] as? String ?? "")
        }
        return pickXcode(selected: selected, apps: apps)
    }

    // The shaders are tested with Xcode 27.2's compiler (dmsh_chain.lock), so that one wins wherever it is. Without it, any Xcode beats the Command Line Tools, and a selected Xcode stays.
    static func pickXcode(selected: String, apps: [(path: String, version: String)]) -> String? {
        let tested = apps.first { $0.version == "27.2" }?.path
        if let tested { return tested == selected ? nil : tested }
        return selected.isEmpty || selected.contains("CommandLineTools") ? apps.first?.path : nil
    }

    static func which(_ tool: String) -> String? {
        for dir in (environment["PATH"] ?? "").split(separator: ":") {
            let p = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    struct Result { let code: Int32; let out: String; let err: String }

    // Runs a tool to its end, at most `timeout` seconds. nil when it does not start.
    static func run(_ exe: String, _ args: [String], cwd: URL? = nil, timeout: Double = 30) -> Result? {
        let p = Process(), o = Pipe(), e = Pipe()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = environment
        p.standardOutput = o
        p.standardError = e
        p.standardInput = FileHandle.nullDevice
        if let cwd { p.currentDirectoryURL = cwd }
        do { try p.run() } catch { return nil }
        let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        var err = Data()
        let g = DispatchGroup()
        g.enter()
        DispatchQueue.global().async { err = e.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        let out = o.fileHandleForReading.readDataToEndOfFile()
        g.wait()
        p.waitUntilExit()
        timer.cancel()
        return Result(code: p.terminationStatus, out: String(decoding: out, as: UTF8.self), err: String(decoding: err, as: UTF8.self))
    }
}

struct EnvItem: Identifiable, Equatable {
    let id: String
    let title: String
    var ok: Bool
    var detail: String
    var fix: String?          // a shell command
    var link: URL?            // where to get it when no command can
    var optional = false      // a warning only
}

struct EnvReport: Equatable {
    var items: [EnvItem] = []
    var python: String?
    var problems: [EnvItem] { items.filter { !$0.ok && !$0.optional } }
    var warnings: [EnvItem] { items.filter { !$0.ok && $0.optional } }
    var fixes: [String] {
        var seen = Set<String>()
        return items.filter { !$0.ok }.compactMap(\.fix).filter { seen.insert($0).inserted }
    }
}

struct PythonProbe: Decodable {
    let version: [Int]
    let translated: Bool
    let missing: [String]
    let optionalMissing: [String]
    var usable: Bool { !translated && (version.first ?? 0, version.dropFirst().first ?? 0) >= (3, 12) }
}

enum EnvCheck {
    static let xcodeURL = URL(string: "https://developer.apple.com/download/all/?q=Xcode%2027.2")!
    static let brewURL = URL(string: "https://brew.sh")!
    static let pipPackages = #"lz4 'capstone>=5,<6' fonttools nsz zbic "backports.zstd; python_version < '3.14'""#

    // -I in the probe: nothing from the folder it starts in is imported. The module list is the script's check_prereqs; nsz and zbic are needed by some games only.
    private static let probe = #"""
    import json, platform, subprocess, sys
    def has(m):
        try: __import__(m); return True
        except Exception: return False
    miss = [n for n, m in (('lz4', 'lz4.block'), ('capstone', 'capstone'), ('fonttools', 'fontTools')) if not has(m)]
    if 'capstone' not in miss:
        import capstone
        if capstone.cs_version()[0] != 5: miss.append('capstone 5')
    if not (has('compression.zstd') or has('backports.zstd')): miss.append('backports.zstd')
    tr = subprocess.run(['sysctl', '-n', 'sysctl.proc_translated'], capture_output=True, text=True).stdout.strip() == '1'
    print(json.dumps({'version': list(sys.version_info[:3]), 'translated': tr, 'missing': miss, 'optionalMissing': [m for m in ('nsz', 'zbic') if not has(m)]}))
    """#

    static func probePython(_ exe: String) -> PythonProbe? {
        guard FileManager.default.isExecutableFile(atPath: exe), let r = Host.run(exe, ["-I", "-c", probe], timeout: 20), r.code == 0 else { return nil }
        return try? JSONDecoder().decode(PythonProbe.self, from: Data(r.out.utf8))
    }

    static func pythonCandidates(preferred: [String]) -> [String] {
        var seen = Set<String>()
        let known = ["/opt/homebrew/bin/python3.14", "/opt/homebrew/bin/python3.13", "/opt/homebrew/bin/python3.12", "/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        return (preferred.filter { !$0.isEmpty } + known).filter { seen.insert($0).inserted }
    }

    // preferred: the player's choice and the app's virtual environment, in that order. venv: where the fix makes that environment.
    static func run(repo: URL, target: BuildTarget, preferredPython: [String], venv: String, needsNsz: Bool, allowOtherMetal: Bool) -> EnvReport {
        var r = EnvReport()
        let v = ProcessInfo.processInfo.operatingSystemVersion
        r.items.append(EnvItem(id: "macos", title: "macOS 26.6 or later", ok: (v.majorVersion, v.minorVersion) >= (26, 6), detail: "This Mac has \(v.majorVersion).\(v.minorVersion)."))

        // Xcode
        let dev = Host.run("/usr/bin/xcode-select", ["-p"])?.out.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let build = Host.run("/usr/bin/xcodebuild", ["-version"])
        let xcodeOK = build?.code == 0 && !dev.contains("CommandLineTools")
        var xcode = EnvItem(id: "xcode", title: "Xcode 27.2", ok: xcodeOK, detail: xcodeOK ? (build?.out.split(separator: "\n").first.map(String.init) ?? "") + " in \(dev)" : "")
        if !xcodeOK {
            xcode.detail = "Not found in Applications, or it does not run. Download Xcode 27.2, move it to Applications, then check again."
            xcode.link = xcodeURL
        }
        r.items.append(xcode)
        if xcodeOK {
            let metal = Host.run("/usr/bin/xcrun", ["-sdk", "macosx", "metal", "--version"])
            r.items.append(EnvItem(id: "metal", title: "Metal compiler", ok: metal?.code == 0, detail: metal?.code == 0 ? "" : "The Metal toolchain is a separate download.",
                                   fix: metal?.code == 0 ? nil : "xcodebuild -downloadComponent MetalToolchain"))
            if target == .ios {
                let sdk = Host.run("/usr/bin/xcrun", ["--sdk", "iphoneos", "--show-sdk-path"])
                r.items.append(EnvItem(id: "ios-sdk", title: "iOS platform", ok: sdk?.code == 0, detail: sdk?.code == 0 ? "" : "Install it in Xcode → Settings → Components."))
            }
        }

        // Homebrew's tools
        let brew = Host.which("brew") != nil
        func tool(_ id: String, _ exe: String, _ title: String, _ fix: String) {
            let ok = Host.which(exe) != nil
            r.items.append(EnvItem(id: id, title: title, ok: ok, detail: ok ? "" : (brew ? "" : "Install Homebrew first."), fix: ok || !brew ? nil : fix, link: ok || brew ? nil : brewURL))
        }
        if target == .ios { tool("xcodegen", "xcodegen", "XcodeGen", "brew install xcodegen") }
        tool("zstd", "zstd", "zstd", "brew install zstd")
        tool("glslang", "glslangValidator", "glslang", "brew install glslang")
        let runtimes = Host.which("dotnet").flatMap { Host.run($0, ["--list-runtimes"]) }
        let dotnetOK = runtimes?.out.contains("Microsoft.NETCore.App 10.") == true
        r.items.append(EnvItem(id: "dotnet", title: ".NET 10", ok: dotnetOK, detail: dotnetOK ? "" : (brew ? "It runs the shader translator." : "Install Homebrew first."),
                               fix: !dotnetOK && brew ? "brew install dotnet" : nil, link: !dotnetOK && !brew ? brewURL : nil))   // the formula, as the cask's installer asks for a password

        // Python: the first that has every module, else the first new enough to make an environment from
        let probes = pythonCandidates(preferred: preferredPython).compactMap { p in probePython(p).map { (p, $0) } }.filter { $0.1.usable }
        let best = probes.first { $0.1.missing.isEmpty } ?? probes.first
        if let (exe, probe) = best {
            let ok = probe.missing.isEmpty
            r.python = exe
            let shown = probe.version.prefix(2).map(String.init).joined(separator: ".")
            let venvPython = venv + "/bin/python"
            let install = "\(shellQuote(exe)) -m venv \(shellQuote(venv)) && \(shellQuote(venvPython)) -m pip install \(pipPackages)"
            r.items.append(EnvItem(id: "python", title: "Python modules", ok: ok, detail: ok ? "Python \(shown): \(exe)" : "Missing from Python \(shown): \(probe.missing.joined(separator: ", ")).", fix: ok ? nil : install))
            if ok, !probe.optionalMissing.isEmpty {
                let nsz = probe.optionalMissing.contains("nsz")
                r.items.append(EnvItem(id: "python-optional", title: "Python modules for some games", ok: false,
                                       detail: "Missing: \(probe.optionalMissing.joined(separator: ", ")). " + (nsz && needsNsz ? "This game's .nsz or .xcz files need nsz." : "Needed for .nsz / .xcz files and for games on newer system versions."),
                                       fix: "\(shellQuote(exe)) -m pip install \(probe.optionalMissing.joined(separator: " "))", optional: !(nsz && needsNsz)))
            }
        } else {
            r.items.append(EnvItem(id: "python", title: "Python 3.12 or newer", ok: false, detail: brew ? "No arm64 Python 3.12 or newer was found." : "Install Homebrew first.",
                                   fix: brew ? "brew install python@3.14" : nil, link: brew ? nil : brewURL))
        }

        // The compiler the shaders were tested with; the script stops on another one unless told otherwise
        if xcodeOK, let py = r.python, !allowOtherMetal, r.items.first(where: { $0.id == "metal" })?.ok == true {
            let c = Host.run(py, [repo.appendingPathComponent("dm/gfx/tools/own_compilers.py").path, "--check-metal"], cwd: repo, timeout: 60)
            if let c, c.code != 0 {
                let why = (c.out + c.err).trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "[RED] ", with: "")
                r.items.append(EnvItem(id: "metal-version", title: "The tested Metal compiler", ok: false, detail: why, link: xcodeURL))
            }
        }
        return r
    }
}
