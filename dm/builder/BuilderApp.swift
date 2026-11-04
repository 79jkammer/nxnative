// Slotless: a Mac app that turns a game the player owns into an app for their iPhone or Mac with the NSP script, without a terminal. The left side sets up the build, the right side shows what
// stands in its way, then its progress and result. By default it asks only for what anyone can answer; Settings has the language and turns on the advanced options, commands and messages.
// Every text goes through L (Strings.swift). Built by scripts/build_builder_app.py; docs/development.md, Slotless.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

let appName = "Slotless"

@main
struct BuilderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = BuilderModel()

    init() { Self.moveFormerFolder() }

    // The app was called NXNative Builder before its first release: what it kept under that name moves here once. The bundle identifier stays, so its settings need no move, only the path of its Python environment.
    private static func moveFormerFolder() {
        let fm = FileManager.default, support = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let old = support.appendingPathComponent("NXNative Builder"), new = Engine.folder
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path), (try? fm.moveItem(at: old, to: new)) != nil else { return }
        if let venv = UserDefaults.standard.string(forKey: "venvPath"), venv.hasPrefix(old.path + "/") {
            UserDefaults.standard.set(new.path + venv.dropFirst(old.path.count), forKey: "venvPath")
        }
    }

    var body: some Scene {
        Window(appName, id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 620)
                .onAppear {
                    delegate.model = model
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    if model.phase == .setup { model.checkEnvironment() }
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("Add Game…")) { Panels.chooseGame(model) }.keyboardShortcut("o")
                Button(L("Choose Keys…")) { Panels.chooseKeys(model) }.keyboardShortcut("k")
            }
            CommandGroup(after: .pasteboard) {
                if model.advancedMode { Button(L("Copy Build Command")) { model.copyCommand() }.disabled(model.game == nil) }
            }
        }
        Settings {
            SettingsView().environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: BuilderModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            model?.stopInstalling()
            guard let model, model.isBuilding else { return .terminateNow }
            let alert = NSAlert()
            alert.messageText = L("Stop the build and quit?")
            alert.informativeText = L("What the build has finished so far is kept, so the next build goes on from there.")
            alert.addButton(withTitle: L("Stop and Quit"))
            alert.addButton(withTitle: L("Keep Building"))
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
            model.cancelBuild { NSApp.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        }
    }
}

@MainActor
enum Panels {
    private static func pick(_ title: String, files: Bool, folders: Bool, start: URL? = nil) -> URL? {
        let p = NSOpenPanel()
        p.message = title
        p.canChooseFiles = files
        p.canChooseDirectories = folders
        p.allowsMultipleSelection = false
        p.directoryURL = start
        return p.runModal() == .OK ? p.url : nil
    }

    static func chooseGame(_ m: BuilderModel) {
        if let u = pick(L("Choose your game's folder, or one of its .nsp, .nsz, .xci or .xcz files."), files: true, folders: true) { _ = m.accept([u]) }
    }

    static func chooseKeys(_ m: BuilderModel) {
        if let u = pick(L("Choose the prod.keys from your console."), files: true, folders: false) { m.setKeys(u) }
    }

    static func chooseRepo(_ m: BuilderModel) {
        if let u = pick(L("Choose your nxnative folder."), files: false, folders: true) { m.setRepo(u) }
    }

    static func choosePython(_ m: BuilderModel) {
        let p = NSOpenPanel()
        p.message = L("Choose a Python 3.12 or newer.")
        p.canChooseDirectories = false
        p.treatsFilePackagesAsDirectories = true
        p.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if p.runModal() == .OK, let u = p.url { m.setPython(u) }
    }

    static func chooseFolder(_ title: String) -> String? { pick(title, files: false, folders: true)?.path }

    static func chooseOutput(_ m: BuilderModel) -> String? {
        let p = NSSavePanel()
        p.message = L("Where should the finished app go?")
        p.nameFieldStringValue = m.gameName + (m.options.target == .ios ? ".ipa" : ".app")
        return p.runModal() == .OK ? p.url?.path : nil
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        Form {
            Section {
                Picker(L("Language"), selection: Binding(get: { m.language }, set: { m.setLanguage($0) })) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                Text(L("Language of this app. Game language is set in the game's own settings."))
            }
            Section {
                Toggle(L("Advanced options"), isOn: Binding(get: { m.advancedMode }, set: { m.setAdvancedMode($0) }))
            } footer: {
                Text(L("Shows commands, messages and build options. Not needed to install a game."))
            }
            if m.advancedMode || m.repo == nil {
                Section {
                    LabeledContent(L("nxnative folder")) {
                        HStack {
                            Text(m.repo.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? L("Not chosen")).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            Button(L("Choose…")) { Panels.chooseRepo(m) }
                        }
                    }
                    if m.advancedMode {
                        LabeledContent(L("Python")) {
                            HStack {
                                Text(m.env?.python.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? L("Found automatically")).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                Button(L("Choose…")) { Panels.choosePython(m) }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - The window

struct RootView: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        HStack(spacing: 0) {
            SetupPane()
                .frame(width: 420)
                .disabled(m.isBuilding || m.isInstallingTools)
            Divider()
            ActivityPane()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if m.dropping {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .background(Color.accentColor.opacity(0.08))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            if m.isBuilding { return false }
            return m.accept(urls)
        } isTargeted: { m.dropping = $0 && !m.isBuilding }
        .sheet(isPresented: $m.showControls) { ControlsView().environmentObject(m) }
        .alert(appName, isPresented: Binding(get: { m.notice != nil }, set: { if !$0 { m.notice = nil } })) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(m.notice ?? "")
        }
    }
}

// MARK: - Setup

struct SetupPane: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if m.repo == nil, m.engineSource == nil {
                    Section {
                        LabeledContent(L("nxnative folder")) { Button(L("Choose…")) { Panels.chooseRepo(m) } }
                    } footer: {
                        Text(L("This app runs the build script from your nxnative checkout."))
                    }
                }
                Section(L("1. Your game")) { GameCard() }
                if m.game?.isDump != true {
                    Section(L("2. Keys")) { KeysRow() }
                }
                Section(m.game?.isDump == true ? L("2. Keys") : L("3. Where to play")) {
                    Picker(L("3. Where to play"), selection: Binding(get: { m.options.target }, set: { m.setTarget($0) })) {
                        ForEach(m.targets) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(targetNote)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if m.options.target == .device, let devices = m.env?.devices, devices.count > 1 {
                        Picker(L("iPhone"), selection: $m.deviceID) {
                            ForEach(devices) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                if m.advancedMode {
                    if m.game != nil { optionsSection }
                    advancedSection
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                SettingsLink {
                    Label(L("Settings"), systemImage: "gearshape")
                }
                Button { m.showControls = true } label: {
                    Label(L("Controls"), systemImage: "gamecontroller")
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var targetNote: String {
        switch m.options.target {
        case .ios: return L("An IPA to sideload with AltStore, Sideloadly or LiveContainer. Needs an iPhone 15 Pro or newer, or an iPad with an M1 or later.")
        case .device: return L("Installs the game on your iPhone over a cable. Needs an iPhone 15 Pro or newer. With a free Apple ID it works for 7 days, then press Reinstall here; your saves stay.")
        case .macApp: return L("Makes an app of the game to open on this Mac.")
        }
    }

    private var optionsSection: some View {
        Section(L("Options")) {
            if let game = m.game, game.versions(of: m.selectedTitle).count > 1 {
                Picker(L("Version"), selection: $m.options.package) {
                    Text(L("Newest")).tag("")
                    ForEach(game.versions(of: m.selectedTitle).reversed(), id: \.self) { v in
                        Text(m.profile?.displayVersions[v].map { "\($0) (v\(v))" } ?? "v\(v)").tag("v\(v)")
                    }
                }
            }
            Picker(L("Game language"), selection: $m.options.language) {
                ForEach(GameLanguage.all, id: \.0) { Text(L($0.1)).tag($0.0) }
            }
            TextField(L("App name"), text: $m.options.appName, prompt: Text(L("The game's name")))
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup(L("Advanced"), isExpanded: $m.showAdvanced) {
                switch m.options.target {
                case .ios:
                    Toggle(L("Keep game files out of the IPA"), isOn: $m.options.romfsSeparate)
                        .help(L("For a game too big to install: the IPA is small, and the game files are copied to the phone once, with the command shown at the end of the build."))
                    Toggle(L("Show the frame rate"), isOn: $m.options.showFPS)
                case .device:
                    TextField(L("Apple team ID"), text: $m.options.teamID, prompt: Text(m.env?.teams.first?.id ?? L("From Xcode")))
                    Toggle(L("Show the frame rate"), isOn: $m.options.showFPS)
                case .macApp:
                    TextField(L("Signing identity"), text: $m.options.macSign, prompt: Text(L("Ad-hoc")))
                }
                Toggle(L("Motion controls"), isOn: $m.options.motion)
                if m.options.target != .device { Toggle(L("Keep extracted files for the next build"), isOn: $m.options.keepExtracted) }
                TextField(L("Bundle ID"), text: $m.options.bundleID, prompt: Text(verbatim: "org.nxnative.<title ID>"))
                TextField(L("GPU archives"), text: $m.options.gpu, prompt: Text(L("From the game's profile")))
                    .help(L("GPU architectures to make a pipeline archive for, comma-separated (g18p), or none."))
                if m.options.target != .device { PathRow(title: L("Output"), path: $m.options.output, prompt: L("Next to the game")) { Panels.chooseOutput(m) } }
                PathRow(title: L("Build folder"), path: $m.options.workDir, prompt: L("In the game's folder")) { Panels.chooseFolder(L("Choose this game's build folder.")) }
                Toggle(L("Allow a damaged package"), isOn: $m.options.allowDamaged)
                    .help(L("Files that fail the hash check are packed as they were read, instead of stopping. Usually a broken copy: dump the game again first."))
                Toggle(L("Allow failed shaders"), isOn: $m.options.allowShaderRegressions)
                    .help(L("Shaders that built before and fail now are left out, instead of stopping."))
                Toggle(L("Allow another Metal compiler"), isOn: Binding(get: { m.options.allowOtherMetal }, set: { m.options.allowOtherMetal = $0; m.checkEnvironment(force: true) }))
                    .help(L("Build shaders with this Mac's compiler when it is not Xcode 27.2's. They can render wrong pictures."))
                Toggle(L("Use a provisional profile"), isOn: $m.options.provisional)
                    .help(L("Guess the game's settings even though it has a profile, to test the guesses."))
                Button(L("Copy Build Command")) { m.copyCommand() }.disabled(m.game == nil)
            }
        }
    }
}

enum GameLanguage {
    static let all = [("", "English (default)"), ("ja", "Japanese"), ("fr", "French"), ("de", "German"), ("es", "Spanish"), ("it", "Italian"), ("nl", "Dutch"), ("pt", "Portuguese"), ("ru", "Russian"), ("ko", "Korean"),
                      ("zh-Hans", "Chinese (Simplified)"), ("zh-Hant", "Chinese (Traditional)"), ("en-GB", "English (UK)"), ("fr-CA", "French (Canada)"), ("es-419", "Spanish (Latin America)"), ("pt-BR", "Portuguese (Brazil)")]
}

struct PathRow: View {
    let title: String
    @Binding var path: String
    let prompt: String
    let choose: () -> String?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text(path.isEmpty ? prompt : (path as NSString).abbreviatingWithTildeInPath)
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !path.isEmpty {
                    Button { path = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L("Reset"))
                }
                Button(L("Choose…")) { if let p = choose() { path = p } }
            }
        }
    }
}

struct GameCard: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        if m.scanning {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Reading the game folder…")).foregroundStyle(.secondary) }
        } else if let game = m.game {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(m.gameName).font(.headline).lineLimit(2)
                    Spacer()
                    Button(L("Change…")) { Panels.chooseGame(m) }
                }
                if m.advancedMode {
                    Text((game.url.path as NSString).abbreviatingWithTildeInPath)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                if game.titles.count > 1 {
                    Picker(L("Game to build"), selection: Binding(get: { m.options.titleID }, set: { m.chooseTitle($0) })) {
                        if m.needsGameChoice { Text(L("Choose…")).tag("") }
                        ForEach(game.titles, id: \.self) { Text(m.name(of: $0)).tag(GameScan.hex($0)) }
                    }
                    if m.needsGameChoice {
                        Label(L("This folder holds %@ games. Choose the one to build.", "\(game.titles.count)"), systemImage: "arrow.up").font(.callout).foregroundStyle(.orange)
                    }
                }
                if let t = m.selectedTitle { profileStatus(t) }
                if m.advancedMode {
                    if game.isDump {
                        Text(L("A folder of the game's files, %@.", formatBytes(Double(game.bytes)))).font(.callout).foregroundStyle(.secondary)
                    }
                    if !m.needsGameChoice { ForEach(game.packages(of: m.selectedTitle)) { packageRow($0) } }
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down").font(.title).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(L("Drop your game here")).font(.headline)
                Text(L("A folder or a file: .nsp, .nsz, .xci or .xcz. Use a game you own."))
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(L("Choose…")) { Panels.chooseGame(m) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            if let e = m.gameError { Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout) }
        }
    }

    @ViewBuilder private func profileStatus(_ t: UInt64) -> some View {
        if m.profile != nil {
            Label(m.advancedMode ? L("Ready to build · %@", GameScan.hex(t)) : L("This game can be built."), systemImage: "checkmark.seal.fill").font(.callout).foregroundStyle(.green)
        } else {
            Label(m.advancedMode ? L("Not tested with this app (%@). It may not start.", GameScan.hex(t)) : L("This game was not tested with this app. It may not start."), systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
        }
    }

    private func packageRow(_ p: GamePackage) -> some View {
        HStack(spacing: 6) {
            Text(p.holdsSeveral ? L("All-in-one") : L(p.kind.rawValue)).font(.caption.weight(.semibold))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            if let v = p.version, p.kind != .dlc { Text(m.profile?.displayVersions[v] ?? "v\(v)").font(.callout) }
            Spacer()
            Text(formatBytes(Double(p.size))).font(.callout).foregroundStyle(.secondary).monospacedDigit()
        }
        .help(p.name)
    }
}

struct KeysRow: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        LabeledContent {
            Button(m.options.keys == nil ? L("Choose…") : L("Change…")) { Panels.chooseKeys(m) }
        } label: {
            if let keys = m.options.keys {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(keys.lastPathComponent)
                        if m.advancedMode {
                            Text((keys.path as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                } icon: {
                    Image(systemName: m.keysProblem == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(m.keysProblem == nil ? Color.green : Color.orange)
                }
            } else {
                Text(L("The keys file (prod.keys) from your own console")).foregroundStyle(.secondary)
            }
        }
        if let p = m.keysProblem { Text(p).font(.callout).foregroundStyle(.orange) }
    }
}

// MARK: - Activity

struct ActivityPane: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        switch m.phase {
        case .setup: ReadyView()
        default: BuildView()
        }
    }
}

struct ReadyView: View {
    @EnvironmentObject private var m: BuilderModel

    private var buildTitle: String {
        guard !m.advancedMode else { return L("Build") }
        switch m.options.target {
        case .ios: return L("Build")
        case .device: return L("Install on iPhone")
        case .macApp: return L("Build for Mac")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if m.repo == nil, m.engineSource != nil { EnginePanel() }
                    if m.options.target == .device, m.installRecord != nil { InstalledPanel() }
                    if m.repo != nil { if m.advancedMode { EnvironmentPanel() } else { SimpleEnvironmentPanel() } }
                    if m.options.target == .device { ControllerTip() }
                    if let s = m.spaceProblem {
                        Label(s, systemImage: "externaldrive.badge.exclamationmark").foregroundStyle(.orange)
                    }
                    Text(L("A first build takes 30–60 minutes and needs about twice the game's size plus 10 GB free. Building again is much faster."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if let b = m.blocker { Text(b).foregroundStyle(.secondary) }
                Spacer()
                Button {
                    m.startBuild()
                } label: {
                    Text(buildTitle).frame(minWidth: 90)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("b")
                .disabled(m.blocker != nil)
            }
            .padding(16)
        }
    }
}

// The first start of a released app: the project it runs comes from GitHub, once
struct EnginePanel: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Getting ready")).font(.title2.weight(.semibold))
            if m.downloadingEngine {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Downloading the app's components (about 200 MB)…")).fontWeight(.medium) }
                Text(L("This happens once.")).font(.callout).foregroundStyle(.secondary)
            } else if m.engineFailed {
                Label(L("The download did not finish. Check your internet connection."), systemImage: "wifi.exclamationmark").foregroundStyle(.orange)
                Button(L("Try Again")) { m.downloadEngine() }.buttonStyle(.borderedProminent)
            }
        }
    }
}

// Touch controls work, but most 3D games are much easier with a controller
struct ControllerTip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(L("A controller is recommended"), systemImage: "gamecontroller.fill").fontWeight(.medium)
            Text(L("Most 3D games are much easier with one: a DualSense, an Xbox controller, a Switch Pro Controller, or one that holds the phone, such as Backbone or Razer Kishi. Pair it in Settings → Bluetooth, or plug it in. The buttons on the screen hide by themselves while it is connected."))
                .font(.callout).foregroundStyle(.secondary)
            Text(L("Playing by touch? In the game, hold the 2D / 3D button to move, resize or hide the buttons."))
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

// The player's keys and controller buttons. Everything else about controls, vibration included, is on the settings screen each game shows before it starts.
struct ControlsView: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text(L("Vibration, camera direction, trackpad camera on the Mac and the size of the buttons on the screen are on the settings screen each game shows before it starts."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(Controls.keyActions, id: \.id) { action in
                        LabeledContent(Controls.label(action.id)) {
                            Button(m.capturingAction == action.id ? L("Press a key…") : Controls.keyName(m.controls.key(of: action.id))) { m.capturingAction = action.id }
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text(L("Keyboard (on the Mac)"))
                }
                Section {
                    ForEach(Controls.padButtons, id: \.self) { button in
                        Picker(Controls.label(button), selection: Binding(get: { m.controls.padTarget(of: button) }, set: { m.controls.assign(pad: button, to: $0); m.saveControls() })) {
                            ForEach(Controls.padButtons, id: \.self) { Text(Controls.label($0)).tag($0) }
                        }
                    }
                } header: {
                    Text(L("Controller: what each button presses"))
                } footer: {
                    Text(L("An iPhone game gets these when it is built. A Mac game gets them at its next start."))
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button(L("Reset")) { m.resetControls() }
                Spacer()
                Button(L("Done")) { m.capturingAction = nil; m.showControls = false }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 460, height: 560)
        .background(KeyCatcher(active: m.capturingAction != nil) { m.assignKey($0) })
    }
}

// Takes the next key press while the controls wait for one, so it does not reach the window's own shortcuts
struct KeyCatcher: NSViewRepresentable {
    let active: Bool
    let onKey: (Int) -> Void

    final class Coordinator { var monitor: Any? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        if let m = context.coordinator.monitor { NSEvent.removeMonitor(m); context.coordinator.monitor = nil }
        guard active else { return }
        let onKey = onKey
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in onKey(Int(e.keyCode)); return nil }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { if let m = coordinator.monitor { NSEvent.removeMonitor(m) } }
}

// What a finished build leaves behind, offered once: to the Trash only when the player asks
struct CleanupPanel: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !m.cleanup.isEmpty {
                Text(L("Free up space")).font(.title3.weight(.semibold))
                ForEach(m.cleanup) { item in
                    Toggle(isOn: Binding(get: { item.selected }, set: { on in if let i = m.cleanup.firstIndex(where: { $0.id == item.id }) { m.cleanup[i].selected = on } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("%@ (%@)", item.title, formatBytes(Double(item.bytes))))
                            Text(item.detail).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                Button(L("Move to Trash")) { m.moveCleanupToTrash() }.disabled(!m.cleanup.contains { $0.selected })
            }
            if m.cleanupDone {
                Label(L("Moved to the Trash. Empty the Trash to free the space."), systemImage: "trash").foregroundStyle(.secondary)
            }
            if m.options.target == .macApp, !m.cleanup.isEmpty {
                Text(L("If you will not build more games, you can also delete Xcode from Applications yourself: it takes many gigabytes.")).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// A game already on the iPhone: when its signature ends, and how to renew it without building the game again
struct InstalledPanel: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        if let r = m.installRecord {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("On %@", r.deviceName)).font(.title2.weight(.semibold))
                if let e = r.expires {
                    let when = e.formatted(date: .abbreviated, time: .shortened)
                    Label(e < Date() ? L("The signature ended on %@: reinstall to play.", when) : L("Works until %@.", when),
                          systemImage: e < Date() ? "exclamationmark.triangle.fill" : "clock")
                        .foregroundStyle(e < Date() ? Color.orange : Color.secondary)
                }
                if r.limitedMemory {
                    Label(L("Without Increased Memory Limit: iOS may close bigger games."), systemImage: "memorychip").foregroundStyle(.secondary).font(.callout)
                }
                HStack {
                    Button(L("Reinstall")) { m.reinstall() }.disabled(m.selectedDevice == nil || m.team == nil)
                    Button(L("Copy Game Files Again")) { m.copyGameFilesAgain() }.disabled(m.selectedDevice == nil)
                        .help(L("Only after deleting the app from the iPhone, which deletes its game files and saves too."))
                }
                Text(L("Reinstalling keeps your saves. Deleting the app from the iPhone does not.")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

// The default view of this Mac: what the player has to do, in words, and one button for all the app can do itself. No commands, and the tools go by one name.
struct SimpleEnvironmentPanel: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Getting this Mac ready")).font(.title2.weight(.semibold))
            if let step = m.installingStep {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(step).fontWeight(.medium) }
                Text(L("No password is needed. This can take several minutes, and you can use your Mac meanwhile.")).font(.callout).foregroundStyle(.secondary)
            } else if let env = m.env {
                let tools = env.items.filter { !$0.ok && $0.helper }
                let steps = (env.problems + env.warnings).filter { !$0.helper && $0.id != "python-optional" }
                if tools.isEmpty, steps.isEmpty {
                    Label(L("This Mac is ready."), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                ForEach(steps) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        EnvRow(item: item)
                        if item.terminal { Button(L("Install Homebrew")) { m.installEverything() }.buttonStyle(.borderedProminent) }
                    }
                }
                if !tools.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(L("Free tools"), systemImage: "wrench.and.screwdriver").fontWeight(.medium)
                        Text(L("The app installs these by itself: %@.", tools.map(\.title).joined(separator: ", "))).font(.callout).foregroundStyle(.secondary)
                        if !env.needsTerminal, !env.fixSteps.isEmpty {
                            Button(L("Install Everything")) { m.installEverything() }.buttonStyle(.borderedProminent).controlSize(.large)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Checking this Mac…")).foregroundStyle(.secondary) }
            }
        }
    }
}

struct EnvironmentPanel: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("This Mac")).font(.title2.weight(.semibold))
                if m.checkingEnv { ProgressView().controlSize(.small) }
                Spacer()
                Button(L("Check Again")) { m.checkEnvironment(force: true) }.disabled(m.checkingEnv || m.isInstallingTools)
            }
            if let step = m.installingStep {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(step).fontWeight(.medium) }
            }
            if let env = m.env {
                let wrong = env.problems + env.warnings
                if wrong.isEmpty {
                    Label(L("Everything a build needs is installed."), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                ForEach(wrong) { EnvRow(item: $0, showsCommand: true) }
                if !env.fixes.isEmpty {
                    HStack(spacing: 8) {
                        if !env.needsTerminal {
                            Button(L("Install Everything")) { m.installEverything() }.buttonStyle(.borderedProminent)
                        }
                        Button(L("Install in Terminal")) { m.runFixes() }
                        Text(L("Runs %@ above.", "\(env.fixes.count)")).font(.callout).foregroundStyle(.secondary)
                    }
                    .disabled(m.isInstallingTools)
                }
                if env.items.first(where: { $0.id == "python" })?.ok == false {
                    Button(L("Use Another Python…")) { Panels.choosePython(m) }
                }
                if !env.problems.isEmpty {
                    Toggle(L("Build anyway"), isOn: $m.buildAnyway)
                        .help(L("The script checks again when it starts, and stops with the reason."))
                }
                let good = env.items.filter(\.ok)
                if !good.isEmpty {
                    DisclosureGroup(L("Installed (%@)", "\(good.count)"), isExpanded: $m.showInstalled) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(good) { item in
                                Label {
                                    Text(item.title) + Text(item.detail.isEmpty ? "" : "  \(item.detail)").foregroundStyle(.secondary)
                                } icon: {
                                    Image(systemName: "checkmark").foregroundStyle(.green)
                                }
                                .font(.callout)
                            }
                        }
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if !m.checkingEnv {
                Text(L("Choose the nxnative folder to check this Mac.")).foregroundStyle(.secondary)
            }
        }
    }
}

struct EnvRow: View {
    let item: EnvItem
    var showsCommand = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(item.title, systemImage: item.optional ? "info.circle" : "xmark.circle.fill")
                .foregroundStyle(item.optional ? Color.secondary : Color.red)
                .fontWeight(.medium)
            if !item.detail.isEmpty { Text(item.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            if showsCommand, let fix = item.fix {
                Text(fix).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
            }
            if let link = item.link { Link(item.linkTitle, destination: link).font(.callout) }
        }
    }
}

struct BuildView: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        VStack(spacing: 0) {
            header.padding(24)
            Divider()
            if m.phase == .finished, !m.advancedMode {
                ScrollView { CleanupPanel() }
            } else {
                VSplitView {
                    StageList().frame(minHeight: 120, maxHeight: .infinity)
                    if m.advancedMode, m.showLog || isFailed { LogView().frame(minHeight: 120, maxHeight: .infinity) }
                    if m.advancedMode, m.phase == .finished { ScrollView { CleanupPanel() }.frame(minHeight: 120) }
                }
            }
            Divider()
            footer.padding(16)
        }
    }

    private var isFailed: Bool { if case .failed = m.phase { return true }; return false }

    @ViewBuilder private var header: some View {
        switch m.phase {
        case .finished:
            if let r = m.installed {
                let until = r.expires.map { L("It works until %@. Reinstall from here to renew it; saves stay.", $0.formatted(date: .abbreviated, time: .shortened)) } ?? ""
                Banner(icon: "checkmark.circle.fill", color: .green, title: L("%@ is on %@", m.gameName, r.deviceName),
                       text: L("First time: on the iPhone, go to Settings → General → VPN & Device Management and trust your Apple ID, then open the game from the Home Screen."),
                       detail: until + (r.limitedMemory ? " " + L("Built without Increased Memory Limit, which this Apple ID cannot give: iOS may close bigger games.") : ""))
            } else {
                Banner(icon: "checkmark.circle.fill", color: .green, title: L("%@ is ready", m.gameName),
                       text: m.outputURL?.path ?? "", detail: m.options.target == .ios ? L("Install the IPA with a sideloading tool such as AltStore, Sideloadly or LiveContainer. Turn on Increased Memory Limit if the tool offers it.") : "")
            }
        case let .failed(why):
            Banner(icon: "xmark.octagon.fill", color: .red, title: L("The build stopped"), text: why,
                   detail: m.advancedMode ? "" : L("Press Try Again. If it stops again, press Copy Details and send the text to whoever helps you."))
        case .cancelled:
            Banner(icon: "stop.circle.fill", color: .secondary, title: L("Build cancelled"), text: L("What was finished is kept: the next build goes on from there."), detail: "")
        default:
            LiveHeader()
        }
    }

    private var footer: some View {
        HStack {
            if m.advancedMode {
                Toggle(L("Show messages"), isOn: $m.showLog).toggleStyle(.checkbox).disabled(isFailed)
            } else if isFailed {
                Button(L("Copy Details")) { m.copyLog() }
            }
            Spacer()
            if m.advancedMode { Button(L("Open Logs")) { m.openLogs() } }
            switch m.phase {
            case .building:
                Button(m.cancelling ? L("Stopping…") : L("Cancel Build"), role: .cancel) { m.cancelBuild() }
                    .disabled(m.cancelling)
                    .keyboardShortcut(".")
            case .finished:
                Button(L("Back")) { m.backToSetup() }
                if m.installed == nil { Button(L("Show in Finder")) { m.revealOutput() }.disabled(m.outputURL == nil) }
                if m.options.target == .macApp, let u = m.outputURL {
                    Button(L("Play")) { NSWorkspace.shared.open(u) }.buttonStyle(.borderedProminent)
                }
            default:
                Button(L("Back")) { m.backToSetup() }
                Button(m.advancedMode ? L("Build Again") : L("Try Again")) { m.startBuild() }.buttonStyle(.borderedProminent).disabled(m.blocker != nil)
            }
        }
    }
}

struct Banner: View {
    let icon: String, color: Color, title: String, text: String, detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.semibold))
                if !text.isEmpty { Text(text).textSelection(.enabled).lineLimit(8) }
                if !detail.isEmpty { Text(detail).font(.callout).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
    }
}

struct LiveHeader: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        let t = m.transcript
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(m.gameName).font(.title2.weight(.semibold)).lineLimit(1)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { c in
                    Text(formatDuration(c.date.timeIntervalSince(m.startedAt))).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if let s = t.current {
                let name = m.stageName(s.name)
                Text(t.stageCount > 0 ? L("Stage %@ of %@: %@", "\(s.k)", "\(t.stageCount)", name) : name).fontWeight(.medium)
                if let f = t.live?.fraction { ProgressView(value: f) } else { ProgressView().progressViewStyle(.linear) }
                HStack {
                    Text(detail(s, t.live)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if let eta = t.live?.eta, eta >= 1 { Text(L("about %@ left in this stage", formatDuration(eta))).monospacedDigit() }
                }
                .font(.callout).foregroundStyle(.secondary)
            } else {
                Text(L("Starting…")).fontWeight(.medium)
                ProgressView().progressViewStyle(.linear)
            }
        }
    }

    // The script's step names its tools, which say nothing to someone who does not know them
    private func detail(_ s: StageRow, _ p: LiveProgress?) -> String {
        [m.advancedMode || !s.fromScript ? s.step : "", p.map(formatCount) ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct StageList: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        List(m.transcript.stages) { s in
            HStack(spacing: 10) {
                icon(s.state).frame(width: 18)
                Text(m.stageName(s.name)).fontWeight(s.state == .running ? .medium : .regular)
                if m.advancedMode || !s.fromScript, !s.summary.isEmpty { Text(s.summary).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                Spacer()
                if s.state != .running { Text(formatDuration(s.elapsed)).monospacedDigit().foregroundStyle(.secondary) }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder private func icon(_ state: StageRow.State) -> some View {
        switch state {
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel(L("Done"))
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red).accessibilityLabel(L("Failed"))
        }
    }
}

struct LogView: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(m.transcript.lines) { line in
                            Text(line.text)
                                .foregroundStyle(line.isError ? Color.red : Color.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                }
                .onChange(of: m.transcript.lines.last?.id) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .bottom) }
                }
                .onAppear {
                    if let id = m.transcript.lines.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            Button(L("Copy Messages")) { m.copyLog() }
                .buttonStyle(.link).font(.caption)
                .padding(.horizontal, 10).padding(.bottom, 6)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
