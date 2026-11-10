import SwiftUI
import Charts
import UniformTypeIdentifiers

struct PartyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: L("Squadra"), subtitle: L("\(model.party.filter { !$0.empty }.count) di 6 Pokémon"), symbol: "person.3.fill", tint: AppSection.party.tint)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 16)], spacing: 16) {
                    ForEach(model.party) { p in
                        PartyCard(slot: p)
                    }
                }
            }
            .padding(26)
        }
    }
}

private struct PartyCard: View {
    @Environment(AppModel.self) private var model
    let slot: SlotSummary
    @State private var hover = false
    @State private var targeted = false

    var body: some View {
        let t = PokeType(key: slot.primaryType)
        let selected = model.selection == slot.ref
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(RadialGradient(colors: [t.glow.opacity(0.7), t.color.opacity(0.15)], center: .center, startRadius: 2, endRadius: 60))
                if slot.empty {
                    Image(systemName: "plus").font(.title2).foregroundStyle(.secondary)
                } else {
                    PokemonSprite(key: slot.sprite, tint: t.color)
                        .padding(6)
                        .offset(y: hover ? -4 : 0)
                }
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 6) {
                if slot.empty {
                    Text(L("Slot libero")).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Text(slot.displayName).font(.system(size: 17, weight: .bold, design: .rounded)).lineLimit(1)
                        GenderMark(gender: slot.gender ?? 2).scaleEffect(0.8)
                        if slot.shiny == true { Image(systemName: "sparkles").foregroundStyle(.yellow) }
                    }
                    Text("Lv. \(slot.level ?? 0)").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    HStack(spacing: 4) { ForEach(slot.types ?? [], id: \.self) { TypePill(type: PokeType(key: $0), compact: true) } }
                    if let item = slot.heldItemName {
                        HStack(spacing: 4) {
                            ItemIcon(key: slot.heldItemKey).frame(width: 16, height: 16)
                            Text(item).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if slot.legal == false {
                Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red).help(L("Non legale"))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(t.color.opacity(slot.empty ? 0.03 : (hover ? 0.16 : 0.10)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(selected ? t.color : .primary.opacity(0.06), lineWidth: selected ? 2.5 : 1)
        )
        .scaleEffect(targeted ? 1.03 : 1)
        .onHover { hover = $0 }
        .animation(Theme.snappy, value: hover)
        .onTapGesture {
            if slot.empty { model.selection = slot.ref; model.detail = nil }
            else { Task { await model.select(slot.ref) } }
        }
        .contextMenu { SlotMenu(slot: slot) }
        .onDrop(of: [.pkmacSlot], isTargeted: $targeted) { providers in
            let copy = NSEvent.modifierFlags.contains(.option)
            let target = slot.ref
            return AppModel.loadDrag(providers) { drag in
                Task {
                    if drag.save == "a" { await model.move(from: drag.ref, to: target, copy: copy) }
                    else { await model.transfer(from: drag, to: SlotDrag(save: "a", ref: target), copy: copy) }
                }
            }
        }
        .onDrag {
            guard !slot.empty else { return NSItemProvider() }
            return AppModel.dragProvider(save: "a", ref: slot.ref, name: slot.displayName)
        }
    }
}

struct Header: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.25), tint], startPoint: .top, endPoint: .bottom)))
                .shadow(color: tint.opacity(0.4), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
                Text(subtitle).font(.system(size: 13, design: .rounded)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Overview

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @State private var data: Overview?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: L("Panoramica"), subtitle: model.save.map { "\($0.game) · \($0.ot)" } ?? "", symbol: "chart.pie.fill", tint: AppSection.overview.tint)
                if let d = data {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                        Tile(title: "Pokémon", value: "\(d.total)", detail: L("su \(d.capacity) posti nei box"), symbol: "square.grid.3x3.fill", tint: .blue)
                        RingTile(title: L("Specie uniche"), value: d.uniqueSpecies, total: d.maxSpecies, tint: .purple)
                        Tile(title: L("Cromatici"), value: "\(d.shiny)", detail: d.total > 0 ? String(format: "%.1f%% della collezione", Double(d.shiny) / Double(d.total) * 100) : "", symbol: "sparkles", tint: .yellow)
                        Tile(title: L("Da sistemare"), value: "\(d.illegal)", detail: d.illegal == 0 ? L("tutto legale") : L("non legali"), symbol: d.illegal == 0 ? "checkmark.seal.fill" : "exclamationmark.octagon.fill", tint: d.illegal == 0 ? .green : .red)
                        if d.eggs > 0 { Tile(title: L("Uova"), value: "\(d.eggs)", detail: L("in attesa di schiudersi"), symbol: "oval.portrait.fill", tint: .orange) }
                    }
                    HStack(alignment: .top, spacing: 14) {
                        Card(title: L("Tipi più presenti"), symbol: "circle.hexagongrid.fill", tint: .pink) {
                            Chart(d.types.prefix(10), id: \.type) { t in
                                BarMark(x: .value("Pokémon", t.count), y: .value("Tipo", PokeType(key: t.type).italian))
                                    .foregroundStyle(PokeType(key: t.type).color.gradient)
                                    .cornerRadius(6)
                                    .annotation(position: .trailing) {
                                        Text("\(t.count)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                                    }
                            }
                            .chartXAxis(.hidden)
                            .frame(height: 280)
                        }
                        Card(title: L("Livelli"), symbol: "chart.bar.fill", tint: .teal) {
                            Chart(Array(d.levels.enumerated()), id: \.offset) { i, v in
                                BarMark(x: .value("Livello", "\(i * 10 + 1)–\(i * 10 + 10)"), y: .value("Pokémon", v))
                                    .foregroundStyle(Theme.brand)
                                    .cornerRadius(6)
                            }
                            .frame(height: 280)
                        }
                    }
                    if d.illegal > 0 {
                        Button {
                            model.searchText = "illegale"
                        } label: {
                            Label(L("Mostra i \(d.illegal) Pokémon non legali"), systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.glass)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(26)
        }
        .task(id: model.save?.dirty) { data = await model.overview() }
    }
}

private struct Tile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(tint)
            Text(value).font(.system(size: 32, weight: .heavy, design: .rounded)).contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.09), in: .rect(cornerRadius: 20, style: .continuous))
    }
}

private struct RingTile: View {
    let title: String
    let value: Int
    let total: Int
    let tint: Color
    @State private var appear = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(tint.opacity(0.15), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: appear ? CGFloat(value) / CGFloat(max(1, total)) : 0)
                    .stroke(AngularGradient(colors: [tint.mix(with: .white, by: 0.3), tint], center: .center), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(Double(value) / Double(max(1, total)) * 100))%").font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .frame(width: 66, height: 66)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)").font(.system(size: 28, weight: .heavy, design: .rounded))
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("su \(total)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.09), in: .rect(cornerRadius: 20, style: .continuous))
        .onAppear { withAnimation(.spring(response: 1, dampingFraction: 0.8).delay(0.15)) { appear = true } }
    }
}

// MARK: - Trainer

/// Player character sprite for the loaded game (Pokémon Showdown trainer sprites), cached on disk.
enum TrainerArt {
    static func name(versionKey: String?, gender: Int) -> String? {
        let f = gender == 1
        switch versionKey ?? "" {
        case "RD", "GN", "BU", "YW", "RBY": return "red-gen1"
        case "GD", "SI", "GS": return "ethan-gen2"
        case "C": return f ? "kris-gen2" : "ethan-gen2c"
        case "R", "S", "RS": return f ? "may-rs" : "brendan-rs"
        case "E": return f ? "may-e" : "brendan-e"
        case "FR", "LG", "FRLG": return f ? "leaf-gen3" : "red-gen3"
        case "D", "P", "DP", "BD", "SP", "BDSP": return f ? "dawn" : "lucas"
        case "Pt": return f ? "dawn-gen4pt" : "lucas-gen4pt"
        case "HG", "SS", "HGSS": return f ? "lyra" : "ethan"
        case "B", "W", "BW": return f ? "hilda" : "hilbert"
        case "B2", "W2", "B2W2": return f ? "rosa" : "nate"
        case "X", "Y", "XY": return f ? "serena" : "calem"
        case "OR", "AS", "ORAS": return f ? "may" : "brendan"
        case "SN", "MN", "SM": return f ? "selene" : "elio"
        case "US", "UM", "USUM": return f ? "selene-usum" : "elio-usum"
        case "GP", "GE", "GG": return f ? "elaine" : "chase"
        case "SW", "SH", "SWSH": return f ? "gloria" : "victor"
        case "PLA": return f ? "akari" : "rei"
        case "SL", "VL", "SV": return f ? "juliana" : "florian"
        case "ZA": return f ? "lida" : "urbain"
        default: return nil
        }
    }

    static func url(_ name: String) -> URL { URL(string: "https://play.pokemonshowdown.com/sprites/trainers/\(name).png")! }
}

actor TrainerArtStore {
    static let shared = TrainerArtStore()
    private var memory: [String: NSImage] = [:]
    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PkMac/Trainers", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    func image(_ name: String) async -> NSImage? {
        if let m = memory[name] { return m }
        let file = dir.appendingPathComponent("\(name).png")
        if let data = try? Data(contentsOf: file), let img = NSImage(data: data) { memory[name] = img; return img }
        guard let (data, resp) = try? await URLSession.shared.data(from: TrainerArt.url(name)),
              (resp as? HTTPURLResponse)?.statusCode == 200, let img = NSImage(data: data) else { return nil }
        let out = img.trimmedTransparent() ?? img
        if let png = out.pngData { try? png.write(to: file) }
        memory[name] = out
        return out
    }
}

struct TrainerSprite: View {
    let versionKey: String?
    let gender: Int
    @State private var image: NSImage?
    @State private var bob = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 8)
                    .offset(y: bob ? -4 : 2)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: bob)
                    .onAppear { bob = true }
            } else {
                HeroOrb().opacity(0.9).padding(30)
            }
        }
        .task(id: "\(versionKey ?? "")-\(gender)") {
            guard let name = TrainerArt.name(versionKey: versionKey, gender: gender) else { image = nil; return }
            image = await TrainerArtStore.shared.image(name)
        }
    }
}

struct TrainerView: View {
    @Environment(AppModel.self) private var model
    @State private var t: TrainerData?
    @State private var name = ""
    @State private var money = ""
    @State private var tid = ""
    @State private var sid = ""
    @State private var gender = 0
    @State private var hours = 0
    @State private var minutes = 0
    @State private var seconds = 0
    @State private var language = 0
    @State private var badges = 0
    @State private var stamps = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Header(title: L("Allenatore"), subtitle: L("Dati del giocatore nel salvataggio"), symbol: "person.text.rectangle.fill", tint: AppSection.trainer.tint)
                if let t {
                    TrainerCard(t: t, previewName: name, previewGender: gender)
                        .frame(maxWidth: 620)
                    HStack(alignment: .top, spacing: 16) {
                        identity(t)
                        progress(t)
                    }
                    .frame(maxWidth: 900)
                    HStack {
                        Button {
                            model.section = .advanced
                        } label: { Label(L("Tutti gli altri campi del salvataggio…"), systemImage: "slider.horizontal.below.square.and.square.filled") }
                        .buttonStyle(.glass)
                        Spacer()
                        Button(L("Ripristina")) { load(t) }.buttonStyle(.glass)
                        Button { Task { await apply(t) } } label: { Label(L("Applica modifiche"), systemImage: "checkmark") }
                            .buttonStyle(.glassProminent)
                            .keyboardShortcut(.return, modifiers: .command)
                    }
                    .frame(maxWidth: 900)
                }
            }
            .padding(26)
        }
        .task(id: model.save?.path) {
            t = await model.trainer()
            if let t { load(t) }
        }
    }

    private func load(_ t: TrainerData) {
        name = t.ot; money = "\(t.money)"; tid = "\(t.tid)"; sid = "\(t.sid)"
        gender = t.gender; hours = t.hours; minutes = t.minutes; seconds = t.seconds
        language = t.language; badges = t.badges?.value ?? 0; stamps = t.stamps?.value ?? 0
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            c()
        }
    }

    private func identity(_ t: TrainerData) -> some View {
        Card(title: L("Identità"), symbol: "person.crop.circle.fill", tint: .teal) {
            VStack(spacing: 12) {
                row(L("Nome (OT)")) {
                    TextField(L("Nome"), text: $name).textFieldStyle(.roundedBorder)
                    Text("\(name.count)/\(t.maxOtLength)").font(.caption.monospacedDigit()).foregroundStyle(name.count > t.maxOtLength ? .red : .secondary)
                }
                if t.hasGender ?? true {
                    row(L("Personaggio")) {
                        Picker("", selection: $gender) {
                            Label(L("Ragazzo"), systemImage: "figure.stand").tag(0)
                            Label(L("Ragazza"), systemImage: "figure.stand.dress").tag(1)
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                }
                row(t.idFormat == "6" ? L("ID (6 cifre)") : L("ID allenatore")) {
                    TextField("ID", text: $tid).textFieldStyle(.roundedBorder).monospacedDigit()
                    Text("max \(t.tidMax ?? 65535)").font(.caption).foregroundStyle(.tertiary)
                }
                if t.hasSid ?? true {
                    row(L("ID segreto")) {
                        TextField("SID", text: $sid).textFieldStyle(.roundedBorder).monospacedDigit()
                        Text("max \(t.sidMax ?? 65535)").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                if let langs = t.languages, !langs.isEmpty {
                    row(L("Lingua")) {
                        Picker("", selection: $language) {
                            ForEach(langs, id: \.v) { Text($0.t).tag($0.v) }
                        }
                        .labelsHidden()
                    }
                }
                Text(L("Cambiare ID o ID segreto rende \"non tuoi\" i Pokémon già catturati (scambio): fallo solo se sai cosa stai facendo."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func progress(_ t: TrainerData) -> some View {
        Card(title: L("Progressi"), symbol: "clock.fill", tint: .orange) {
            VStack(spacing: 12) {
                row(L("Soldi")) {
                    TextField(L("Soldi"), text: $money).textFieldStyle(.roundedBorder).monospacedDigit()
                    Button(L("Max")) { money = "\(t.maxMoney)" }.buttonStyle(.glass).controlSize(.small)
                }
                row(L("Tempo di gioco")) {
                    Stepper(value: $hours, in: 0...(t.maxHours ?? 999)) { Text("\(hours) h").monospacedDigit().frame(width: 52, alignment: .trailing) }
                    Stepper(value: $minutes, in: 0...59) { Text("\(minutes) m").monospacedDigit().frame(width: 40, alignment: .trailing) }
                    Stepper(value: $seconds, in: 0...59) { Text("\(seconds) s").monospacedDigit().frame(width: 36, alignment: .trailing) }
                }
                if let b = t.badges {
                    row(L("Medaglie")) {
                        if b.layout == "galar" {
                            GalarBadgeCase(value: $badges, shield: t.versionKey == "SH")
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(stride(from: 0, to: b.count, by: 8)), id: \.self) { start in
                                    HStack(spacing: 5) {
                                        ForEach(start..<min(start + 8, b.count), id: \.self) { i in
                                            let on = badges & (1 << i) != 0
                                            let sprites = b.sprites ?? []
                                            let sid: Int? = sprites.indices.contains(i) ? sprites[i] : nil
                                            Button {
                                                badges ^= (1 << i)
                                            } label: {
                                                BadgeIcon(spriteID: sid, on: on)
                                            }
                                            .buttonStyle(.plain)
                                            .allowsHitTesting(b.readOnly != true)
                                            .help(L("Medaglia \(i + 1)"))
                                        }
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 6)
                        if b.readOnly != true {
                            Button(L("Tutte")) { badges = (1 << b.count) - 1 }.buttonStyle(.glass).controlSize(.small)
                        }
                    }
                    if b.readOnly == true {
                        Text(L("In Scarlatto e Violetto le medaglie sono i segnali della trama «palestra superata»: qui le vedi, ma si cambiano solo da Eventi di gioco o Dati avanzati."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let st = t.stamps {
                    row(L("Timbri")) {
                        StampGrid(names: st.names, value: $stamps)
                    }
                }
                if let seen = t.seenCount, let caught = t.caughtCount, seen + caught > 0 {
                    row("Pokédex") {
                        Text(L("\(seen) visti · \(caught) catturati")).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Apri")) { model.section = .pokedex }.buttonStyle(.glass).controlSize(.small)
                    }
                }
            }
        }
    }

    private func apply(_ t: TrainerData) async {
        var p: [String: Any] = ["ot": name, "hours": hours, "minutes": minutes, "seconds": seconds]
        if let m = Int(money) { p["money"] = m }
        if t.hasGender ?? true { p["gender"] = gender }
        if let v = Int(tid) { p["tid"] = v }
        if (t.hasSid ?? true), let v = Int(sid) { p["sid"] = v }
        if !(t.languages ?? []).isEmpty { p["language"] = language }
        if let b = t.badges, b.readOnly != true { p["badges"] = badges }
        if t.stamps != nil { p["stamps"] = stamps }
        if let nt = await model.setTrainer(p) {
            self.t = nt
            load(nt)
            model.toast(.success, L("Dati allenatore aggiornati"))
        }
    }
}

private struct TrainerCard: View {
    let t: TrainerData
    var previewName: String
    var previewGender: Int
    @State private var tilt = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x2CC5A4), Color(hex: 0x3F7BFF), Color(hex: 0x8A4DFF)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.white.opacity(0.10)).frame(width: 260).offset(x: 360, y: -90)
            Circle().fill(.white.opacity(0.07)).frame(width: 180).offset(x: 420, y: 120)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("TRAINER CARD")).font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(2).opacity(0.8)
                    Text(previewName.isEmpty ? t.ot : previewName).font(.system(size: 34, weight: .heavy, design: .rounded)).lineLimit(1)
                    HStack(spacing: 28) {
                        field("ID", "\(t.tid)")
                        field(L("Gioco"), t.game)
                    }
                    HStack(spacing: 28) {
                        field(L("Soldi"), "₽ \(t.money.formatted())")
                        field(L("Tempo di gioco"), "\(t.hours)h \(t.minutes)m")
                    }
                }
                Spacer(minLength: 0)
                TrainerSprite(versionKey: t.versionKey, gender: previewGender)
                    .frame(width: 170, height: 200)
                    .id(previewGender)
                    .transition(.scale.combined(with: .opacity))
            }
            .foregroundStyle(.white)
            .padding(26)
            .animation(Theme.spring, value: previewGender)
        }
        .frame(height: 250)
        .clipShape(.rect(cornerRadius: 26, style: .continuous))
        .shadow(color: Color(hex: 0x3F7BFF).opacity(0.35), radius: 20, y: 12)
        .rotation3DEffect(.degrees(tilt ? 2.5 : -2.5), axis: (x: 0.4, y: 1, z: 0))
        .animation(.easeInOut(duration: 4).repeatForever(), value: tilt)
        .onAppear { tilt = true }
    }

    private func field(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k.uppercased()).font(.system(size: 9.5, weight: .bold, design: .rounded)).tracking(1).opacity(0.75)
            Text(v).font(.system(size: 16, weight: .bold, design: .rounded))
        }
    }
}


/// One gym badge: the official sprite of that game (PokeAPI) when available, a generic seal otherwise.
/// Badges not obtained are shown faded and in grey.
struct BadgeIcon: View {
    let spriteID: Int?
    let on: Bool
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .saturation(on ? 1 : 0)
                    .opacity(on ? 1 : 0.28)
                    .shadow(color: .black.opacity(on ? 0.25 : 0), radius: 2, y: 1)
            } else {
                Image(systemName: on ? "seal.fill" : "seal")
                    .font(.system(size: 17))
                    .foregroundStyle(on ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(.tertiary))
            }
        }
        .frame(width: 24, height: 24)
        .scaleEffect(on ? 1 : 0.92)
        .animation(Theme.snappy, value: on)
        .task(id: spriteID) {
            guard let spriteID else { image = nil; return }
            image = await SpriteStore.shared.badge(spriteID)
        }
    }
}


/// Sun/Moon trainer card stamps: one toggle per stamp.
struct StampGrid: View {
    let names: [String]
    @Binding var value: Int

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                let on = value & (1 << i) != 0
                Button { value ^= (1 << i) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: on ? "checkmark.seal.fill" : "seal")
                            .foregroundStyle(on ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(.tertiary))
                        Text(name).font(.system(size: 11.5, design: .rounded)).foregroundStyle(on ? .primary : .secondary).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Sword/Shield: one round badge case made of eight pieces, one per gym; click a piece to add or remove that badge.
/// Original drawing (type symbols), not the game's artwork.
struct GalarBadgeCase: View {
    @Binding var value: Int
    let shield: Bool

    /// Gym order as stored in the save: Grass, Water, Fire, Fighting/Ghost, Fairy, Rock/Ice, Dark, Dragon.
    private var gyms: [(symbol: String, color: Color, name: String)] {
        [
            ("leaf.fill", Color(hex: 0x5FBD58), L("Erba")),
            ("drop.fill", Color(hex: 0x3D9BE9), L("Acqua")),
            ("flame.fill", Color(hex: 0xF08030), L("Fuoco")),
            shield ? ("moon.haze.fill", Color(hex: 0x705898), L("Spettro")) : ("figure.boxing", Color(hex: 0xC03028), L("Lotta")),
            ("sparkles", Color(hex: 0xEE99AC), L("Folletto")),
            shield ? ("snowflake", Color(hex: 0x6CC9E0), L("Ghiaccio")) : ("mountain.2.fill", Color(hex: 0xB8A038), L("Roccia")),
            ("moon.fill", Color(hex: 0x4A4A4A), L("Buio")),
            ("lizard.fill", Color(hex: 0x3B4CCA), L("Drago")),
        ]
    }

    var body: some View {
        let size: CGFloat = 132
        ZStack {
            Circle().fill(.primary.opacity(0.06))
            ForEach(0..<8, id: \.self) { i in
                let on = value & (1 << i) != 0
                let g = gyms[i]
                let mid = Angle.degrees(Double(i) * 45 - 90 + 22.5)
                ZStack {
                    Wedge(start: .degrees(Double(i) * 45 - 90), end: .degrees(Double(i + 1) * 45 - 90))
                        .fill(on ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xF6DC7A), Color(hex: 0xE2B53E)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(.primary.opacity(0.07)))
                    Wedge(start: .degrees(Double(i) * 45 - 90), end: .degrees(Double(i + 1) * 45 - 90))
                        .stroke(.primary.opacity(0.18), lineWidth: 1)
                    Image(systemName: g.symbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(on ? g.color : Color.secondary.opacity(0.45))
                        .offset(x: cos(mid.radians) * size * 0.31, y: sin(mid.radians) * size * 0.31)
                }
                .contentShape(Wedge(start: .degrees(Double(i) * 45 - 90), end: .degrees(Double(i + 1) * 45 - 90)))
                .onTapGesture { withAnimation(Theme.snappy) { value ^= (1 << i) } }
                .help(L("Medaglia \(i + 1) · \(g.name)"))
            }
            Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1.5)
        }
        .frame(width: size, height: size)
    }
}

/// Pie slice from the centre, angles measured clockwise from the right.
struct Wedge: Shape {
    let start: Angle
    let end: Angle
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let radius = min(r.width, r.height) / 2
        var p = Path()
        p.move(to: c)
        p.addArc(center: c, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        p.closeSubpath()
        return p
    }
}
