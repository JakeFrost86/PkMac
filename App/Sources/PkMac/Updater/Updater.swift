import Foundation
import AppKit
import Observation

/// Three update channels, all from inside the app:
///  1. PKHeX.Core      – newest DLL straight from NuGet, hot-swapped into a copy of the engine
///  2. Engine pack     – engine + plugins rebuilt by GitHub Actions (when a plugin or the core API changes)
///  3. App             – the whole PkMac.app from GitHub Releases
/// Every engine change is self-tested before activation; on failure the current version stays.
@MainActor
@Observable
final class Updater {
    enum Phase: Equatable {
        case idle
        case checking
        case working(String, Double)   // message, 0...1
        case done(String)
        case failed(String)
    }

    struct Release: Sendable, Equatable {
        var version: String
        var tag: String
        var notes: String
        var asset: URL
        var date: Date?
    }

    var phase: Phase = .idle
    var latestCore: String?
    var enginePack: Release?
    var appRelease: Release?
    var lastCheck: Date? = UserDefaults.standard.object(forKey: "updates.lastCheck") as? Date
    var log: [String] = []

    var autoCheck: Bool {
        get { UserDefaults.standard.object(forKey: "updates.auto") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "updates.auto") }
    }
    var autoInstallCore: Bool {
        get { UserDefaults.standard.object(forKey: "updates.autoCore") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "updates.autoCore") }
    }
    var repo: String {
        get {
            UserDefaults.standard.string(forKey: "updates.repo")
                ?? (Bundle.main.object(forInfoDictionaryKey: "PkMacUpdateRepo") as? String) ?? ""
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespaces), forKey: "updates.repo") }
    }

    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpAdditionalHeaders = ["User-Agent": "PkMac/\(Updater.appVersion)"]
        return URLSession(configuration: c)
    }()

    // MARK: checking

    func coreUpdateAvailable(current: String?) -> Bool {
        guard let latestCore, let current else { return false }
        return VersionCompare.newer(latestCore, than: current)
    }

    func engineUpdateAvailable(current: String?) -> Bool {
        guard let pack = enginePack, let current else { return false }
        return VersionCompare.newer(pack.version, than: current)
    }

    var appUpdateAvailable: Bool {
        guard let r = appRelease else { return false }
        return VersionCompare.newer(r.version, than: Self.appVersion)
    }

    func shouldAutoCheck() -> Bool {
        guard autoCheck else { return false }
        guard let lastCheck else { return true }
        return Date().timeIntervalSince(lastCheck) > 6 * 3600
    }

    func checkAll() async {
        phase = .checking
        async let core = fetchLatestCore()
        async let releases = fetchReleases()
        latestCore = await core
        let (pack, app) = await releases
        enginePack = pack
        appRelease = app
        lastCheck = Date()
        UserDefaults.standard.set(lastCheck, forKey: "updates.lastCheck")
        phase = .idle
    }

    private func fetchLatestCore() async -> String? {
        guard let url = URL(string: "https://api.nuget.org/v3-flatcontainer/pkhex.core/index.json"),
              let res = try? await session.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: res.0) as? [String: Any],
              let versions = obj["versions"] as? [String] else { return nil }
        return versions.filter { !$0.contains("-") }.max { VersionCompare.compare($0, $1) == .orderedAscending }
    }

    private func fetchReleases() async -> (Release?, Release?) {
        let repo = self.repo
        guard repo.contains("/"),
              let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=30"),
              let res = try? await session.data(from: url),
              (res.1 as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONSerialization.jsonObject(with: res.0) as? [[String: Any]] else { return (nil, nil) }

        func release(prefix: String, asset name: String) -> Release? {
            let candidates: [Release] = list.compactMap { r in
                guard (r["draft"] as? Bool) != true,
                      let tag = r["tag_name"] as? String, tag.hasPrefix(prefix),
                      let assets = r["assets"] as? [[String: Any]],
                      let a = assets.first(where: { ($0["name"] as? String) == name }),
                      let s = a["browser_download_url"] as? String, let u = URL(string: s) else { return nil }
                let date = (r["published_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
                return Release(version: String(tag.dropFirst(prefix.count)), tag: tag, notes: r["body"] as? String ?? "", asset: u, date: date)
            }
            return candidates.max { VersionCompare.compare($0.version, $1.version) == .orderedAscending }
        }
        return (release(prefix: "engine-", asset: "PkMacEngine-osx-arm64.zip"), release(prefix: "v", asset: "PkMac.zip"))
    }

    // MARK: installing

    private func step(_ msg: String, _ p: Double) {
        phase = .working(msg, p)
        log.append(msg)
    }

    private func download(_ url: URL, to dest: URL, label: String) async throws {
        step(label, 0.1)
        let (tmp, resp) = try await session.download(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw EngineError(message: "Download non riuscito (\(url.lastPathComponent)).") }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    private func workDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PkMacUpdate-\(name)-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Hot-swaps PKHeX.Core.dll from NuGet into a copy of the active engine.
    /// Returns the new manifest when activated.
    func installCore(version: String, savePath: String?) async -> EngineManifest? {
        do {
            guard let currentDir = EngineManager.activeDirectory() else { throw EngineError(message: "Motore non trovato.") }
            let base = EngineManager.activeManifest() ?? EngineManager.bundledManifest() ?? EngineManifest(engine: "1.0.0", core: "?")
            let work = try workDir("core")
            defer { try? FileManager.default.removeItem(at: work) }

            let v = version.lowercased()
            let nupkg = work.appendingPathComponent("core.nupkg")
            try await download(URL(string: "https://api.nuget.org/v3-flatcontainer/pkhex.core/\(v)/pkhex.core.\(v).nupkg")!, to: nupkg, label: "Scarico PKHeX.Core \(version) da NuGet…")

            step("Estraggo il pacchetto…", 0.35)
            let extracted = work.appendingPathComponent("pkg", isDirectory: true)
            try await Shell.ditto(["-x", "-k", nupkg.path, extracted.path])
            guard let dll = Self.bestCoreDLL(in: extracted.appendingPathComponent("lib")) else {
                throw EngineError(message: "Il pacchetto non contiene una libreria compatibile con .NET 10: serve un nuovo pacchetto motore.")
            }

            step("Preparo una copia del motore…", 0.5)
            let target = AppPaths.engines.appendingPathComponent("engine-\(base.engine)-core-\(version)", isDirectory: true)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: currentDir, to: target)
            let destDLL = target.appendingPathComponent("PKHeX.Core.dll")
            try? FileManager.default.removeItem(at: destDLL)
            try FileManager.default.copyItem(at: dll, to: destDLL)

            step("Eseguo i test di sicurezza (salvataggi, checksum, Auto Legality)…", 0.7)
            guard let report = await EngineManager.selfTest(dir: target, savePath: savePath) else {
                try? FileManager.default.removeItem(at: target)
                throw EngineError(message: "Il nuovo core non si avvia: resto sulla versione attuale.")
            }
            guard report.ok else {
                try? FileManager.default.removeItem(at: target)
                let failed = report.checks.filter { !$0.ok }.map { "\($0.name): \($0.detail ?? "")" }.joined(separator: "\n")
                throw EngineError(message: "Il core \(version) non ha superato i test, resto sulla versione attuale.\n\(failed)")
            }

            let manifest = EngineManifest(engine: base.engine, core: report.versions.core, alm: report.versions.alm, source: "core-update")
            try EngineManager.activate(dir: target, manifest: manifest)
            phase = .done("PKHeX.Core \(report.versions.core) installato e verificato.")
            return manifest
        } catch {
            phase = .failed(error.localizedDescription)
            return nil
        }
    }

    static func bestCoreDLL(in lib: URL) -> URL? {
        let fm = FileManager.default
        guard let tfms = try? fm.contentsOfDirectory(atPath: lib.path) else { return nil }
        // Accept netN.0 with N <= 10 (the engine runtime), newest first.
        let usable = tfms.compactMap { tfm -> (Int, String)? in
            guard tfm.hasPrefix("net"), let major = Int(tfm.dropFirst(3).split(separator: ".").first ?? ""), major <= 10, major >= 5 else { return nil }
            return (major, tfm)
        }.sorted { $0.0 > $1.0 }
        for (_, tfm) in usable {
            let dll = lib.appendingPathComponent(tfm).appendingPathComponent("PKHeX.Core.dll")
            if fm.fileExists(atPath: dll.path) { return dll }
        }
        return nil
    }

    /// Installs a full engine pack (engine + plugins) from GitHub Releases.
    func installEnginePack(_ release: Release, savePath: String?) async -> EngineManifest? {
        do {
            let work = try workDir("engine")
            defer { try? FileManager.default.removeItem(at: work) }
            let zip = work.appendingPathComponent("engine.zip")
            try await download(release.asset, to: zip, label: "Scarico il pacchetto motore \(release.version)…")
            step("Estraggo…", 0.4)
            let target = AppPaths.engines.appendingPathComponent("pack-\(release.version)", isDirectory: true)
            try? FileManager.default.removeItem(at: target)
            try await Shell.ditto(["-x", "-k", zip.path, target.path])
            // The zip may contain a top-level folder.
            var root = target
            if !FileManager.default.fileExists(atPath: target.appendingPathComponent(AppPaths.engineBinary).path),
               let sub = try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil).first(where: { $0.hasDirectoryPath }) {
                root = sub
            }
            let bin = root.appendingPathComponent(AppPaths.engineBinary)
            _ = try? await Shell.run(URL(fileURLWithPath: "/usr/bin/xattr"), ["-dr", "com.apple.quarantine", root.path])
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)

            step("Eseguo i test di sicurezza…", 0.7)
            guard let report = await EngineManager.selfTest(dir: root, savePath: savePath), report.ok else {
                try? FileManager.default.removeItem(at: target)
                throw EngineError(message: "Il pacchetto motore \(release.version) non ha superato i test: resto sulla versione attuale.")
            }
            let manifest = EngineManifest(engine: report.versions.engine, core: report.versions.core, alm: report.versions.alm, source: "pack")
            try EngineManager.activate(dir: root, manifest: manifest)
            phase = .done("Motore \(report.versions.engine) con PKHeX.Core \(report.versions.core) installato.")
            return manifest
        } catch {
            phase = .failed(error.localizedDescription)
            return nil
        }
    }

    /// Downloads the new app, then a helper script swaps the bundle after PkMac quits and relaunches it.
    func installApp(_ release: Release) async {
        do {
            let work = try workDir("app")
            let zip = work.appendingPathComponent("PkMac.zip")
            try await download(release.asset, to: zip, label: "Scarico PkMac \(release.version)…")
            step("Estraggo…", 0.5)
            let out = work.appendingPathComponent("out", isDirectory: true)
            try await Shell.ditto(["-x", "-k", zip.path, out.path])
            guard let newApp = try FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }),
                  let bundle = Bundle(url: newApp), bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw EngineError(message: "L'archivio scaricato non contiene PkMac.")
            }
            step("Installo e riavvio…", 0.9)
            let dest = Bundle.main.bundleURL.path
            let script = work.appendingPathComponent("swap.sh")
            let body = """
            #!/bin/sh
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
            rm -rf "\(dest).old"
            if mv "\(dest)" "\(dest).old" && /usr/bin/ditto "\(newApp.path)" "\(dest)"; then
              rm -rf "\(dest).old"
            else
              rm -rf "\(dest)"; mv "\(dest).old" "\(dest)"
            fi
            /usr/bin/xattr -dr com.apple.quarantine "\(dest)" 2>/dev/null
            /usr/bin/open "\(dest)"
            rm -rf "\(work.path)"
            """
            try body.write(to: script, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [script.path]
            try p.run()
            NSApp.terminate(nil)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Refreshes the PokeAPI form→sprite map from the repo (no rebuild needed for new forms).
    func refreshSpriteMap() async {
        guard repo.contains("/"),
              let url = URL(string: "https://raw.githubusercontent.com/\(repo)/main/App/Resources/pokeapi-forms.json"),
              let res = try? await session.data(from: url),
              (res.1 as? HTTPURLResponse)?.statusCode == 200,
              (try? JSONSerialization.jsonObject(with: res.0)) != nil else { return }
        try? res.0.write(to: AppPaths.support.appendingPathComponent("pokeapi-forms.json"), options: .atomic)
    }
}
