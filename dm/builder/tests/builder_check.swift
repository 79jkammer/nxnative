// Slotless's logic and its run of a script, without its window: dm/tools/tests/test_builder_app.py compiles this with Strings.swift, BuildCore.swift, Controls.swift, Device.swift, Environment.swift and BuilderModel.swift, and runs it
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

func checkStrings() {
    Lang.selected = .ru
    check(L("Back") != "Back" && L("Not in the table") == "Not in the table", "the Russian table, and English for what it lacks")
    check(L("Installing %@ (%@ of %@)…", "A", "1", "2").contains("1") && L("Installing %@ (%@ of %@)…", "A", "1", "2").contains("2"), "arguments in a translation")
    for (key, value) in Lang.russian {
        check(key.components(separatedBy: "%@").count == value.components(separatedBy: "%@").count, "the same arguments: \(key)")
    }
    Lang.selected = .en
    check(L("Back") == "Back" && L("Works until %@.", "x") == "Works until x.", "English")
    check(friendlyStage("build nx_extract") == "Preparing tools" && friendlyStage("extract v0") == "Unpacking the game" && friendlyStage("rewrite") == "Adapting the game", "stages in words")
    check(friendlyStage("iOS shaders").hasPrefix("Preparing the graphics") && friendlyStage("Vulkan shaders").hasPrefix("Preparing the graphics") && friendlyStage("IPA pack") == "Building the app", "stages in words")
    check(friendlyStage("Install on Phone") == "Install on Phone", "the install's own stages stay")
    let items = [EnvItem(id: "a", title: "A", ok: false, detail: "", fix: "a", helper: true), EnvItem(id: "b", title: "B", ok: true, detail: "", fix: "b", helper: true), EnvItem(id: "h", title: "H", ok: false, detail: "", fix: "h", terminal: true)]
    let report = EnvReport(items: items)
    check(report.fixSteps.map(\.command) == ["a"] && report.needsTerminal, "what runs here, and what goes to Terminal")
    var own = BuildTranscript()
    own.beginOwnStage(k: 1, n: 1, name: "n", step: "s")
    own.apply(.stage(k: 2, n: 2, name: "m", step: ""))
    check(own.stages[0].fromScript == false && own.stages[1].fromScript, "whose stage it is")
}

func checkControls(_ tmp: URL) throws {
    var c = Controls()
    check(c.envLines.isEmpty && c.key(of: "A") == 38 && c.key(of: "RSU") == nil && c.padTarget(of: "A") == "A", "the defaults")
    c.assign(key: 50, to: "A")
    check(c.key(of: "A") == 50 && c.envLines == ["DM_KEYMAP=A=50"], "\(c.envLines)")
    c.assign(key: 40, to: "A")   // B's default key
    check(c.key(of: "A") == 40 && c.key(of: "B") == nil, "the key's old action goes without one, as in the host")
    c.assign(key: 38, to: "A")   // back to its own default
    check(c.key(of: "A") == 38 && c.keys["A"] == nil && c.key(of: "B") == 40, "a default needs no line")
    c.assign(key: 13, to: "RSU"); c.assign(key: 0, to: "RSL")
    check(c.key(of: "RSU") == 13 && c.key(of: "LSU") == nil, "the camera on WASD")
    c.reset()
    c.assign(pad: "A", to: "B"); c.assign(pad: "B", to: "A"); c.assign(pad: "X", to: "X")
    check(c.envLines == ["DM_PAD_MAP=A=B,B=A"], "\(c.envLines)")
    check(c.merged(into: "DM_FPS_TARGET=30\nDM_PAD_MAP=old\n") == "DM_FPS_TARGET=30\nDM_PAD_MAP=A=B,B=A\n", "the player's other lines stay")
    check(Controls().merged(into: "DM_KEYMAP=A=1\n") == "", "nothing left")
    check(Controls.keyName(38) == "J" && Controls.keyName(nil) == "No key" && Controls.keyName(127) == "#127", "key names")

    let fm = FileManager.default
    let game = tmp.appendingPathComponent("cleanup"), build = game.appendingPathComponent("X_build"), derived = build.appendingPathComponent("xcode-derived-data"), nsp = game.appendingPathComponent("g.nsp")
    try fm.createDirectory(at: derived, withIntermediateDirectories: true)
    try Data(count: 20_000).write(to: derived.appendingPathComponent("o"))
    try Data(count: 20_000).write(to: nsp)
    let mac = Cleanup.items(target: .macApp, buildFolder: build, gameFiles: [nsp], output: game.appendingPathComponent("G.app"))
    check(mac.map(\.id) == ["build", "game"] && mac[0].selected && !mac[1].selected && mac[0].bytes > 0, "a Mac game: the build is offered, the game's files only by choice: \(mac.map(\.id))")
    let phone = Cleanup.items(target: .device, buildFolder: build, gameFiles: [], output: nil)
    check(phone.map(\.id) == ["derived", "build"] && phone[0].selected && !phone[1].selected, "an iPhone game keeps what Reinstall needs unless asked")
    check(Cleanup.items(target: .macApp, buildFolder: build, gameFiles: [], output: build.appendingPathComponent("G.app")).isEmpty, "never the folder that holds the output")
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

func checkDevice() {
    // The shape devicectl writes: the deprecated groups, the newer properties.*, and devices that do not count
    let json = #"""
    {"result":{"devices":[
     {"hardwareProperties":{"platform":"iOS","reality":"physical","udid":"U1","marketingName":"iPhone 16 Pro Max","productType":"iPhone17,2"},"connectionProperties":{"tunnelState":"connected","transportType":"wired"},"deviceProperties":{"name":"Phone","developerModeStatus":"disabled"}},
     {"properties":{"hardware":{"platform":"iOS","reality":"physical","udid":"U2","marketingName":"iPhone 14","productType":"iPhone14,7"},"connection":{"state":"connected","transportType":"localNetwork"},"device":{"name":"A old","developerModeStatus":"enabled"}}},
     {"hardwareProperties":{"platform":"iOS","reality":"physical","udid":"U3","productType":"iPhone17,1"},"connectionProperties":{"tunnelState":"unavailable"},"deviceProperties":{"name":"Away"}},
     {"hardwareProperties":{"platform":"watchOS","reality":"physical","udid":"U4"},"connectionProperties":{"tunnelState":"connected"}},
     {"hardwareProperties":{"platform":"iOS","reality":"virtual","udid":"U5"},"connectionProperties":{"tunnelState":"connected"}}
    ]}}
    """#
    let devices = DeviceList.parse(Data(json.utf8))
    check(devices.map(\.id) == ["U1", "U2"], "connected physical devices, by cable first: \(devices.map(\.id))")
    check(devices[0].developerMode == false && devices[0].supported == true && devices[0].wired, "\(devices[0])")
    check(devices[1].developerMode == true && devices[1].supported == false && !devices[1].wired, "\(devices[1])")
    check(DeviceList.parse(Data("not json".utf8)).isEmpty, "other output")
    check(ConnectedDevice(id: "", name: "", model: "", productType: "iPhone16,1", developerMode: nil, wired: true).supported == true, "the iPhone 15 Pro")
    check(ConnectedDevice(id: "", name: "", model: "", productType: "iPhone15,4", developerMode: nil, wired: true).supported == false, "the iPhone 15")
    check(ConnectedDevice(id: "", name: "", model: "", productType: "iPad14,3", developerMode: nil, wired: true).supported == nil, "an iPad")

    let prefs: [String: Any] = ["DVTDeveloperAccountManagerAppleIDLists": ["IDE.Identifiers.Prod": [["username": "a@b.c"]]],
                                "IDEProvisioningTeamByIdentifier": ["x": [["teamID": "PAID000000", "teamName": "Paid", "isFreeProvisioningTeam": false], ["teamID": "FREE000000", "teamName": "Me (Personal Team)", "isFreeProvisioningTeam": true]]]]
    check(AppleAccount.hasAccount(prefs) && AppleAccount.teams(prefs).map(\.id) == ["FREE000000", "PAID000000"], "a free team first")
    check(!AppleAccount.hasAccount(["DVTDeveloperAccountManagerAppleIDLists": ["IDE.Identifiers.Prod": [Any]()]]), "no account")
    check(AppleAccount.teams(["IDEProvisioningTeams": ["a@b.c": [["teamID": "OLD0000000"]]]]).map(\.id) == ["OLD0000000"], "the older key")

    // Both ways openssl writes a subject; the (…) in the name is not the team
    check(AppleAccount.certificateTeam(subject: "subject= /UID=ABC/CN=Apple Development: Me (ZZZZZZZZZZ)/OU=TEAM123456/O=Me/C=US") == "TEAM123456", "a slash subject")
    check(AppleAccount.certificateTeam(subject: "subject=UID = ABC, CN = Apple Development: Me (ZZZZZZZZZZ), OU = TEAM123456, O = Me, C = US") == "TEAM123456", "a comma subject")
    check(AppleAccount.certificateTeam(subject: "subject=CN = Apple Development: Me (ZZZZZZZZZZ)") == nil, "no OU")
    let waiting = EnvCheck.deviceItems(devices: [], hasAccount: true, teams: [])
    check(waiting.first { $0.id == "apple-id" }?.ok == true && waiting.first { $0.id == "apple-team" }?.detail.contains("Manage Certificates") == true, "an account with no team says what is left")

    // Everything is the player's to do: no item carries a command, and none shows the account's name
    let none = EnvCheck.deviceItems(devices: [], hasAccount: false, teams: [])
    check(none.map(\.id) == ["apple-id", "device"] && none.allSatisfy { !$0.ok && $0.fix == nil }, "nothing yet: \(none.map(\.id))")
    let off = EnvCheck.deviceItems(devices: [devices[0]], hasAccount: true, teams: [AppleTeam(id: "T", name: "n", isFree: true)])
    check(off.first { $0.id == "developer-mode" }?.ok == false && off.first { $0.id == "device" }?.ok == true && !off.contains { $0.id == "device-model" }, "Developer Mode: \(off.map(\.id))")
    check(EnvCheck.deviceItems(devices: [devices[1]], hasAccount: true, teams: []).contains { $0.id == "device-model" && !$0.ok }, "an old iPhone is said to be")

    check(XcodeInstall.bundleID(team: "ABC123DEFG", title: 0x010015100B514000) == "org.nxnative.uabc123defg.010015100b514000", "a bundle ID of the player's own")
    let full = XcodeInstall.arguments(project: "/p", scheme: "s", device: "U1", team: "T", derivedData: "/d", limitedMemory: false)
    check(full.contains("id=U1") && full.contains("DEVELOPMENT_TEAM=T") && full.contains("-allowProvisioningUpdates") && !full.contains("CODE_SIGN_ENTITLEMENTS="), "\(full)")
    check(XcodeInstall.arguments(project: "/p", scheme: "s", device: "U1", team: "T", derivedData: "/d", limitedMemory: true).contains("CODE_SIGN_ENTITLEMENTS="), "no entitlements")
    let list = Data(#"{"project":{"schemes":["DmIOS","Mario (010015100B514000)"]}}"#.utf8)
    check(XcodeInstall.scheme(listJSON: list, title: 0x010015100B514000) == "Mario (010015100B514000)", "the game's scheme")
    check(XcodeInstall.scheme(listJSON: list, title: nil) == "Mario (010015100B514000)", "without a title ID")
    check(XcodeInstall.appPath(settingsJSON: Data(#"[{"buildSettings":{"TARGET_BUILD_DIR":"/o","FULL_PRODUCT_NAME":"DmIOS.app"}}]"#.utf8)) == "/o/DmIOS.app", "the app")
    let plist = #"<?xml version="1.0"?><plist version="1.0"><dict><key>ExpirationDate</key><date>2026-11-10T00:00:00Z</date></dict></plist>"#
    check(XcodeInstall.expiry(profilePlist: Data(plist.utf8)) != nil, "the profile's end")

    check(InstallFailure.classify(["Personal development teams, including \"Me\", do not support the Increased Memory Limit capability."]) == .memoryCapability, "capability")
    check(InstallFailure.classify(["Provisioning profile doesn't include the com.apple.developer.kernel.increased-memory-limit entitlement."]) == .memoryCapability, "entitlement")
    check(InstallFailure.classify(["error: No Accounts: Add a new account in Accounts settings."]) == .noAccount, "account")
    check(InstallFailure.classify(["error: The app identifier \"x\" cannot be registered to your development team"]) == .bundleID, "bundle ID")
    check(InstallFailure.classify(["Your maximum App ID limit has been reached."]) == .appLimit, "limit")
    check(InstallFailure.classify(["ERROR: the device is locked"]) == .deviceLocked, "locked")
    check(InstallFailure.classify(["noise", "foo.c:1: error: boom"]) == .other("foo.c:1: error: boom"), "other")

    // What the script gets for an install
    var o = BuildOptions()
    o.gameFolder = URL(fileURLWithPath: "/g")
    o.keys = URL(fileURLWithPath: "/k")
    o.target = .device
    o.teamID = "T"
    o.output = "/x.ipa"
    o.keepExtracted = false
    o.xcodeWorkspace = "/g/NxNative.xcworkspace"
    let a = o.arguments()
    check(a.contains("--prepare-xcode") && a.contains("separate") && a.contains("--team-id") && a.contains("--xcode-workspace") && a[a.firstIndex(of: "--platform")! + 1] == "ios", "\(a)")
    check(!a.contains("-o") && !a.contains("--no-keep-extracted"), "what a prepared project cannot take: \(a)")
    var t = BuildTranscript()
    t.apply(.say("[1] app name: G; version: 1.0; bundle ID: org.x.y; app: /a"))
    t.apply(.say("[2] game project: /a b/xcode/DmIOS.xcodeproj"))
    check(t.bundleID == "org.x.y" && t.project == "/a b/xcode/DmIOS.xcodeproj", "\(t.bundleID ?? "") \(t.project ?? "")")
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

// A NUP's head as scripts/pack_nup.py reads it: (title, kind, version, has code), and each file's unpacked size. test_builder_app.py also runs this on a file its packer's test wrote (NUP_SAMPLE).
func nupBytes(_ packages: [(UInt64, UInt8, UInt32, Bool)], files: [UInt64], magic: String = "NUP\u{01}") -> Data {
    func le<T: FixedWidthInteger>(_ v: T) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    func join(_ parts: [Data]) -> Data { parts.reduce(Data(), +) }
    var toc = join([Data("TOC\u{01}".utf8), le(UInt32(packages.count)), le(UInt64(0)), le(UInt64(files.count)), Data(count: 24)])
    for p in packages {
        let exefs: UInt32 = p.3 ? 0 : .max
        toc += join([le(p.0), le(UInt32(0)), le(exefs), le(UInt32.max), le(p.2), le(p.1), le(UInt8(0)), le(UInt16(0)), le(UInt32(0)), le(UInt64(0)), le(UInt32(0)), Data(count: 20)])
    }
    for f in files { toc += join([le(UInt32(0)), le(UInt32(0)), le(f), le(UInt64(0)), le(UInt64(0)), Data(count: 48)]) }
    return join([Data(magic.utf8), le(UInt16(0x80)), le(UInt16(0)), le(UInt64(0x80)), le(UInt64(toc.count)), Data(count: 0x80 - 24), toc])
}

func checkNup(_ tmp: URL) throws {
    let fm = FileManager.default
    let title: UInt64 = 0x0400AAAA00000000, big: UInt64 = 40 << 30
    let d = tmp.appendingPathComponent("nup")
    try fm.createDirectory(at: d, withIntermediateDirectories: true)
    try nupBytes([(title, 0, 0, true), (title, 1, 131072, true), (title + 0x1001, 2, 0, false)], files: [big, 1 << 30]).write(to: d.appendingPathComponent("Game.NUP"))
    var s = try GameScan.scan(d)
    check(s.titles == [title], "a NUP's game comes from its table of contents: \(s.titles.map(GameScan.hex))")
    check(s.versions == [0, 131072], "a NUP's versions: \(s.versions)")
    check(s.packages[0].holdsSeveral && s.packages[0].kind == .base, "a NUP is one file that holds several")
    check(!s.needsKeys(title: title, file: "") && !s.needsKeys(title: nil, file: "Game.NUP"), "a NUP needs no keys")
    check(GameScan.spaceNeeded(s) > 80 << 30, "the space a NUP needs counts its unpacked size")

    var o = BuildOptions()
    o.gameFolder = d; o.gameFile = "Game.NUP"; o.titleID = GameScan.hex(title); o.needsKeys = false
    o.keys = URL(fileURLWithPath: "/k/prod.keys")
    let a = o.arguments()
    check(a.first == d.appendingPathComponent("Game.NUP").path, "the chosen NUP goes in place of the folder: \(a)")
    check(!a.contains("-k") && !a.contains("--game-file") && !a.contains("--title-id"), "the container says the rest: \(a)")

    // A package beside a NUP: the script packs the package unless the NUP is the chosen file
    try pfs0(["a.nca"]).write(to: d.appendingPathComponent("Game [0400AAAA00000000][v0].nsp"))
    s = try GameScan.scan(d)
    check(s.needsKeys(title: title, file: ""), "a package beside the NUP needs keys")
    check(!s.needsKeys(title: title, file: "Game.NUP"), "the chosen NUP does not")

    // An update alone, as a standalone NUP has it; a base record with no code is no version
    let lone = tmp.appendingPathComponent("lone")
    try fm.createDirectory(at: lone, withIntermediateDirectories: true)
    try nupBytes([(title, 0, 0, false), (title | 0x800, 1, 65536, true)], files: [1]).write(to: lone.appendingPathComponent("u.nup"))
    let u = try GameScan.scan(lone)
    check(u.titles == [title] && u.versions == [65536], "an update alone: \(u.titles) \(u.versions)")

    // A newer format is still offered: the script says what is wrong. A file that is no NUP is not a game
    let other = tmp.appendingPathComponent("other")
    try fm.createDirectory(at: other, withIntermediateDirectories: true)
    try nupBytes([(title, 0, 0, true)], files: [1], magic: "NUP\u{02}").write(to: other.appendingPathComponent("new.nup"))
    check(try GameScan.scan(other).unidentified.map(\.name) == ["new.nup"], "a NUP of a newer format")
    let not = tmp.appendingPathComponent("not")
    try fm.createDirectory(at: not, withIntermediateDirectories: true)
    try Data("renamed".utf8).write(to: not.appendingPathComponent("x.nup"))
    do { _ = try GameScan.scan(not); check(false, "a file that only has the extension is refused") } catch {}

    if let sample = ProcessInfo.processInfo.environment["NUP_SAMPLE"] {
        let real = try GameScan.scan(URL(fileURLWithPath: sample).deletingLastPathComponent())
        check(real.titles == [0x040074A01BF12000] && real.versions == [0, 458752] && real.packages[0].unpacked > 0, "a NUP the packer's test wrote: \(real.titles) \(real.versions)")
    }
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

    // A folder with two games: each sees its own files, versions and size
    let two = tmp.appendingPathComponent("two")
    try fm.createDirectory(at: two, withIntermediateDirectories: true)
    try pfs0(["a.nca"]).write(to: two.appendingPathComponent("First Game [0100AAAA00000000][v0].nsp"))
    try pfs0(["a.nca"]).write(to: two.appendingPathComponent("First Game [0100AAAA00000800][v65536].nsp"))
    try pfs0(["a.nca"]).write(to: two.appendingPathComponent("Second [0100BBBB00000000][v0].nsp"))
    let both = try GameScan.scan(two)
    let first: UInt64 = 0x0100AAAA00000000, second: UInt64 = 0x0100BBBB00000000
    check(both.titles == [first, second], "two games")
    check(both.packages(of: first).count == 2 && both.packages(of: second).count == 1 && both.packages(of: nil).count == 3, "each game's files")
    check(both.versions(of: first) == [0, 65536] && both.versions(of: second) == [0], "each game's versions")
    check(both.bytes(of: second) < both.bytes(of: first) && both.bytes(of: nil) == both.bytes, "each game's size")
    check(both.fileName(of: second) == "Second" && both.fileName(of: first) == "First Game", "names from the files")
    try fm.createDirectory(at: two.appendingPathComponent("0100AAAA00000000_build"), withIntermediateDirectories: true)
    check(GameScan.spaceNeeded(both, title: first) == 0 && GameScan.spaceNeeded(both, title: second) > 0, "only the first one was built")

    // A file the player chose is the game, in a folder of others: nothing else counts as it, whether or not it can be identified
    try pfs0([]).write(to: two.appendingPathComponent("New game.nsp"))
    let downloads = try GameScan.scan(two)
    check(downloads.unidentified.map(\.name) == ["New game.nsp"], "a file that says nothing about itself")
    check(downloads.files(title: nil, file: "New game.nsp").map(\.name) == ["New game.nsp"], "only the chosen file, while its game is not known")
    check(!downloads.files(title: second, file: "").contains { $0.name == "New game.nsp" }, "cleaning up another game does not offer it")
    check(downloads.files(title: nil, file: "").count == downloads.packages.count, "a folder of one game is all of it")
    check(GameFolder.displayName("New game.nsp") == "New game" && GameFolder.displayName("Second [0100BBBB00000000][v0].nsp") == "Second", "a file's game name")
    check(GameScan.spaceNeeded(downloads, title: nil, file: "New game.nsp") > 0, "another game's build folder is not this one's")
    var byFile = BuildOptions()
    byFile.gameFile = "New game.nsp"
    check(byFile.arguments().contains("--game-file"), "the file names the game")
    byFile.titleID = "0100AAAA00000000"
    check(!byFile.arguments().contains("--game-file") && byFile.arguments().contains("--title-id"), "the title ID does, once it is known")
    try fm.removeItem(at: two.appendingPathComponent("New game.nsp"))
    check(XcodeInstall.bundleID(team: "ABC123DEFG", title: nil) == "org.nxnative.uabc123defg.{title}", "a bundle ID the script finishes")
    if case .game("0100AAAA00000000")? = BuildEvent.parse(#"{"ev":"game","title_id":"0100AAAA00000000"}"#) {} else { check(false, "the game event") }

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
        try runner.start(tool: python, arguments: [script] + args, cwd: URL(fileURLWithPath: "/"),
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
        Lang.selected = .en   // the checks read the English texts, whatever this Mac's language is
        checkStrings()
        checkXcode()
        checkDevice()
        checkArguments()
        checkEvents()
        try checkScan(tmp)
        try checkNup(tmp)
        try checkControls(tmp)
        checkRun(fake, python, tmp)
        print(failures == 0 ? "ok" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
