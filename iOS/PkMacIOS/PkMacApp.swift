import SwiftUI
import UniformTypeIdentifiers

/// PkMac for iPhone, iPhone Duo and iPad: the same views as the Mac app (shared from App/Sources/PkMac),
/// with the engine compiled ahead of time and loaded in-process (EngineLibrary.swift).
/// PKMAC_SELFTEST=<file name in Documents> runs the engine probe unattended instead (iOS/build.sh simtest).
@main
struct PkMacIOSApp: App {
    @State private var model = AppModel()
    @State private var probe: EngineProbe? = ProcessInfo.processInfo.environment["PKMAC_SELFTEST"] != nil ? EngineProbe() : nil
    @State private var language = Lang.current

    init() {
        ErrorReporter.install()
    }

    var body: some Scene {
        WindowGroup {
            if let probe {
                ProbeView().environment(probe)
                    .task { await probe.boot() }
            } else {
                RootView()
                    .platformPresenters()
                    .environment(model)
                    .id(language)
                    .task {
                        ErrorReporter.onReport = { title, detail in
                            Task { _ = await model.ask(title, detail, buttons: ["OK"]) }
                        }
                        await model.bootstrap()
                        ErrorReporter.checkPreviousCrash()
                        await debugAutomation()
                    }
                    .onOpenURL { url in
                        Task { await model.open(url) }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Lang.didChange)) { _ in
                        language = Lang.current
                        Task { await model.applyLanguage() }
                    }
            }
        }
    }
}

extension PkMacIOSApp {
    /// Screenshot runs (iOS/build.sh shots): PKMAC_OPEN=<file in Documents> opens a save,
    /// PKMAC_SECTION=<AppSection raw value> shows a section.
    @MainActor func debugAutomation() async {
        let env = ProcessInfo.processInfo.environment
        guard let name = env["PKMAC_OPEN"] else { return }
        await model.open(URL.documentsDirectory.appending(path: name))
        if let raw = env["PKMAC_SECTION"], let s = AppSection(rawValue: raw) { model.section = s }
        if env["PKMAC_SELECT"] == "1", let slot = model.box?.slots.first(where: { !$0.empty }) {
            await model.select(slot.ref)
            model.inspectRequests += 1
        }
        try? await Task.sleep(for: .seconds(1))
        switch env["PKMAC_SHEET"] {
        case "create": model.showCreate = true
        case "showdown": model.showShowdownImport = true
        case "settings": model.showSettings = true
        default: break
        }
    }
}

@MainActor @Observable
final class EngineProbe {
    let engine = EngineClient()
    var lines: [String] = []
    var busy = false

    func log(_ s: String) { lines.append(s); print("[probe] \(s)") }

    func boot() async {
        do {
            let t0 = Date()
            try engine.start()
            let hello = try await engine.send("hello")
            log("Motore caricato in \(Int(Date().timeIntervalSince(t0) * 1000)) ms: \(String(decoding: hello, as: UTF8.self).prefix(160))")
        } catch { log("❌ avvio motore: \(error.localizedDescription)") }
        if let name = ProcessInfo.processInfo.environment["PKMAC_SELFTEST"] {
            let url = URL.documentsDirectory.appending(path: name)
            await test(url)
            let report = lines.joined(separator: "\n")
            try? report.write(to: URL.documentsDirectory.appending(path: "selftest.txt"), atomically: true, encoding: .utf8)
            log("SELFTEST FINITO")
        }
    }

    func test(_ url: URL) async {
        busy = true; defer { busy = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        func step(_ name: String, _ method: String, _ params: [String: Any] = [:]) async -> [String: Any]? {
            let t0 = Date()
            do {
                let data = try await engine.send(method, params)
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                log("✅ \(name) [\(ms) ms] \(String(decoding: data, as: UTF8.self).prefix(140))")
                return obj as? [String: Any]
            } catch {
                log("❌ \(name): \(error.localizedDescription)")
                return nil
            }
        }
        _ = await step("lingua", "setLanguage", ["lang": "it"])
        guard let opened = await step("apri \(url.lastPathComponent)", "open", ["path": url.path]) else { return }
        if opened["needsChoice"] as? Bool == true, let saves = opened["saves"] as? [[String: Any]], let entry = saves.first?["entry"] as? String {
            _ = await step("apri voce zip", "open", ["path": url.path, "entry": entry])
        }
        _ = await step("info", "info")
        if let box = await step("box 1", "box", ["box": 0]), let slots = box["slots"] as? [[String: Any]] {
            let names = slots.compactMap { $0["speciesName"] as? String }
            log("   box 1: \(names.joined(separator: ", "))")
            if let first = slots.first(where: { $0["empty"] as? Bool == false }), let ref = first["ref"] {
                if let d = await step("dettaglio", "pokemon", ["ref": ref]) {
                    let legal = (d["legality"] as? [String: Any])?["valid"] as? Bool
                    log("   \((d["summary"] as? [String: Any])?["speciesName"] ?? "?") legale=\(legal.map { "\($0)" } ?? "?") PID \(d["pid"] ?? "?")")
                }
                _ = await step("anteprima rendi legale", "legalizePreview", ["ref": ref, "mine": false])
            }
        }
        if let info = await step("info box", "info"), let boxCount = info["boxCount"] as? Int, boxCount > 0 {
            let ref: [String: Any] = ["kind": "box", "box": boxCount - 1, "slot": 0]
            if let made = await step("Auto Legality: crea Pikachu cromatico", "createPokemon", ["ref": ref, "species": 25, "shiny": true]) {
                log("   legale dopo la creazione: \(made["legal"] ?? "?")")
            }
            _ = await step("Auto Legality: import Showdown", "importShowdown", ["text": "Pikachu\nAbility: Static\n- Thunderbolt\n- Quick Attack", "box": boxCount - 1, "slot": 1])
        }
        _ = await step("borsa", "bag")
        _ = await step("allenatore", "trainer")
        _ = await step("pokédex", "dex")
        _ = await step("doni (database)", "giftDb", ["query": "", "limit": 5])
        _ = await step("ispettore", "inspect", ["path": ""])
        _ = await step("checksum", "checksum")
    }
}

struct ProbeView: View {
    @Environment(EngineProbe.self) private var probe
    @State private var picking = false

    var body: some View {
        NavigationStack {
            List(Array(probe.lines.enumerated()), id: \.offset) { _, l in
                Text(l).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            }
            .navigationTitle("PkMac · prova motore")
            .toolbar {
                Button { picking = true } label: { Label("Apri", systemImage: "folder") }
                    .disabled(probe.busy)
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.data, .zip]) { result in
                if case .success(let url) = result { Task { await probe.test(url) } }
            }
        }
    }
}
