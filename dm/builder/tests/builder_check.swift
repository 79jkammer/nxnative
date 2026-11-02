// NXNative Builder's logic and its run of a script, without its window: dm/tools/tests/test_builder_app.py compiles this with BuildCore.swift, Environment.swift and BuilderModel.swift, and runs it
// with the fake script (tests/fake_build.py) and a temporary folder. Exit 0 when every check holds.
import Foundation

var failures = 0

func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if !ok { failures += 1; print("FAILED line \(line): \(what)") }
}

// A PFS0 with these file names, then filler so the file looks like a package.
func pfs0(_ names: [String]) -> Data {
    func le32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: v >> ($0 * 8)) } }
    var strs: [UInt8] = [], offs: [Int] = []
    for n in names { offs.append(strs.count); strs += Array(n.utf8) + [0] }
    var d = Array("PFS0".utf8) + le32(names.count) + le32(strs.count) + le32(0)
    for o in offs { d += [UInt8](repeating: 0, count: 16) + le32(o) + le32(0) }
    return Data(d + strs + [1, 2, 3, 4])
}

func checkXcode() {
    let clt = "/Library/Developer/CommandLineTools", tested = "/A/Xcode-27.2.app/Contents/Developer", newer = "/A/Xcode.app/Contents/Developer"
    check(Host.pickXcode(selected: clt, apps: [(newer, "28.0"), (tested, "27.2")]) == tested, "the tested Xcode wins")
    check(Host.pickXcode(selected: newer, apps: [(newer, "28.0"), (tested, "27.2")]) == tested, "also over a selected one")
    check(Host.pickXcode(selected: tested, apps: [(newer, "28.0"), (tested, "27.2")]) == nil, "it is selected already")
    check(Host.pickXcode(selected: clt, apps: [(newer, "28.0")]) == newer, "any Xcode beats the Command Line Tools")
    check(Host.pickXcode(selected: newer, apps: [(newer, "28.0")]) == nil, "a selected Xcode stays")
    check(Host.pickXcode(selected: clt, apps: []) == nil, "no Xcode")
}

func checkArguments() {
    var o = BuildOptions()
    o.gameFolder = URL(fileURLWithPath: "/g/My Game")
    o.keys = URL(fileURLWithPath: "/k/prod.keys")
    check(o.arguments() == ["/g/My Game", "-k", "/k/prod.keys", "--platform", "ios", "--progress", "json"], "defaults add nothing: \(o.arguments())")
    o.needsKeys = false
    check(!o.arguments().contains("-k"), "a dump needs no keys")
    o.target = .macApp
    o.romfsSeparate = true
    o.showFPS = false
    o.macSign = "Developer ID"
    o.appName = "  "
    let mac = o.arguments()
    check(mac.contains("mac-app") && !mac.contains("--romfs") && !mac.contains("--no-show-fps") && mac.contains("--mac-sign") && !mac.contains("--app-name"), "options of the other platform are left out: \(mac)")
    o.target = .ios
    o.package = "v65536"
    o.allowDamaged = true
    o.motion = false
    let ios = o.arguments()
    check(ios.contains("--romfs") && ios.contains("--no-show-fps") && !ios.contains("--mac-sign") && ios.contains("v65536") && ios.contains("--allow-damaged") && ios.contains("--no-motion"), "\(ios)")
    check(shellQuote("/a b/it's") == #"'/a b/it'\''s'"#, "quoting")
    check(shellQuote("/a/b.keys") == "/a/b.keys", "a plain path stays plain")
}

func checkEvents() {
    check(BuildEvent.parse(#"{"ev":"stage","t":1,"k":2,"n":7,"name":"extract","step":"a"}"#) == .stage(k: 2, n: 7, name: "extract", step: "a"), "stage")
    check(BuildEvent.parse(#"{"ev":"future","t":1}"#) == nil, "an unknown event is dropped")
    check(BuildEvent.parse("") == nil, "an empty line is dropped")
    check(BuildEvent.parse("not json") == .say("not json"), "other output is kept as a message")
    guard case let .progress(_, _, _, none)? = BuildEvent.parse(#"{"ev":"progress","k":1,"name":"n","step":"s","done":3,"total":0,"unit":"files","est":false,"note":"","frac":null,"eta":null,"elapsed":2}"#) else {
        return check(false, "progress")
    }
    check(none.fraction == nil && none.eta == nil && none.done == 3, "a count without a total")
    check(formatCount(none) == "3 files", formatCount(none))
    guard case let .progress(_, _, _, bytes)? = BuildEvent.parse(#"{"ev":"progress","k":1,"name":"n","step":"s","done":1048576,"total":2097152,"unit":"B","est":true,"note":"x","frac":0.5,"eta":4,"elapsed":2}"#) else {
        return check(false, "progress")
    }
    check(bytes.fraction == 0.5 && formatCount(bytes).contains("of ~") && formatCount(bytes).hasSuffix("· x"), formatCount(bytes))

    var t = BuildTranscript()
    t.apply(.stage(k: 1, n: 2, name: "one", step: "a"))
    t.apply(.progress(k: 1, name: "one", step: "b", LiveProgress(fraction: 0.5)))
    check(t.current?.step == "b" && t.live?.fraction == 0.5, "progress moves the step")
    t.apply(.stageEnd(k: 1, name: "one", ok: true, summary: "fine", elapsed: 3))
    check(t.stages[0].state == .done && t.stages[0].summary == "fine" && t.live == nil, "a stage ends")
    t.apply(.stage(k: 2, n: 3, name: "two", step: ""))
    check(t.stageCount == 3 && t.stages.count == 2, "n can grow")
    t.apply(.say("[RED] broken"))
    check(t.lastError == "broken" && t.lines.last?.isError == true, "a red message")
    t.apply(.say("[12:00:00] done: /a b/Game (1).ipa (4.2 GB)"))
    check(t.output == "/a b/Game (1).ipa", "the output: \(t.output ?? "none")")
    check(BuildTranscript.donePath("[1] done: /x/G.app (1.0 GB); open it from Finder") == "/x/G.app", "a Mac app's message")
    check(BuildTranscript.donePath("[1] done: the game runs on the Mac with this command") == nil, "not an output")
    for i in 0..<(BuildTranscript.maxLines + 10) { t.apply(.say("line \(i)")) }
    check(t.lines.count == BuildTranscript.maxLines, "the messages are bounded")
}

func checkScan(_ tmp: URL) throws {
    let fm = FileManager.default
    let g = tmp.appendingPathComponent("game")
    try fm.createDirectory(at: g, withIntermediateDirectories: true)
    do { _ = try GameScan.scan(g); check(false, "an empty folder is refused") } catch {}
    // The ticket wins over a wrong tag, as in the script's title_of
    try pfs0(["aa.nca", "0100AAAA00000000000000000000000A.tik", "bb.cnmt.nca"]).write(to: g.appendingPathComponent("Game [0100AAAA00000001][v0].nsp"))
    try pfs0(["cc.nca"]).write(to: g.appendingPathComponent("Game [0100AAAA00000800][v65536].nsp"))
    try pfs0(["cc.nca"]).write(to: g.appendingPathComponent("Game [0100AAAA00001001][v0].nsz"))
    try Data("no pfs0 here".utf8).write(to: g.appendingPathComponent("notes.txt"))
    let s = try GameScan.scan(g)
    check(s.packages.count == 3 && !s.isDump, "packages: \(s.packages.map(\.name))")
    check(s.titles == [0x0100AAAA00000000], "one base game: \(s.titles.map(GameScan.hex))")
    check(s.versions == [0, 65536], "versions: \(s.versions)")
    check(Set(s.packages.map(\.kind)) == [.base, .update, .dlc], "kinds")
    check(GameScan.spaceNeeded(s) > 10 << 30, "the space a first build needs")
    try fm.createDirectory(at: g.appendingPathComponent("0100AAAA00000000_build"), withIntermediateDirectories: true)
    check(GameScan.spaceNeeded(try GameScan.scan(g)) == 0, "a build folder is there already")

    // A package that says nothing about itself, and a merged one
    let bare = tmp.appendingPathComponent("bare")
    try fm.createDirectory(at: bare, withIntermediateDirectories: true)
    try Data(repeating: 0, count: 64).write(to: bare.appendingPathComponent("game.nsp"))
    let b = try GameScan.scan(bare)
    check(b.packages[0].kind == .unknown && b.titles.isEmpty, "the script identifies such a package")
    try pfs0(["a.cnmt.nca", "b.cnmt.nca"]).write(to: bare.appendingPathComponent("all.nsp"))
    check(try GameScan.scan(bare).packages.contains { $0.holdsSeveral }, "a merged package")
    // A truncated header must not crash the scan
    var cut = Data("PFS0".utf8); cut.append(contentsOf: [255, 255, 0, 0, 255, 255, 0, 0, 0, 0, 0, 0])
    try cut.write(to: bare.appendingPathComponent("cut.nsp"))
    check(GameScan.pfs0Names(bare.appendingPathComponent("cut.nsp")).isEmpty, "a cut header")

    // A dump
    let dump = tmp.appendingPathComponent("dump")
    try fm.createDirectory(at: dump.appendingPathComponent("base/exefs"), withIntermediateDirectories: true)
    try fm.createDirectory(at: dump.appendingPathComponent("updates/458752/exefs"), withIntermediateDirectories: true)
    var npdm = Data(count: 0x100)
    npdm.replaceSubrange(0..<4, with: Array("META".utf8))
    npdm[0x70] = 0x80; npdm[0x74] = 0x20
    npdm.replaceSubrange(0x80..<0x84, with: Array("ACI0".utf8))
    let id: UInt64 = 0x040074A01BF12000
    for i in 0..<8 { npdm[0x90 + i] = UInt8(truncatingIfNeeded: id >> (UInt64(i) * 8)) }
    try npdm.write(to: dump.appendingPathComponent("base/exefs/main.npdm"))
    let d = try GameScan.scan(dump)
    check(d.isDump && d.titles == [id] && d.versions == [458752] && d.bytes == 0x100, "a dump: \(d)")

    // Keys: only names matter, and the message never holds a value
    let keys = tmp.appendingPathComponent("prod.keys")
    try "master_key_00 = 00112233\nheader_key = deadbeef\n".write(to: keys, atomically: true, encoding: .utf8)
    check(KeysCheck.problem(keys) == nil, "good keys")
    try "master_key_00 = 00112233\n".write(to: keys, atomically: true, encoding: .utf8)
    check(KeysCheck.problem(keys)?.contains("00112233") == false, "no header key, no value shown")
    check(KeysCheck.problem(tmp.appendingPathComponent("missing")) != nil, "a missing file")

    // A profile
    let repo = tmp.appendingPathComponent("repo")
    let profile = repo.appendingPathComponent("dm/games/0100AAAA00000000")
    try fm.createDirectory(at: profile, withIntermediateDirectories: true)
    try "# c\nname\tThe Game\nbuild\tv0\t1.0.0\tmain=aa\nbuild\tv65536\t1.0.1\tmain=bb\n".write(to: profile.appendingPathComponent("game.tsv"), atomically: true, encoding: .utf8)
    let p = GameProfile.load(repo: repo, title: 0x0100AAAA00000000)
    check(p?.name == "The Game" && p?.displayVersions[65536] == "1.0.1", "a profile")
    check(GameProfile.load(repo: repo, title: 1) == nil, "no profile")
}

// Runs the fake script to its end, on the main run loop as the app does.
@MainActor
func runFake(_ script: String, _ python: String, _ args: [String], cancelAfter: (() -> Bool)? = nil) -> (BuildTranscript, Int32, String) {
    var t = BuildTranscript(), result: (Int32, String)?
    let runner = BuildRunner()
    do {
        try runner.start(python: python, script: URL(fileURLWithPath: script), arguments: args, cwd: URL(fileURLWithPath: "/"),
                         onLine: { line in if let e = BuildEvent.parse(line) { t.apply(e) } }, onExit: { result = ($0, $1) })
    } catch {
        check(false, "the script did not start: \(error)")
        return (t, -1, "")
    }
    let deadline = Date().addingTimeInterval(60)
    var cancelled = false
    while result == nil, Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        if !cancelled, let c = cancelAfter, c() { runner.cancel(); cancelled = true }
    }
    check(result != nil, "the script ended")
    return (t, result?.0 ?? -1, result?.1 ?? "")
}

@MainActor
func checkRun(_ fake: String, _ python: String, _ tmp: URL) {
    let (done, code, _) = runFake(fake, python, [tmp.path, "-o", "/x/Game.ipa"])
    check(code == 0 && done.output == "/x/Game.ipa" && done.stages.count == 7 && done.stages.allSatisfy { $0.state == .done }, "a finished build: \(code) \(done.stages.map(\.name))")

    let (failed, failCode, stderr) = runFake(fake, python, [tmp.path, "--app-name", "fail"])
    check(failCode == 1 && failed.lastError?.hasPrefix("patch_nso.py exit code 1") == true && failed.stages.last?.state == .failed && stderr.contains("a line on stderr"), "a stopped build: \(failCode) \(failed.lastError ?? "")")

    // Cancel stops the whole process group: the tool the script runs too
    let pidFile = tmp.appendingPathComponent("child.pid")
    setenv("FAKE_CHILD_PID", pidFile.path, 1)
    let (_, hangCode, _) = runFake(fake, python, [tmp.path, "--app-name", "hang"]) { FileManager.default.fileExists(atPath: pidFile.path) }
    check(hangCode == 130, "an interrupted build exits with 130: \(hangCode)")
    if let s = try? String(contentsOf: pidFile, encoding: .utf8), let pid = Int32(s) {
        check(kill(pid, 0) != 0, "the script's child stopped too")
    } else {
        check(false, "no child pid")
    }
}

@main
struct BuilderCheck {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        let fake = args[1], python = args[2], tmp = URL(fileURLWithPath: args[3])
        checkXcode()
        checkArguments()
        checkEvents()
        try checkScan(tmp)
        checkRun(fake, python, tmp)
        print(failures == 0 ? "ok" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
