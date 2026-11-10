import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let pkmacSlot = UTType(exportedAs: "io.github.pkmac.slot")
}

struct BoxView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var selectionNS

    var body: some View {
        VStack(spacing: 0) {
            BoxHeader()
                .padding(.horizontal, 26)
                .padding(.top, 18)
            BoxStrip()
                .padding(.top, 12)

            GeometryReader { geo in
                if let box = model.box {
                    let columns = (model.save?.boxSlotCount ?? 30) <= 20 ? 5 : 6
                    let rows = Int(ceil(Double(box.slots.count) / Double(columns)))
                    let spacing: CGFloat = 12
                    let side = min((geo.size.width - 52 - spacing * CGFloat(columns - 1)) / CGFloat(columns),
                                   (geo.size.height - 30 - spacing * CGFloat(rows - 1)) / CGFloat(rows))
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(max(64, side)), spacing: spacing), count: columns), spacing: spacing) {
                        ForEach(box.slots) { slot in
                            SlotCell(slot: slot, size: max(64, side), namespace: selectionNS)
                        }
                    }
                    .id(box.box)
                    .transition(.asymmetric(
                        insertion: .move(edge: model.boxDirection).combined(with: .opacity),
                        removal: .move(edge: model.boxDirection == .trailing ? .leading : .trailing).combined(with: .opacity)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 26)
                }
            }
            .clipped()
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { v in
                        guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                        Task { await model.showBox(model.currentBox + (v.translation.width < 0 ? 1 : -1)) }
                    }
            )

            // Plain row (not a safe-area inset: changing insets during layout crashes AppKit).
            if !Diag.off("DOCK"), model.save?.hasParty == true, !model.party.isEmpty {
                PartyDock()
                    .frame(height: 78)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 14)
            }
        }
        .onKeyPress(.leftArrow) { Task { await model.showBox(model.currentBox - 1) }; return .handled }
        .onKeyPress(.rightArrow) { Task { await model.showBox(model.currentBox + 1) }; return .handled }
    }
}

private struct BoxHeader: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false
    @State private var newName = ""

    var body: some View {
        HStack(spacing: 14) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    Button { Task { await model.showBox(model.currentBox - 1) } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 30)
                    }
                    Button { Task { await model.showBox(model.currentBox + 1) } } label: {
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 30)
                    }
                }
                .buttonStyle(.glass)
            }

            VStack(alignment: .leading, spacing: 1) {
                if editing {
                    TextField(L("Nome box"), text: $newName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .onSubmit {
                            editing = false
                            Task { await model.renameBox(newName) }
                        }
                        .onExitCommand { editing = false }
                } else {
                    Text(model.box?.name ?? "")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .onTapGesture(count: 2) {
                            guard model.save?.canRenameBoxes == true else { return }
                            newName = model.box?.name ?? ""
                            editing = true
                        }
                        .help(model.save?.canRenameBoxes == true ? L("Doppio clic per rinominare") : "")
                }
                let filled = model.box?.slots.filter { !$0.empty }.count ?? 0
                Text(L("Box \(model.currentBox + 1) di \(model.save?.boxCount ?? 0) · \(filled)/\(model.box?.slots.count ?? 0) Pokémon"))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { model.showShowdownImport = true } label: {
                        Label(L("Importa Showdown"), systemImage: "square.and.arrow.down.on.square")
                    }
                    Button { model.showCreate = true } label: {
                        Label(L("Crea"), systemImage: "plus")
                    }
                    Menu {
                        Button { Task { await model.legalizeBox() } } label: { Label(L("Legalizza tutto il box"), systemImage: "wand.and.stars") }
                        Button { model.exportBox() } label: { Label(L("Esporta box come file .pk…"), systemImage: "square.and.arrow.up") }
                        Divider()
                        Button { model.section = .sorting } label: { Label(L("Ordina per Pokédex…"), systemImage: "arrow.up.arrow.down") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 18)
                    }
                    .menuIndicator(.hidden)
                }
                .buttonStyle(.glass)
            }
        }
    }
}

/// Horizontal strip of mini boxes with fill level; click to jump.
private struct BoxStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(model.boxList) { b in
                        let selected = b.box == model.currentBox
                        let capacity = Double(model.save?.boxSlotCount ?? 30)
                        Button { Task { await model.showBox(b.box) } } label: {
                            VStack(spacing: 4) {
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(.primary.opacity(0.07))
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(selected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.accentColor.opacity(0.45)))
                                        .frame(height: max(3, 20 * CGFloat(Double(b.count) / capacity)))
                                    if b.shiny > 0 {
                                        Image(systemName: "sparkle")
                                            .font(.system(size: 7, weight: .black))
                                            .foregroundStyle(.yellow)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                            .padding(2)
                                    }
                                }
                                .frame(width: 26, height: 20)
                                Text("\(b.box + 1)")
                                    .font(.system(size: 9.5, weight: selected ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(selected ? .primary : .secondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 3)
                            .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .help(L("\(b.name) · \(b.count) Pokémon — trascina qui un Pokémon per spostarlo in questo box"))
                        .modifier(BoxChipDrop(box: b.box, enabled: !Diag.off("CHIPDROP")))
                        .id(b.box)
                    }
                }
                .padding(.horizontal, 26)
            }
            .onChange(of: model.currentBox) { _, new in
                withAnimation(Theme.spring) { proxy.scrollTo(new, anchor: .center) }
            }
        }
        .frame(height: 44)
    }
}

/// Dropping a Pokémon on a box chip moves it to the first free slot of that box.
private struct BoxChipDrop: ViewModifier {
    @Environment(AppModel.self) private var model
    let box: Int
    var enabled = true
    @State private var targeted = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        if enabled { dropping(content) } else { content }
    }

    private func dropping(_ content: Content) -> some View {
        content
            .scaleEffect(targeted ? 1.25 : 1)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.brand, lineWidth: targeted ? 2 : 0))
            .animation(Theme.snappy, value: targeted)
            .onDrop(of: [.pkmacSlot], isTargeted: $targeted) { providers in
                let copy = NSEvent.modifierFlags.contains(.option)
                return AppModel.loadDrag(providers) { drag in
                    Task {
                        if drag.save == "a" { await model.moveToBox(from: drag.ref, box: box, copy: copy) }
                        else if let empty = await firstEmpty() {
                            await model.transfer(from: drag, to: SlotDrag(save: "a", ref: .box(box, empty)), copy: copy)
                        } else { model.toast(.warning, L("Il box \(box + 1) è pieno")) }
                    }
                }
            }
            .onChange(of: targeted) { _, on in
                // Hovering a chip while dragging opens that box, like the games.
                hoverTask?.cancel()
                guard on else { return }
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(650))
                    if !Task.isCancelled, model.currentBox != box { await model.showBox(box) }
                }
            }
    }

    private func firstEmpty() async -> Int? {
        let data: BoxData? = try? await model.call("box", ["box": box])
        return data?.slots.firstIndex { $0.empty && $0.locked != true }
    }
}

/// Compact party row under the box grid: drag between party and boxes.
struct PartyDock: View {
    @Environment(AppModel.self) private var model
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L("Squadra")).font(.system(size: 12, weight: .bold, design: .rounded))
                Text(L("trascina ⇅")).font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
            }
            .frame(width: 64, alignment: .leading)
            ForEach(model.party) { p in
                SlotCell(slot: p, size: 54, namespace: ns)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

struct SlotCell: View {
    @Environment(AppModel.self) private var model
    let slot: SlotSummary
    let size: CGFloat
    var namespace: Namespace.ID

    @State private var hover = false
    @State private var targeted = false

    private var type: PokeType { PokeType(key: slot.primaryType) }
    private var selected: Bool { model.selection == slot.ref }

    var body: some View {
        ZStack {
            background
            if !slot.empty {
                PokemonSprite(key: slot.sprite, tint: type.color)
                    .padding(size * 0.1)
                    .offset(y: hover ? -3 : 0)
                    .shadow(color: type.color.opacity(hover ? 0.45 : 0.2), radius: hover ? 10 : 4, y: hover ? 8 : 3)
                overlays
            } else if slot.locked == true {
                Image(systemName: "lock.fill").foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .contentShape(.rect(cornerRadius: Theme.cellCorner))
        .scaleEffect(targeted ? 1.08 : (hover && !slot.empty ? 1.03 : 1))
        .animation(Theme.snappy, value: hover)
        .animation(Theme.snappy, value: targeted)
        .onHover { hover = $0 }
        .onTapGesture {
            if slot.empty {
                withAnimation(Theme.spring) { model.selection = slot.ref; model.detail = nil }
            } else {
                Task { await model.select(slot.ref) }
            }
        }
        .contextMenu { SlotMenu(slot: slot) }
        .onDrag {
            guard !slot.empty else { return NSItemProvider() }
            return AppModel.dragProvider(save: "a", ref: slot.ref, name: slot.displayName)
        } preview: {
            PokemonSprite(key: slot.sprite, tint: type.color).frame(width: size * 0.9, height: size * 0.9)
        }
        .onDrop(of: [.pkmacSlot, .fileURL], isTargeted: $targeted) { providers in
            handleDrop(providers)
        }
        .help(slot.empty ? L("Slot vuoto") : L("\(slot.displayName) · Lv. \(slot.level ?? 0)\(slot.heldItemName.map { " · \($0)" } ?? "")"))
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cellCorner, style: .continuous)
        if slot.empty {
            shape.fill(.primary.opacity(targeted ? 0.10 : 0.035))
                .overlay(shape.strokeBorder(.primary.opacity(selected ? 0.35 : 0.07), style: StrokeStyle(lineWidth: 1, dash: selected ? [] : [4, 4])))
        } else {
            shape
                .fill(
                    RadialGradient(colors: [type.glow.opacity(0.42), type.color.opacity(0.16), type.color.opacity(0.06)],
                                   center: .init(x: 0.5, y: 0.42), startRadius: 2, endRadius: size * 0.75)
                )
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .overlay {
                    if selected {
                        shape.strokeBorder(type.color, lineWidth: 2.5)
                            .shadow(color: type.color.opacity(0.7), radius: 8)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
        }
    }

    @ViewBuilder private var overlays: some View {
        VStack {
            HStack(alignment: .top) {
                if slot.shiny == true {
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.14, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                        .symbolEffect(.pulse, isActive: hover)
                }
                if slot.alpha == true {
                    Text("α").font(.system(size: size * 0.15, weight: .black, design: .rounded)).foregroundStyle(.red)
                }
                Spacer()
                if slot.legal == false {
                    Circle().fill(.red).frame(width: 9, height: 9)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .help(L("Non legale"))
                }
            }
            Spacer()
            HStack(alignment: .bottom) {
                if size > 80 {
                    Text("Lv.\(slot.level ?? 0)")
                        .font(.system(size: max(9, size * 0.1), weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let item = slot.heldItemKey {
                    ItemIcon(key: item).frame(width: size * 0.22, height: size * 0.22)
                }
            }
        }
        .padding(size * 0.07)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let copy = NSEvent.modifierFlags.contains(.option)
        let target = slot.ref
        if AppModel.loadDrag(providers, { drag in
            Task {
                if drag.save == "a" { await model.move(from: drag.ref, to: target, copy: copy) }
                else { await model.transfer(from: drag, to: SlotDrag(save: "a", ref: target), copy: copy) }
            }
        }) { return true }
        Task { @MainActor in
            let urls = await providers.loadURLs()
            await model.handleDrop(urls, onto: slot.ref)
        }
        return true
    }
}

struct SlotMenu: View {
    @Environment(AppModel.self) private var model
    let slot: SlotSummary

    var body: some View {
        if slot.empty {
            Button { model.selection = slot.ref; model.showCreate = true } label: { Label(L("Crea Pokémon qui…"), systemImage: "plus") }
            Button { model.showShowdownImport = true } label: { Label(L("Importa set Showdown…"), systemImage: "doc.on.clipboard") }
        } else {
            Button { Task { await model.legalize(slot.ref) } } label: { Label(L("Rendi legale…"), systemImage: "wand.and.stars") }
            Button { Task { await model.legalize(slot.ref, mine: true) } } label: { Label(L("Rendi mio…"), systemImage: "person.crop.circle.badge.checkmark") }
            Button { Task { await model.copyShowdown(slot.ref) } } label: { Label(L("Copia set Showdown"), systemImage: "doc.on.doc") }
            Button { model.exportPk(slot.ref) } label: { Label(L("Esporta file .pk…"), systemImage: "square.and.arrow.up") }
            Divider()
            Button { Task { await model.heal(slot.ref) } } label: { Label(L("Cura"), systemImage: "cross.case.fill") }
            Button { Task { await model.maxIVs(slot.ref) } } label: { Label(L("IV al massimo"), systemImage: "chart.bar.fill") }
            Divider()
            Button(role: .destructive) { Task { await model.delete(slot.ref) } } label: { Label(L("Rilascia"), systemImage: "trash") }
        }
    }
}
