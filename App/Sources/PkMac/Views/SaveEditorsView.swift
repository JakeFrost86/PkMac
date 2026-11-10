import SwiftUI

// MARK: - Pokédex

struct PokedexView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.pkCompact) private var compact
    @State private var data: DexData?
    @State private var filter = ""
    @State private var show = 0 // 0 all, 1 caught, 2 seen only, 3 missing
    @State private var loading = true

    private var entries: [DexEntry] {
        (data?.entries ?? []).filter { e in
            (filter.isEmpty || e.name.localizedCaseInsensitiveContains(filter) || "\(e.species)" == filter) &&
            (show == 0 || (show == 1 && e.caught) || (show == 2 && e.seen && !e.caught) || (show == 3 && !e.seen))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(title: "Pokédex", subtitle: subtitle, symbol: "book.closed.fill", tint: AppSection.pokedex.tint)
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if data?.supported != true {
                ContentUnavailableView(L("Pokédex non modificabile"), systemImage: "book.closed", description: Text(L("Questo salvataggio non espone un Pokédex.")))
            } else {
                progressBar
                controls
                grid
            }
        }
        .pkPadding(26)
        .task(id: model.save?.path) {
            loading = true
            data = await model.dex()
            loading = false
        }
    }

    private var subtitle: String {
        guard let d = data, d.supported else { return L("Visti e catturati") }
        return L("\(d.caught ?? 0) catturati · \(d.seen ?? 0) visti su \(d.total ?? 0)")
    }

    private var progressBar: some View {
        let total = Double(max(1, data?.total ?? 1))
        let caught = Double(data?.caught ?? 0), seen = Double(data?.seen ?? 0)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.07))
                Capsule().fill(AppSection.pokedex.tint.opacity(0.3)).frame(width: geo.size.width * seen / total)
                Capsule().fill(LinearGradient(colors: [AppSection.pokedex.tint, Color(hex: 0xFF8A5C)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * caught / total)
            }
        }
        .frame(height: 10)
        .animation(Theme.spring, value: data?.caught)
    }

    private var controls: some View {
        // Narrow screens: the filter becomes a row of its own under the search field.
        PKCompactWrap(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("Nome o numero"), text: $filter).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(.primary.opacity(0.05), in: Capsule())
                .frame(maxWidth: 240)
                if !compact { showPicker.frame(maxWidth: 360) }
                Spacer()
                completeMenu
            }
        } extra: {
            showPicker
        }
    }

    private var showPicker: some View {
        Picker("", selection: $show) {
            Text(L("Tutti")).tag(0); Text(L("Catturati")).tag(1); Text(L("Solo visti")).tag(2); Text(L("Mancanti")).tag(3)
        }
        .pickerStyle(.segmented).labelsHidden()
    }

    private var completeMenu: some View {
            Menu {
                Button { Task { await bulk("seenAll") } } label: { Label(L("Segna tutti come visti"), systemImage: "eye.fill") }
                Button { Task { await bulk("caughtAll") } } label: { Label(L("Segna tutti come catturati"), systemImage: "checkmark.seal.fill") }
                Divider()
                Button(role: .destructive) { Task { await bulk("clear") } } label: { Label(L("Azzera il Pokédex"), systemImage: "trash") }
            } label: { Label(L("Completa"), systemImage: "wand.and.stars") }
            .menuIndicator(.hidden)
            .buttonStyle(.pkGlass)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 10)], spacing: 10) {
                ForEach(entries) { e in
                    DexTile(entry: e) { seen, caught in
                        Task {
                            if let d = await model.setDex(changes: [["species": e.species, "seen": seen, "caught": caught]]) {
                                data = d
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .scrollIndicators(.never)
    }

    private func bulk(_ a: String) async {
        if let d = await model.setDex(action: a) {
            withAnimation(Theme.spring) { data = d }
            model.toast(.success, L("Pokédex aggiornato"), Platform.isMac ? L("Puoi annullare con ⌘Z.") : L("Puoi annullare con il tasto Annulla."))
        }
    }
}

private struct DexTile: View {
    let entry: DexEntry
    let onSet: (Bool, Bool) -> Void
    @State private var hover = false

    var body: some View {
        let t = PokeType(key: entry.types.first)
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                PokemonSprite(key: SpriteKey(species: entry.species, formKey: entry.formKey, shiny: false, female: false, egg: false, form: 0), tint: t.color)
                    .frame(width: 64, height: 64)
                    .saturation(entry.caught ? 1 : (entry.seen ? 0.35 : 0))
                    .brightness(entry.seen ? 0 : -0.6)
                    .opacity(entry.seen ? 1 : 0.55)
                    .frame(maxWidth: .infinity)
                Text(String(format: "%04d", entry.species))
                    .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(entry.name).font(.system(size: 11.5, weight: .semibold, design: .rounded)).lineLimit(1)
            HStack(spacing: 10) {
                Button { onSet(!entry.seen, entry.seen ? false : entry.caught) } label: {
                    Image(systemName: entry.seen ? "eye.fill" : "eye.slash")
                        .foregroundStyle(entry.seen ? AnyShapeStyle(t.color) : AnyShapeStyle(.tertiary))
                }
                .help(entry.seen ? L("Visto") : L("Non visto"))
                Button { onSet(true, !entry.caught) } label: {
                    Image(systemName: entry.caught ? "checkmark.seal.fill" : "seal")
                        .foregroundStyle(entry.caught ? AnyShapeStyle(t.color) : AnyShapeStyle(.tertiary))
                }
                .help(entry.caught ? L("Catturato") : L("Non catturato"))
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
        }
        .padding(8)
        .background(t.color.opacity(entry.caught ? (hover ? 0.18 : 0.11) : 0.04), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.06)))
        .onHover { hover = $0 }
        .hoverLift(hover)
    }
}

// MARK: - Events

struct EventsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.pkCompact) private var compact
    @State private var data: EventsData?
    @State private var flags: [Bool] = []
    @State private var system: [Bool] = []
    @State private var work: [Int] = []
    @State private var changedFlags: [Int: Bool] = [:]
    @State private var changedSystem: [Int: Bool] = [:]
    @State private var changedWork: [Int: Int] = [:]
    @State private var tab = 0
    @State private var category = L("Tutte")
    @State private var filter = ""
    @State private var showUnnamed = false
    @State private var loading = true
    @State private var jump = ""

    private var dirty: Bool { !changedFlags.isEmpty || !changedSystem.isEmpty || !changedWork.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(title: L("Eventi di gioco"), subtitle: subtitle, symbol: "flag.2.crossed.fill", tint: AppSection.events.tint)
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let d = data, !d.supported {
                VStack(spacing: 14) {
                    ContentUnavailableView(L("Eventi nei blocchi"), systemImage: "square.stack.3d.up", description: Text(d.message ?? ""))
                    if d.useBlocks == true {
                        Button { model.section = .advanced } label: { Label(L("Apri i blocchi di gioco"), systemImage: "arrow.right") }
                            .buttonStyle(.pkGlassProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                controls
                list
            }
        }
        .pkPadding(26)
        .task(id: model.save?.path) { await load() }
    }

    private var subtitle: String {
        guard let d = data, d.supported else { return L("Trama, strumenti nascosti, allenatori, leggendari…") }
        return L("\(d.flagCount ?? 0) flag · \(d.workCount ?? 0) valori") + ((d.systemCount ?? 0) > 0 ? L(" · \(d.systemCount!) flag di sistema") : "") + (dirty ? L(" · modifiche da applicare") : "")
    }

    private func load() async {
        loading = true
        data = await model.events()
        flags = data?.flags ?? []; system = data?.system ?? []; work = data?.work ?? []
        changedFlags = [:]; changedSystem = [:]; changedWork = [:]
        loading = false
    }

    private var categories: [String] {
        let src: [String]
        switch tab {
        case 1: src = (data?.namedWork ?? []).map(\.category)
        case 2: src = (data?.namedSystem ?? []).map(\.category)
        default: src = (data?.namedFlags ?? []).map(\.category)
        }
        return [L("Tutte")] + Array(Set(src)).sorted()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if compact {
                // Narrow screens: one control per line.
                tabPicker
                HStack(spacing: 10) {
                    categoryPicker
                    Spacer()
                    applyButtons
                }
                searchField
                Toggle(L("Mostra anche gli indici senza nome"), isOn: $showUnnamed).toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 12))
                HStack(spacing: 10) {
                    Spacer()
                    jumpControls
                }
                .font(.system(size: 12))
            } else {
                HStack(spacing: 10) {
                    tabPicker.frame(width: 260)
                    categoryPicker.frame(width: 220)
                    searchField.frame(maxWidth: 240)
                    Spacer()
                    applyButtons
                }
                HStack(spacing: 10) {
                    Toggle(L("Mostra anche gli indici senza nome"), isOn: $showUnnamed).toggleStyle(.switch).controlSize(.small)
                    Spacer()
                    jumpControls
                }
                .font(.system(size: 12))
            }
        }
        .onChange(of: tab) { _, _ in category = L("Tutte") }
    }

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            Text(L("Flag")).tag(0)
            Text(L("Valori")).tag(1)
            if (data?.systemCount ?? 0) > 0 { Text(L("Sistema")).tag(2) }
        }
        .pickerStyle(.segmented).labelsHidden()
    }

    private var categoryPicker: some View {
        Picker(L("Categoria"), selection: $category) {
            ForEach(categories, id: \.self) { Text($0).tag($0) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(L("Cerca un evento"), text: $filter).textFieldStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.primary.opacity(0.05), in: Capsule())
    }

    @ViewBuilder private var applyButtons: some View {
        if dirty {
            Button(L("Annulla")) { Task { await load() } }.buttonStyle(.pkGlass)
            Button { Task { await apply() } } label: { Label(L("Applica \(changedFlags.count + changedSystem.count + changedWork.count)"), systemImage: "checkmark") }
                .buttonStyle(.pkGlassProminent)
                .keyboardShortcut(.return, modifiers: .command)
        }
    }

    @ViewBuilder private var jumpControls: some View {
        Text(L("Vai all'indice")).font(.caption).foregroundStyle(.secondary)
        TextField("0", text: $jump).textFieldStyle(.roundedBorder).frame(width: 70)
            .onSubmit { filter = jump; showUnnamed = true }
    }

    private struct Row: Identifiable { let id: Int; let name: String; let category: String; let options: [NamedWork.Option] }

    private var rows: [Row] {
        let named: [Row]
        let count: Int
        switch tab {
        case 1:
            named = (data?.namedWork ?? []).map { Row(id: $0.i, name: $0.name, category: $0.category, options: $0.options) }
            count = work.count
        case 2:
            named = (data?.namedSystem ?? []).map { Row(id: $0.i, name: $0.name, category: $0.category, options: []) }
            count = system.count
        default:
            named = (data?.namedFlags ?? []).map { Row(id: $0.i, name: $0.name, category: $0.category, options: []) }
            count = flags.count
        }
        var all = named
        if showUnnamed {
            let known = Set(named.map(\.id))
            all += (0..<count).filter { !known.contains($0) }.map { Row(id: $0, name: L("Indice \($0)"), category: L("Senza nome"), options: []) }
            all.sort { $0.id < $1.id }
        }
        return all.filter { r in
            (category == L("Tutte") || r.category == category) &&
            (filter.isEmpty || r.name.localizedCaseInsensitiveContains(filter) || "\(r.id)" == filter)
        }
    }

    private var list: some View {
        let rs = rows
        return Group {
            if rs.isEmpty {
                ContentUnavailableView(L("Nessun evento"), systemImage: "flag.slash",
                                       description: Text(showUnnamed ? L("Nessun risultato.") : L("Per questo gioco PKHeX non ha nomi: attiva “Mostra anche gli indici senza nome”.")))
            } else {
                List(rs) { r in
                    eventRow(r)
                        .padding(.vertical, 2)
                }
                .listStyle(.inset)
                .clipShape(.rect(cornerRadius: 16))
            }
        }
    }

    @ViewBuilder private func eventRow(_ r: Row) -> some View {
        if compact && tab == 1 {
            // Values have a picker and a number field: below the name on narrow screens.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) { rowTitle(r) }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    control(r)
                }
            }
        } else {
            HStack(spacing: 10) {
                rowTitle(r)
                Spacer()
                control(r)
            }
        }
    }

    @ViewBuilder private func rowTitle(_ r: Row) -> some View {
        Text("\(r.id)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary).frame(width: compact ? 36 : 46, alignment: .trailing)
        VStack(alignment: .leading, spacing: 1) {
            Text(r.name).font(.system(size: 12.5, weight: .medium))
            Text(r.category).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func control(_ r: Row) -> some View {
        switch tab {
        case 1:
            if r.id < work.count {
                let binding = Binding<Int>(get: { work[r.id] }, set: { work[r.id] = $0; changedWork[r.id] = $0 })
                if !r.options.isEmpty {
                    Picker("", selection: binding) {
                        ForEach(r.options, id: \.v) { Text("\($0.t) (\($0.v))").tag($0.v) }
                        if !r.options.contains(where: { $0.v == work[r.id] }) { Text("\(work[r.id])").tag(work[r.id]) }
                    }
                    .labelsHidden().pkFixedWidth(220, compact: compact, 170)
                }
                TextField("", value: binding, format: .number).textFieldStyle(.roundedBorder).pkFixedWidth(90, compact: compact, 70).monospacedDigit()
                    .changed(changedWork[r.id] != nil)
            }
        case 2:
            if r.id < system.count {
                Toggle("", isOn: Binding(get: { system[r.id] }, set: { system[r.id] = $0; changedSystem[r.id] = $0 }))
                    .toggleStyle(.switch).labelsHidden().changed(changedSystem[r.id] != nil)
            }
        default:
            if r.id < flags.count {
                Toggle("", isOn: Binding(get: { flags[r.id] }, set: { flags[r.id] = $0; changedFlags[r.id] = $0 }))
                    .toggleStyle(.switch).labelsHidden().changed(changedFlags[r.id] != nil)
            }
        }
    }

    private func apply() async {
        if let d = await model.setEvents(flags: changedFlags, system: changedSystem, work: changedWork) {
            data = d
            flags = d.flags ?? []; system = d.system ?? []; work = d.work ?? []
            changedFlags = [:]; changedSystem = [:]; changedWork = [:]
            model.toast(.success, L("Eventi aggiornati"), Platform.isMac ? L("Puoi annullare con ⌘Z.") : L("Puoi annullare con il tasto Annulla."))
        }
    }
}

private extension View {
    /// Fixed width, narrower on small screens.
    @ViewBuilder func pkFixedWidth(_ regular: CGFloat, compact: Bool, _ narrow: CGFloat) -> some View {
        if compact { frame(width: narrow) } else { frame(width: regular) }
    }

    func changed(_ on: Bool) -> some View {
        self.padding(2).background(on ? Color.orange.opacity(0.22) : .clear, in: .rect(cornerRadius: 8))
    }
}

// MARK: - Mystery gifts

struct GiftsView: View {
    @Environment(AppModel.self) private var model
    @State private var album: GiftAlbum?
    @State private var db: GiftDb?
    @State private var query = ""
    @State private var selected: GiftCard?
    @State private var lines: [String] = []
    @State private var kind = 0 // 0 all, 1 Pokémon, 2 items/others
    @State private var region = "" // "" all, "any" valid everywhere, or a LanguageID
    @State private var showDetail = false
    @Environment(\.pkCompact) private var compact

    var body: some View {
        Group {
            if compact {
                // Narrow screens: no side panel, the chosen gift opens in a sheet.
                VStack(alignment: .leading, spacing: 16) {
                    giftsHeader
                    albumSection
                    databaseSection
                }
                .sheet(isPresented: $showDetail) {
                    detailPanel
                        .padding(12)
                        .presentationDetents([.medium, .large])
                }
            } else {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 16) {
                        giftsHeader
                        albumSection
                        databaseSection
                    }
                    .frame(maxWidth: .infinity)
                    detailPanel
                        .frame(width: 300)
                }
            }
        }
        .pkPadding(26)
        .task(id: model.save?.path) {
            album = await model.giftAlbum()
            await search()
        }
    }

    private var giftsHeader: some View {
        Header(title: L("Doni segreti"), subtitle: L("Album delle carte dono e database eventi filtrato per \(model.save?.game ?? "il gioco")"), symbol: "gift.fill", tint: AppSection.gifts.tint)
    }

    // Album

    @ViewBuilder private var albumSection: some View {
        if let a = album, a.supported, let cards = a.cards {
            Card(title: L("Album nel salvataggio · \(cards.filter { !$0.card.empty }.count)/\(cards.count)"), symbol: "rectangle.stack.fill", tint: AppSection.gifts.tint) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(cards.enumerated()), id: \.offset) { i, e in
                            AlbumSlot(entry: e, isLock: a.lockCapsuleSlot == i, selected: selected?.slot == i && selected?.id == nil) {
                                selected = e.card; lines = e.lines
                                if compact && !e.card.empty { showDetail = true }
                            }
                            .contextMenu {
                                if !e.card.empty {
                                    if a.canToggleUsed == true {
                                        Button(e.card.used == true ? L("Segna come non ritirato") : L("Segna come già ritirato")) {
                                            Task { if let r = await model.setGiftFlags(["slot": i, "used": !(e.card.used ?? false)]) { album = r } }
                                        }
                                    }
                                    Button(L("Elimina carta"), role: .destructive) {
                                        Task { if let r = await model.deleteGift(slot: i) { album = r; selected = nil } }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                if compact {
                    VStack(alignment: .leading, spacing: 8) {
                        if a.hasFlags == true {
                            HStack {
                                receivedInfo(a)
                            }
                        }
                        importGiftButton
                    }
                } else {
                    HStack {
                        if a.hasFlags == true {
                            receivedInfo(a)
                        }
                        Spacer()
                        importGiftButton
                    }
                }
            }
        } else if let a = album {
            Card(title: L("Album"), symbol: "info.circle.fill", tint: AppSection.gifts.tint) {
                HStack {
                    Text(a.message ?? "").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { _ = await model.importGiftFile() } } label: { Label(L("Importa file dono…"), systemImage: "doc.badge.plus") }
                        .buttonStyle(.pkGlass).controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder private func receivedInfo(_ a: GiftAlbum) -> some View {
        Text(L("\(a.received?.count ?? 0) doni risultano già ricevuti nel gioco"))
            .font(.caption).foregroundStyle(.secondary)
        Button(L("Azzera ricevuti")) {
            Task { if let r = await model.setGiftFlags(["action": "clear"]) { album = r } }
        }
        .buttonStyle(.pkGlass).controlSize(.small)
        .help(L("Permette di ricevere di nuovo i doni già riscattati"))
    }

    private var importGiftButton: some View {
        Button { Task { if await model.importGiftFile() { album = await model.giftAlbum() } } } label: {
            Label(L("Importa file dono…"), systemImage: "doc.badge.plus")
        }
        .buttonStyle(.pkGlass).controlSize(.small)
    }

    // Database

    private var databaseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: 8) {
                        giftSearchField
                        kindPicker
                        regionPicker
                    }
                } else {
                    HStack(spacing: 10) {
                        giftSearchField
                        kindPicker.frame(width: 280)
                        regionPicker.frame(width: 210)
                    }
                }
            }
            .onChange(of: query) { _, _ in Task { try? await Task.sleep(for: .milliseconds(300)); await search() } }
            .onChange(of: region) { _, _ in Task { await search() } }
            if let db {
                Text(L("\(db.total) doni compatibili con \(model.save?.game ?? "questo gioco")") + (db.total > db.shown ? L(" · mostrati i primi \(db.shown), affina la ricerca") : ""))
                    .font(.caption).foregroundStyle(.secondary)
                let items = db.items.filter { kind == 0 || (kind == 1 ? $0.isEntity == true : $0.isEntity != true) }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 10)], spacing: 10) {
                        ForEach(items, id: \.id) { g in
                            GiftRow(card: g, selected: selected?.id == g.id && g.id != nil)
                                .onTapGesture {
                                    selected = g
                                    if compact { showDetail = true }
                                    Task { lines = await model.giftDetail(g.id ?? -1)?.lines ?? [] }
                                }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.never)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }

    private var giftSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(L("Cerca evento, Pokémon, oggetto, OT, numero carta…"), text: $query).textFieldStyle(.plain)
                .onSubmit { Task { await search() } }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.primary.opacity(0.05), in: Capsule())
    }

    private var kindPicker: some View {
        Picker("", selection: $kind) { Text(L("Tutti")).tag(0); Text("Pokémon").tag(1); Text(L("Oggetti e altro")).tag(2) }
            .pickerStyle(.segmented).labelsHidden()
    }

    private var regionPicker: some View {
        Picker(selection: $region) {
            Text(L("Tutte le regioni")).tag("")
            Text(L("Valide in tutto il mondo")).tag("any")
            Divider()
            ForEach(GiftRegion.all, id: \.id) { r in Text(r.title).tag(String(r.id)) }
        } label: { Image(systemName: "globe") }
        .help(L("Le carte non registrano il paese di distribuzione, solo le lingue in cui si possono ricevere: il filtro usa quelle."))
    }

    private func search() async {
        db = await model.giftDatabase(query: query, region: region)
    }

    // Detail

    @ViewBuilder private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let g = selected, !g.empty {
                ZStack {
                    Circle().fill(RadialGradient(colors: [AppSection.gifts.tint.opacity(0.45), .clear], center: .center, startRadius: 4, endRadius: 110))
                    if let s = g.sprite {
                        PokemonSprite(key: s, tint: AppSection.gifts.tint).frame(width: 150, height: 150)
                    } else if let k = g.itemKey {
                        ItemIcon(key: k).frame(width: 72, height: 72)
                    } else {
                        Image(systemName: "gift.fill").font(.system(size: 60)).foregroundStyle(AppSection.gifts.tint)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 170)
                Text(g.displayTitle).font(.system(size: 18, weight: .bold, design: .rounded))
                HStack(spacing: 6) {
                    if let t = g.type { StatusBadge(kind: .info, text: t.uppercased()) }
                    if let c = g.cardId, c > 0 { StatusBadge(kind: .info, text: "#\(c)") }
                    if g.shiny == true { StatusBadge(kind: .warn, text: L("Shiny")) }
                }
                Label(GiftRegion.describe(g.languages ?? []), systemImage: "globe")
                    .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                            Text(l).font(.system(size: 11.5)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                Spacer(minLength: 0)
                if let id = g.id {
                    if g.canReceive == true {
                        Button { Task { await model.receiveGift(id) } } label: {
                            Label(L("Metti il Pokémon nel box"), systemImage: "tray.and.arrow.down.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.pkGlassProminent).controlSize(.large)
                    }
                    if g.canAlbum == true {
                        Button { Task { if let r = await model.giftToAlbum(id) { album = r } } } label: {
                            Label(L("Aggiungi la carta all'album"), systemImage: "rectangle.stack.badge.plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.pkGlass).controlSize(.large)
                        Text(L("La carta finirà nell'album: nel gioco la ritiri dal fattorino/postino come un vero dono."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView(L("Scegli un dono"), systemImage: "gift", description: Text(L("Seleziona una carta dell'album o un evento del database.")))
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .pkGlassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

private struct AlbumSlot: View {
    let entry: AlbumEntry
    let isLock: Bool
    let selected: Bool
    let onTap: () -> Void
    @State private var hover = false

    var body: some View {
        let c = entry.card
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(c.empty ? AnyShapeStyle(.primary.opacity(0.04)) : AnyShapeStyle(LinearGradient(colors: [AppSection.gifts.tint.opacity(0.35), Color(hex: 0x8A4DFF).opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                if let s = c.sprite {
                    PokemonSprite(key: s, tint: AppSection.gifts.tint).padding(6)
                } else if let k = c.itemKey {
                    ItemIcon(key: k).padding(16)
                } else if !c.empty {
                    Image(systemName: "gift.fill").font(.title2).foregroundStyle(.white)
                } else {
                    Image(systemName: isLock ? "lock.fill" : "plus").foregroundStyle(.tertiary)
                }
                if c.used == true {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(4)
                }
            }
            .frame(width: 70, height: 70)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? AppSection.gifts.tint : .primary.opacity(0.08), lineWidth: selected ? 2 : 1))
            Text(c.empty ? (isLock ? L("Capsula") : L("Vuoto")) : c.displayTitle)
                .font(.system(size: 10, weight: .medium, design: .rounded)).lineLimit(1).frame(width: 74)
                .foregroundStyle(c.empty ? .tertiary : .primary)
        }
        .onHover { hover = $0 }
        .hoverLift(hover)
        .onTapGesture(perform: onTap)
    }
}

private struct GiftRow: View {
    let card: GiftCard
    let selected: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(AppSection.gifts.tint.opacity(0.16))
                if let s = card.sprite { PokemonSprite(key: s, tint: AppSection.gifts.tint).padding(2) }
                else if let k = card.itemKey { ItemIcon(key: k).padding(10) }
                else { Image(systemName: "gift.fill").foregroundStyle(AppSection.gifts.tint) }
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.displayTitle).font(.system(size: 12.5, weight: .semibold, design: .rounded)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(card.type ?? "").font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                    if card.isEntity == true {
                        Text(L("· \(card.speciesName ?? "") Lv.\(card.level ?? 0)")).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                    } else if let i = card.item {
                        Text("· \(i)").font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if card.shiny == true { Image(systemName: "sparkles").font(.system(size: 9)).foregroundStyle(.yellow) }
                }
            }
            Spacer(minLength: 0)
            if let langs = card.languages, !langs.isEmpty {
                Text(GiftRegion.codes(langs))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.primary.opacity(0.08), in: Capsule())
                    .foregroundStyle(.secondary)
                    .help(GiftRegion.describe(langs))
            }
        }
        .padding(8)
        .background(AppSection.gifts.tint.opacity(selected ? 0.2 : (hover ? 0.1 : 0.05)), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? AppSection.gifts.tint : .clear, lineWidth: 1.5))
        .contentShape(.rect)
        .onHover { hover = $0 }
    }
}


/// Regions shown by the gift filter, keyed by PKHeX LanguageID.
enum GiftRegion {
    static let all: [(id: Int, title: String)] = [
        (1, L("Giappone")), (2, L("Inglese (USA, Europa, Australia)")), (3, L("Francese")), (4, L("Italiano")),
        (5, L("Tedesco")), (7, L("Spagnolo")), (8, L("Corea")), (9, L("Cina")), (10, L("Taiwan e Hong Kong")),
    ]
    private static let short: [Int: String] = [1: "JPN", 2: "ENG", 3: "FRA", 4: "ITA", 5: "GER", 7: "SPA", 8: "KOR", 9: "CHS", 10: "CHT"]

    static func codes(_ languages: [Int]) -> String {
        let c = languages.compactMap { short[$0] }
        return c.count > 3 ? "\(c.prefix(2).joined(separator: " ")) +\(c.count - 2)" : c.joined(separator: " ")
    }

    static func describe(_ languages: [Int]) -> String {
        if languages.isEmpty { return L("Valido in tutto il mondo") }
        return L("Solo: \(languages.compactMap { short[$0] }.joined(separator: ", "))")
    }
}
