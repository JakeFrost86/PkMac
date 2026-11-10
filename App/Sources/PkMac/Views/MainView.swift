import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var showInspector = Platform.isMac && !Diag.off("INSPECTOR")
    @Environment(\.pkCompact) private var compact
    @State private var showDetailSheet = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 300)
        } detail: {
            ZStack(alignment: .top) {
                // Fixed minimum: section content must never push its own minimum size into the split view
                // (a changing minimum makes AppKit loop on constraint updates and abort).
                // Constant minimum size for every split-view column: SwiftUI otherwise forwards the
                // content's (changing) minimum to NSSplitView, which can re-layout in a loop and abort.
                content
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .modifier(PKWidthReader())
                    .clipped()
                if !model.searchText.isEmpty {
                    SearchResultsPanel()
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(Theme.spring, value: model.searchText.isEmpty)
            #if os(iOS)
            .toolbar { toolbar }   // iPhone: the detail column carries its own toolbar
            #endif
            .inspector(isPresented: inspectorShown) {
                PokemonInspector()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .inspectorColumnWidth(min: 360, ideal: 410, max: 520)
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: L("Cerca Pokémon, soprannome, OT… o \"shiny\", \"illegale\""))
        .onChange(of: model.searchText) { _, _ in
            Task { await model.search() }
        }
        #if os(macOS)
        .toolbar { toolbar }
        #endif
        .navigationTitle(model.save?.game ?? "PkMac")
        .pkNavigationSubtitle(subtitle)
        #if os(macOS)
        .modifier(ModelSheets(enabled: true))
        #else
        // While the details sheet is up, it presents these itself (iOS shows one sheet per presenter).
        .modifier(ModelSheets(enabled: !showDetailSheet))
        #endif
        #if os(iOS)
        // iPhone / iPad: the details open when a slot is tapped. Narrow screens use a plain sheet
        // (reliable to dismiss and reopen); wide ones keep the inspector column.
        .onChange(of: model.inspectRequests) { _, _ in
            if compact { showDetailSheet = true } else { showInspector = true }
        }
        .sheet(isPresented: $showDetailSheet) {
            PokemonInspector()
                .modifier(ModelSheets(enabled: true))
                .environment(model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        #endif
    }

    /// The inspector column; on iPhone the details live in `showDetailSheet` instead.
    private var inspectorShown: Binding<Bool> {
        #if os(iOS)
        Binding(get: { showInspector && !compact }, set: { showInspector = $0 })
        #else
        $showInspector
        #endif
    }

    private var subtitle: String {
        guard let s = model.save else { return "" }
        return L("\(s.ot) · ID \(s.tid)") + (s.dirty ? L(" · modificato") : "")
    }

    @ViewBuilder private var content: some View {
        switch model.section {
        case .boxes: BoxView()
        case .party: PartyView()
        case .overview: OverviewView()
        case .trainer: TrainerView()
        case .bag: BagView()
        case .pokedex: PokedexView()
        case .events: EventsView()
        case .gifts: GiftsView()
        case .transfer: TransferView()
        case .advanced: AdvancedView()
        case .alm: AutoLegalityView()
        case .sorting: SortingView()
        case .special: SpecialFinderView()
        case .liveHex: LiveHexView()
        case .home: HomeLiveView()
        case .backups: BackupsView()
        }
    }

    #if os(macOS)
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { Task { await model.undo() } } label: { Label(L("Annulla"), systemImage: "arrow.uturn.backward") }
                .disabled(model.save?.undo == nil)
                .help(model.save?.undo.map { L("Annulla: \($0)") } ?? L("Niente da annullare"))
            Button { Task { await model.redo() } } label: { Label(L("Ripeti"), systemImage: "arrow.uturn.forward") }
                .disabled(model.save?.redo == nil)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            ChecksumIndicator()
            Button { model.openPanel() } label: { Label(L("Apri"), systemImage: "folder") }
                .help(L("Apri un altro salvataggio (⌘O)"))
            Button { Task { await model.saveFile() } } label: {
                Label(L("Salva"), systemImage: model.save?.dirty == true ? "square.and.arrow.down.fill" : "square.and.arrow.down")
            }
            .help(L("Salva con verifica dei checksum e backup automatico (⌘S)"))
            .disabled(model.save == nil)
            Button { showInspector.toggle() } label: { Label(L("Dettagli"), systemImage: "sidebar.trailing") }
        }
    }
    #else
    /// iPhone / iPad: fewer buttons in the bar; the rest (open, export, settings, close) in the "…" menu.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { Task { await model.undo() } } label: { Label(L("Annulla"), systemImage: "arrow.uturn.backward") }
                .disabled(model.save?.undo == nil)
            if !compact {
                Button { Task { await model.redo() } } label: { Label(L("Ripeti"), systemImage: "arrow.uturn.forward") }
                    .disabled(model.save?.redo == nil)
                ChecksumIndicator()
            }
            Button { Task { await model.saveFile() } } label: {
                Label(L("Salva"), systemImage: model.save?.dirty == true ? "square.and.arrow.down.fill" : "square.and.arrow.down")
            }
            .disabled(model.save == nil)
            if !compact {
                Button { showInspector.toggle() } label: { Label(L("Dettagli"), systemImage: "sidebar.trailing") }
            }
            Menu {
                if compact {
                    Button { Task { await model.redo() } } label: { Label(L("Ripeti"), systemImage: "arrow.uturn.forward") }
                        .disabled(model.save?.redo == nil)
                }
                Button { model.openPanel() } label: { Label(L("Apri"), systemImage: "folder") }
                Button { model.saveAsPanel() } label: { Label(L("Esporta come…"), systemImage: "square.and.arrow.up") }
                Button { model.section = .transfer; model.openSecondPanel() } label: {
                    Label(L("Apri secondo salvataggio per trasferire…"), systemImage: "arrow.left.arrow.right")
                }
                Divider()
                SettingsButton { Label(L("Impostazioni"), systemImage: "gearshape") }
                Button(role: .destructive) { model.closeSave() } label: { Label(L("Chiudi salvataggio"), systemImage: "xmark.circle") }
            } label: {
                Label(L("Altro"), systemImage: "ellipsis.circle")
            }
        }
    }
    #endif
}

/// The model-driven sheets (Showdown import, create Pokémon, legalize preview). `enabled: false` keeps a
/// presenter from showing them while another one (the iPhone details sheet) is in charge.
struct ModelSheets: ViewModifier {
    @Environment(AppModel.self) private var model
    var enabled: Bool

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .sheet(isPresented: enabled ? $model.showShowdownImport : .constant(false)) { ShowdownImportSheet() }
            .sheet(isPresented: enabled ? $model.showCreate : .constant(false)) { CreatePokemonSheet() }
            .sheet(item: enabled ? $model.pendingLegalize : .constant(nil)) { p in LegalizePreviewSheet(pending: p) }
    }
}

struct ChecksumIndicator: View {
    @Environment(AppModel.self) private var model
    @State private var status: ChecksumStatus?
    @State private var show = false

    var body: some View {
        let ok = model.save?.checksumValid ?? true
        Button {
            show.toggle()
        } label: {
            Label(ok ? L("Checksum OK") : L("Checksum"), systemImage: ok ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .foregroundStyle(ok ? .green : .orange)
        }
        .help(ok ? L("I checksum del salvataggio sono validi") : L("Il file originale aveva checksum non validi"))
        .popover(isPresented: $show) {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("Integrità del salvataggio"), systemImage: "shield.lefthalf.filled")
                    .font(.headline)
                Text(L("Prima di ogni salvataggio PkMac ricalcola i checksum, rilegge il file generato, confronta box e squadra, crea un backup e verifica la scrittura byte per byte."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let s = model.save, !s.checksumValid {
                    Text(s.checksumInfo).font(.caption.monospaced()).foregroundStyle(.orange)
                }
            }
            .padding(16)
            .pkPopoverFrame(width: 320)
        }
    }
}

struct SearchResultsPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.searchResults.isEmpty ? L("Nessun risultato") : "\(model.searchResults.count) risultati")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if !model.searchResults.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.searchResults) { r in
                            Button { Task { await model.reveal(r.ref) } } label: {
                                VStack(spacing: 4) {
                                    PokemonSprite(key: r.sprite, tint: PokeType(key: r.primaryType).color)
                                        .frame(width: 58, height: 58)
                                    Text(r.displayName).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                    Text(r.ref.label).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                .frame(width: 92)
                                .padding(.vertical, 8)
                                .background(PokeType(key: r.primaryType).color.opacity(0.10), in: .rect(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .pkGlassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
