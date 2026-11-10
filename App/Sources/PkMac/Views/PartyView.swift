import SwiftUI
import Charts
import UniformTypeIdentifiers

struct PartyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: "Squadra", subtitle: "\(model.party.filter { !$0.empty }.count) di 6 Pokémon", symbol: "person.3.fill", tint: AppSection.party.tint)
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
                    Text("Slot libero").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
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
                Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red).help("Non legale")
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
            guard let p = providers.first else { return false }
            p.loadDataRepresentation(forTypeIdentifier: UTType.pkmacSlot.identifier) { data, _ in
                guard let data, let from = try? JSONDecoder().decode(SlotRef.self, from: data) else { return }
                Task { @MainActor in await model.move(from: from, to: slot.ref, copy: false) }
            }
            return true
        }
        .onDrag {
            guard !slot.empty, let data = try? JSONEncoder().encode(slot.ref) else { return NSItemProvider() }
            let p = NSItemProvider()
            p.registerDataRepresentation(forTypeIdentifier: UTType.pkmacSlot.identifier, visibility: .ownProcess) { done in done(data, nil); return nil }
            return p
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
                Header(title: "Panoramica", subtitle: model.save.map { "\($0.game) · \($0.ot)" } ?? "", symbol: "chart.pie.fill", tint: AppSection.overview.tint)
                if let d = data {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                        Tile(title: "Pokémon", value: "\(d.total)", detail: "su \(d.capacity) posti nei box", symbol: "square.grid.3x3.fill", tint: .blue)
                        RingTile(title: "Specie uniche", value: d.uniqueSpecies, total: d.maxSpecies, tint: .purple)
                        Tile(title: "Cromatici", value: "\(d.shiny)", detail: d.total > 0 ? String(format: "%.1f%% della collezione", Double(d.shiny) / Double(d.total) * 100) : "", symbol: "sparkles", tint: .yellow)
                        Tile(title: "Da sistemare", value: "\(d.illegal)", detail: d.illegal == 0 ? "tutto legale" : "non legali", symbol: d.illegal == 0 ? "checkmark.seal.fill" : "exclamationmark.octagon.fill", tint: d.illegal == 0 ? .green : .red)
                        if d.eggs > 0 { Tile(title: "Uova", value: "\(d.eggs)", detail: "in attesa di schiudersi", symbol: "oval.portrait.fill", tint: .orange) }
                    }
                    HStack(alignment: .top, spacing: 14) {
                        Card(title: "Tipi più presenti", symbol: "circle.hexagongrid.fill", tint: .pink) {
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
                        Card(title: "Livelli", symbol: "chart.bar.fill", tint: .teal) {
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
                            Label("Mostra i \(d.illegal) Pokémon non legali", systemImage: "magnifyingglass")
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

struct TrainerView: View {
    @Environment(AppModel.self) private var model
    @State private var t: TrainerData?
    @State private var name = ""
    @State private var money = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Header(title: "Allenatore", subtitle: "Dati del giocatore nel salvataggio", symbol: "person.text.rectangle.fill", tint: AppSection.trainer.tint)
                if let t {
                    TrainerCard(t: t)
                        .frame(maxWidth: 560)
                    Card(title: "Modifica", symbol: "pencil", tint: .teal) {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Nome").foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                                TextField("Nome", text: $name).textFieldStyle(.roundedBorder)
                                Text("max \(t.maxOtLength)").font(.caption).foregroundStyle(.tertiary)
                            }
                            HStack {
                                Text("Soldi").foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                                TextField("Soldi", text: $money).textFieldStyle(.roundedBorder)
                                Button("Massimo") { money = "\(t.maxMoney)" }.buttonStyle(.glass).controlSize(.small)
                            }
                            HStack {
                                Spacer()
                                Button("Applica") {
                                    Task {
                                        var p: [String: Any] = ["ot": name]
                                        if let m = Int(money) { p["money"] = m }
                                        if let nt = await model.setTrainer(p) { self.t = nt; model.toast(.success, "Dati allenatore aggiornati") }
                                    }
                                }
                                .buttonStyle(.glassProminent)
                            }
                        }
                    }
                    .frame(maxWidth: 560)
                }
            }
            .padding(26)
        }
        .task {
            t = await model.trainer()
            name = t?.ot ?? ""
            money = t.map { "\($0.money)" } ?? ""
        }
    }
}

private struct TrainerCard: View {
    let t: TrainerData
    @State private var tilt = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x2CC5A4), Color(hex: 0x3F7BFF), Color(hex: 0x8A4DFF)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.white.opacity(0.10)).frame(width: 260).offset(x: 330, y: -90)
            Circle().fill(.white.opacity(0.07)).frame(width: 180).offset(x: 380, y: 120)
            HeroOrb().frame(width: 70, height: 70).opacity(0.9).offset(x: 450, y: 20)
            VStack(alignment: .leading, spacing: 16) {
                Text("TRAINER CARD").font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(2).opacity(0.8)
                Text(t.ot).font(.system(size: 34, weight: .heavy, design: .rounded))
                HStack(spacing: 28) {
                    field("ID", "\(t.tid)")
                    field("Gioco", t.game)
                }
                HStack(spacing: 28) {
                    field("Soldi", "₽ \(t.money.formatted())")
                    field("Tempo di gioco", "\(t.hours)h \(t.minutes)m")
                }
            }
            .foregroundStyle(.white)
            .padding(26)
        }
        .frame(height: 240)
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
