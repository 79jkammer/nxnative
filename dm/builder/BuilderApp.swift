// NXNative Builder: a Mac app that turns a game the player owns into an IPA or a Mac app with the NSP script, without a terminal. The left side sets up the build, the right side shows what
// stands in its way, then its progress and result. Built by scripts/build_builder_app.py; docs/development.md, NXNative Builder.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct BuilderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = BuilderModel()

    var body: some Scene {
        Window("NXNative Builder", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 620)
                .onAppear {
                    delegate.model = model
                    NSApp.applicationIconImage = AppIcon.make()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    if model.phase == .setup { model.checkEnvironment() }
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Game…") { Panels.chooseGame(model) }.keyboardShortcut("o")
                Button("Choose Keys…") { Panels.chooseKeys(model) }.keyboardShortcut("k")
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy Build Command") { model.copyCommand() }.disabled(model.game == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: BuilderModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        guard let model = MainActor.assumeIsolated({ model }), MainActor.assumeIsolated({ model.isBuilding }) else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop the build and quit?"
        alert.informativeText = "What the build has finished so far is kept, so the next build goes on from there."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Keep Building")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        MainActor.assumeIsolated { model.cancelBuild { NSApp.reply(toApplicationShouldTerminate: true) } }
        return .terminateLater
    }
}

enum AppIcon {
    static func make() -> NSImage {
        NSImage(size: NSSize(width: 512, height: 512), flipped: false) { r in
            let shape = NSBezierPath(roundedRect: r.insetBy(dx: 40, dy: 40), xRadius: 96, yRadius: 96)
            NSGradient(starting: NSColor(red: 0.93, green: 0.20, blue: 0.24, alpha: 1), ending: NSColor(red: 0.66, green: 0.07, blue: 0.20, alpha: 1))?.draw(in: shape, angle: -90)
            let config = NSImage.SymbolConfiguration(pointSize: 230, weight: .medium).applying(.init(paletteColors: [.white]))
            if let s = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                s.draw(in: NSRect(x: (r.width - s.size.width) / 2, y: (r.height - s.size.height) / 2, width: s.size.width, height: s.size.height))
            }
            return true
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
        if let u = pick("Choose your game's folder, or one of its .nsp, .nsz, .xci or .xcz files.", files: true, folders: true) { _ = m.accept([u]) }
    }

    static func chooseKeys(_ m: BuilderModel) {
        if let u = pick("Choose the prod.keys from your console.", files: true, folders: false) { m.setKeys(u) }
    }

    static func chooseRepo(_ m: BuilderModel) {
        if let u = pick("Choose your nxnative folder.", files: false, folders: true) { m.setRepo(u) }
    }

    static func choosePython(_ m: BuilderModel) {
        let p = NSOpenPanel()
        p.message = "Choose a Python 3.12 or newer."
        p.canChooseDirectories = false
        p.treatsFilePackagesAsDirectories = true
        p.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if p.runModal() == .OK, let u = p.url { m.setPython(u) }
    }

    static func chooseFolder(_ title: String) -> String? { pick(title, files: false, folders: true)?.path }

    static func chooseOutput(_ m: BuilderModel) -> String? {
        let p = NSSavePanel()
        p.message = "Where should the finished \(m.options.target == .ios ? "IPA" : "app") go?"
        p.nameFieldStringValue = m.gameName + (m.options.target == .ios ? ".ipa" : ".app")
        return p.runModal() == .OK ? p.url?.path : nil
    }
}

// MARK: - The window

struct RootView: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        HStack(spacing: 0) {
            SetupPane()
                .frame(width: 420)
                .disabled(m.isBuilding)
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
        .alert("NXNative Builder", isPresented: Binding(get: { m.notice != nil }, set: { if !$0 { m.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(m.notice ?? "")
        }
    }
}

// MARK: - Setup

struct SetupPane: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        Form {
            if m.repo == nil {
                Section {
                    LabeledContent("nxnative folder") { Button("Choose…") { Panels.chooseRepo(m) } }
                } footer: {
                    Text("This app runs the build script from your nxnative checkout.")
                }
            }
            Section("Game") { GameCard() }
            if m.game?.isDump != true {
                Section("Keys") { KeysRow() }
            }
            Section("Build for") {
                Picker("Build for", selection: Binding(get: { m.options.target }, set: { m.setTarget($0) })) {
                    ForEach(BuildTarget.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(m.options.target == .ios
                     ? "An IPA to sideload with AltStore, Sideloadly or LiveContainer. Needs an iPhone 15 Pro or newer, or an iPad with an M1 or later."
                     : "An app of the game to open from Finder on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if m.game != nil { optionsSection }
            advancedSection
        }
        .formStyle(.grouped)
    }

    private var optionsSection: some View {
        Section("Options") {
            if let game = m.game, game.titles.count > 1 {
                Picker("Game", selection: $m.options.titleID) {
                    Text("Choose…").tag("")
                    ForEach(game.titles, id: \.self) { t in
                        Text(GameProfile.load(repo: m.repo ?? game.url, title: t)?.name ?? GameScan.hex(t)).tag(GameScan.hex(t))
                    }
                }
            }
            if let game = m.game, game.versions.count > 1 {
                Picker("Version", selection: $m.options.package) {
                    Text("Newest").tag("")
                    ForEach(game.versions.reversed(), id: \.self) { v in
                        Text(m.profile?.displayVersions[v].map { "\($0) (v\(v))" } ?? "v\(v)").tag("v\(v)")
                    }
                }
            }
            Picker("Language", selection: $m.options.language) {
                ForEach(Language.all, id: \.0) { Text($0.1).tag($0.0) }
            }
            TextField("App name", text: $m.options.appName, prompt: Text("The game's name"))
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced", isExpanded: $m.showAdvanced) {
                if m.options.target == .ios {
                    Toggle("Keep game files out of the IPA", isOn: $m.options.romfsSeparate)
                        .help("For a game too big to install: the IPA is small, and the game files are copied to the phone once, with the command shown at the end of the build.")
                    Toggle("Show the frame rate", isOn: $m.options.showFPS)
                } else {
                    TextField("Signing identity", text: $m.options.macSign, prompt: Text("Ad-hoc"))
                }
                Toggle("Motion controls", isOn: $m.options.motion)
                Toggle("Keep extracted files for the next build", isOn: $m.options.keepExtracted)
                TextField("Bundle ID", text: $m.options.bundleID, prompt: Text("org.nxnative.<title ID>"))
                TextField("GPU archives", text: $m.options.gpu, prompt: Text("From the game's profile"))
                    .help("GPU architectures to make a pipeline archive for, comma-separated (g18p), or none.")
                PathRow(title: "Output", path: $m.options.output, prompt: "Next to the game") { Panels.chooseOutput(m) }
                PathRow(title: "Build folder", path: $m.options.workDir, prompt: "In the game's folder") { Panels.chooseFolder("Choose this game's build folder.") }
                Toggle("Allow a damaged package", isOn: $m.options.allowDamaged)
                    .help("Files that fail the hash check are packed as they were read, instead of stopping. Usually a broken copy: dump the game again first.")
                Toggle("Allow failed shaders", isOn: $m.options.allowShaderRegressions)
                    .help("Shaders that built before and fail now are left out, instead of stopping.")
                Toggle("Allow another Metal compiler", isOn: Binding(get: { m.options.allowOtherMetal }, set: { m.options.allowOtherMetal = $0; m.checkEnvironment(force: true) }))
                    .help("Build shaders with this Mac's compiler when it is not Xcode 27.2's. They can render wrong pictures.")
                Toggle("Use a provisional profile", isOn: $m.options.provisional)
                    .help("Guess the game's settings even though it has a profile, to test the guesses.")
                Button("Copy Build Command") { m.copyCommand() }.disabled(m.game == nil)
            }
        }
    }
}

enum Language {
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
                        .accessibilityLabel("Reset \(title)")
                }
                Button("Choose…") { if let p = choose() { path = p } }
            }
        }
    }
}

struct GameCard: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        if m.scanning {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Reading the game folder…").foregroundStyle(.secondary) }
        } else if let game = m.game {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(m.gameName).font(.headline).lineLimit(2)
                    Spacer()
                    Button("Change…") { Panels.chooseGame(m) }
                }
                Text((game.url.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let t = m.selectedTitle { profileStatus(t) }
                if game.isDump {
                    Text("A folder of the game's files, \(formatBytes(Double(game.bytes)))" + (game.versions.isEmpty ? "" : ", with \(game.versions.count) update\(game.versions.count == 1 ? "" : "s")") + ".")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(game.packages) { packageRow($0) }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down").font(.title).foregroundStyle(.secondary).accessibilityHidden(true)
                Text("Drop your game here").font(.headline)
                Text("Its folder with the game, update and DLC (.nsp, .nsz, .xci or .xcz), or one of those files.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Choose…") { Panels.chooseGame(m) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            if let e = m.gameError { Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout) }
        }
    }

    @ViewBuilder private func profileStatus(_ t: UInt64) -> some View {
        if m.profile != nil {
            Label("Supported · \(GameScan.hex(t))", systemImage: "checkmark.seal.fill").font(.callout).foregroundStyle(.green)
        } else {
            Label("No profile for \(GameScan.hex(t)): settings are guessed, and the build may not start.", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
        }
    }

    private func packageRow(_ p: GamePackage) -> some View {
        HStack(spacing: 6) {
            Text(p.holdsSeveral ? "All-in-one" : p.kind.rawValue).font(.caption.weight(.semibold))
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
            Button(m.options.keys == nil ? "Choose…" : "Change…") { Panels.chooseKeys(m) }
        } label: {
            if let keys = m.options.keys {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(keys.lastPathComponent)
                        Text((keys.path as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                } icon: {
                    Image(systemName: m.keysProblem == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(m.keysProblem == nil ? Color.green : Color.orange)
                }
            } else {
                Text("prod.keys").foregroundStyle(.secondary)
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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EnvironmentPanel()
                    if let s = m.spaceProblem {
                        Label(s, systemImage: "externaldrive.badge.exclamationmark").foregroundStyle(.orange)
                    }
                    Text("A first build takes 30–60 minutes and needs about twice the game's size plus 10 GB free. Building again is much faster.")
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
                    Text("Build").frame(minWidth: 90)
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

struct EnvironmentPanel: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This Mac").font(.title2.weight(.semibold))
                if m.checkingEnv { ProgressView().controlSize(.small) }
                Spacer()
                Button("Check Again") { m.checkEnvironment(force: true) }.disabled(m.checkingEnv)
            }
            if let env = m.env {
                let wrong = env.problems + env.warnings
                if wrong.isEmpty {
                    Label("Everything a build needs is installed.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                ForEach(wrong) { EnvRow(item: $0) }
                if !env.fixes.isEmpty {
                    HStack(spacing: 8) {
                        Button("Install in Terminal") { m.runFixes() }.buttonStyle(.borderedProminent)
                        Text("Runs \(env.fixes.count == 1 ? "the command" : "the \(env.fixes.count) commands") above.").font(.callout).foregroundStyle(.secondary)
                    }
                }
                if env.items.first(where: { $0.id == "python" })?.ok == false {
                    Button("Use Another Python…") { Panels.choosePython(m) }
                }
                if !env.problems.isEmpty {
                    Toggle("Build anyway", isOn: $m.buildAnyway)
                        .help("The script checks again when it starts, and stops with the reason.")
                }
                let good = env.items.filter(\.ok)
                if !good.isEmpty {
                    DisclosureGroup("Installed (\(good.count))", isExpanded: $m.showInstalled) {
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
                Text("Choose the nxnative folder to check this Mac.").foregroundStyle(.secondary)
            }
        }
    }
}

struct EnvRow: View {
    let item: EnvItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(item.title, systemImage: item.optional ? "info.circle" : "xmark.circle.fill")
                .foregroundStyle(item.optional ? Color.secondary : Color.red)
                .fontWeight(.medium)
            if !item.detail.isEmpty { Text(item.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            if let fix = item.fix {
                Text(fix).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
            }
            if let link = item.link { Link("Open the download page", destination: link).font(.callout) }
        }
    }
}

struct BuildView: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        VStack(spacing: 0) {
            header.padding(24)
            Divider()
            VSplitView {
                StageList().frame(minHeight: 120, maxHeight: .infinity)
                if m.showLog || isFailed { LogView().frame(minHeight: 120, maxHeight: .infinity) }
            }
            Divider()
            footer.padding(16)
        }
    }

    private var isFailed: Bool { if case .failed = m.phase { return true }; return false }

    @ViewBuilder private var header: some View {
        switch m.phase {
        case .finished:
            Banner(icon: "checkmark.circle.fill", color: .green, title: "\(m.gameName) is ready",
                   text: m.outputURL?.path ?? "", detail: m.options.target == .ios ? "Install the IPA with a sideloading tool such as AltStore, Sideloadly or LiveContainer. Turn on Increased Memory Limit if the tool offers it." : "")
        case let .failed(why):
            Banner(icon: "xmark.octagon.fill", color: .red, title: "The build stopped", text: why, detail: "")
        case .cancelled:
            Banner(icon: "stop.circle.fill", color: .secondary, title: "Build cancelled", text: "What was finished is kept: the next build goes on from there.", detail: "")
        default:
            LiveHeader()
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Show messages", isOn: $m.showLog).toggleStyle(.checkbox).disabled(isFailed)
            Spacer()
            Button("Open Logs") { m.openLogs() }
            switch m.phase {
            case .building:
                Button(m.cancelling ? "Stopping…" : "Cancel Build", role: .cancel) { m.cancelBuild() }
                    .disabled(m.cancelling)
                    .keyboardShortcut(".")
            case .finished:
                Button("Back") { m.backToSetup() }
                Button("Show in Finder") { m.revealOutput() }.disabled(m.outputURL == nil)
                if m.options.target == .macApp, let u = m.outputURL {
                    Button("Play") { NSWorkspace.shared.open(u) }.buttonStyle(.borderedProminent)
                }
            default:
                Button("Back") { m.backToSetup() }
                Button("Build Again") { m.startBuild() }.buttonStyle(.borderedProminent).disabled(m.blocker != nil)
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
                Text(t.stageCount > 0 ? "Stage \(s.k) of \(t.stageCount): \(s.name)" : s.name).fontWeight(.medium)
                if let f = t.live?.fraction { ProgressView(value: f) } else { ProgressView().progressViewStyle(.linear) }
                HStack {
                    Text(detail(s, t.live)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if let eta = t.live?.eta, eta >= 1 { Text("about \(formatDuration(eta)) left in this stage").monospacedDigit() }
                }
                .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Starting…").fontWeight(.medium)
                ProgressView().progressViewStyle(.linear)
            }
        }
    }

    private func detail(_ s: StageRow, _ p: LiveProgress?) -> String {
        [s.step, p.map(formatCount) ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct StageList: View {
    @EnvironmentObject private var m: BuilderModel

    var body: some View {
        List(m.transcript.stages) { s in
            HStack(spacing: 10) {
                icon(s.state).frame(width: 18)
                Text(s.name).fontWeight(s.state == .running ? .medium : .regular)
                if !s.summary.isEmpty { Text(s.summary).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                Spacer()
                if s.state != .running { Text(formatDuration(s.elapsed)).monospacedDigit().foregroundStyle(.secondary) }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder private func icon(_ state: StageRow.State) -> some View {
        switch state {
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Done")
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red).accessibilityLabel("Failed")
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
            Button("Copy Messages") { m.copyLog() }
                .buttonStyle(.link).font(.caption)
                .padding(.horizontal, 10).padding(.bottom, 6)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
