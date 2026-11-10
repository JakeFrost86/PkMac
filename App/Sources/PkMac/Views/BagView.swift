import SwiftUI

// MARK: - Bag

struct BagView: View {
    @Environment(AppModel.self) private var model
    @State private var data: BagData?
    @State private var pouches: [BagPouch] = []
    @State private var pouchIndex = 0
    @State private var filter = ""
    @State private var dirty = false
    @State private var adding = false
    @State private var loading = true

    private var pouch: BagPouch? { pouches.indices.contains(pouchIndex) ? pouches[pouchIndex] : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(title: L("Borsa"), subtitle: subtitle, symbol: "bag.fill", tint: AppSection.bag.tint)
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if data?.supported != true || pouches.isEmpty {
                ContentUnavailableView(L("Borsa non disponibile"), systemImage: "bag", description: Text(L("Questo salvataggio non ha una borsa modificabile.")))
            } else {
                pouchBar
                toolbar
                itemsGrid
            }
        }
        .pkPadding(26)
        .task(id: model.save?.path) { await load() }
    }

    private var subtitle: String {
        let total = pouches.reduce(0) { $0 + $1.items.count }
        return L("\(total) oggetti in \(pouches.count) tasche") + (dirty ? L(" · modifiche da applicare") : "")
    }

    private func load() async {
        loading = true
        data = await model.bag()
        pouches = data?.pouches ?? []
        if pouchIndex >= pouches.count { pouchIndex = 0 }
        dirty = false
        loading = false
    }

    /// Pouch tabs wrap onto more lines when they don't fit, so every pouch stays reachable.
    private var pouchBar: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(pouches.enumerated()), id: \.offset) { i, p in
                let on = i == pouchIndex
                Button {
                    withAnimation(Theme.spring) { pouchIndex = i }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: p.symbol)
                        Text(p.name).lineLimit(1)
                        Text("\(p.items.count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.primary.opacity(0.1), in: Capsule())
                    }
                    .font(.system(size: 12, weight: on ? .bold : .medium, design: .rounded))
                }
                .buttonStyle(.pkGlass)
                .controlSize(.small)
                .tint(on ? AppSection.bag.tint : nil)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Filtra gli oggetti"), text: $filter).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.primary.opacity(0.05), in: Capsule())
            .frame(maxWidth: 260)

            if let p = pouch {
                Text("\(p.items.count)/\(p.capacity) posti · max \(p.maxCount) per oggetto")
                    .font(.system(size: 11.5, design: .rounded)).foregroundStyle(.secondary)
            }
            Spacer()
            PKGlassContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { adding = true } label: { Label(L("Aggiungi"), systemImage: "plus") }
                        .disabled((pouch?.items.count ?? 0) >= (pouch?.capacity ?? 0))
                        .popover(isPresented: $adding, arrowEdge: .bottom) {
                            if let p = pouch {
                                ItemPicker(items: p.allowed.filter { a in !p.items.contains { $0.id == a.v } }) { pick in
                                    add(pick)
                                }
                            }
                        }
                    Menu {
                        Button { Task { await action("giveAll") } } label: { Label(L("Dai tutti gli oggetti della tasca"), systemImage: "sparkles") }
                        Button { Task { await action("maxAll") } } label: { Label(L("Quantità massima a tutti"), systemImage: "arrow.up.to.line") }
                        Divider()
                        Button { Task { await action("sortName") } } label: { Label(L("Ordina per nome"), systemImage: "textformat") }
                        Button { Task { await action("sortCount") } } label: { Label(L("Ordina per quantità"), systemImage: "number") }
                        Divider()
                        Button(role: .destructive) { Task { await action("clear") } } label: { Label(L("Svuota la tasca"), systemImage: "trash") }
                    } label: { Image(systemName: "wand.and.stars").frame(width: 18) }
                    .menuIndicator(.hidden)
                    .help(L("Azioni rapide sulla tasca"))
                }
                .buttonStyle(.pkGlass)
            }
            if dirty {
                Button(L("Annulla")) { Task { await load() } }.buttonStyle(.pkGlass)
                Button { Task { await apply() } } label: { Label(L("Applica"), systemImage: "checkmark") }
                    .buttonStyle(.pkGlassProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(Theme.spring, value: dirty)
    }

    private var itemsGrid: some View {
        ScrollView {
            let items = (pouch?.items ?? []).filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
            if items.isEmpty {
                ContentUnavailableView(filter.isEmpty ? L("Tasca vuota") : L("Nessun risultato"), systemImage: "tray",
                                       description: Text(filter.isEmpty ? L("Usa “Aggiungi” o le azioni rapide per riempirla.") : ""))
                    .padding(.top, 40)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 12)], spacing: 12) {
                ForEach(items) { item in
                    BagItemTile(item: item, tint: AppSection.bag.tint) { newCount in
                        setCount(item.id, newCount)
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .scrollIndicators(.never)
    }

    private func setCount(_ id: Int, _ count: Int) {
        guard pouches.indices.contains(pouchIndex) else { return }
        if count <= 0 {
            withAnimation(Theme.spring) { pouches[pouchIndex].items.removeAll { $0.id == id } }
        } else if let i = pouches[pouchIndex].items.firstIndex(where: { $0.id == id }) {
            pouches[pouchIndex].items[i].count = count
        }
        dirty = true
    }

    private func add(_ a: AllowedItem) {
        guard var p = pouch else { return }
        let max = p.maxCount
        p.items.append(BagItem(id: a.v, count: 1, name: a.t, key: a.key, sid: a.sid, max: max))
        withAnimation(Theme.spring) { pouches[pouchIndex] = p }
        dirty = true
    }

    private func apply() async {
        if let d = await model.setBag(pouches) {
            data = d; pouches = d.pouches; dirty = false
            model.toast(.success, L("Borsa aggiornata"))
        }
    }

    private func action(_ a: String) async {
        if dirty { await apply() }
        if let d = await model.bagAction(pouch: pouch?.index ?? 0, action: a) {
            withAnimation(Theme.spring) { data = d; pouches = d.pouches }
        }
    }
}

private struct BagItemTile: View {
    let item: BagItem
    let tint: Color
    let onChange: (Int) -> Void
    @State private var hover = false
    @State private var text = ""

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(RadialGradient(colors: [tint.opacity(0.28), tint.opacity(0.04)], center: .center, startRadius: 1, endRadius: 26))
                ItemIcon(key: item.key, id: item.sid).frame(width: 34, height: 34)
                    .scaleEffect(hover ? 1.15 : 1)
                    .rotationEffect(.degrees(hover ? -6 : 0))
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                HStack(spacing: 4) {
                    Button { onChange(item.count - 1) } label: { Image(systemName: "minus") }
                        .buttonStyle(.borderless)
                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded).monospacedDigit())
                        .frame(width: 44)
                        .padding(.vertical, 2)
                        .background(.primary.opacity(0.06), in: Capsule())
                        .onSubmit { onChange(min(item.max, max(0, Int(text) ?? item.count))) }
                    Button { onChange(min(item.max, item.count + 1)) } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                    Spacer(minLength: 0)
                    Button { onChange(item.max) } label: { Text("max").font(.system(size: 10, weight: .bold, design: .rounded)) }
                        .buttonStyle(.borderless)
                        .opacity(hover ? 1 : 0)
                }
                .font(.system(size: 11, weight: .bold))
            }
            Button { onChange(0) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                .buttonStyle(.plain)
                .opacity(hover ? 1 : 0)
                .help(L("Rimuovi"))
        }
        .padding(10)
        .background(tint.opacity(hover ? 0.12 : 0.06), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.06)))
        .onHover { h in withAnimation(Theme.snappy) { hover = h } }
        .onAppear { text = "\(item.count)" }
        .onChange(of: item.count) { _, c in text = "\(c)" }
    }
}

/// Item search popover with sprites.
struct ItemPicker: View {
    let items: [AllowedItem]
    let onPick: (AllowedItem) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private var filtered: [AllowedItem] {
        query.isEmpty ? items : items.filter { $0.t.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Cerca un oggetto"), text: $query).textFieldStyle(.plain).focused($focused)
                    .onSubmit { if let f = filtered.first { onPick(f); dismiss() } }
            }
            .padding(10)
            .background(.primary.opacity(0.05), in: .rect(cornerRadius: 10))
            .padding(10)
            List(filtered) { it in
                Button { onPick(it); dismiss() } label: {
                    HStack(spacing: 10) {
                        ItemIcon(key: it.key, id: it.sid).frame(width: 24, height: 24)
                        Text(it.t)
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .pkPopoverFrame(width: 320, height: 420)
        .onAppear { focused = Platform.isMac }   // iPhone: browse first, the keyboard opens on tap
    }
}


/// Lays children left to right and wraps to a new line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(width: width, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].items.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].items.isEmpty
            rows[rows.count - 1].items.append(i)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.items.isEmpty }
    }
}
