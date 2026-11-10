import SwiftUI

struct PokemonInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let d = model.detail {
                PokemonDetailView(detail: d)
                    .id(d.summary.ref)
            } else if let sel = model.selection {
                EmptySlotPanel(ref: sel)
            } else {
                NothingSelected()
            }
        }
        .animation(Theme.spring, value: model.selection)
    }
}

private struct NothingSelected: View {
    var body: some View {
        VStack(spacing: 14) {
            OrbGlyph()
                .foregroundStyle(.tertiary)
                .frame(width: 54, height: 54)
            Text(L("Seleziona un Pokémon")).font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(L("Clicca uno slot per vederlo e modificarlo.\nTrascina per spostare, ⌥ per copiare."))
                .font(.system(size: 12.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptySlotPanel: View {
    @Environment(AppModel.self) private var model
    let ref: SlotRef

    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                .frame(width: 110, height: 110)
                .overlay(Image(systemName: "plus").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary))
            Text(L("Slot vuoto")).font(.system(size: 17, weight: .bold, design: .rounded))
            Text(ref.label).foregroundStyle(.secondary).font(.callout)
            VStack(spacing: 10) {
                Button { model.showCreate = true } label: {
                    Label(L("Crea un Pokémon legale"), systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                Button { model.showShowdownImport = true } label: {
                    Label(L("Incolla set Showdown"), systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                Button {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = false
                    panel.message = L("Scegli un file .pk")
                    if panel.runModal() == .OK, let url = panel.url { Task { await model.importPk(url, to: ref) } }
                } label: {
                    Label(L("Importa file .pk…"), systemImage: "doc.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
            .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Detail

private enum DetailTab: String, CaseIterable, Identifiable {
    case summary, stats, moves, origin, ribbons
    var id: String { rawValue }
    var title: String {
        switch self {
        case .summary: L("Riepilogo")
        case .stats: L("Statistiche")
        case .moves: L("Mosse")
        case .origin: L("Origine")
        case .ribbons: L("Fiocchi")
        }
    }
    var symbol: String {
        switch self {
        case .summary: "sparkles.rectangle.stack"
        case .stats: "hexagon"
        case .moves: "bolt.circle"
        case .origin: "globe.europe.africa"
        case .ribbons: "rosette"
        }
    }
}

struct PokemonDetailView: View {
    @Environment(AppModel.self) private var model
    let detail: PokemonDetail
    @State private var tab: DetailTab = .summary
    @State private var showAdvanced = false

    private var type: PokeType { PokeType(key: detail.summary.primaryType) }

    var body: some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .pkmacTourTab)) { n in
                guard let raw = n.object as? String else { return }
                if raw == "advanced" { showAdvanced = true; return }
                showAdvanced = false
                if let t = DetailTab(rawValue: raw) { tab = t }
            }
            .sheet(isPresented: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(L("Dati avanzati · \(detail.summary.displayName)"), systemImage: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Spacer()
                        Button(L("Fine")) { showAdvanced = false }.keyboardShortcut(.defaultAction).buttonStyle(.glassProminent)
                    }
                    Text(L("Ogni proprietà del Pokémon come la vede PKHeX. Le modifiche si applicano subito e sono annullabili con ⌘Z."))
                        .font(.caption).foregroundStyle(.secondary)
                    InspectorBrowser(target: ["target": "pkm", "ref": detail.summary.ref.json], rootTitle: detail.summary.displayName)
                }
                .padding(20)
                .frame(width: 720, height: 620)
            }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                Hero(detail: detail)
                LegalityBanner(detail: detail)
                HStack(spacing: 8) {
                    Picker("", selection: $tab) {
                        ForEach(DetailTab.allCases) { t in
                            Image(systemName: t.symbol).help(t.title).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Button { showAdvanced = true } label: { Image(systemName: "slider.horizontal.3") }
                        .buttonStyle(.glass)
                        .help(L("Dati avanzati: tutti i campi del Pokémon"))
                }
                Text(tab.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, -8)

                Group {
                    switch tab {
                    case .summary: SummaryTab(detail: detail)
                    case .stats: StatsTab(detail: detail)
                    case .moves: MovesTab(detail: detail)
                    case .origin: OriginTab(detail: detail)
                    case .ribbons: RibbonsTab(ref: detail.summary.ref)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(Theme.spring, value: tab)

                ActionBar(detail: detail)
            }
            .padding(18)
        }
        .scrollIndicators(.never)
        .tint(type.color)
    }
}

private struct Hero: View {
    @Environment(AppModel.self) private var model
    let detail: PokemonDetail
    @State private var animated = false
    @State private var editingName = false
    @State private var name = ""
    @State private var rotate = false

    private var s: SlotSummary { detail.summary }
    private var type: PokeType { PokeType(key: s.primaryType) }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [type.glow.opacity(0.75), type.color.opacity(0.25), .clear], center: .center, startRadius: 10, endRadius: 150))
                    .frame(width: 280, height: 280)
                    .blur(radius: 6)
                Circle()
                    .strokeBorder(AngularGradient(colors: [type.color.opacity(0.0), type.glow.opacity(0.7), type.color.opacity(0.0)], center: .center), lineWidth: 2)
                    .frame(width: 214, height: 214)
                    .rotationEffect(.degrees(rotate ? 360 : 0))
                    .animation(.linear(duration: 14).repeatForever(autoreverses: false), value: rotate)
                if s.shiny == true {
                    SparkleField(color: .yellow).frame(width: 260, height: 240)
                }
                PokemonSprite(key: s.sprite, style: animated ? .animated : .artwork, tint: type.color)
                    .frame(width: animated ? 150 : 210, height: animated ? 150 : 210)
                    .shadow(color: type.deep.opacity(0.35), radius: 16, y: 14)
                    .onTapGesture { withAnimation(Theme.spring) { animated.toggle() } }
                    .help(L("Clicca per l'animazione"))
            }
            .frame(height: 240)
            .onAppear { rotate = true }

            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    if editingName {
                        TextField(L("Soprannome"), text: $name)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .frame(maxWidth: 220)
                            .onSubmit {
                                editingName = false
                                Task { await model.update(["nickname": name]) }
                            }
                            .onExitCommand { editingName = false }
                    } else {
                        Text(s.displayName)
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .onTapGesture(count: 2) {
                                guard detail.canEdit else { return }
                                name = s.nickname ?? ""
                                editingName = true
                            }
                            .help(L("Doppio clic per cambiare soprannome"))
                    }
                    GenderMark(gender: s.gender ?? 2)
                }
                HStack(spacing: 6) {
                    Text("Lv. \(s.level ?? 0)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.primary.opacity(0.08), in: Capsule())
                    if s.isNicknamed == true, let sp = s.speciesName {
                        Text(sp).font(.system(size: 12.5, design: .rounded)).foregroundStyle(.secondary)
                    }
                    if s.gmax == true {
                        Text(L("Gigamax")).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.pink)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(s.types ?? [], id: \.self) { TypePill(type: PokeType(key: $0)) }
                    if let tera = detail.teraType {
                        HStack(spacing: 3) {
                            Image(systemName: "diamond.fill").font(.system(size: 9))
                            Text(L("Tera \(PokeType(key: tera).italian)")).font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(PokeType(key: tera).color)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(PokeType(key: tera).color.opacity(0.14), in: Capsule())
                    }
                }
            }
        }
    }
}

struct GenderMark: View {
    let gender: Int
    var body: some View {
        switch gender {
        case 0: Text("♂").font(.system(size: 20, weight: .bold)).foregroundStyle(Color(hex: 0x4A90FF))
        case 1: Text("♀").font(.system(size: 20, weight: .bold)).foregroundStyle(Color(hex: 0xFF5C93))
        default: EmptyView()
        }
    }
}

private struct LegalityBanner: View {
    @Environment(AppModel.self) private var model
    let detail: PokemonDetail
    @State private var showReport = false

    var body: some View {
        let ok = detail.legality.valid
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.octagon.fill")
                .font(.system(size: 20))
                .foregroundStyle(ok ? .green : .red)
                .symbolEffect(.bounce, value: ok)
            VStack(alignment: .leading, spacing: 1) {
                Text(ok ? L("Legale") : L("Non legale")).font(.system(size: 13.5, weight: .bold, design: .rounded))
                Text(ok ? L("Superati tutti i controlli di PKHeX") : firstProblem)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if !ok {
                Button { Task { await model.legalize(detail.summary.ref) } } label: {
                    Label(L("Rendi legale"), systemImage: "wand.and.stars")
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)
                .controlSize(.small)
            }
            Button { showReport = true } label: { Image(systemName: "doc.text.magnifyingglass") }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help(L("Rapporto di legalità completo"))
                .popover(isPresented: $showReport) {
                    ScrollView {
                        Text(detail.legality.verbose)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: 440, height: 380)
                }
        }
        .padding(12)
        .glassEffect(.regular.tint((ok ? Color.green : .red).opacity(0.12)), in: .rect(cornerRadius: 16))
    }

    private var firstProblem: String {
        detail.legality.report.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.contains("===") }.map(String.init) ?? L("Controlla il rapporto")
    }
}

// MARK: - Tabs

private struct SummaryTab: View {
    @Environment(AppModel.self) private var model
    let detail: PokemonDetail
    @State private var level: Double = 1
    @State private var friendship: Double = 0

    var body: some View {
        let lists = model.lists
        let s = detail.summary
        VStack(spacing: 12) {
            Card(title: L("Carattere e abilità"), symbol: "theatermasks.fill", tint: PokeType(key: s.primaryType).color) {
                VStack(spacing: 8) {
                    if detail.hasNatures, let natures = lists?.natures {
                        PickerRow(label: L("Natura"), value: detail.natureName + natureHint, symbol: "leaf", items: natures, selected: detail.nature, disabled: !detail.canEdit) { pick in
                            Task { await model.update(["nature": pick.v]) }
                        }
                    }
                    if !detail.abilities.isEmpty {
                        let items = detail.abilities.map { ListItem(v: $0.index, t: $0.name + ($0.hidden ? L(" (nascosta)") : "")) }
                        let current = detail.abilities.first { $0.id == detail.ability }?.index
                        PickerRow(label: L("Abilità"), value: detail.abilityName ?? "—", symbol: "star.circle", items: items, selected: current, disabled: !detail.canEdit) { pick in
                            Task { await model.update(["abilityIndex": pick.v]) }
                        }
                    }
                    if let items = lists?.items, detail.format >= 2 {
                        PickerRow(label: L("Strumento"), value: s.heldItemName ?? L("Nessuno"), symbol: "bag", items: items, selected: s.heldItem, disabled: !detail.canEdit) { pick in
                            Task { await model.update(["heldItem": pick.v]) }
                        }
                    }
                    if let balls = lists?.balls, detail.format >= 3 {
                        PickerRow(label: L("Ball"), value: detail.ballName, symbol: "circle.circle", items: balls, selected: s.ball, disabled: !detail.canEdit) { pick in
                            Task { await model.update(["ball": pick.v]) }
                        }
                    }
                    if detail.teraTypeIndex != nil, let types = lists?.types {
                        let teraItems = types.filter { !($0.key ?? "").isEmpty }
                        PickerRow(label: L("Teratipo"), value: PokeType(key: detail.teraType).italian, symbol: "diamond", items: teraItems, selected: nil) { pick in
                            Task { await model.update(["teraType": pick.v]) }
                        }
                    }
                }
            }

            Card(title: L("Livello e affetto"), symbol: "chart.line.uptrend.xyaxis", tint: PokeType(key: s.primaryType).color) {
                VStack(spacing: 10) {
                    ValueSlider(label: "Lv.", value: $level, range: 1...100) {
                        Task { await model.update(["level": Int(level)]) }
                    }
                    ValueSlider(label: L("Affetto"), value: $friendship, range: 0...255, tint: .pink) {
                        Task { await model.update(["friendship": Int(friendship)]) }
                    }
                    HStack {
                        Toggle(isOn: Binding(get: { s.shiny ?? false }, set: { v in Task { await model.update(["shiny": v]) } })) {
                            Label(L("Cromatico"), systemImage: "sparkles")
                        }
                        .toggleStyle(.switch)
                        Spacer()
                        if detail.format >= 2 {
                            Toggle(isOn: Binding(get: { detail.pokerus }, set: { v in Task { await model.update(["pokerus": v]) } })) {
                                Label(L("Pokérus"), systemImage: "allergens")
                            }
                            .toggleStyle(.switch)
                        }
                    }
                    .font(.system(size: 12.5, design: .rounded))
                    if detail.genderRatio != 255 && detail.genderRatio != 0 && detail.genderRatio != 254 {
                        Picker(L("Sesso"), selection: Binding(get: { s.gender ?? 0 }, set: { v in Task { await model.update(["gender": v]) } })) {
                            Text(L("♂ Maschio")).tag(0)
                            Text(L("♀ Femmina")).tag(1)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .disabled(!detail.canEdit)
        }
        .onAppear { sync() }
        .onChange(of: detail.summary.level) { _, _ in sync() }
    }

    private func sync() {
        level = Double(detail.summary.level ?? 1)
        friendship = Double(detail.friendship)
    }

    private var natureHint: String {
        guard detail.natureUp >= 0 else { return "" }
        return "  +\(Theme.statShort[detail.natureUp]) −\(Theme.statShort[detail.natureDown])"
    }
}

private struct StatsTab: View {
    @Environment(AppModel.self) private var model
    let detail: PokemonDetail
    @State private var ivs: [Double] = Array(repeating: 0, count: 6)
    @State private var evs: [Double] = Array(repeating: 0, count: 6)

    private var type: PokeType { PokeType(key: detail.summary.primaryType) }

    var body: some View {
        VStack(spacing: 12) {
            Card(title: L("Statistiche"), symbol: "hexagon.fill", tint: type.color) {
                StatRadar(values: detail.stats, base: detail.baseStats, tint: type.color, up: detail.natureUp, down: detail.natureDown)
                    .frame(height: 230)
                HStack {
                    Text(L("Totale base \(detail.baseStats.reduce(0, +))"))
                    Spacer()
                    Text(L("IV medi \(Int(Double(detail.ivs.reduce(0, +)) / 6))/\(detail.maxIV)"))
                }
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(.secondary)
            }

            Card(title: L("IV · valori individuali"), symbol: "dna", tint: type.color) {
                VStack(spacing: 6) {
                    ForEach(0..<6, id: \.self) { i in
                        ValueSlider(label: Theme.statShort[i], value: $ivs[i], range: 0...Double(detail.maxIV), tint: Theme.stat(i)) {
                            commitIVs()
                        }
                    }
                    HStack {
                        Button(L("Tutti al massimo")) { ivs = Array(repeating: Double(detail.maxIV), count: 6); commitIVs() }
                        Button(L("Trick Room (Vel 0)")) { ivs = Array(repeating: Double(detail.maxIV), count: 6); ivs[5] = 0; commitIVs() }
                        Spacer()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }

            Card(title: L("EV · punti allenamento"), symbol: "figure.strengthtraining.traditional", tint: type.color) {
                VStack(spacing: 6) {
                    ForEach(0..<6, id: \.self) { i in
                        ValueSlider(label: Theme.statShort[i], value: $evs[i], range: 0...Double(min(detail.maxEV, 255)), step: detail.format >= 3 ? 4 : 1, tint: Theme.stat(i)) {
                            commitEVs()
                        }
                    }
                    if detail.format >= 3 {
                        let total = Int(evs.reduce(0, +))
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: min(1, Double(total) / 510))
                                .tint(total > 510 ? .red : type.color)
                            Text("\(total) / 510 EV")
                                .font(.system(size: 11, design: .rounded).monospacedDigit())
                                .foregroundStyle(total > 510 ? .red : .secondary)
                        }
                    }
                    HStack {
                        Button(L("Azzera")) { evs = Array(repeating: 0, count: 6); commitEVs() }
                        Button(L("252 Att / 252 Vel")) { evs = [4, 252, 0, 0, 0, 252]; commitEVs() }
                        Button(L("252 AtSp / 252 Vel")) { evs = [4, 0, 0, 252, 0, 252]; commitEVs() }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(detail.format < 3)
                }
            }
        }
        .disabled(!detail.canEdit)
        .onAppear(perform: sync)
        .onChange(of: detail.ivs) { _, _ in sync() }
        .onChange(of: detail.evs) { _, _ in sync() }
    }

    private func sync() {
        ivs = detail.ivs.map(Double.init)
        evs = detail.evs.map(Double.init)
    }
    private func commitIVs() { Task { await model.update(["ivs": ivs.map { Int($0) }]) } }
    private func commitEVs() {
        if detail.format >= 3 && evs.reduce(0, +) > 510 {
            model.toast(.warning, L("Troppi EV"), L("Il totale non può superare 510."))
            sync()
            return
        }
        Task { await model.update(["evs": evs.map { Int($0) }]) }
    }
}

private struct MovesTab: View {
    @Environment(AppModel.self) private var model
    let detail: PokemonDetail

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(detail.moves.enumerated()), id: \.offset) { i, move in
                MoveCard(index: i, move: move, detail: detail)
            }
            Text(L("Suggerimento: se le mosse non sono legali, usa «Rendi legale» per farle sistemare ad Auto Legality."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
}

private struct MoveCard: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let move: MoveSlot
    let detail: PokemonDetail
    @State private var open = false
    @State private var hover = false

    var body: some View {
        let t = PokeType(key: move.type)
        Button { open = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(move.id == 0 ? AnyShapeStyle(.primary.opacity(0.06)) : AnyShapeStyle(LinearGradient(colors: [t.glow, t.color], startPoint: .top, endPoint: .bottom)))
                    Image(systemName: move.id == 0 ? "plus" : t.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(move.id == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(move.name ?? L("Nessuna mossa"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(move.id == 0 ? .secondary : .primary)
                    if move.id != 0 {
                        Text(t.italian).font(.system(size: 11, design: .rounded)).foregroundStyle(t.color)
                    }
                }
                Spacer()
                if move.id != 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("PP").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        Text("\(move.pp)").font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(move.id == 0 ? AnyShapeStyle(.primary.opacity(0.03)) : AnyShapeStyle(t.color.opacity(hover ? 0.18 : 0.11)))
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(t.color.opacity(move.id == 0 ? 0 : 0.25)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .disabled(!detail.canEdit)
        .popover(isPresented: $open, arrowEdge: .leading) {
            SearchPicker(title: L("Mossa"), items: model.lists?.moves ?? [], selected: move.id, showsTypes: true) { pick in
                var ids = detail.moves.map(\.id)
                ids[index] = pick.v
                Task { await model.update(["moves": ids]) }
            }
        }
    }
}

private struct OriginTab: View {
    @Environment(AppModel.self) private var model
    let detail: PokemonDetail
    @State private var ot = ""
    @State private var tid = ""
    @State private var sid = ""
    @State private var ht = ""
    @State private var metLevel = ""
    @State private var pid = ""
    @State private var ec = ""
    @State private var games: [ListItem] = []
    @State private var metLocations: [ListItem] = []
    @State private var eggLocations: [ListItem] = []

    private var o: OriginData? { detail.origin }

    var body: some View {
        VStack(spacing: 12) {
            if let o {
                trainer(o)
                encounter(o)
                if o.hasEgg { egg(o) }
                if o.hasHandler { handler(o) }
                technical(o)
            }
        }
        .onAppear(perform: load)
        .onChange(of: detail.origin) { _, _ in load() }
        .task(id: "\(detail.origin?.version ?? 0)") { await loadLists() }
        .disabled(!detail.canEdit)
    }

    private func load() {
        guard let o else { return }
        ot = detail.ot; tid = "\(o.tid)"; sid = "\(o.sid)"; ht = o.htName
        metLevel = "\(o.metLevel)"; pid = o.pid; ec = o.ec
    }

    private func loadLists() async {
        guard let o else { return }
        let met: OriginLists? = try? await model.call("originLists", ["version": o.version, "egg": false])
        let egg: OriginLists? = try? await model.call("originLists", ["version": o.version, "egg": true])
        games = met?.games ?? []
        metLocations = met?.locations ?? []
        eggLocations = egg?.locations ?? []
    }

    private func set(_ changes: [String: Any]) { Task { await model.update(changes) } }

    private func field(_ label: String, _ text: Binding<String>, key: String, width: CGFloat = 150, number: Bool = false, mono: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
                .multilineTextAlignment(.trailing)
                .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .onSubmit {
                    if number { if let n = Int(text.wrappedValue.trimmingCharacters(in: .whitespaces)) { set([key: n]) } }
                    else { set([key: text.wrappedValue]) }
                }
        }
        .font(.system(size: 13, design: .rounded))
    }

    private func genderPicker(_ label: String, _ value: Int, key: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: Binding(get: { value }, set: { set([key: $0]) })) {
                Text("♂").tag(0); Text("♀").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 90)
        }
        .font(.system(size: 13, design: .rounded))
    }

    private func dateRow(_ label: String, _ value: String?, key: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            if let value, let d = Self.fmt.date(from: value) {
                DatePicker("", selection: Binding(get: { d }, set: { set([key: Self.fmt.string(from: $0)]) }), displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.field)
                Button { set([key: ""]) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).help(L("Nessuna data"))
            } else {
                Text("—").foregroundStyle(.tertiary)
                Button(L("Imposta")) { set([key: Self.fmt.string(from: Date())]) }.buttonStyle(.glass).controlSize(.small)
            }
        }
        .font(.system(size: 13, design: .rounded))
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private func name(_ list: [ListItem], _ v: Int) -> String { list.first { $0.v == v }?.t ?? (v == 0 ? "—" : "#\(v)") }

    private func trainer(_ o: OriginData) -> some View {
        Card(title: L("Allenatore originale"), symbol: "person.crop.circle", tint: .teal) {
            VStack(spacing: 8) {
                field(L("Nome"), $ot, key: "ot")
                if o.hasOtGender { genderPicker(L("Sesso"), o.otGender, key: "otGender") }
                field("ID", $tid, key: "tid", width: 110, number: true)
                if o.hasSid { field(L("ID segreto"), $sid, key: "sid", width: 110, number: true) }
                if let langs = model.lists?.languages, !langs.isEmpty {
                    PickerRow(label: L("Lingua"), value: name(langs, o.language), items: langs, selected: o.language) { set(["language": $0.v]) }
                }
            }
        }
    }

    private func encounter(_ o: OriginData) -> some View {
        Card(title: L("Incontro"), symbol: "map", tint: .orange) {
            VStack(spacing: 8) {
                if o.hasVersion, !games.isEmpty {
                    PickerRow(label: L("Gioco d'origine"), value: name(games, o.version), items: games, selected: o.version) { set(["version": $0.v]) }
                }
                if let balls = model.lists?.balls, !balls.isEmpty {
                    PickerRow(label: L("Ball"), value: name(balls, o.ball), items: balls, selected: o.ball) { set(["ball": $0.v]) }
                }
                if o.hasMet {
                    PickerRow(label: L("Luogo"), value: name(metLocations, o.metLocation), items: metLocations, selected: o.metLocation) { set(["metLocation": $0.v]) }
                    field(L("Livello d'incontro"), $metLevel, key: "metLevel", width: 70, number: true)
                }
                if o.hasDates { dateRow(L("Data d'incontro"), o.metDate, key: "metDate") }
                if o.hasFateful {
                    Toggle(L("Incontro fatale (evento)"), isOn: Binding(get: { o.fateful }, set: { set(["fateful": $0]) }))
                        .toggleStyle(.switch).font(.system(size: 13, design: .rounded))
                }
            }
        }
    }

    private func egg(_ o: OriginData) -> some View {
        Card(title: L("Uovo"), symbol: "oval.portrait", tint: .yellow) {
            VStack(spacing: 8) {
                PickerRow(label: L("Luogo dell'uovo"), value: name(eggLocations, o.eggLocation), items: eggLocations, selected: o.eggLocation) { set(["eggLocation": $0.v]) }
                dateRow(L("Data dell'uovo"), o.eggDate, key: "eggDate")
            }
        }
    }

    private func handler(_ o: OriginData) -> some View {
        Card(title: L("Allenatore attuale"), symbol: "person.2", tint: .purple) {
            VStack(spacing: 8) {
                HStack {
                    Text(L("Ce l'ha")).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: Binding(get: { o.currentHandler }, set: { set(["currentHandler": $0]) })) {
                        Text("OT").tag(0); Text(L("Altro allenatore")).tag(1)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                }
                .font(.system(size: 13, design: .rounded))
                field(L("Nome"), $ht, key: "htName")
                genderPicker(L("Sesso"), o.htGender, key: "htGender")
            }
        }
    }

    private func technical(_ o: OriginData) -> some View {
        Card(title: L("Dati tecnici"), symbol: "cpu", tint: .gray) {
            VStack(spacing: 8) {
                HStack {
                    field("PID", $pid, key: "pid", width: 110, mono: true)
                    Button { set(["rerollPid": true]) } label: { Image(systemName: "dice") }.buttonStyle(.glass).controlSize(.small)
                        .help(L("Nuovo PID casuale (mantiene il sesso)"))
                }
                if o.hasEc {
                    HStack {
                        field(L("Encryption constant"), $ec, key: "ec", width: 110, mono: true)
                        Button { set(["rerollEc": true]) } label: { Image(systemName: "dice") }.buttonStyle(.glass).controlSize(.small)
                            .help(L("Nuova encryption constant casuale"))
                    }
                }
                InfoRow(L("Formato"), L("Gen \(detail.format) · origine Gen \(detail.generation)"))
                InfoRow(L("Esperienza"), "\(detail.exp)")
                InfoRow(L("Nome file"), detail.fileName, mono: true)
                Text(L("Ogni campo è modificabile come in PKHeX: il controllo di legalità in alto ti dice subito se il risultato è ancora legale."))
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var mono = false
    init(_ label: String, _ value: String, mono: Bool = false) {
        self.label = label; self.value = value; self.mono = mono
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 13, weight: .medium, design: .rounded))
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 13, design: .rounded))
    }
}

private struct ActionBar: View {
    @Environment(AppModel.self) private var model
    let detail: PokemonDetail

    var body: some View {
        let ref = detail.summary.ref
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button { Task { await model.copyShowdown(ref) } } label: { Label("Showdown", systemImage: "doc.on.doc") }
                Button { model.exportPk(ref) } label: { Label(L("Esporta"), systemImage: "square.and.arrow.up") }
                Button { Task { await model.heal(ref) } } label: { Label(L("Cura"), systemImage: "cross.case") }
                Spacer()
                Button(role: .destructive) { Task { await model.delete(ref) } } label: { Image(systemName: "trash") }
                    .help(L("Rilascia"))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .disabled(!detail.canEdit)
    }
}


// MARK: - Ribbons & marks

private struct RibbonsTab: View {
    @Environment(AppModel.self) private var model
    let ref: SlotRef
    @State private var data: RibbonsData?
    @State private var marks = false
    @State private var filter = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let d = data {
                HStack {
                    StatusBadge(kind: d.ribbonsValid ? .ok : .bad, text: d.ribbonsValid ? L("Fiocchi legali") : L("Fiocchi non legali"))
                    Text("\(d.owned)/\(d.ribbons.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Button { Task { data = await model.setRibbons(ref, action: "allValid") ?? data } } label: { Label(L("Tutti quelli ottenibili legalmente"), systemImage: "rosette") }
                        Button(role: .destructive) { Task { data = await model.setRibbons(ref, action: "removeAll") ?? data } } label: { Label(L("Togli tutti"), systemImage: "xmark") }
                    } label: { Image(systemName: "wand.and.stars") }
                    .menuIndicator(.hidden).buttonStyle(.glass).controlSize(.small)
                }
                if d.ribbons.contains(where: \.mark) {
                    Picker("", selection: $marks) { Text(L("Fiocchi")).tag(false); Text(L("Emblemi")).tag(true) }
                        .pickerStyle(.segmented).labelsHidden()
                }
                TextField(L("Cerca"), text: $filter).textFieldStyle(.roundedBorder)
                let rows = d.ribbons.filter { $0.mark == marks && (filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter)) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(rows) { r in
                        RibbonChip(row: r, affixed: false) { v in
                            Task { data = await model.setRibbons(ref, set: [["prop": r.prop, "value": v]]) ?? data }
                        }
                    }
                }
                if rows.isEmpty {
                    Text(d.ribbons.isEmpty ? L("Questo formato non ha fiocchi.") : L("Nessun risultato.")).font(.callout).foregroundStyle(.secondary)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: ref) { data = await model.ribbons(ref) }
    }
}

private struct RibbonChip: View {
    let row: RibbonRow
    let affixed: Bool
    let onSet: (Int) -> Void
    @State private var hover = false

    private var on: Bool { row.value > 0 }
    private var hue: Double { Double(row.prop.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % 360) / 360 }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Image(systemName: row.mark ? "seal.fill" : "rosette")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(on ? AnyShapeStyle(LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 1), Color(hue: hue, saturation: 0.8, brightness: 0.8)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(.quaternary))
                    .symbolEffect(.bounce, value: on)
            }
            .frame(width: 22)
            Text(row.name).font(.system(size: 11, weight: on ? .semibold : .regular)).lineLimit(2).foregroundStyle(on ? .primary : .secondary)
            Spacer(minLength: 0)
            if row.count {
                Stepper("\(row.value)", value: Binding(get: { row.value }, set: { onSet($0) }), in: 0...row.max)
                    .font(.system(size: 10.5).monospacedDigit()).controlSize(.mini)
            }
        }
        .padding(7)
        .background(on ? Color.accentColor.opacity(hover ? 0.16 : 0.1) : .primary.opacity(hover ? 0.06 : 0.03), in: .rect(cornerRadius: 10, style: .continuous))
        .contentShape(.rect)
        .onHover { hover = $0 }
        .onTapGesture { if !row.count { onSet(on ? 0 : 1) } }
        .help(row.name)
    }
}

extension Notification.Name {
    static let pkmacTourTab = Notification.Name("pkmacTourTab")
}

enum InspectorTour {
    static let tabs = ["summary", "stats", "moves", "origin", "ribbons", "advanced", "summary"]
}
