import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            UpdatesSettings()
                .tabItem { Label("Aggiornamenti", systemImage: "arrow.triangle.2.circlepath") }
            AppearanceSettings()
                .tabItem { Label("Aspetto", systemImage: "paintpalette") }
            NamingSettings()
                .tabItem { Label("Nomi file", systemImage: "textformat") }
            GeneralSettings()
                .tabItem { Label("Generale", systemImage: "gearshape") }
            AboutSettings()
                .tabItem { Label("Info", systemImage: "info.circle") }
        }
        .frame(width: 640, height: 640)
    }
}

private struct UpdatesSettings: View {
    @Environment(AppModel.self) private var model
    @State private var repo = ""

    var body: some View {
        let u = model.updater
        let v = model.hello?.versions
        Form {
            SwiftUI.Section {
                VersionRow(title: "PKHeX.Core", symbol: "cpu.fill", current: v?.core ?? "…",
                           latest: u.latestCore, available: u.coreUpdateAvailable(current: v?.core),
                           note: "Scaricato da NuGet e installato al volo, senza ricompilare.") {
                    if let l = u.latestCore { Task { await model.installCore(l) } }
                }
                VersionRow(title: "Motore e plugin", symbol: "puzzlepiece.extension.fill", current: v?.engine ?? "…",
                           latest: u.enginePack?.version, available: u.engineUpdateAvailable(current: v?.engine),
                           note: "Auto Legality \(v?.alm ?? "?"), LiveHeX, HOME Live, PokeFilename, PluginPile. Ricompilato da GitHub Actions.") {
                    Task { await model.installEnginePack() }
                }
                VersionRow(title: "PkMac", symbol: "macwindow", current: Updater.appVersion,
                           latest: u.appRelease?.version, available: u.appUpdateAvailable,
                           note: "L'app intera, dalle release GitHub.") {
                    if let r = u.appRelease { Task { await u.installApp(r) } }
                }
            } header: {
                HStack {
                    Text("Versioni")
                    Spacer()
                    Button {
                        Task { await model.checkUpdates(silent: false) }
                    } label: {
                        if u.phase == .checking { ProgressView().controlSize(.small) } else { Label("Controlla ora", systemImage: "arrow.clockwise") }
                    }
                    .buttonStyle(.glass)
                }
            }

            switch u.phase {
            case .working(let msg, let p):
                SwiftUI.Section { ProgressView(value: p) { Text(msg) } }
            case .failed(let msg):
                SwiftUI.Section { Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            case .done(let msg):
                SwiftUI.Section { Label(msg, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            default: EmptyView()
            }

            SwiftUI.Section("Automatico") {
                Toggle("Controlla gli aggiornamenti all'avvio", isOn: Binding(get: { u.autoCheck }, set: { u.autoCheck = $0 }))
                Toggle("Installa da solo i nuovi PKHeX.Core (dopo i test di sicurezza)", isOn: Binding(get: { u.autoInstallCore }, set: { u.autoInstallCore = $0 }))
                if let d = u.lastCheck {
                    Text("Ultimo controllo: \(d.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }
            }

            SwiftUI.Section("Repository GitHub di PkMac") {
                TextField("utente/PkMac", text: $repo)
                    .onSubmit { u.repo = repo }
                Text("Da qui arrivano gli aggiornamenti del motore e dell'app.").font(.caption).foregroundStyle(.secondary)
                Button("Torna al motore incluso nell'app") { Task { await model.rollbackEngine() } }
                    .disabled(EngineManager.activeManifest() == nil)
            }
        }
        .formStyle(.grouped)
        .onAppear { repo = u.repo }
        .onDisappear { u.repo = repo }
    }
}

private struct VersionRow: View {
    let title: String
    let symbol: String
    let current: String
    let latest: String?
    let available: Bool
    let note: String
    let install: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.brand))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).fontWeight(.semibold)
                    Text(current).foregroundStyle(.secondary).monospacedDigit()
                }
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if available, let latest {
                Button("Installa \(latest)", action: install).buttonStyle(.glassProminent)
            } else if latest != nil {
                StatusBadge(kind: .ok, text: "Aggiornato")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct NamingSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("namer.kind") private var kind = "Default"
    @AppStorage("namer.regular") private var pattern = "{Species} - {Nickname} - {PID}"

    var body: some View {
        Form {
            SwiftUI.Section("PokeFilename") {
                Picker("Stile dei nomi", selection: $kind) {
                    Text("PKHeX (predefinito)").tag("Default")
                    Text("Anubis").tag("AnubisNamer")
                    Text("Personalizzato").tag("CustomNamer")
                }
                if kind == "CustomNamer" {
                    TextField("Schema", text: $pattern)
                        .font(.system(.body, design: .monospaced))
                    Text("Parole chiave: {Species} {Nickname} {FormName} {CurrentLevel} {Nature} {ShinyType} {ItemName} {OriginalTrainerName} {TID16} {PID} {Legality} {Alpha} {Gigantamax} e qualsiasi proprietà PKHeX tra graffe.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Usato quando esporti file .pk dai box.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: kind) { _, _ in Task { await model.applyALMSettings() } }
        .onChange(of: pattern) { _, _ in Task { await model.applyALMSettings() } }
    }
}

private struct AppearanceSettings: View {
    @AppStorage(AppIconManager.key) private var icon = AppIconManager.defaultID
    @AppStorage(SpriteSettings.key) private var sprites = SpriteSettings.Mode.threeD.rawValue

    var body: some View {
        Form {
            SwiftUI.Section("Sprite dei Pokémon") {
                Picker("Stile", selection: $sprites) {
                    ForEach(SpriteSettings.Mode.allCases) { m in
                        Text(m.title).tag(m.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                HStack(spacing: 18) {
                    ForEach([1, 6, 25, 150], id: \.self) { sp in
                        PokemonSprite(key: SpriteKey(species: sp, formKey: "", shiny: false, female: false, egg: false))
                            .frame(width: 64, height: 64)
                    }
                }
                .frame(maxWidth: .infinity)
                .id(sprites)
                Text(SpriteSettings.Mode(rawValue: sprites)?.detail ?? "").font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Section("Icona dell'app") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                    ForEach(AppIconManager.all, id: \.id) { item in
                        Button {
                            icon = item.id
                            AppIconManager.apply(item.id)
                        } label: {
                            VStack(spacing: 4) {
                                if let img = AppIconManager.image(item.id) {
                                    Image(nsImage: img).resizable().interpolation(.high).scaledToFit()
                                        .frame(width: 64, height: 64)
                                }
                                Text(item.name).font(.system(size: 10.5)).lineLimit(1)
                            }
                            .padding(6)
                            .background(icon == item.id ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(icon == item.id ? Color.accentColor : .clear, lineWidth: 2))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Cambia subito l'icona nel Dock e nel Finder.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct GeneralSettings: View {
    @State private var cache: Int64 = 0

    var body: some View {
        Form {
            SwiftUI.Section("Sprite (PokeAPI)") {
                LabeledContent("Cache su disco", value: ByteCountFormatter.string(fromByteCount: cache, countStyle: .file))
                Button("Svuota la cache degli sprite") {
                    Task { await SpriteStore.shared.clearCache(); cache = await SpriteStore.shared.cacheSize() }
                }
                Text("Gli sprite di github.com/PokeAPI/sprites vengono scaricati la prima volta e poi restano sul Mac.").font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Section("Cartelle") {
                Button("Apri la cartella di PkMac") { NSWorkspace.shared.open(AppPaths.support) }
            }
        }
        .formStyle(.grouped)
        .task { cache = await SpriteStore.shared.cacheSize() }
    }
}

private struct AboutSettings: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                AnimatedLogo(width: 150, showText: false)
                Text("PkMac \(Updater.appVersion)").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Theme.brand)
                Text("Editor di salvataggi Pokémon per macOS, basato su PKHeX.Core.").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    credit("PKHeX.Core", "Kaphotics (kwsch) e collaboratori · GPLv3")
                    credit("Auto Legality Mod, LiveHeX", "architdate, kwsch, santacrab2 · PKHeX-Plugins")
                    credit("HOME Live", "Manu098vm · HOME-Live-Plugin")
                    credit("PokeFilename", "architdate, Lusamine")
                    credit("PluginPile (ordinamento, Pokémon speciali)", "foohyfooh")
                    credit("Sprite", "PokeAPI/sprites")
                }
                .padding(14)
                .background(.primary.opacity(0.04), in: .rect(cornerRadius: 14))
                Text("Pokémon è un marchio di Nintendo, Creatures e GAME FREAK. PkMac non è affiliato con loro. Non usare Pokémon modificati in lotta o negli scambi con chi non ne è al corrente.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }

    private func credit(_ what: String, _ who: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(what).fontWeight(.semibold)
            Spacer()
            Text(who).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .font(.system(size: 12))
    }
}
