import SwiftUI
import UniformTypeIdentifiers

/// Save editors (bag, events, Pokédex, gifts, blocks, ribbons) and the second save used for transfers.
extension AppModel {

    // MARK: - Generic

    /// Calls the engine and shows an error toast on failure.
    func editor<T: Decodable>(_ method: String, _ params: [String: Any] = [:], failure: String = L("Operazione non riuscita")) async -> T? {
        do { return try await call(method, params) } catch {
            toast(.error, failure, error.localizedDescription)
            return nil
        }
    }

    /// Like `editor` but for edits: refreshes the save info (dirty flag, undo) afterwards.
    func edit<T: Decodable>(_ method: String, _ params: [String: Any], failure: String = L("Modifica non applicata")) async -> T? {
        let r: T? = await editor(method, params, failure: failure)
        if r != nil { try? await refreshInfo() }
        return r
    }

    // MARK: - Drag & drop helpers

    static func dragProvider(save: String, ref: SlotRef, name: String?) -> NSItemProvider {
        let p = NSItemProvider()
        guard let data = try? JSONEncoder().encode(SlotDrag(save: save, ref: ref)) else { return p }
        p.registerDataRepresentation(forTypeIdentifier: UTType.pkmacSlot.identifier, visibility: .ownProcess) { done in
            done(data, nil); return nil
        }
        p.suggestedName = name
        return p
    }

    /// Reads a slot drag payload (old payloads were a bare SlotRef from save "a").
    static func loadDrag(_ providers: [NSItemProvider], _ handler: @escaping @MainActor (SlotDrag) -> Void) -> Bool {
        guard let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.pkmacSlot.identifier) }) else { return false }
        p.loadDataRepresentation(forTypeIdentifier: UTType.pkmacSlot.identifier) { data, _ in
            guard let data else { return }
            let drag = (try? JSONDecoder().decode(SlotDrag.self, from: data))
                ?? (try? JSONDecoder().decode(SlotRef.self, from: data)).map { SlotDrag(save: "a", ref: $0) }
            guard let drag else { return }
            Task { @MainActor in handler(drag) }
        }
        return true
    }

    func moveToBox(from: SlotRef, box: Int, copy: Bool) async {
        do {
            let data = try await send("moveToBox", ["from": from.json, "box": box, "copy": copy])
            let to = try? JSONDecoder().decode(SlotRef.self, from: data)
            await afterMutation()
            if !copy, selection == from, let to { await select(to) }
            toast(.success, copy ? L("Copiato nel box \(box + 1)") : L("Spostato nel box \(box + 1)"))
        } catch {
            toast(.error, L("Spostamento non riuscito"), error.localizedDescription)
        }
    }

    // MARK: - Second save

    func openSecondPanel() {
        Task {
            if let url = await pickFile(message: L("Scegli il secondo salvataggio verso cui (o da cui) trasferire i Pokémon")) {
                await openSecond(url)
            }
        }
    }

    func openSecond(_ url: URL, entry: String? = nil) async {
        if saveB?.dirty == true {
            switch await ask(L("Il secondo salvataggio ha modifiche non salvate"), buttons: [L("Salva"), L("Non salvare"), L("Annulla")]) {
            case 0: await saveSecond()
            case 2: return
            default: break
            }
        }
        await perform(L("Apro il secondo salvataggio…")) {
            let target = try FileBridge.prepare(url)
            var params: [String: Any] = ["path": target.path, "save": "b"]
            if let entry { params["entry"] = entry }
            let raw = try await send("open", params)
            if let choice = try? JSONDecoder().decode(OpenChoice.self, from: raw), choice.needsChoice, let first = choice.saves.first {
                // Azurii zip with several saves: take the most recent; the user can reopen another from the menu.
                let again = try await send("open", ["path": target.path, "save": "b", "entry": first.entry])
                saveB = try JSONDecoder().decode(SaveInfo.self, from: again)
                toast(.info, L("Zip con più salvataggi"), L("Ho aperto \(first.game)."))
            } else {
                saveB = try JSONDecoder().decode(SaveInfo.self, from: raw)
            }
            currentBoxB = 0
            try await reloadB()
            if let b = saveB { toast(.success, L("Secondo salvataggio: \(b.game)"), "\(b.ot) · \(b.playTime)") }
        }
    }

    func reloadB() async throws {
        guard let s = saveB else { return }
        saveB = try await call("info", ["save": "b"])
        if s.hasBox { boxB = try await call("box", ["box": currentBoxB, "save": "b"]) } else { boxB = nil }
        if s.hasParty { partyB = try await call("party", ["save": "b"]) } else { partyB = [] }
    }

    func showBoxB(_ index: Int) async {
        guard let s = saveB, s.hasBox else { return }
        let target = (index + s.boxCount) % s.boxCount
        if let data: BoxData = try? await call("box", ["box": target, "save": "b"]) {
            withAnimation(Theme.spring) { currentBoxB = target; boxB = data }
        }
    }

    func showBoxA(_ index: Int) async {
        guard let s = save, s.hasBox else { return }
        let target = (index + s.boxCount) % s.boxCount
        if let data: BoxData = try? await call("box", ["box": target]) {
            withAnimation(Theme.spring) { transferBoxA = target; boxA = data }
        }
    }

    func reloadTransferA() async {
        guard let s = save, s.hasBox else { return }
        if transferBoxA >= s.boxCount { transferBoxA = 0 }
        boxA = try? await call("box", ["box": transferBoxA])
    }

    func saveSecond() async {
        guard saveB != nil else { return }
        await perform(L("Verifico e salvo il secondo salvataggio…")) {
            let result: SaveResult = try await call("save", ["backup": true, "save": "b"])
            try FileBridge.writeBack(result.path)
            try await reloadB()
            toast(.success, L("Secondo salvataggio scritto"), L("Checksum verificati\(result.backup != nil ? ", backup creato" : "")."))
        }
    }

    func closeSecond() async {
        _ = try? await send("close", ["save": "b"])
        saveB = nil; boxB = nil; partyB = []
    }

    /// Moves (or copies with ⌥) a Pokémon between any two slots of the two open saves.
    func transfer(from: SlotDrag, to: SlotDrag, copy: Bool) async {
        if from.save == to.save {
            if from.save == "a" {
                await move(from: from.ref, to: to.ref, copy: copy)
                await reloadTransferA()
            } else {
                do {
                    try await send("move", ["from": from.ref.json, "to": to.ref.json, "copy": copy, "save": "b"])
                    try await reloadB()
                } catch { toast(.error, L("Spostamento non riuscito"), error.localizedDescription) }
            }
            return
        }
        do {
            try await send("transfer", [
                "from": ["save": from.save], "fromRef": from.ref.json,
                "to": ["save": to.save], "toRef": to.ref.json,
                "copy": copy,
            ])
            await afterMutation()
            await reloadTransferA()
            try await reloadB()
            let dest = to.save == "a" ? save?.game : saveB?.game
            toast(.success, copy ? L("Copiato in \(dest ?? "")") : L("Trasferito in \(dest ?? "")"), Platform.isMac
                  ? L("Convertito e verificato per il gioco di destinazione. ⌘Z annulla il trasferimento in entrambi i salvataggi.")
                  : L("Convertito e verificato per il gioco di destinazione. Il tasto Annulla annulla il trasferimento in entrambi i salvataggi."))
        } catch {
            toast(.error, L("Trasferimento non permesso"), error.localizedDescription)
        }
    }

    func transferCheck(from: SlotDrag, toSave: String) async -> TransferCheck? {
        try? await call("transferCheck", ["from": ["save": from.save], "fromRef": from.ref.json, "to": ["save": toSave]])
    }

    // MARK: - Bag

    func bag() async -> BagData? { await editor("bag", failure: L("Impossibile leggere la borsa")) }

    func setBag(_ pouches: [BagPouch]) async -> BagData? {
        let payload: [[String: Any]] = pouches.map { p in
            ["index": p.index, "items": p.items.map { ["id": $0.id, "count": $0.count] }]
        }
        return await edit("bagSet", ["pouches": payload])
    }

    func bagAction(pouch: Int, action: String, count: Int = -1) async -> BagData? {
        await edit("bagAction", ["pouch": pouch, "action": action, "count": count])
    }

    // MARK: - Events

    func events() async -> EventsData? { await editor("events", failure: L("Impossibile leggere gli eventi")) }

    func setEvents(flags: [Int: Bool], system: [Int: Bool], work: [Int: Int]) async -> EventsData? {
        let r: EventsData? = await edit("eventsSet", [
            "flags": flags.map { [$0.key, $0.value] as [Any] },
            "system": system.map { [$0.key, $0.value] as [Any] },
            "work": work.map { [$0.key, $0.value] as [Any] },
        ])
        return r
    }

    // MARK: - Pokédex

    func dex() async -> DexData? { await editor("dex", failure: L("Impossibile leggere il Pokédex")) }

    func setDex(action: String? = nil, changes: [[String: Any]] = []) async -> DexData? {
        var p: [String: Any] = ["changes": changes]
        if let action { p["action"] = action }
        return await edit("dexSet", p)
    }

    // MARK: - Mystery gifts

    func giftAlbum() async -> GiftAlbum? { await editor("giftAlbum", failure: L("Impossibile leggere i doni segreti")) }

    func giftDatabase(query: String, region: String = "") async -> GiftDb? {
        await editor("giftDb", ["query": query, "limit": 600, "region": region], failure: L("Database dei doni non disponibile"))
    }

    func giftDetail(_ id: Int) async -> GiftDetail? { try? await call("giftDb", ["detail": id]) }

    func receiveGift(_ id: Int, at ref: SlotRef? = nil) async {
        await perform(L("Genero il Pokémon del dono…")) {
            var p: [String: Any] = ["id": id]
            if let ref { p["ref"] = ref.json }
            _ = try await send("giftReceive", p)
            await afterMutation()
            toast(.success, L("Pokémon evento aggiunto"), L("Lo trovi nel primo slot libero dei box."))
        }
    }

    func giftToAlbum(_ id: Int, slot: Int = -1) async -> GiftAlbum? {
        let r: GiftAlbum? = await edit("giftToAlbum", ["id": id, "slot": slot], failure: L("Dono non inserito"))
        if r != nil { toast(.success, L("Carta aggiunta all'album"), L("Ritirala dal fattorino nel gioco.")) }
        return r
    }

    func deleteGift(slot: Int) async -> GiftAlbum? { await edit("giftDelete", ["slot": slot]) }

    func setGiftFlags(_ params: [String: Any]) async -> GiftAlbum? { await edit("giftFlags", params) }

    func importGiftFile() async -> Bool {
        guard let url = await pickFile(message: L("Scegli un file dono segreto (.wc9, .wc8, .wb7, .wc7, .wc6, .pgf, .pcd, .pgt, .wa8…)")) else { return false }
        var ok = false
        await perform(L("Importo il dono…")) {
            _ = try await send("giftImportFile", ["path": url.path])
            await afterMutation()
            ok = true
            toast(.success, L("Dono importato"), url.lastPathComponent)
        }
        return ok
    }

    // MARK: - Blocks & inspector

    func blocks(query: String, valuesOnly: Bool) async -> BlocksData? {
        await editor("blocks", ["query": query, "valuesOnly": valuesOnly], failure: L("Impossibile leggere i blocchi"))
    }

    func setBlock(key: String, value: Any) async -> Bool {
        do {
            _ = try await send("blockSet", ["key": key, "value": value])
            try? await refreshInfo()
            return true
        } catch {
            toast(.error, L("Valore non salvato"), error.localizedDescription)
            return false
        }
    }

    func inspect(target: [String: Any], path: [String]) async -> InspectData? {
        var p = target
        p["path"] = path
        return await editor("inspect", p, failure: L("Impossibile leggere i dati"))
    }

    func inspectSet(target: [String: Any], path: [String], prop: String, value: Any) async -> [InspectProp]? {
        var p = target
        p["path"] = path
        p["prop"] = prop
        p["value"] = value
        let r: InspectSetResult? = await edit("inspectSet", p)
        if r != nil, target["target"] as? String == "pkm" { await afterMutation() }
        return r?.props
    }

    // MARK: - Ribbons

    func ribbons(_ ref: SlotRef) async -> RibbonsData? { try? await call("ribbons", ["ref": ref.json]) }

    func setRibbons(_ ref: SlotRef, set: [[String: Any]] = [], action: String? = nil, affixed: Int? = nil) async -> RibbonsData? {
        var p: [String: Any] = ["ref": ref.json, "set": set]
        if let action { p["action"] = action }
        if let affixed { p["affixed"] = affixed }
        let r: RibbonsSetResult? = await edit("ribbonsSet", p)
        if r != nil { await afterMutation() }
        return r?.ribbons
    }
}


// MARK: - Backup policy (Settings › Backup)

struct BackupStats: Codable, Sendable {
    var root: String
    var count: Int
    var saves: Int
    var size: Int64
    var oldest: String?
    var keep: Int
    var days: Int
}

private struct BackupChange: Codable, Sendable {
    var removed: Int
    var stats: BackupStats
}

enum BackupPolicy {
    static let keepKey = "pkmac.backupKeep"
    static let daysKey = "pkmac.backupDays"
    static var keep: Int { UserDefaults.standard.object(forKey: keepKey) as? Int ?? 20 }
    static var days: Int { UserDefaults.standard.object(forKey: daysKey) as? Int ?? 0 }
}

extension AppModel {
    func applyBackupPolicy() async {
        _ = try? await send("backupPolicy", ["keep": BackupPolicy.keep, "days": BackupPolicy.days])
    }

    func backupStats() async -> BackupStats? { try? await call("backupStats") }

    /// Applies the current policy to every save's backups now; returns how many files were removed.
    func pruneBackups() async -> (Int, BackupStats)? {
        await applyBackupPolicy()
        guard let r: BackupChange = try? await call("backupPrune") else { return nil }
        return (r.removed, r.stats)
    }

    func deleteAllBackups() async -> (Int, BackupStats)? {
        guard let r: BackupChange = try? await call("backupDeleteAll") else { return nil }
        return (r.removed, r.stats)
    }
}
