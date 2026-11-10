import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            UpdatesSettings()
                .tabItem { Label(L("Aggiornamenti"), systemImage: "arrow.triangle.2.circlepath") }
            AppearanceSettings()
                .tabItem { Label(L("Aspetto"), systemImage: "paintpalette") }
            NamingSettings()
                .tabItem { Label(L("Nomi file"), systemImage: "textformat") }
            GeneralSettings()
                .tabItem { Label(L("Generale"), systemImage: "gearshape") }
            BackupSettings()
                .tabItem { Label(L("Backup"), systemImage: "clock.arrow.circlepath") }
            AboutSettings()
                .tabItem { Label(L("Info"), systemImage: "info.circle") }
        }
        .frame(width: 640, height: 640)
    }
}

private struct UpdatesSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let u = model.updater
        let v = model.hello?.versions
        Form {
            SwiftUI.Section {
                VersionRow(title: "PKHeX.Core", symbol: "cpu.fill", current: v?.core ?? "…",
                           latest: u.latestCore, available: u.coreUpdateAvailable(current: v?.core),
                           note: L("Scaricato da NuGet e installato al volo, senza ricompilare.")) {
                    if let l = u.latestCore { Task { await model.installCore(l) } }
                }
                VersionRow(title: L("Motore e plugin"), symbol: "puzzlepiece.extension.fill", current: v?.engine ?? "…",
                           latest: u.enginePack?.version, available: u.engineUpdateAvailable(current: v?.engine),
                           note: L("Auto Legality \(v?.alm ?? "?"), LiveHeX, HOME Live, PokeFilename, PluginPile. Ricompilato da GitHub Actions.")) {
                    Task { await model.installEnginePack() }
                }
                VersionRow(title: "PkMac", symbol: "macwindow", current: Updater.appVersion,
                           latest: u.appRelease?.version, available: u.appUpdateAvailable,
                           note: L("L'app intera, dalle release GitHub.")) {
                    if let r = u.appRelease { Task { await u.installApp(r) } }
                }
            } header: {
                HStack {
                    Text(L("Versioni"))
                    Spacer()
                    Button {
                        Task { await model.checkUpdates(silent: false) }
                    } label: {
                        if u.phase == .checking { ProgressView().controlSize(.small) } else { Label(L("Controlla ora"), systemImage: "arrow.clockwise") }
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

            SwiftUI.Section(L("Automatico")) {
                Toggle(L("Controlla gli aggiornamenti all'avvio"), isOn: Binding(get: { u.autoCheck }, set: { u.autoCheck = $0 }))
                Toggle(L("Installa da solo i nuovi PKHeX.Core (dopo i test di sicurezza)"), isOn: Binding(get: { u.autoInstallCore }, set: { u.autoInstallCore = $0 }))
                if let d = u.lastCheck {
                    Text(L("Ultimo controllo: \(d.formatted(date: .abbreviated, time: .shortened))")).font(.caption).foregroundStyle(.secondary)
                }
            }

            SwiftUI.Section(L("Ripristino")) {
                Button(L("Torna al motore incluso nell'app")) { Task { await model.rollbackEngine() } }
                    .disabled(EngineManager.activeManifest() == nil)
                Text(L("Utile se un aggiornamento del motore dovesse dare problemi.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
                Button(L("Installa \(latest)"), action: install).buttonStyle(.glassProminent)
            } else if latest != nil {
                StatusBadge(kind: .ok, text: L("Aggiornato"))
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
                Picker(L("Stile dei nomi"), selection: $kind) {
                    Text(L("PKHeX (predefinito)")).tag("Default")
                    Text(L("Anubis")).tag("AnubisNamer")
                    Text(L("Personalizzato")).tag("CustomNamer")
                }
                if kind == "CustomNamer" {
                    TextField(L("Schema"), text: $pattern)
                        .font(.system(.body, design: .monospaced))
                    Text(L("Parole chiave: {Species} {Nickname} {FormName} {CurrentLevel} {Nature} {ShinyType} {ItemName} {OriginalTrainerName} {TID16} {PID} {Legality} {Alpha} {Gigantamax} e qualsiasi proprietà PKHeX tra graffe."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(L("Usato quando esporti file .pk dai box.")).font(.caption).foregroundStyle(.secondary)
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
            SwiftUI.Section(L("Sprite dei Pokémon")) {
                Picker(L("Stile"), selection: $sprites) {
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
            SwiftUI.Section(L("Icona dell'app")) {
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
                Text(L("Cambia subito l'icona nel Dock e nel Finder.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct GeneralSettings: View {
    @State private var cache: Int64 = 0

    var body: some View {
        Form {
            SwiftUI.Section(L("Lingua")) {
                Picker(L("Lingua dell'app"), selection: Binding(get: { Lang.choice }, set: { Lang.switchTo($0) })) {
                    Text(L("Automatica (lingua di macOS)")).tag("system")
                    Text("Italiano").tag("it")
                    Text("English").tag("en")
                }
                Text(L("Vale anche per i nomi di Pokémon, mosse e strumenti e per i messaggi di legalità. Cambiando lingua PkMac si riavvia.")).font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Section(L("Sprite (PokeAPI)")) {
                LabeledContent(L("Cache su disco"), value: ByteCountFormatter.string(fromByteCount: cache, countStyle: .file))
                Button(L("Svuota la cache degli sprite")) {
                    Task { await SpriteStore.shared.clearCache(); cache = await SpriteStore.shared.cacheSize() }
                }
                Text(L("Gli sprite di github.com/PokeAPI/sprites vengono scaricati la prima volta e poi restano sul Mac.")).font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Section(L("Cartelle")) {
                Button(L("Apri la cartella di PkMac")) { NSWorkspace.shared.open(AppPaths.support) }
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
                Text(L("Editor di salvataggi Pokémon per macOS, basato su PKHeX.Core.")).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    credit("PKHeX.Core", L("Kaphotics (kwsch) e collaboratori · GPLv3"))
                    credit("Auto Legality Mod, LiveHeX", L("architdate, kwsch, santacrab2 · PKHeX-Plugins"))
                    credit("HOME Live", L("Manu098vm · HOME-Live-Plugin"))
                    credit("PokeFilename", L("architdate, Lusamine"))
                    credit("PluginPile (ordinamento, Pokémon speciali)", "foohyfooh")
                    credit("Sprite", "PokeAPI/sprites")
                }
                .padding(14)
                .background(.primary.opacity(0.04), in: .rect(cornerRadius: 14))
                Text(L("Pokémon è un marchio di Nintendo, Creatures e GAME FREAK. PkMac non è affiliato con loro. Non usare Pokémon modificati in lotta o negli scambi con chi non ne è al corrente."))
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


/// Backups of the saves: how many to keep, for how long, and cleanup.
private struct BackupSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(BackupPolicy.keepKey) private var keep = 20
    @AppStorage(BackupPolicy.daysKey) private var days = 0
    @State private var stats: BackupStats?
    @State private var message: String?
    @State private var confirmDelete = false

    var body: some View {
        Form {
            SwiftUI.Section {
                Picker(L("Backup da tenere per ogni salvataggio"), selection: $keep) {
                    ForEach([3, 5, 10, 20, 40, 100], id: \.self) { Text("\($0)").tag($0) }
                    Text(L("Tutti")).tag(0)
                }
                Picker(L("Elimina i backup più vecchi di"), selection: $days) {
                    Text(L("Mai")).tag(0)
                    Text(L("7 giorni")).tag(7)
                    Text(L("30 giorni")).tag(30)
                    Text(L("90 giorni")).tag(90)
                    Text(L("6 mesi")).tag(180)
                    Text(L("1 anno")).tag(365)
                }
                Text(L("PkMac fa un backup prima di ogni salvataggio e uno al giorno quando apri un file. Ogni volta che ne crea uno nuovo elimina quelli in più per quel salvataggio, secondo queste regole. Il backup appena creato non viene mai eliminato."))
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text(L("Regole")) }

            SwiftUI.Section {
                if let stats {
                    LabeledContent(L("Backup sul Mac"), value: L("\(stats.count) file di \(stats.saves) salvataggi"))
                    LabeledContent(L("Spazio occupato"), value: ByteCountFormatter.string(fromByteCount: stats.size, countStyle: .file))
                    if let o = stats.oldest, let d = ISO8601DateFormatter.flexible.date(from: o) {
                        LabeledContent(L("Il più vecchio"), value: d.formatted(date: .abbreviated, time: .shortened))
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
                HStack {
                    Button { Task { if let r = await model.pruneBackups() { stats = r.1; message = L("Eliminati \(r.0) backup in più.") } } } label: {
                        Label(L("Pulisci ora"), systemImage: "wand.and.sparkles")
                    }
                    Button { if let s = stats { NSWorkspace.shared.open(URL(fileURLWithPath: s.root)) } } label: {
                        Label(L("Apri cartella"), systemImage: "folder")
                    }
                    Spacer()
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label(L("Elimina tutti"), systemImage: "trash")
                    }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            } header: { Text(L("Spazio")) }
        }
        .formStyle(.grouped)
        .task { stats = await model.backupStats() }
        .onChange(of: keep) { _, _ in Task { await model.applyBackupPolicy(); stats = await model.backupStats() } }
        .onChange(of: days) { _, _ in Task { await model.applyBackupPolicy(); stats = await model.backupStats() } }
        .confirmationDialog(L("Eliminare tutti i backup?"), isPresented: $confirmDelete) {
            Button(L("Elimina tutti i backup"), role: .destructive) {
                Task { if let r = await model.deleteAllBackups() { stats = r.1; message = L("Eliminati \(r.0) backup.") } }
            }
        } message: {
            Text(L("Verranno cancellati per sempre i backup di tutti i salvataggi. I salvataggi veri non vengono toccati."))
        }
    }
}

