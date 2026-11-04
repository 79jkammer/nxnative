// Slotless's install over a cable, without any UI: what devicectl says about a connected iPhone, the Apple team Xcode knows, the arguments of xcodebuild, and what its failures mean.
// A free Apple ID is enough for this: Xcode signs the app for this one device, for 7 days. The player starts every install from the window (BuilderModel.installOnDevice); docs/development.md, Slotless.
import Foundation

struct ConnectedDevice: Identifiable, Equatable {
    let id: String   // the UDID
    let name: String
    let model: String
    let productType: String
    let developerMode: Bool?   // nil when devicectl does not say
    let wired: Bool

    // README.md, Games: an iPhone 15 Pro (iPhone16,1) or newer, for the BC-compressed textures. nil for an iPad, whose product type does not tell its chip.
    var supported: Bool? {
        guard productType.hasPrefix("iPhone"), let major = Int(productType.dropFirst(6).prefix { $0 != "," }) else { return nil }
        return major >= 16
    }
}

enum DeviceList {
    // devicectl's --json-output: the newer properties.* where they are, else the fields it marks as deprecated.
    static func parse(_ data: Data) -> [ConnectedDevice] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let result = o["result"] as? [String: Any], let list = result["devices"] as? [[String: Any]] else { return [] }
        let found = list.compactMap { d -> ConnectedDevice? in
            let p = d["properties"] as? [String: Any] ?? [:]
            func group(_ new: String, _ old: String) -> [String: Any] { (p[new] as? [String: Any] ?? [:]).merging(d[old] as? [String: Any] ?? [:]) { a, _ in a } }
            let hw = group("hardware", "hardwareProperties"), conn = group("connection", "connectionProperties"), dev = group("device", "deviceProperties")
            guard hw["platform"] as? String == "iOS", hw["reality"] as? String == "physical", let udid = hw["udid"] as? String else { return nil }
            guard conn["state"] as? String == "connected" || conn["tunnelState"] as? String == "connected" else { return nil }
            return ConnectedDevice(id: udid, name: dev["name"] as? String ?? "iPhone", model: hw["marketingName"] as? String ?? "", productType: hw["productType"] as? String ?? "",
                                   developerMode: (dev["developerModeStatus"] as? String).map { $0 == "enabled" }, wired: conn["transportType"] as? String == "wired")
        }
        return found.sorted { ($0.wired ? 0 : 1, $0.name) < ($1.wired ? 0 : 1, $1.name) }
    }

    static func current() -> [ConnectedDevice] {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("nxnative-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: out) }
        guard Host.run(Host.tool("xcrun"), ["devicectl", "list", "devices", "--quiet", "--json-output", out.path], timeout: 20)?.code == 0, let d = try? Data(contentsOf: out) else { return [] }
        return parse(d)
    }
}

struct AppleTeam: Equatable {
    let id: String
    let name: String
    let isFree: Bool
}

// What Xcode's own settings say about the player's Apple accounts. The account's name is never read out of them: only whether there is one, and its teams.
enum AppleAccount {
    static func hasAccount(_ prefs: [String: Any]) -> Bool {
        guard let lists = prefs["DVTDeveloperAccountManagerAppleIDLists"] as? [String: Any] else { return false }
        return lists.values.contains { ($0 as? [Any])?.isEmpty == false }
    }

    // Older Xcodes list the teams under IDEProvisioningTeamByIdentifier or IDEProvisioningTeams; a free one first, as that is what this app is for. Xcode 27 keeps no such key: see certificateTeam.
    static func teams(_ prefs: [String: Any]) -> [AppleTeam] {
        var found: [AppleTeam] = []
        func walk(_ v: Any) {
            if let d = v as? [String: Any] {
                if let id = d["teamID"] as? String, !id.isEmpty {
                    let free = (d["isFreeProvisioningTeam"] as? NSNumber)?.boolValue ?? false
                    if !found.contains(where: { $0.id == id }) { found.append(AppleTeam(id: id, name: d["teamName"] as? String ?? id, isFree: free)) }
                } else { d.values.forEach(walk) }
            } else if let a = v as? [Any] { a.forEach(walk) }
        }
        ["IDEProvisioningTeamByIdentifier", "IDEProvisioningTeams"].compactMap { prefs[$0] }.forEach(walk)
        return found.sorted { ($0.isFree ? 0 : 1, $0.id) < ($1.isFree ? 0 : 1, $1.id) }
    }

    // The team in an Apple Development certificate's subject: its OU. The (…) in its common name is the certificate's own ID, not the team, and the name is the player's, so neither is read.
    static func certificateTeam(subject: String) -> String? {
        guard let r = subject.range(of: #"(^|[/,\s])OU\s*=\s*[A-Z0-9]{10}($|[/,\s])"#, options: .regularExpression) else { return nil }
        return subject[r].components(separatedBy: "=").last?.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    // Each valid Apple Development certificate in the keychain, read with no prompt: certificates are not secret, their private keys are.
    private static func certificateTeams() -> [AppleTeam] {
        guard let pem = Host.run(Host.tool("security"), ["find-certificate", "-a", "-c", "Apple Development", "-p"], timeout: 15)?.out else { return [] }
        var found: [AppleTeam] = []
        for part in pem.components(separatedBy: "-----END CERTIFICATE-----") where part.contains("BEGIN CERTIFICATE") {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("nxnative-cert-\(UUID().uuidString).pem")
            defer { try? FileManager.default.removeItem(at: file) }
            guard (try? (part + "-----END CERTIFICATE-----\n").write(to: file, atomically: true, encoding: .utf8)) != nil else { continue }
            guard let r = Host.run("/usr/bin/openssl", ["x509", "-in", file.path, "-noout", "-subject", "-checkend", "0"], timeout: 10), r.code == 0,
                  let id = certificateTeam(subject: r.out), !found.contains(where: { $0.id == id }) else { continue }
            found.append(AppleTeam(id: id, name: id, isFree: false))
        }
        return found
    }

    static func current() -> (hasAccount: Bool, teams: [AppleTeam]) {
        let prefs = UserDefaults(suiteName: "com.apple.dt.Xcode")?.dictionaryRepresentation() ?? [:]
        let listed = teams(prefs)
        return (hasAccount(prefs), listed.isEmpty ? certificateTeams() : listed)
    }
}

// One game installed on a device: what a reinstall needs, and when its signature ends.
struct DeviceInstallRecord: Codable, Equatable {
    var project: String
    var scheme: String
    var bundleID: String
    var deviceName: String
    var expires: Date?
    var limitedMemory: Bool
    var imageStamp: String?   // the game files last copied to the phone
}

enum XcodeInstall {
    // A free team's App IDs are unique across all of Apple: org.nxnative.<title ID> can be someone else's, and this one is the player's own. It stays the same, so a reinstall keeps the app and its saves.
    static func bundleID(team: String, title: UInt64) -> String { "org.nxnative.u\(team.lowercased()).\(GameScan.hex(title).lowercased())" }

    // CODE_SIGN_ENTITLEMENTS= overrides the project's Gen/dm.xcconfig, which asks for Increased Memory Limit: for an account that cannot get it, with no need to prepare the project again.
    static func arguments(project: String, scheme: String, device: String, team: String, derivedData: String, limitedMemory: Bool) -> [String] {
        ["-project", project, "-scheme", scheme, "-configuration", "Release", "-destination", "id=\(device)", "-derivedDataPath", derivedData,
         "-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration", "DEVELOPMENT_TEAM=\(team)", "CODE_SIGN_STYLE=Automatic"] + (limitedMemory ? ["CODE_SIGN_ENTITLEMENTS="] : [])
    }

    // xcodebuild -list -json: the game's scheme is named "<game name> (<title ID>)" (build_ipa.sh)
    static func scheme(listJSON: Data, title: UInt64?) -> String? {
        guard let o = (try? JSONSerialization.jsonObject(with: listJSON)) as? [String: Any], let p = o["project"] as? [String: Any], let schemes = p["schemes"] as? [String] else { return nil }
        if let title, let s = schemes.first(where: { $0.contains(GameScan.hex(title)) }) { return s }
        return schemes.first { $0.hasSuffix(")") } ?? schemes.first
    }

    // xcodebuild -showBuildSettings -json
    static func appPath(settingsJSON: Data) -> String? {
        guard let a = (try? JSONSerialization.jsonObject(with: settingsJSON)) as? [[String: Any]] else { return nil }
        for t in a {
            guard let s = t["buildSettings"] as? [String: Any], let dir = s["TARGET_BUILD_DIR"] as? String, let name = s["FULL_PRODUCT_NAME"] as? String, name.hasSuffix(".app") else { continue }
            return dir + "/" + name
        }
        return nil
    }

    // The decoded embedded.mobileprovision (security cms -D)
    static func expiry(profilePlist: Data) -> Date? {
        (try? PropertyListSerialization.propertyList(from: profilePlist, format: nil) as? [String: Any])?["ExpirationDate"] as? Date
    }
}

enum InstallFailure: Equatable {
    case memoryCapability, noAccount, bundleID, appLimit, deviceLocked, developerMode, other(String)

    static func classify(_ lines: [String]) -> InstallFailure {
        let text = lines.joined(separator: "\n").lowercased()
        func has(_ s: String...) -> Bool { s.allSatisfy { text.contains($0) } }
        if has("increased-memory-limit") || has("increased memory limit") || (has("do not support the") && has("capability")) { return .memoryCapability }
        if has("no accounts") || has("no account for team") || has("session has expired") || has("sign in with your apple") { return .noAccount }
        if has("maximum app id") || has("maximum number of") || has("app id limit") || has("too many") && has("app") { return .appLimit }
        if has("cannot be registered") || has("bundle identifier") && has("not available") { return .bundleID }
        if has("developer mode") { return .developerMode }
        if has("is locked") || has("passcode") || has("unlock") { return .deviceLocked }
        let errors = lines.filter { $0.contains("error:") || $0.hasPrefix("ERROR") }
        return .other(errors.prefix(4).joined(separator: "\n"))
    }

    var message: String {
        switch self {
        case .memoryCapability: return L("This account cannot give the app Increased Memory Limit.")
        case .noAccount: return L("Xcode has no working Apple ID for this team. Add it in Xcode → Settings → Apple Accounts, then try again.")
        case .bundleID: return L("Apple refuses this bundle ID. Enter another one under Advanced, then build again.")
        case .appLimit: return L("This free Apple ID reached Apple's limit of apps. Delete an app signed with it from the iPhone, or wait up to 7 days.")
        case .deviceLocked: return L("Unlock the iPhone and keep it unlocked, then try again.")
        case .developerMode: return L("Turn on Developer Mode on the iPhone: Settings → Privacy & Security → Developer Mode, then restart it.")
        case let .other(text): return text.isEmpty ? L("The step failed: its log is in the game's logs folder.") : text
        }
    }
}
