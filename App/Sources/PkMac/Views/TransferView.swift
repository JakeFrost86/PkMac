import SwiftUI

/// Two saves side by side: drag Pokémon between them. Every move is converted for the destination game
/// by the engine and refused when the Pokémon can't exist there.
struct TransferView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.pkCompact) private var compact

    var body: some View {
        Group {
            if compact {
                // Narrow screens: the two saves one under the other, scrolling together.
                ScrollView { content.pkPadding(26) }
            } else {
                content.pkPadding(26)
            }
        }
        .task(id: model.save?.path) { await model.reloadTransferA() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(title: L("Trasferisci tra salvataggi"),
                   subtitle: Platform.isMac
                       ? L("Trascina un Pokémon da un gioco all'altro · ⌥ per copiare · i trasferimenti impossibili vengono bloccati")
                       : L("Trascina un Pokémon da un gioco all'altro · i trasferimenti impossibili vengono bloccati"),
                   symbol: "arrow.left.arrow.right.square.fill", tint: AppSection.transfer.tint)
            if compact {
                VStack(spacing: 12) {
                    SavePane(side: "a")
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.brand)
                    SavePane(side: "b")
                }
            } else {
                HStack(alignment: .top, spacing: 18) {
                    SavePane(side: "a")
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.brand)
                        .padding(.top, 140)
                    SavePane(side: "b")
                }
            }
        }
    }
}

private struct SavePane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.pkCompact) private var compact
    let side: String

    private var info: SaveInfo? { side == "a" ? model.save : model.saveB }
    private var box: BoxData? { side == "a" ? model.boxA : model.boxB }
    private var boxIndex: Int { side == "a" ? model.transferBoxA : model.currentBoxB }
    private var party: [SlotSummary] { side == "a" ? model.party : model.partyB }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let info {
                header(info)
                if info.hasBox, let box {
                    HStack {
                        Button { Task { await go(boxIndex - 1) } } label: { Image(systemName: "chevron.left") }
                        Text(box.name).font(.system(size: 15, weight: .bold, design: .rounded)).frame(maxWidth: .infinity)
                        Button { Task { await go(boxIndex + 1) } } label: { Image(systemName: "chevron.right") }
                    }
                    .buttonStyle(.pkGlass)
                    let columns = info.boxSlotCount <= 20 ? 5 : 6
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: columns), spacing: 7) {
                        ForEach(box.slots) { s in
                            TransferCell(side: side, slot: s)
                        }
                    }
                    .id("\(side)-\(box.box)")
                    .transition(.opacity)
                }
                if info.hasParty {
                    Text(L("Squadra")).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 6), spacing: 7) {
                        ForEach(party) { s in TransferCell(side: side, slot: s) }
                    }
                }
            } else {
                emptyB
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .top)
        .pkGlassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private func go(_ i: Int) async {
        if side == "a" { await model.showBoxA(i) } else { await model.showBoxB(i) }
    }

    private func header(_ info: SaveInfo) -> some View {
        HStack(spacing: 10) {
            GameBadge(game: info.versionKey, generation: info.generation)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.game).font(.system(size: 15, weight: .bold, design: .rounded))
                Text(L("\(info.ot) · Gen \(info.generation)\(info.dirty ? " · modificato" : "")"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if side == "b" {
                Menu {
                    Button { model.openSecondPanel() } label: { Label(L("Apri un altro…"), systemImage: "folder") }
                    Button { Task { await model.closeSecond() } } label: { Label(L("Chiudi"), systemImage: "xmark") }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuIndicator(.hidden).buttonStyle(.pkGlass)
                Button { Task { await model.saveSecond() } } label: { Label(L("Salva"), systemImage: "square.and.arrow.down") }
                    .buttonStyle(.pkGlassProminent).disabled(!info.dirty)
            } else {
                Button { Task { await model.saveFile() } } label: { Label(L("Salva"), systemImage: "square.and.arrow.down") }
                    .buttonStyle(.pkGlass).disabled(!info.dirty)
            }
        }
    }

    private var emptyB: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Theme.brand)
            Text(L("Apri un secondo salvataggio")).font(.system(size: 17, weight: .bold, design: .rounded))
            Text(L("Anche di un'altra generazione o uno zip di Azurii. Puoi trasferire solo i Pokémon che il gioco di destinazione può davvero ricevere."))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
            Button { model.openSecondPanel() } label: { Label(L("Scegli il file…"), systemImage: "folder").fixedSize() }
                .buttonStyle(.pkGlassProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 260 : 420)
        .dropDestination(for: URL.self) { urls, _ in
            guard let u = urls.first else { return false }
            Task { await model.openSecond(u) }
            return true
        }
    }
}

private struct TransferCell: View {
    @Environment(AppModel.self) private var model
    let side: String
    let slot: SlotSummary
    @State private var targeted = false
    @State private var hover = false
    @State private var verdict: TransferCheck?

    var body: some View {
        let t = PokeType(key: slot.primaryType)
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(slot.empty ? AnyShapeStyle(.primary.opacity(targeted ? 0.12 : 0.04)) : AnyShapeStyle(t.color.opacity(hover ? 0.24 : 0.14)))
            if !slot.empty {
                PokemonSprite(key: slot.sprite, tint: t.color).padding(4)
                if slot.shiny == true {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .bold)).foregroundStyle(.yellow)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(4)
                }
            }
            if let v = verdict, hover, side == "a" || side == "b" {
                Image(systemName: v.ok ? "checkmark.circle.fill" : "nosign")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(v.ok ? .green : .red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(3)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(targeted ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(.primary.opacity(0.06)), lineWidth: targeted ? 2 : 1))
        .scaleEffect(targeted ? 1.08 : 1)
        .animation(Theme.snappy, value: targeted)
        .onHover { h in
            hover = h
            guard h, !slot.empty, verdict == nil, (side == "a" ? model.saveB : model.save) != nil else { return }
            Task { verdict = await model.transferCheck(from: SlotDrag(save: side, ref: slot.ref), toSave: side == "a" ? "b" : "a") }
        }
        .help(help)
        .onDrag {
            guard !slot.empty else { return NSItemProvider() }
            return AppModel.dragProvider(save: side, ref: slot.ref, name: slot.displayName)
        } preview: {
            PokemonSprite(key: slot.sprite, tint: t.color).frame(width: 60, height: 60)
        }
        .onDrop(of: [.pkmacSlot], isTargeted: $targeted) { providers in
            let copy = NSEvent.modifierFlags.contains(.option)
            let target = SlotDrag(save: side, ref: slot.ref)
            return AppModel.loadDrag(providers) { drag in
                Task { await model.transfer(from: drag, to: target, copy: copy) }
            }
        }
        .onChange(of: slot) { _, _ in verdict = nil }
    }

    private var help: String {
        guard !slot.empty else { return L("Slot vuoto · rilascia qui un Pokémon") }
        var s = L("\(slot.displayName) · Lv. \(slot.level ?? 0)")
        if let v = verdict {
            s += v.ok ? L("\n✓ Trasferibile nell'altro gioco") : "\n✕ \(v.problem ?? "Non trasferibile")"
        }
        return s
    }
}
