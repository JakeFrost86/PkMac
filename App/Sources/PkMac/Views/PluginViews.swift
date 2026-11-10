import SwiftUI

// MARK: - Auto Legality

struct AutoLegalityView: View {
    @Environment(AppModel.self) private var model
    @State private var events: EventsStatus?
    @State private var shinyDex = false
    @State private var formsDex = false
    @State private var dexResult: LivingDexResult?
    @AppStorage("alm.ribbons") private var ribbons = false
    @AppStorage("alm.balls") private var balls = true
    @AppStorage("alm.trainer") private var trainer = true
    @AppStorage("alm.markings") private var markings = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: "Auto Legality Mod", subtitle: "Pokémon legali generati partendo da un set · santacrab2/PKHeX-Plugins", symbol: "wand.and.stars", tint: AppSection.alm.tint)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ActionTile(title: "Importa da Showdown", text: "Incolla uno o più set (o un link pokepast.es): ogni Pokémon viene generato legale nel primo slot libero del box.", symbol: "doc.on.clipboard.fill", tint: .orange) {
                        model.showShowdownImport = true
                    }
                    ActionTile(title: "Crea un Pokémon", text: "Scegli specie, forma e se cromatico: Auto Legality trova un incontro legale nel gioco aperto.", symbol: "plus.circle.fill", tint: .pink) {
                        model.showCreate = true
                    }
                    ActionTile(title: "Legalizza il box", text: "Rigenera tutti i Pokémon non legali del box \(model.currentBox + 1). L'operazione si può annullare.", symbol: "checkmark.seal.fill", tint: .green) {
                        Task { await model.legalizeBox() }
                    }
                }

                Card(title: "Pokédex vivente", symbol: "books.vertical.fill", tint: .purple) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Genera un esemplare legale di ogni specie disponibile nel gioco e lo sistema nei box liberi a partire dal box \(model.currentBox + 1).")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Toggle("Cromatici", isOn: $shinyDex)
                            Toggle("Includi le forme", isOn: $formsDex)
                            Spacer()
                            Button {
                                Task { dexResult = await model.livingDex(shiny: shinyDex, forms: formsDex) }
                            } label: { Label("Genera", systemImage: "sparkles") }
                            .buttonStyle(.glassProminent)
                        }
                        if let r = dexResult {
                            StatusBadge(kind: r.skipped == 0 ? .ok : .warn, text: "\(r.placed) Pokémon inseriti" + (r.skipped > 0 ? " · \(r.skipped) senza spazio" : ""))
                        }
                    }
                }

                Card(title: "Database eventi", symbol: "gift.fill", tint: .blue) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("La raccolta di Project Pokémon permette ad Auto Legality di generare i Pokémon evento (Dono Segreto).")
                                .font(.callout).foregroundStyle(.secondary)
                            if let e = events {
                                StatusBadge(kind: e.installed ? .ok : .info, text: e.installed ? "\(e.files) eventi installati" : "Non installato")
                            }
                        }
                        Spacer()
                        Button {
                            Task { await model.downloadEvents(); events = await model.eventsStatus() }
                        } label: { Label(events?.installed == true ? "Aggiorna" : "Scarica", systemImage: "arrow.down.circle") }
                        .buttonStyle(.glass)
                    }
                }

                Card(title: "Opzioni", symbol: "slider.horizontal.3", tint: .gray) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Usa i dati allenatore del salvataggio", isOn: $trainer)
                        Toggle("Ball coordinata al colore del Pokémon", isOn: $balls)
                        Toggle("Aggiungi tutti i nastri legali", isOn: $ribbons)
                        Toggle("Imposta i segni (markings)", isOn: $markings)
                    }
                    .onChange(of: [trainer, balls, ribbons, markings]) { _, _ in Task { await model.applyALMSettings() } }
                }
            }
            .padding(26)
        }
        .task { events = await model.eventsStatus() }
    }
}

struct ActionTile: View {
    let title: String
    let text: String
    let symbol: String
    let tint: Color
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [tint.mix(with: .white, by: 0.25), tint], startPoint: .top, endPoint: .bottom))
                    .symbolEffect(.bounce, value: hover)
                Text(title).font(.system(size: 16, weight: .bold, design: .rounded))
                Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(tint.opacity(hover ? 0.16 : 0.09), in: .rect(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(tint.opacity(hover ? 0.4 : 0.12)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .hoverLift(hover)
    }
}

// MARK: - Sorting (PluginPile)

struct SortingView: View {
    @Environment(AppModel.self) private var model
    @State private var options: [SortOption] = []
    @State private var areas = false
    @State private var startBox = 1
    @State private var endBox = 0
    @State private var checkForms = true
    @State private var extras: Set<String> = []

    private let extraOptions: [(String, String)] = [
        ("LevelDesc", "Livello (decrescente)"), ("LevelAsc", "Livello (crescente)"),
        ("ShinyDesc", "Cromatici prima"), ("GenderAsc", "Sesso"), ("MetDateAsc", "Data d'incontro"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: "Ordina per Pokédex", subtitle: "Ordinamento regionale · foohyfooh/PKHeXPluginPile", symbol: "arrow.up.arrow.down.circle.fill", tint: AppSection.sorting.tint)

                Card(title: "Intervallo", symbol: "square.stack.3d.up.fill", tint: .green) {
                    HStack(spacing: 18) {
                        Stepper("Dal box \(startBox)", value: $startBox, in: 1...(model.save?.boxCount ?? 1))
                        Stepper(endBox == 0 ? "fino all'ultimo" : "al box \(endBox)", value: $endBox, in: 0...(model.save?.boxCount ?? 1))
                        Spacer()
                        Toggle("Solo forme del Pokédex", isOn: $checkForms)
                        Toggle("Mostra aree", isOn: $areas)
                    }
                    HStack(spacing: 8) {
                        Text("Poi per:").foregroundStyle(.secondary)
                        ForEach(extraOptions, id: \.0) { o in
                            Toggle(o.1, isOn: Binding(get: { extras.contains(o.0) }, set: { on in if on { extras.insert(o.0) } else { extras.remove(o.0) } }))
                                .toggleStyle(.button)
                                .controlSize(.small)
                        }
                    }
                    .font(.system(size: 12))
                }

                let groups = Dictionary(grouping: options, by: \.group)
                ForEach(["Regionali", "Aree", "Nazionale"], id: \.self) { g in
                    if let opts = groups[g], !opts.isEmpty {
                        Text(g).sectionHeader()
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                            ForEach(opts) { o in
                                Button {
                                    Task { await model.sort(o.id, startBox: startBox - 1, endBox: endBox == 0 ? -1 : endBox - 1, checkForms: checkForms, extra: Array(extras)) }
                                } label: {
                                    HStack {
                                        Image(systemName: g == "Nazionale" ? "globe" : "map.fill").foregroundStyle(.green)
                                        Text(o.name).font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                        Spacer()
                                        Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                                    }
                                    .padding(14)
                                    .background(.green.opacity(0.08), in: .rect(cornerRadius: 16, style: .continuous))
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(26)
        }
        .task(id: areas) { options = await model.sortOptions(areas: areas) }
    }
}

// MARK: - Special finder (PluginPile)

struct SpecialFinderView: View {
    @Environment(AppModel.self) private var model
    @State private var report: SpecialReport?
    @State private var scanning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: "Pokémon speciali", subtitle: "Dunsparce a tre segmenti, Tandemaus da tre, evoluzioni di Wurmple · foohyfooh/PKHeXPluginPile", symbol: "sparkle.magnifyingglass", tint: AppSection.special.tint)
                if let r = report {
                    HStack(spacing: 12) {
                        StatusBadge(kind: .info, text: "\(r.totals.dunsparce) Dunsparce")
                        StatusBadge(kind: .info, text: "\(r.totals.tandemaus) Tandemaus")
                        StatusBadge(kind: .info, text: "\(r.totals.wurmple) Wurmple")
                    }
                    if r.found.isEmpty {
                        Text("Nessun Pokémon speciale nel salvataggio.").foregroundStyle(.secondary).padding(.top, 20)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                        ForEach(r.found) { f in
                            Button { Task { await model.reveal(f.pokemon.ref) } } label: {
                                HStack(spacing: 12) {
                                    PokemonSprite(key: f.pokemon.sprite, tint: .pink).frame(width: 64, height: 64)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(f.label).font(.system(size: 14, weight: .bold, design: .rounded))
                                        Text(f.hint).font(.system(size: 11.5)).foregroundStyle(.secondary)
                                        Text(f.pokemon.ref.label).font(.system(size: 11, weight: .medium)).foregroundStyle(.pink)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(.pink.opacity(0.08), in: .rect(cornerRadius: 18, style: .continuous))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    ProgressView("Cerco…").frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(26)
        }
        .task(id: model.save?.dirty) { report = await model.findSpecial() }
    }
}

// MARK: - LiveHeX

struct LiveHexView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("live.ip") private var ip = "192.168.1.2"
    @AppStorage("live.port") private var port = 6000
    @State private var status: LiveStatus?
    @State private var autoRead = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: "LiveHeX", subtitle: "Modifica in diretta i box del gioco in esecuzione · santacrab2/PKHeX-Plugins", symbol: "antenna.radiowaves.left.and.right", tint: AppSection.liveHex.tint)

                if model.save?.liveHex != true {
                    Card(title: "Non disponibile", symbol: "exclamationmark.triangle.fill", tint: .orange) {
                        Text("LiveHeX supporta i giochi Switch (Spada/Scudo, DLPS, Leggende Arceus, Scarlatto/Violetto, Let's Go, Z-A) e i giochi 3DS via NTR. Apri un salvataggio dello stesso gioco che stai giocando.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Card(title: "Connessione", symbol: "network", tint: .red) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                TextField("Indirizzo IP della console", text: $ip).textFieldStyle(.roundedBorder).frame(width: 200)
                                TextField("Porta", value: $port, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 80)
                                if status?.connected == true {
                                    Button("Disconnetti") { Task { await model.liveDisconnect(); status = nil } }
                                        .buttonStyle(.glass)
                                } else {
                                    Button("Connetti") {
                                        Task { status = await model.liveConnect(ip: ip, port: port) }
                                    }
                                    .buttonStyle(.glassProminent)
                                }
                                Spacer()
                                if let s = status, s.connected {
                                    StatusBadge(kind: .ok, text: "\(s.game) \(s.gameVersion)")
                                }
                            }
                            Text(model.save?.liveHexSwitch == true
                                 ? "Serve sys-botbase 2.5 o successivo sulla Switch (porta 6000). Su Mac la connessione è via Wi-Fi."
                                 : "Per il 3DS serve NTR attivo (porta 8000).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if status?.connected == true {
                        Card(title: "Box \(model.currentBox + 1) · \(model.box?.name ?? "")", symbol: "square.grid.3x3.fill", tint: .red) {
                            HStack(spacing: 12) {
                                Button { Task { await model.liveRead(box: model.currentBox) } } label: {
                                    Label("Leggi dal gioco", systemImage: "arrow.down.to.line.circle.fill")
                                }
                                .buttonStyle(.glassProminent)
                                Button { Task { await model.liveWrite(box: model.currentBox) } } label: {
                                    Label("Scrivi nel gioco", systemImage: "arrow.up.to.line.circle.fill")
                                }
                                .buttonStyle(.glass)
                                Spacer()
                                Toggle("Leggi automaticamente cambiando box", isOn: $autoRead)
                            }
                            Text("Le modifiche ai box appaiono subito nel gioco. Per altri dati salva in gioco e riavvia.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .onChange(of: model.currentBox) { _, b in
                            if autoRead { Task { await model.liveRead(box: b) } }
                        }
                    }
                }
            }
            .padding(26)
        }
    }
}

// MARK: - HOME Live

struct HomeLiveView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("home.ip") private var ip = "192.168.1.2"
    @AppStorage("home.port") private var port = 6000
    @State private var connected: HomeConnectResult?
    @State private var homeBox = 0
    @State private var data: HomeBox?
    @State private var selected: HomeSlot?
    @State private var dumpFormat = "decrypted"
    @State private var dumpFrom = 1
    @State private var dumpTo = 300

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: "HOME Live", subtitle: "Visualizza e salva i Pokémon depositati in Pokémon HOME · Manu098vm", symbol: "house.fill", tint: AppSection.home.tint)

                Card(title: "Connessione a Pokémon HOME", symbol: "network", tint: .blue) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            TextField("Indirizzo IP della Switch", text: $ip).textFieldStyle(.roundedBorder).frame(width: 200)
                            TextField("Porta", value: $port, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 80)
                            if connected != nil {
                                Button("Disconnetti") { Task { await model.homeDisconnect(); connected = nil; data = nil } }.buttonStyle(.glass)
                            } else {
                                Button("Connetti") {
                                    Task {
                                        connected = await model.homeConnect(ip: ip, port: port)
                                        if connected != nil { data = await model.homeBox(0) }
                                    }
                                }
                                .buttonStyle(.glassProminent)
                            }
                            Spacer()
                            if let c = connected { StatusBadge(kind: .ok, text: "HOME \(c.supportedVersion) · \(c.boxes) box") }
                        }
                        Text("Apri Pokémon HOME sulla Switch (con sys-botbase) e tocca lo schermo almeno una volta. Non serve l'abbonamento: puoi vedere anche i box oltre il primo. Solo lettura: HOME non viene mai modificato.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if connected != nil {
                    HStack {
                        Button { Task { homeBox = max(0, homeBox - 1); data = await model.homeBox(homeBox) } } label: { Image(systemName: "chevron.left") }
                        Text("Box HOME \(homeBox + 1)").font(.system(size: 18, weight: .bold, design: .rounded)).frame(minWidth: 140)
                        Button { Task { homeBox = min(299, homeBox + 1); data = await model.homeBox(homeBox) } } label: { Image(systemName: "chevron.right") }
                        Spacer()
                        if let sel = selected, let p = sel.pokemon {
                            Button {
                                guard let slot = model.firstEmptySlot() else { model.toast(.warning, "Box pieno", "Libera uno slot nel box \(model.currentBox + 1)."); return }
                                Task { await model.homeImport(homeBox: homeBox, homeSlot: sel.ref.slot, to: .box(model.currentBox, slot)) }
                            } label: {
                                Label("Porta \(p.displayName) nel box \(model.currentBox + 1)", systemImage: "arrow.down.circle.fill")
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(sel.transferable != true)
                        }
                    }
                    .buttonStyle(.glass)

                    if let d = data {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                            ForEach(d.slots) { s in
                                let t = PokeType(key: s.pokemon?.primaryType)
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(s.empty ? AnyShapeStyle(.primary.opacity(0.04)) : AnyShapeStyle(t.color.opacity(0.14)))
                                    if let p = s.pokemon {
                                        PokemonSprite(key: p.sprite, tint: t.color).padding(8)
                                            .opacity(s.transferable == true ? 1 : 0.45)
                                    }
                                    if selected?.ref == s.ref {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(t.color, lineWidth: 2.5)
                                    }
                                }
                                .aspectRatio(1, contentMode: .fit)
                                .onTapGesture { if !s.empty { selected = s } }
                                .help(s.pokemon.map { "\($0.displayName)\(s.transferable == true ? "" : " · non trasferibile in questo gioco")" } ?? "")
                            }
                        }
                    }

                    Card(title: "Backup completo di HOME", symbol: "externaldrive.fill.badge.timemachine", tint: .indigo) {
                        HStack(spacing: 12) {
                            Stepper("Dal box \(dumpFrom)", value: $dumpFrom, in: 1...300)
                            Stepper("al box \(dumpTo)", value: $dumpTo, in: dumpFrom...300)
                            Picker("Formato", selection: $dumpFormat) {
                                Text("Decifrato (.ph)").tag("decrypted")
                                Text("Cifrato (.eh)").tag("encrypted")
                                Text("Entrambi").tag("both")
                            }
                            .frame(width: 220)
                            Spacer()
                            Button {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
                                panel.prompt = "Salva qui"
                                if panel.runModal() == .OK, let dir = panel.url {
                                    Task { await model.homeDump(dir: dir, from: dumpFrom - 1, to: dumpTo - 1, format: dumpFormat) }
                                }
                            } label: { Label("Salva su disco", systemImage: "square.and.arrow.down") }
                            .buttonStyle(.glassProminent)
                        }
                    }
                }
            }
            .padding(26)
        }
    }
}

// MARK: - Backups

struct BackupsView: View {
    @Environment(AppModel.self) private var model
    @State private var items: [BackupItem] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: "Backup", subtitle: "Copie automatiche all'apertura e prima di ogni salvataggio", symbol: "clock.arrow.circlepath", tint: AppSection.backups.tint)
                if items.isEmpty {
                    Text("Ancora nessun backup per questo file.").foregroundStyle(.secondary)
                }
                VStack(spacing: 8) {
                    ForEach(items) { b in
                        HStack(spacing: 12) {
                            Image(systemName: b.reason.contains("apertura") ? "tray.and.arrow.down.fill" : "shield.lefthalf.filled")
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)
                                .background(.primary.opacity(0.05), in: .rect(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(b.dateValue.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 13, weight: .semibold))
                                Text("\(b.reason.capitalized) · \(ByteCountFormatter.string(fromByteCount: Int64(b.size), countStyle: .file))")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(b.dateValue, style: .relative).font(.caption).foregroundStyle(.tertiary)
                            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: b.path)]) } label: { Image(systemName: "folder") }
                                .buttonStyle(.glass)
                            Button("Ripristina") {
                                let alert = NSAlert()
                                alert.messageText = "Ripristinare questo backup?"
                                alert.informativeText = "Il file attuale verrà a sua volta salvato in un backup prima del ripristino."
                                alert.addButton(withTitle: "Ripristina")
                                alert.addButton(withTitle: "Annulla")
                                if alert.runModal() == .alertFirstButtonReturn {
                                    Task { await model.restore(b); items = await model.backups() }
                                }
                            }
                            .buttonStyle(.glass)
                        }
                        .padding(10)
                        .background(.primary.opacity(0.03), in: .rect(cornerRadius: 14, style: .continuous))
                    }
                }
                Button {
                    NSWorkspace.shared.open(AppPaths.backups)
                } label: { Label("Apri la cartella dei backup", systemImage: "folder") }
                .buttonStyle(.glass)
            }
            .padding(26)
        }
        .task(id: model.lastSave?.sha256) { items = await model.backups() }
    }
}
