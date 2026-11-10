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
            Text("Seleziona un Pokémon").font(.system(size: 16, weight: .semibold, design: .rounded))
            Text("Clicca uno slot per vederlo e modificarlo.\nTrascina per spostare, ⌥ per copiare.")
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
            Text("Slot vuoto").font(.system(size: 17, weight: .bold, design: .rounded))
            Text(ref.label).foregroundStyle(.secondary).font(.callout)
            VStack(spacing: 10) {
                Button { model.showCreate = true } label: {
                    Label("Crea un Pokémon legale", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                Button { model.showShowdownImport = true } label: {
                    Label("Incolla set Showdown", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                Button {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = false
                    panel.message = "Scegli un file .pk"
                    if panel.runModal() == .OK, let url = panel.url { Task { await model.importPk(url, to: ref) } }
                } label: {
                    Label("Importa file .pk…", systemImage: "doc.badge.plus").frame(maxWidth: .infinity)
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
    case summary = "Riepilogo", stats = "Statistiche", moves = "Mosse", origin = "Origine", ribbons = "Fiocchi", advanced = "Avanzate"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .summary: "sparkles.rectangle.stack"
        case .stats: "hexagon"
        case .moves: "bolt.circle"
        case .origin: "globe.europe.africa"
        case .ribbons: "rosette"
        case .advanced: "slider.horizontal.3"
        }
    }
}

struct PokemonDetailView: View {
    @Environment(AppModel.self) private var model
    let detail: PokemonDetail
    @State private var tab: DetailTab = .summary

    private var type: PokeType { PokeType(key: detail.summary.primaryType) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Hero(detail: detail)
                LegalityBanner(detail: detail)
                Picker("", selection: $tab) {
                    ForEach(DetailTab.allCases) { t in
                        Image(systemName: t.symbol).help(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, -8)
                    .contentTransition(.opacity)

                Group {
                    switch tab {
                    case .summary: SummaryTab(detail: detail)
                    case .stats: StatsTab(detail: detail)
                    case .moves: MovesTab(detail: detail)
                    case .origin: OriginTab(detail: detail)
                    case .ribbons: RibbonsTab(ref: detail.summary.ref)
                    case .advanced:
                        InspectorBrowser(target: ["target": "pkm", "ref": detail.summary.ref.json], rootTitle: detail.summary.displayName, compact: true)
                            .frame(minHeight: 460)
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
                    .help("Clicca per l'animazione")
            }
            .frame(height: 240)
            .onAppear { rotate = true }

            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    if editingName {
                        TextField("Soprannome", text: $name)
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
                            .help("Doppio clic per cambiare soprannome")
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
                        Text("Gigamax").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.pink)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(s.types ?? [], id: \.self) { TypePill(type: PokeType(key: $0)) }
                    if let tera = detail.teraType {
                        HStack(spacing: 3) {
                            Image(systemName: "diamond.fill").font(.system(size: 9))
                            Text("Tera \(PokeType(key: tera).italian)").font(.system(size: 11, weight: .semibold, design: .rounded))
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
                Text(ok ? "Legale" : "Non legale").font(.system(size: 13.5, weight: .bold, design: .rounded))
                Text(ok ? "Superati tutti i controlli di PKHeX" : firstProblem)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if !ok {
                Button { Task { await model.legalize(detail.summary.ref) } } label: {
                    Label("Rendi legale", systemImage: "wand.and.stars")
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)
                .controlSize(.small)
            }
            Button { showReport = true } label: { Image(systemName: "doc.text.magnifyingglass") }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Rapporto di legalità completo")
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
        detail.legality.report.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.contains("===") }.map(String.init) ?? "Controlla il rapporto"
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
            Card(title: "Carattere e abilità", symbol: "theatermasks.fill", tint: PokeType(key: s.primaryType).color) {
                VStack(spacing: 8) {
                    if detail.hasNatures, let natures = lists?.natures {
                        PickerRow(label: "Natura", value: detail.natureName + natureHint, symbol: "leaf", items: natures, selected: detail.nature, disabled: !detail.canEdit) { pick in
                            Task { await model.update(["nature": pick.v]) }
                        }
                    }
                    if !detail.abilities.isEmpty {
                        let items = detail.abilities.map { ListItem(v: $0.index, t: $0.name + ($0.hidden ? " (nascosta)" : "")) }
                        let current = detail.abilities.first { $0.id == detail.ability }?.index
                        PickerRow(label: "Abilità", value: detail.abilityName ?? "—", symbol: "star.circle", items: items, selected: current, disabled: !detail.canEdit) { pick in
                            Task { await model.update(["abilityIndex": pick.v]) }
                        }
                    }
                    if let items = lists?.items, detail.format >= 2 {
                        PickerRow(label: "Strumento", value: s.heldItemName ?? "Nessuno", symbol: "bag", items: items, selected: s.heldItem, disabled: !detail.canEdit) { pick in
                            Task { await model.update(["heldItem": pick.v]) }
                        }
                    }
                    if let balls = lists?.balls, detail.format >= 3 {
                        PickerRow(label: "Ball", value: detail.ballName, symbol: "circle.circle", items: balls, selected: s.ball, disabled: !detail.canEdit) { pick in
                            Task { await model.update(["ball": pick.v]) }
                        }
                    }
                    if detail.teraTypeIndex != nil, let types = lists?.types {
                        let teraItems = types.filter { !($0.key ?? "").isEmpty }
                        PickerRow(label: "Teratipo", value: PokeType(key: detail.teraType).italian, symbol: "diamond", items: teraItems, selected: nil) { pick in
                            Task { await model.update(["teraType": pick.v]) }
                        }
                    }
                }
            }

            Card(title: "Livello e affetto", symbol: "chart.line.uptrend.xyaxis", tint: PokeType(key: s.primaryType).color) {
                VStack(spacing: 10) {
                    ValueSlider(label: "Lv.", value: $level, range: 1...100) {
                        Task { await model.update(["level": Int(level)]) }
                    }
                    ValueSlider(label: "Affetto", value: $friendship, range: 0...255, tint: .pink) {
                        Task { await model.update(["friendship": Int(friendship)]) }
                    }
                    HStack {
                        Toggle(isOn: Binding(get: { s.shiny ?? false }, set: { v in Task { await model.update(["shiny": v]) } })) {
                            Label("Cromatico", systemImage: "sparkles")
                        }
                        .toggleStyle(.switch)
                        Spacer()
                        if detail.format >= 2 {
                            Toggle(isOn: Binding(get: { detail.pokerus }, set: { v in Task { await model.update(["pokerus": v]) } })) {
                                Label("Pokérus", systemImage: "allergens")
                            }
                            .toggleStyle(.switch)
                        }
                    }
                    .font(.system(size: 12.5, design: .rounded))
                    if detail.genderRatio != 255 && detail.genderRatio != 0 && detail.genderRatio != 254 {
                        Picker("Sesso", selection: Binding(get: { s.gender ?? 0 }, set: { v in Task { await model.update(["gender": v]) } })) {
                            Text("♂ Maschio").tag(0)
                            Text("♀ Femmina").tag(1)
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
            Card(title: "Statistiche", symbol: "hexagon.fill", tint: type.color) {
                StatRadar(values: detail.stats, base: detail.baseStats, tint: type.color, up: detail.natureUp, down: detail.natureDown)
                    .frame(height: 230)
                HStack {
                    Text("Totale base \(detail.baseStats.reduce(0, +))")
                    Spacer()
                    Text("IV medi \(Int(Double(detail.ivs.reduce(0, +)) / 6))/\(detail.maxIV)")
                }
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(.secondary)
            }

            Card(title: "IV · valori individuali", symbol: "dna", tint: type.color) {
                VStack(spacing: 6) {
                    ForEach(0..<6, id: \.self) { i in
                        ValueSlider(label: Theme.statShort[i], value: $ivs[i], range: 0...Double(detail.maxIV), tint: Theme.stat(i)) {
                            commitIVs()
                        }
                    }
                    HStack {
                        Button("Tutti al massimo") { ivs = Array(repeating: Double(detail.maxIV), count: 6); commitIVs() }
                        Button("Trick Room (Vel 0)") { ivs = Array(repeating: Double(detail.maxIV), count: 6); ivs[5] = 0; commitIVs() }
                        Spacer()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }

            Card(title: "EV · punti allenamento", symbol: "figure.strengthtraining.traditional", tint: type.color) {
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
                        Button("Azzera") { evs = Array(repeating: 0, count: 6); commitEVs() }
                        Button("252 Att / 252 Vel") { evs = [4, 252, 0, 0, 0, 252]; commitEVs() }
                        Button("252 AtSp / 252 Vel") { evs = [4, 0, 0, 252, 0, 252]; commitEVs() }
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
            model.toast(.warning, "Troppi EV", "Il totale non può superare 510.")
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
            Text("Suggerimento: se le mosse non sono legali, usa «Rendi legale» per farle sistemare ad Auto Legality.")
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
                    Text(move.name ?? "Nessuna mossa")
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
            SearchPicker(title: "Mossa", items: model.lists?.moves ?? [], selected: move.id, showsTypes: true) { pick in
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

    var body: some View {
        VStack(spacing: 12) {
            Card(title: "Allenatore originale", symbol: "person.crop.circle", tint: .teal) {
                VStack(spacing: 8) {
                    HStack {
                        Text("Nome").foregroundStyle(.secondary)
                        Spacer()
                        TextField("OT", text: $ot)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                            .multilineTextAlignment(.trailing)
                            .onSubmit { Task { await model.update(["ot": ot]) } }
                    }
                    InfoRow("ID", "\(detail.tid)")
                    if detail.format >= 3 { InfoRow("ID segreto", "\(detail.sid)") }
                }
            }
            Card(title: "Incontro", symbol: "map", tint: .orange) {
                VStack(spacing: 8) {
                    InfoRow("Gioco d'origine", detail.versionName)
                    InfoRow("Luogo", detail.metLocation.isEmpty ? "—" : detail.metLocation)
                    InfoRow("Livello d'incontro", "\(detail.metLevel)")
                    InfoRow("Lingua", model.lists?.name(\.languages, detail.language) ?? "\(detail.language)")
                }
            }
            Card(title: "Dati tecnici", symbol: "cpu", tint: .gray) {
                VStack(spacing: 8) {
                    InfoRow("PID", detail.pid, mono: true)
                    InfoRow("Encryption constant", detail.encryptionConstant, mono: true)
                    InfoRow("Formato", "Gen \(detail.format) · origine Gen \(detail.generation)")
                    InfoRow("Esperienza", "\(detail.exp)")
                    InfoRow("Nome file", detail.fileName, mono: true)
                }
            }
        }
        .onAppear { ot = detail.ot }
        .disabled(!detail.canEdit)
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
                Button { model.exportPk(ref) } label: { Label("Esporta", systemImage: "square.and.arrow.up") }
                Button { Task { await model.heal(ref) } } label: { Label("Cura", systemImage: "cross.case") }
                Spacer()
                Button(role: .destructive) { Task { await model.delete(ref) } } label: { Image(systemName: "trash") }
                    .help("Rilascia")
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
                    StatusBadge(kind: d.ribbonsValid ? .ok : .bad, text: d.ribbonsValid ? "Fiocchi legali" : "Fiocchi non legali")
                    Text("\(d.owned)/\(d.ribbons.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Button { Task { data = await model.setRibbons(ref, action: "allValid") ?? data } } label: { Label("Tutti quelli ottenibili legalmente", systemImage: "rosette") }
                        Button(role: .destructive) { Task { data = await model.setRibbons(ref, action: "removeAll") ?? data } } label: { Label("Togli tutti", systemImage: "xmark") }
                    } label: { Image(systemName: "wand.and.stars") }
                    .menuIndicator(.hidden).buttonStyle(.glass).controlSize(.small)
                }
                if d.ribbons.contains(where: \.mark) {
                    Picker("", selection: $marks) { Text("Fiocchi").tag(false); Text("Emblemi").tag(true) }
                        .pickerStyle(.segmented).labelsHidden()
                }
                TextField("Cerca", text: $filter).textFieldStyle(.roundedBorder)
                let rows = d.ribbons.filter { $0.mark == marks && (filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter)) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(rows) { r in
                        RibbonChip(row: r, affixed: false) { v in
                            Task { data = await model.setRibbons(ref, set: [["prop": r.prop, "value": v]]) ?? data }
                        }
                    }
                }
                if rows.isEmpty {
                    Text(d.ribbons.isEmpty ? "Questo formato non ha fiocchi." : "Nessun risultato.").font(.callout).foregroundStyle(.secondary)
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
