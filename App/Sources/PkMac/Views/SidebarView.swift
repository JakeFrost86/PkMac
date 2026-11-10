import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // Footer below the list (not a safe-area inset): with a scrolling sidebar the inset made
        // AppKit re-layout in a loop and abort.
        VStack(spacing: 0) {
        List(selection: Binding(get: { model.section }, set: { if let s = $0 { model.section = s } })) {
            if let save = model.save {
                SaveCard(save: save)
                    .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 10, trailing: 6))
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            }

            SwiftUI.Section("Salvataggio") {
                ForEach(AppSection.saveSections) { s in
                    if (s != .boxes || model.save?.hasBox == true) && (s != .party || model.save?.hasParty == true) {
                        SidebarRow(section: s, badge: badge(for: s)).tag(s)
                    }
                }
            }
            SwiftUI.Section("Strumenti") {
                ForEach(AppSection.toolSections) { s in
                    SidebarRow(section: s, badge: s == .transfer ? model.saveB.map { $0.versionKey } : nil).tag(s)
                }
            }
            SwiftUI.Section("Plugin") {
                ForEach(AppSection.pluginSections) { s in
                    SidebarRow(section: s, badge: nil).tag(s)
                }
            }
            SwiftUI.Section("Sicurezza") {
                SidebarRow(section: .backups, badge: nil).tag(AppSection.backups)
            }
        }
        .listStyle(.sidebar)
        // A scroller that appears/disappears changes the row width, which changes the height,
        // which toggles the scroller again: AppKit gives up after too many layout passes.
        .scrollIndicators(.never)
        EngineFooter()
        }
    }

    private func badge(for s: AppSection) -> String? {
        switch s {
        case .boxes: model.save.map { "\($0.boxCount)" }
        case .party: model.save.map { "\($0.partyCount)" }
        default: nil
        }
    }
}

private struct SidebarRow: View {
    let section: AppSection
    let badge: String?

    var body: some View {
        Label {
            HStack {
                Text(section.title).lineLimit(1)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: section.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(LinearGradient(colors: [section.tint.mix(with: .white, by: 0.2), section.tint], startPoint: .top, endPoint: .bottom))
                )
        }
        .padding(.vertical, 2)
    }
}

private struct SaveCard: View {
    let save: SaveInfo
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                GameBadge(game: save.versionKey, generation: save.generation)
                VStack(alignment: .leading, spacing: 2) {
                    Text(save.game)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(2)
                    Text("Gen \(save.generation) · \(save.fileName ?? "")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if let c = save.container {
                Label(c.isBackup ? "Backup Azurii · \(c.title ?? "")" : "Salvataggio Azurii", systemImage: "doc.zipper")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x3FB6FF))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(hex: 0x3FB6FF).opacity(0.14), in: Capsule())
                    .help("Il file resta uno zip di Azurii: \(c.entry)")
            }
            HStack(spacing: 14) {
                Metric(symbol: "person.fill", value: save.ot)
                Metric(symbol: "clock.fill", value: save.playTime)
                if save.dirty {
                    Spacer()
                    Circle().fill(.orange).frame(width: 8, height: 8).help("Modifiche non salvate")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(model.accentType.color.opacity(0.18)), in: .rect(cornerRadius: 18))
    }

    private struct Metric: View {
        let symbol: String
        let value: String
        var body: some View {
            Label(value, systemImage: symbol)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// A colored game "cartridge" badge derived from the version.
struct GameBadge: View {
    let game: String
    let generation: Int

    private var colors: [Color] {
        switch game {
        case "SL": [Color(hex: 0xFF5B4A), Color(hex: 0xFF9E3D)]
        case "VL": [Color(hex: 0x8A4DFF), Color(hex: 0x4D6BFF)]
        case "SW": [Color(hex: 0x3FB6FF), Color(hex: 0x2B7BFF)]
        case "SH": [Color(hex: 0xFF4D8D), Color(hex: 0xC2185B)]
        case "BD": [Color(hex: 0x5AA9FF), Color(hex: 0x2F6BFF)]
        case "SP": [Color(hex: 0xFF8FD8), Color(hex: 0xD45AB3)]
        case "PLA": [Color(hex: 0x9C8A5A), Color(hex: 0x5D7F6A)]
        case "GP", "GE": [Color(hex: 0xFFD54A), Color(hex: 0xC69C4B)]
        case "ZA": [Color(hex: 0x4DE0B0), Color(hex: 0x2A9D8F)]
        default:
            switch generation {
            case 1: [Color(hex: 0xE53935), Color(hex: 0x1E88E5)]
            case 2: [Color(hex: 0xF9A825), Color(hex: 0x90A4AE)]
            case 3: [Color(hex: 0xD32F2F), Color(hex: 0x00897B)]
            case 4: [Color(hex: 0x1976D2), Color(hex: 0xEC407A)]
            case 5: [Color(hex: 0x424242), Color(hex: 0xBDBDBD)]
            case 6: [Color(hex: 0x1565C0), Color(hex: 0xC62828)]
            default: [Color(hex: 0xFF8F00), Color(hex: 0x6A1B9A)]
            }
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(game.count <= 3 ? game : String(game.prefix(3)))
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        }
        .frame(width: 40, height: 40)
        .shadow(color: colors[0].opacity(0.4), radius: 6, y: 3)
    }
}

private struct EngineFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(model.engineState == .ready ? .green : .orange).frame(width: 6, height: 6)
            Text("PKHeX.Core \(model.hello?.versions.core ?? "…")")
            Spacer()
            if model.updater.coreUpdateAvailable(current: model.hello?.versions.core) || model.updater.appUpdateAvailable
                || model.updater.engineUpdateAvailable(current: model.hello?.versions.engine) {
                SettingsLink {
                    Label("Aggiorna", systemImage: "arrow.down.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
        .font(.system(size: 11, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
