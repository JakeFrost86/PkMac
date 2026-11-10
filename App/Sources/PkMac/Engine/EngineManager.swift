import Foundation

enum AppPaths {
    static let support: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PkMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    static var engines: URL {
        let u = support.appendingPathComponent("Engine", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var activeFile: URL { engines.appendingPathComponent("active.json") }
    static var backups: URL { support.appendingPathComponent("Backups", isDirectory: true) }
    #if os(macOS)
    static var bundledEngine: URL? { Bundle.main.resourceURL?.appendingPathComponent("Engine", isDirectory: true) }
    #else
    /// iPhone / iPad: the engine is PkMacEngine.framework inside the app (Frameworks/).
    /// The in-process engine finds the same Application Support/PkMac folder through HOME (the app sandbox).
    static var bundledEngine: URL? { Bundle.main.privateFrameworksURL?.appendingPathComponent("PkMacEngine.framework", isDirectory: true) }
    #endif
    static let engineBinary = "PkMacEngine"
}

/// Describes an installed engine folder (bundled or downloaded).
struct EngineManifest: Codable, Sendable {
    var engine: String
    var core: String
    var alm: String?
    var source: String?     // "bundle", "core-update", "pack"
    var dir: String?
}

enum EngineManager {
    static func bundledManifest() -> EngineManifest? {
        guard let dir = AppPaths.bundledEngine else { return nil }
        return read(dir.appendingPathComponent("manifest.json"))
    }

    static func activeManifest() -> EngineManifest? { read(AppPaths.activeFile) }

    private static func read(_ url: URL) -> EngineManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(EngineManifest.self, from: data)
    }

    /// Folder of the engine to launch: the downloaded one if valid and not older than the bundled one.
    static func activeDirectory() -> URL? {
        let bundled = AppPaths.bundledEngine
        #if os(iOS)
        return bundled   // iOS: always the engine compiled into the app (no downloaded engines)
        #else
        if let m = activeManifest(), let dir = m.dir {
            let url = URL(fileURLWithPath: dir, isDirectory: true)
            let bin = url.appendingPathComponent(AppPaths.engineBinary)
            let bundledEngine = bundledManifest()?.engine ?? "0"
            if FileManager.default.isExecutableFile(atPath: bin.path),
               VersionCompare.compare(m.engine, bundledEngine) != .orderedAscending {
                return url
            }
        }
        return bundled
        #endif
    }

    static func executable() -> URL? {
        activeDirectory()?.appendingPathComponent(AppPaths.engineBinary)
    }

    static func activate(dir: URL, manifest: EngineManifest) throws {
        var m = manifest
        m.dir = dir.path
        try JSONEncoder().encode(m).write(to: AppPaths.activeFile, options: .atomic)
        try JSONEncoder().encode(m).write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
        cleanup(keeping: dir)
    }

    static func resetToBundled() {
        try? FileManager.default.removeItem(at: AppPaths.activeFile)
    }

    /// Keeps the active engine plus the most recent previous one (for manual rollback).
    static func cleanup(keeping active: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: AppPaths.engines, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let dirs = items.filter { $0.hasDirectoryPath && $0.standardizedFileURL != active.standardizedFileURL }
            .sorted { (a, b) in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
        for old in dirs.dropFirst(1) { try? fm.removeItem(at: old) }
    }

    /// Runs `PkMacEngine --selftest` in a folder and returns the report.
    static func selfTest(dir: URL, savePath: String?) async -> SelfTestReport? {
        #if os(iOS)
        return nil   // iOS can't launch other programs; the bundled engine is never swapped
        #else
        let bin = dir.appendingPathComponent(AppPaths.engineBinary)
        var args = ["--selftest"]
        if let savePath { args.append(savePath) }
        guard let out = try? await Shell.run(bin, args, timeout: 180) else { return nil }
        let line = out.split(separator: "\n").last.map(String.init) ?? ""
        return try? JSONDecoder().decode(SelfTestReport.self, from: Data(line.utf8))
        #endif
    }
}

enum VersionCompare {
    /// Compares dotted versions numerically ("26.10.18" vs "26.9.3").
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        let pb = b.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
    static func newer(_ a: String, than b: String) -> Bool { compare(a, b) == .orderedDescending }
}

#if os(macOS)
enum Shell {
    struct Failure: LocalizedError {
        let status: Int32
        let output: String
        var errorDescription: String? { L("Comando fallito (\(status)): \(output.prefix(400))") }
    }

    /// Runs a process and returns stdout; throws on non-zero exit.
    static func run(_ exe: URL, _ args: [String], timeout: TimeInterval = 120) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            p.currentDirectoryURL = exe.deletingLastPathComponent()
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.terminationHandler = { proc in
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 || exe.lastPathComponent == AppPaths.engineBinary {
                    cont.resume(returning: o)
                } else {
                    cont.resume(throwing: Failure(status: proc.terminationStatus, output: e.isEmpty ? o : e))
                }
            }
            do { try p.run() } catch { cont.resume(throwing: error); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if p.isRunning { p.terminate() }
            }
        }
    }

    static func ditto(_ args: [String]) async throws {
        _ = try await run(URL(fileURLWithPath: "/usr/bin/ditto"), args)
    }
}
#endif
