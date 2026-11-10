import AppKit
import SwiftUI

/// Persistent log: ~/Library/Logs/PkMac/PkMac.log (rotated at 2 MB).
enum Log {
    static let dir: URL = {
        let d = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/PkMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    static let file = dir.appendingPathComponent("PkMac.log")
    static let crashMarker = dir.appendingPathComponent("last-crash.txt")
    private static let queue = DispatchQueue(label: "pkmac.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"; return f
    }()

    static func write(_ level: String, _ s: String) {
        let line = "\(stamp.string(from: Date())) [\(level)] \(s)\n"
        // Errors are written synchronously: the process may be about to die.
        let run: (@escaping () -> Void) -> Void = level == "ERRORE" ? { queue.sync(execute: $0) } : { queue.async(execute: $0) }
        run {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               (attrs[.size] as? Int ?? 0) > 2_000_000 {
                let old = dir.appendingPathComponent("PkMac.old.log")
                try? FileManager.default.removeItem(at: old)
                try? FileManager.default.moveItem(at: file, to: old)
            }
            if let h = try? FileHandle(forWritingTo: file) {
                h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
            } else {
                try? Data(line.utf8).write(to: file)
            }
        }
    }

    static func app(_ s: String) { write("app", s) }
    static func engine(_ s: String) { write("motore", s) }
    static func error(_ s: String) { write("ERRORE", s) }
}

/// Catches errors instead of letting the app close: AppKit exceptions become a log entry plus a
/// popup, and a hard crash leaves a report that is shown at the next launch.
@objc(PkMacApplication)
final class PkMacApplication: NSApplication {
    private var lastAlert = Date.distantPast
    private var silenced = false
    private var count = 0

    override func reportException(_ exception: NSException) {
        count += 1
        let stack = exception.callStackSymbols.prefix(40).joined(separator: "\n")
        Log.error("Eccezione #\(count): \(exception.name.rawValue): \(exception.reason ?? "")\n\(stack)")
        guard !silenced, Date().timeIntervalSince(lastAlert) > 8 else { return }
        lastAlert = Date()
        let reason = exception.reason ?? exception.name.rawValue
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            ErrorReporter.show(title: L("PkMac ha intercettato un errore"),
                               detail: L("L'app resta aperta e i tuoi dati non sono stati toccati.\n\n\(reason)")) { silence in
                if silence { self?.silenced = true }
            }
        }
    }
}

enum ErrorReporter {
    private static var showing = false

    /// Called first thing at launch.
    static func install() {
        // Exceptions thrown inside the event loop are reported instead of terminating the app.
        UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": false])
        // Log every Objective-C exception at the moment it is thrown (name, reason, stack):
        // some AppKit exceptions are fatal and never reach reportException.
        objc_setExceptionPreprocessor { obj in
            if let e = obj as? NSException {
                Log.error("Eccezione lanciata: \(e.name.rawValue): \(e.reason ?? "")\n\(Thread.callStackSymbols.prefix(60).joined(separator: "\n"))")
                if (e.reason ?? "").contains("Update Constraints"), Thread.isMainThread {
                    MainActor.assumeIsolated { Log.error("Viste ospitate nella finestra:\n" + ErrorReporter.hostingDump()) }
                }
            }
            return obj
        }
        NSSetUncaughtExceptionHandler { e in
            Log.error("Eccezione non gestita: \(e.name.rawValue): \(e.reason ?? "")\n\(e.callStackSymbols.joined(separator: "\n"))")
            ErrorReporter.writeMarker(L("Eccezione: \(e.name.rawValue)\n\(e.reason ?? "")\n\n\(e.callStackSymbols.prefix(30).joined(separator: "\n"))"))
        }
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] {
            signal(sig) { s in
                ErrorReporter.writeMarker(L("Segnale \(s) (\(String(cString: strsignal(s))))\n\n\(Thread.callStackSymbols.prefix(40).joined(separator: "\n"))"))
                signal(s, SIG_DFL)
                raise(s)
            }
        }
        Log.app("Avvio PkMac \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    /// Nested SwiftUI hosting views (and scroll views) with their frames: the suspects of a layout loop.
    @MainActor static func hostingDump() -> String {
        var out: [String] = []
        func walk(_ v: NSView, _ depth: Int) {
            let name = String(describing: type(of: v))
            if name.contains("Hosting") || name.contains("ScrollView") || name.contains("Glass") || name.contains("SplitView") || name.contains("Table") {
                let short = name.count > 220 ? String(name.prefix(220)) + "…" : name
                out.append(String(repeating: "  ", count: min(depth, 30)) + "\(short) \(NSStringFromRect(v.frame))")
            }
            if out.count < 400 { v.subviews.forEach { walk($0, depth + 1) } }
        }
        for w in NSApp.windows { if let c = w.contentView?.superview ?? w.contentView { walk(c, 0) } }
        return out.joined(separator: "\n")
    }

    static func writeMarker(_ text: String) {
        let body = "\(Date())\n\(text)\n"
        try? body.write(to: Log.crashMarker, atomically: false, encoding: .utf8)
        if let h = try? FileHandle(forWritingTo: Log.file) {
            h.seekToEndOfFile(); h.write(Data(L("[CRASH] \(body)").utf8)); try? h.close()
        }
    }

    /// Shown at launch when the previous session ended with a crash.
    @MainActor static func checkPreviousCrash() {
        guard let text = try? String(contentsOf: Log.crashMarker, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: Log.crashMarker)
        show(title: L("L'ultima volta PkMac si è chiusa per un errore"),
             detail: L("Il dettaglio è nel registro (Aiuto ▸ Mostra il registro degli errori).\n\n") + String(text.prefix(600))) { _ in }
    }

    @MainActor static func show(title: String, detail: String, done: @escaping (Bool) -> Void) {
        guard !showing else { return }
        showing = true
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: L("Ok"))
        alert.addButton(withTitle: L("Mostra il registro"))
        alert.addButton(withTitle: L("Non mostrare più (questa sessione)"))
        let r = alert.runModal()
        showing = false
        if r == .alertSecondButtonReturn { revealLog() }
        done(r == .alertThirdButtonReturn)
    }

    static func revealLog() {
        if !FileManager.default.fileExists(atPath: Log.file.path) { try? Data().write(to: Log.file) }
        NSWorkspace.shared.activateFileViewerSelecting([Log.file])
    }
}
