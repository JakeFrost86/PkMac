import SwiftUI
import Observation
import UniformTypeIdentifiers

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case boxes, party, overview, trainer
    case bag, pokedex, events, gifts, transfer, advanced
    case alm, sorting, special, liveHex, home
    case backups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .boxes: L("Box")
        case .party: L("Squadra")
        case .overview: L("Panoramica")
        case .trainer: L("Allenatore")
        case .bag: L("Borsa")
        case .pokedex: "Pokédex"
        case .events: L("Eventi di gioco")
        case .gifts: L("Doni segreti")
        case .transfer: L("Trasferisci")
        case .advanced: L("Dati avanzati")
        case .alm: "Auto Legality"
        case .sorting: L("Ordina")
        case .special: L("Pokémon speciali")
        case .liveHex: "LiveHeX"
        case .home: L("HOME Live")
        case .backups: L("Backup")
        }
    }

    var symbol: String {
        switch self {
        case .boxes: "square.grid.3x3.fill"
        case .party: "person.3.fill"
        case .overview: "chart.pie.fill"
        case .trainer: "person.text.rectangle.fill"
        case .bag: "bag.fill"
        case .pokedex: "book.closed.fill"
        case .events: "flag.2.crossed.fill"
        case .gifts: "gift.fill"
        case .transfer: "arrow.left.arrow.right.square.fill"
        case .advanced: "slider.horizontal.below.square.and.square.filled"
        case .alm: "wand.and.stars"
        case .sorting: "arrow.up.arrow.down.circle.fill"
        case .special: "sparkle.magnifyingglass"
        case .liveHex: "antenna.radiowaves.left.and.right"
        case .home: "house.fill"
        case .backups: "clock.arrow.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .boxes: Color(hex: 0x4A90FF)
        case .party: Color(hex: 0xFF5F6D)
        case .overview: Color(hex: 0xA066FF)
        case .trainer: Color(hex: 0x2CC5A4)
        case .bag: Color(hex: 0xE8894A)
        case .pokedex: Color(hex: 0xF0524F)
        case .events: Color(hex: 0x7A6CFF)
        case .gifts: Color(hex: 0xFF6FB5)
        case .transfer: Color(hex: 0x22B8CF)
        case .advanced: Color(hex: 0x6B7A90)
        case .alm: Color(hex: 0xF7A531)
        case .sorting: Color(hex: 0x5CC85A)
        case .special: Color(hex: 0xFF5C93)
        case .liveHex: Color(hex: 0xE24C4C)
        case .home: Color(hex: 0x3FB6FF)
        case .backups: Color(hex: 0x8C8C9A)
        }
    }

    static let saveSections: [AppSection] = [.boxes, .party, .overview, .trainer, .bag, .pokedex, .events, .gifts]
    static let toolSections: [AppSection] = [.transfer, .advanced]
    static let pluginSections: [AppSection] = [.alm, .sorting, .special, .liveHex, .home]
}

struct Toast: Identifiable, Equatable {
    enum Kind { case success, info, warning, error }
    let id = UUID()
    var kind: Kind
    var title: String
    var message: String?
}

struct ProgressInfo: Equatable {
    var task: String
    var done: Int
    var total: Int
    var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
}

@MainActor
@Observable
final class AppModel {
    enum EngineState: Equatable { case starting, ready, failed(String) }

    // Engine
    private(set) var engine: EngineClient?
    var engineState: EngineState = .starting
    var hello: Hello?
    let updater = Updater()

    // Save
    var save: SaveInfo?
    var lists: DataLists?
    var section: AppSection = .boxes
    var currentBox = 0
    var box: BoxData?
    var boxList: [BoxListItem] = []
    var party: [SlotSummary] = []
    var selection: SlotRef?
    var detail: PokemonDetail?
    var hoverSlot: SlotRef?

    // UI state
    var toasts: [Toast] = []
    var busy: String?
    var progress: ProgressInfo?
    var lastSave: SaveResult?
    var showSaveReport = false
    var showShowdownImport = false
    var showCreate = false
    var searchText = ""
    var searchResults: [SlotSummary] = []
    var isDropTargeted = false
    var boxDirection: Edge = .trailing
    var zipChoice: OpenChoice?
    var recentFiles: [String] = UserDefaults.standard.stringArray(forKey: "recentFiles") ?? []

    // Second save (transfers)
    var saveB: SaveInfo?
    var boxB: BoxData?
    var currentBoxB = 0
    var partyB: [SlotSummary] = []
    var transferBoxA = 0
    var boxA: BoxData?

    var accentType: PokeType { PokeType(key: detail?.summary.primaryType ?? box?.slots.first(where: { !$0.empty })?.primaryType) }

    // MARK: - Engine lifecycle

    func bootstrap() async {
        await startEngine()
        if updater.shouldAutoCheck() {
            Task { await checkUpdates(silent: true) }
        }
    }

    func startEngine() async {
        engineState = .starting
        engine?.stop()
        guard let exe = EngineManager.executable(), FileManager.default.isExecutableFile(atPath: exe.path) else {
            engineState = .failed(L("Motore PKHeX non trovato nel pacchetto dell'app."))
            return
        }
        let client = EngineClient(executable: exe)
        client.onEvent = { [weak self] name, data in
            Task { @MainActor in self?.handleEvent(name, data) }
        }
        client.onExit = { [weak self] code in
            Task { @MainActor in
                guard let self, self.engine === client else { return }
                self.engineState = .failed(L("Il motore si è chiuso inaspettatamente (\(code))."))
            }
        }
        do {
            try client.start()
            engine = client
            hello = try await client.call("hello")
            var langParams: [String: Any] = ["lang": Lang.engineCode]
            if let table = Bundle.main.url(forResource: Lang.engineCode, withExtension: "json", subdirectory: "Lang") { langParams["table"] = table.path }
            try await client.send("setLanguage", langParams)
            await applyALMSettings()
            engineState = .ready
        } catch {
            // A broken downloaded engine must never lock the user out: fall back to the bundled one.
            if EngineManager.activeManifest() != nil {
                EngineManager.resetToBundled()
                await startEngine()
                toast(.warning, L("Motore aggiornato non valido"), L("Sono tornato alla versione inclusa nell'app."))
                return
            }
            engineState = .failed(error.localizedDescription)
        }
    }

    /// Restarts the engine (after an update) and reopens the current save.
    func restartEngine() async {
        let path = save?.path
        await startEngine()
        if let path { await open(URL(fileURLWithPath: path), remember: false) }
    }

    private func handleEvent(_ name: String, _ data: [String: Any]) {
        if name == "progress" {
            progress = ProgressInfo(task: data["task"] as? String ?? "", done: data["done"] as? Int ?? 0, total: data["total"] as? Int ?? 0)
        }
    }

    func call<T: Decodable>(_ method: String, _ params: [String: Any] = [:]) async throws -> T {
        guard let engine else { throw EngineError(message: L("Motore non pronto.")) }
        return try await engine.call(method, params)
    }

    @discardableResult
    func send(_ method: String, _ params: [String: Any] = [:]) async throws -> Data {
        guard let engine else { throw EngineError(message: L("Motore non pronto.")) }
        return try await engine.send(method, params)
    }

    /// Runs an action with a busy overlay and error toast.
    func perform(_ label: String?, _ work: () async throws -> Void) async {
        if let label { busy = label }
        defer { busy = nil; progress = nil }
        do { try await work() } catch {
            toast(.error, L("Operazione non riuscita"), error.localizedDescription)
        }
    }

    func toast(_ kind: Toast.Kind, _ title: String, _ message: String? = nil) {
        let t = Toast(kind: kind, title: title, message: message)
        if kind == .error { Log.error("\(title)\(message.map { ": \($0)" } ?? "")") }
        withAnimation(Theme.spring) { toasts.append(t) }
        Task {
            try? await Task.sleep(for: .seconds(kind == .error ? 7 : 3.5))
            withAnimation(Theme.spring) { toasts.removeAll { $0.id == t.id } }
        }
    }

    // MARK: - Save files

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("Scegli un salvataggio Pokémon (main, .sav, .dsv, .dat, .gci, .bin…) o uno zip di Azurii")
        panel.prompt = L("Apri")
        if panel.runModal() == .OK, let url = panel.url {
            Task { await open(url) }
        }
    }

    func open(_ url: URL, remember: Bool = true, entry: String? = nil) async {
        if save?.dirty == true, save?.path != url.path {
            let alert = NSAlert()
            alert.messageText = L("Ci sono modifiche non salvate")
            alert.informativeText = L("Vuoi salvarle prima di aprire un altro file?")
            alert.addButton(withTitle: L("Salva"))
            alert.addButton(withTitle: L("Non salvare"))
            alert.addButton(withTitle: L("Annulla"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: await saveFile()
            case .alertThirdButtonReturn: return
            default: break
            }
        }
        await perform(url.pathExtension.lowercased() == "zip" ? L("Leggo lo zip di Azurii…") : L("Apro il salvataggio…")) {
            var params: [String: Any] = ["path": url.path]
            if let entry { params["entry"] = entry }
            let raw = try await send("open", params)
            if let choice = try? JSONDecoder().decode(OpenChoice.self, from: raw), choice.needsChoice {
                zipChoice = choice
                return
            }
            let info = try JSONDecoder().decode(SaveInfo.self, from: raw)
            save = info
            lists = try await call("lists")
            selection = nil
            detail = nil
            currentBox = 0
            section = info.hasBox ? .boxes : .party
            try await reloadAll()
            if remember { rememberRecent(url.path) }
            if !info.checksumValid {
                toast(.warning, L("Checksum non validi nel file originale"), info.checksumInfo)
            } else if let c = info.container {
                toast(.success, L("\(info.game) da Azurii"), c.isBackup ? L("Dal backup \(c.zipName): lo zip verrà aggiornato al salvataggio.") : L("Salvataggio Azurii: lo zip resta reimportabile in Azurii."))
            } else {
                toast(.success, info.game, L("\(info.ot) · \(info.playTime) di gioco"))
            }
        }
    }

    func reloadAll() async throws {
        guard let save else { return }
        if save.hasBox {
            boxList = try await call("boxes")
            box = try await call("box", ["box": currentBox])
        } else {
            boxList = []
        }
        if save.hasParty { party = try await call("party") }
        try await refreshInfo()
        if let selection { try await loadDetail(selection) }
    }

    func refreshInfo() async throws {
        save = try await call("info")
    }

    private func rememberRecent(_ path: String) {
        recentFiles.removeAll { $0 == path }
        recentFiles.insert(path, at: 0)
        recentFiles = Array(recentFiles.prefix(8))
        UserDefaults.standard.set(recentFiles, forKey: "recentFiles")
    }

    func saveFile(as url: URL? = nil) async {
        guard save != nil else { return }
        await perform(L("Verifico i checksum e salvo…")) {
            var params: [String: Any] = ["backup": true]
            if let url { params["path"] = url.path }
            let result: SaveResult = try await call("save", params)
            lastSave = result
            withAnimation(Theme.spring) { showSaveReport = true }
            try await refreshInfo()
            if let url { rememberRecent(url.path) }
        }
    }

    func saveAsPanel() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = save?.fileName ?? "main"
        panel.message = L("Esporta il salvataggio verificato")
        if panel.runModal() == .OK, let url = panel.url {
            Task { await saveFile(as: url) }
        }
    }

    func closeSave() {
        Task {
            try? await send("close")
            save = nil; box = nil; party = []; boxList = []; detail = nil; selection = nil
        }
    }

    // MARK: - Boxes

    func showBox(_ index: Int) async {
        guard let save, save.hasBox else { return }
        let target = (index + save.boxCount) % save.boxCount
        boxDirection = target > currentBox ? .trailing : .leading
        do {
            let data: BoxData = try await call("box", ["box": target])
            withAnimation(Theme.spring) {
                currentBox = target
                box = data
            }
        } catch {
            toast(.error, L("Impossibile leggere il box"), error.localizedDescription)
        }
    }

    func reloadBox() async {
        guard let save, save.hasBox else { return }
        if let data: BoxData = try? await call("box", ["box": currentBox]) { box = data }
        if let list: [BoxListItem] = try? await call("boxes") { boxList = list }
    }

    func reloadParty() async {
        guard save?.hasParty == true else { return }
        if let p: [SlotSummary] = try? await call("party") { party = p }
    }

    func afterMutation() async {
        await reloadBox()
        await reloadParty()
        try? await refreshInfo()
        if let selection { try? await loadDetail(selection) }
    }

    // MARK: - Selection & editing

    func select(_ ref: SlotRef?) async {
        selection = ref
        guard let ref else { detail = nil; return }
        do { try await loadDetail(ref) } catch {
            toast(.error, L("Impossibile leggere il Pokémon"), error.localizedDescription)
        }
    }

    private func loadDetail(_ ref: SlotRef) async throws {
        let data = try await send("pokemon", ["ref": ref.json])
        if let d = try? JSONDecoder().decode(PokemonDetail.self, from: data) {
            withAnimation(Theme.spring) { detail = d }
        } else {
            withAnimation(Theme.spring) { detail = nil }
        }
    }

    func update(_ changes: [String: Any]) async {
        guard let ref = selection else { return }
        do {
            let d: PokemonDetail = try await call("update", ["ref": ref.json, "changes": changes])
            withAnimation(Theme.snappy) { detail = d }
            await reloadBox()
            await reloadParty()
            try? await refreshInfo()
        } catch {
            toast(.error, L("Modifica non applicata"), error.localizedDescription)
        }
    }

    func move(from: SlotRef, to: SlotRef, copy: Bool) async {
        guard from != to || copy else { return }
        do {
            try await send("move", ["from": from.json, "to": to.json, "copy": copy])
            await afterMutation()
            if !copy, selection == from { await select(to) }
        } catch {
            toast(.error, L("Spostamento non riuscito"), error.localizedDescription)
        }
    }

    func delete(_ ref: SlotRef) async {
        do {
            try await send("delete", ["ref": ref.json])
            if selection == ref { detail = nil }
            await afterMutation()
            toast(.info, L("Pokémon rilasciato"), L("Puoi annullare con ⌘Z."))
        } catch {
            toast(.error, L("Eliminazione non riuscita"), error.localizedDescription)
        }
    }

    func undo() async { await undoRedo("undo") }
    func redo() async { await undoRedo("redo") }

    private func undoRedo(_ method: String) async {
        do {
            let r: UndoResult = try await call(method)
            if let label = r.applied {
                await afterMutation()
                toast(.info, method == "undo" ? L("Annullato: \(label)") : L("Ripristinato: \(label)"))
            }
        } catch {
            toast(.error, L("Impossibile annullare"), error.localizedDescription)
        }
    }

    func heal(_ ref: SlotRef) async {
        await perform(nil) { _ = try await send("heal", ["ref": ref.json]); await afterMutation() }
    }

    func maxIVs(_ ref: SlotRef) async {
        await perform(nil) { _ = try await send("maxStats", ["ref": ref.json]); await afterMutation() }
    }

    func renameBox(_ name: String) async {
        await perform(nil) {
            _ = try await send("renameBox", ["box": currentBox, "name": name])
            await reloadBox()
            try await refreshInfo()
        }
    }

    // MARK: - Files

    func exportPk(_ ref: SlotRef) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Esporta qui")
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        Task {
            await perform(nil) {
                let data = try await send("exportPk", ["ref": ref.json, "dir": dir.path])
                let path = (try? JSONDecoder().decode(String.self, from: data)) ?? dir.path
                toast(.success, L("Pokémon esportato"), URL(fileURLWithPath: path).lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
    }

    func exportBox() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Esporta box")
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        Task {
            await perform(L("Esporto il box…")) {
                let paths: [String] = try await call("exportBox", ["box": currentBox, "dir": dir.path])
                toast(.success, L("\(paths.count) Pokémon esportati"))
                NSWorkspace.shared.open(dir)
            }
        }
    }

    func importPk(_ url: URL, to ref: SlotRef) async {
        await perform(nil) {
            _ = try await send("importPk", ["path": url.path, "ref": ref.json])
            await afterMutation()
            await select(ref)
            toast(.success, L("Pokémon importato"), url.lastPathComponent)
        }
    }

    func copyShowdown(_ ref: SlotRef) async {
        do {
            let data = try await send("exportShowdown", ["ref": ref.json])
            let text = (try? JSONDecoder().decode(String.self, from: data)) ?? ""
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            toast(.success, L("Set Showdown copiato"))
        } catch {
            toast(.error, L("Impossibile esportare"), error.localizedDescription)
        }
    }

    // MARK: - Search

    func search() async {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard save != nil, q.count >= 2 else { searchResults = []; return }
        searchResults = (try? await call("search", ["query": q])) ?? []
    }

    func reveal(_ ref: SlotRef) async {
        if ref.isParty {
            section = .party
        } else if let b = ref.box {
            section = .boxes
            if b != currentBox { await showBox(b) }
        }
        await select(ref)
        searchText = ""
        searchResults = []
    }

    // MARK: - Plugins

    func applyALMSettings() async {
        let d = UserDefaults.standard
        let params: [String: Any] = [
            "setAllLegalRibbons": d.bool(forKey: "alm.ribbons"),
            "setMatchingBalls": d.object(forKey: "alm.balls") as? Bool ?? true,
            "useTrainerData": d.object(forKey: "alm.trainer") as? Bool ?? true,
            "useMarkings": d.object(forKey: "alm.markings") as? Bool ?? true,
            "timeout": d.object(forKey: "alm.timeout") as? Int ?? 15,
        ]
        _ = try? await send("almConfigure", params)
        let namer = d.string(forKey: "namer.kind") ?? "Default"
        var namerParams: [String: Any] = ["namer": namer]
        if let r = d.string(forKey: "namer.regular") { namerParams["regular"] = r }
        _ = try? await send("setNamer", namerParams)
    }

    func legalize(_ ref: SlotRef) async {
        await perform(L("Auto Legality al lavoro…")) {
            let r: LegalizeResult = try await call("legalize", ["ref": ref.json])
            await afterMutation()
            if r.after && !r.before { toast(.success, L("Ora è legale"), L("Auto Legality ha rigenerato il Pokémon.")) }
            else if r.after { toast(.info, L("Era già legale")) }
            else { toast(.warning, L("Non è stato possibile renderlo legale"), L("Prova a cambiare mosse o abilità.")) }
        }
    }

    func legalizeBox() async {
        await perform(L("Legalizzo il box…")) {
            let data = try await send("legalizeBox", ["box": currentBox])
            let fixed = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["fixedCount"] as? Int ?? 0
            await afterMutation()
            toast(fixed > 0 ? .success : .info, fixed > 0 ? L("\(fixed) Pokémon resi legali") : L("Niente da sistemare"))
        }
    }

    func importShowdown(_ text: String) async -> [ImportResult] {
        var out: [ImportResult] = []
        await perform(L("Genero i Pokémon legali…")) {
            let start = firstEmptySlot() ?? 0
            out = try await call("importShowdown", ["text": text, "box": currentBox, "slot": start])
            await afterMutation()
        }
        return out
    }

    func firstEmptySlot() -> Int? { box?.slots.firstIndex { $0.empty && $0.locked != true } }

    func createPokemon(species: Int, form: Int, shiny: Bool, at ref: SlotRef) async {
        await perform(L("Creo un Pokémon legale…")) {
            let r: CreateResult = try await call("createPokemon", ["ref": ref.json, "species": species, "form": form, "shiny": shiny])
            await afterMutation()
            await select(ref)
            toast(r.legal ? .success : .warning, r.legal ? L("Pokémon creato, legale") : L("Creato, ma non del tutto legale"))
        }
    }

    func livingDex(shiny: Bool, forms: Bool) async -> LivingDexResult? {
        var out: LivingDexResult?
        await perform(L("Genero il Pokédex vivente…")) {
            out = try await call("livingDex", ["startBox": currentBox, "shiny": shiny, "forms": forms])
            await afterMutation()
        }
        return out
    }

    func sortOptions(areas: Bool) async -> [SortOption] {
        (try? await call("sortOptions", ["areas": areas])) ?? []
    }

    func sort(_ id: String, startBox: Int, endBox: Int, checkForms: Bool, extra: [String]) async {
        await perform(L("Ordino i box…")) {
            _ = try await send("sort", ["id": id, "startBox": startBox, "endBox": endBox, "checkForms": checkForms, "extra": extra])
            await afterMutation()
            toast(.success, L("Box ordinati"), L("Puoi annullare con ⌘Z."))
        }
    }

    func findSpecial() async -> SpecialReport? {
        try? await call("findSpecial")
    }

    func overview() async -> Overview? { try? await call("stats") }

    func speciesInfo(_ species: Int, form: Int) async -> SpeciesInfo? {
        try? await call("speciesInfo", ["species": species, "form": form])
    }

    func trainer() async -> TrainerData? { try? await call("trainer") }

    func setTrainer(_ params: [String: Any]) async -> TrainerData? {
        do {
            let t: TrainerData = try await call("setTrainer", params)
            try? await refreshInfo()
            return t
        } catch {
            toast(.error, L("Modifica non applicata"), error.localizedDescription)
            return nil
        }
    }

    func backups() async -> [BackupItem] { (try? await call("backups")) ?? [] }

    func restore(_ item: BackupItem) async {
        await perform(L("Ripristino il backup…")) {
            save = try await call("restoreBackup", ["backup": item.path])
            try await reloadAll()
            toast(.success, L("Backup ripristinato"), L("Il file attuale è stato a sua volta salvato in un backup."))
        }
    }

    func eventsStatus() async -> EventsStatus? { try? await call("eventsStatus") }

    func downloadEvents() async {
        await perform(L("Scarico il database eventi di Project Pokémon…")) {
            _ = try await send("downloadEvents")
            toast(.success, L("Database eventi aggiornato"), L("Auto Legality ora può generare i Pokémon evento."))
        }
    }

    // LiveHeX
    func liveConnect(ip: String, port: Int) async -> LiveStatus? {
        var s: LiveStatus?
        await perform(L("Mi collego al gioco…")) { s = try await call("liveConnect", ["ip": ip, "port": port]) }
        return s
    }
    func liveDisconnect() async { _ = try? await send("liveDisconnect") }
    func liveRead(box: Int) async {
        await perform(L("Leggo il box dalla console…")) {
            _ = try await send("liveReadBox", ["box": box])
            if box != currentBox { await showBox(box) }
            await afterMutation()
            toast(.success, L("Box \(box + 1) letto dal gioco"))
        }
    }
    func liveWrite(box: Int) async {
        await perform(L("Scrivo il box nella console…")) {
            _ = try await send("liveWriteBox", ["box": box])
            toast(.success, L("Box \(box + 1) inviato al gioco"))
        }
    }

    // HOME Live
    func homeConnect(ip: String, port: Int) async -> HomeConnectResult? {
        var r: HomeConnectResult?
        await perform(L("Mi collego a Pokémon HOME…")) { r = try await call("homeConnect", ["ip": ip, "port": port]) }
        return r
    }
    func homeDisconnect() async { _ = try? await send("homeDisconnect") }
    func homeBox(_ b: Int) async -> HomeBox? {
        do { return try await call("homeBox", ["box": b]) } catch {
            toast(.error, L("Lettura HOME non riuscita"), error.localizedDescription)
            return nil
        }
    }
    func homeImport(homeBox: Int, homeSlot: Int, to ref: SlotRef) async {
        await perform(L("Porto il Pokémon da HOME…")) {
            _ = try await send("homeImport", ["homeBox": homeBox, "homeSlot": homeSlot, "ref": ref.json])
            await afterMutation()
            toast(.success, L("Importato da HOME"), ref.label)
        }
    }
    func homeDump(dir: URL, from: Int, to: Int, format: String) async {
        await perform(L("Backup di HOME in corso…")) {
            let r: HomeDumpResult = try await call("homeDump", ["dir": dir.path, "fromBox": from, "toBox": to, "format": format])
            toast(.success, L("\(r.files) Pokémon salvati"), r.dir)
            NSWorkspace.shared.open(dir)
        }
    }

    // MARK: - Updates

    func checkUpdates(silent: Bool) async {
        await updater.checkAll()
        await updater.refreshSpriteMap()
        let core = hello?.versions.core
        let engineV = hello?.versions.engine
        if updater.engineUpdateAvailable(current: engineV), let pack = updater.enginePack {
            if !silent { toast(.info, L("Nuovo pacchetto motore \(pack.version)"), L("Aprilo da Impostazioni › Aggiornamenti.")) }
        } else if updater.coreUpdateAvailable(current: core), let latest = updater.latestCore {
            if updater.autoInstallCore && save?.dirty != true {
                await installCore(latest)
            } else {
                toast(.info, L("PKHeX.Core \(latest) disponibile"), L("Installalo da Impostazioni › Aggiornamenti."))
            }
        } else if !silent {
            toast(.success, L("Tutto aggiornato"), L("PKHeX.Core \(core ?? "?")"))
        }
        if updater.appUpdateAvailable, let r = updater.appRelease {
            toast(.info, L("PkMac \(r.version) disponibile"), L("Aggiorna da Impostazioni › Aggiornamenti."))
        }
    }

    func installCore(_ version: String) async {
        guard await ensureSavedBeforeRestart() else { return }
        if await updater.installCore(version: version, savePath: save?.path) != nil {
            await restartEngine()
            toast(.success, L("PKHeX.Core \(hello?.versions.core ?? version) attivo"), L("Aggiornato senza ricompilare l'app."))
        } else if case .failed(let msg) = updater.phase {
            toast(.warning, L("Aggiornamento del core annullato"), msg)
        }
    }

    func installEnginePack() async {
        guard let pack = updater.enginePack, await ensureSavedBeforeRestart() else { return }
        if await updater.installEnginePack(pack, savePath: save?.path) != nil {
            await restartEngine()
            toast(.success, L("Motore \(hello?.versions.engine ?? pack.version) attivo"))
        }
    }

    func rollbackEngine() async {
        guard await ensureSavedBeforeRestart() else { return }
        EngineManager.resetToBundled()
        await restartEngine()
        toast(.info, L("Tornato al motore incluso nell'app"), L("PKHeX.Core \(hello?.versions.core ?? "?")"))
    }

    private func ensureSavedBeforeRestart() async -> Bool {
        guard save?.dirty == true else { return true }
        let alert = NSAlert()
        alert.messageText = L("Salvare prima di aggiornare?")
        alert.informativeText = L("Il motore verrà riavviato e il salvataggio riaperto dal disco.")
        alert.addButton(withTitle: L("Salva e continua"))
        alert.addButton(withTitle: L("Annulla"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        await saveFile()
        return save?.dirty != true
    }

    // MARK: - Drag & drop

    func handleDrop(_ urls: [URL], onto ref: SlotRef?) async {
        guard let url = urls.first else { return }
        let ext = url.pathExtension.lowercased()
        if ext == "zip" { await open(url); return }
        let pkExt = ["pk1","pk2","pk3","pk4","pk5","pk6","pk7","pk8","pk9","pb7","pb8","pa8","pa9","ck3","xk3","bk4","rk4","sk2"]
        if pkExt.contains(ext), save != nil {
            let target = ref ?? firstEmptySlot().map { SlotRef.box(currentBox, $0) }
            guard let target else { toast(.warning, L("Box pieno"), L("Trascina il file su uno slot.")); return }
            await importPk(url, to: target)
        } else {
            await open(url)
        }
    }
}
