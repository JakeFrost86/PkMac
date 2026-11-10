import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var showInspector = !Diag.off("INSPECTOR")

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
                    .clipped()
                if !model.searchText.isEmpty {
                    SearchResultsPanel()
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(Theme.spring, value: model.searchText.isEmpty)
            .inspector(isPresented: $showInspector) {
                PokemonInspector()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .inspectorColumnWidth(min: 360, ideal: 410, max: 520)
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Cerca Pokémon, soprannome, OT… o \"shiny\", \"illegale\"")
        .onChange(of: model.searchText) { _, _ in
            Task { await model.search() }
        }
        .toolbar { toolbar }
        .navigationTitle(model.save?.game ?? "PkMac")
        .navigationSubtitle(subtitle)
        .sheet(isPresented: $model.showShowdownImport) { ShowdownImportSheet() }
        .sheet(isPresented: $model.showCreate) { CreatePokemonSheet() }
    }

    private var subtitle: String {
        guard let s = model.save else { return "" }
        return "\(s.ot) · ID \(s.tid)" + (s.dirty ? " · modificato" : "")
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

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { Task { await model.undo() } } label: { Label("Annulla", systemImage: "arrow.uturn.backward") }
                .disabled(model.save?.undo == nil)
                .help(model.save?.undo.map { "Annulla: \($0)" } ?? "Niente da annullare")
            Button { Task { await model.redo() } } label: { Label("Ripeti", systemImage: "arrow.uturn.forward") }
                .disabled(model.save?.redo == nil)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            ChecksumIndicator()
            Button { model.openPanel() } label: { Label("Apri", systemImage: "folder") }
                .help("Apri un altro salvataggio (⌘O)")
            Button { Task { await model.saveFile() } } label: {
                Label("Salva", systemImage: model.save?.dirty == true ? "square.and.arrow.down.fill" : "square.and.arrow.down")
            }
            .help("Salva con verifica dei checksum e backup automatico (⌘S)")
            .disabled(model.save == nil)
            Button { showInspector.toggle() } label: { Label("Dettagli", systemImage: "sidebar.trailing") }
        }
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
            Label(ok ? "Checksum OK" : "Checksum", systemImage: ok ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .foregroundStyle(ok ? .green : .orange)
        }
        .help(ok ? "I checksum del salvataggio sono validi" : "Il file originale aveva checksum non validi")
        .popover(isPresented: $show) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Integrità del salvataggio", systemImage: "shield.lefthalf.filled")
                    .font(.headline)
                Text("Prima di ogni salvataggio PkMac ricalcola i checksum, rilegge il file generato, confronta box e squadra, crea un backup e verifica la scrittura byte per byte.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let s = model.save, !s.checksumValid {
                    Text(s.checksumInfo).font(.caption.monospaced()).foregroundStyle(.orange)
                }
            }
            .padding(16)
            .frame(width: 320)
        }
    }
}

struct SearchResultsPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.searchResults.isEmpty ? "Nessun risultato" : "\(model.searchResults.count) risultati")
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
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
