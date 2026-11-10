import SwiftUI

struct ShowdownImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var results: [ImportResult] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "doc.on.clipboard.fill").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text(L("Importa set Showdown")).font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(L("Auto Legality genera ogni set come Pokémon legale nel box \(model.currentBox + 1).")).font(.callout).foregroundStyle(.secondary)
                }
            }
            TextEditor(text: $text)
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(.primary.opacity(0.05), in: .rect(cornerRadius: 14))
                .frame(minHeight: 240)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(L("Garchomp @ Choice Scarf\nAbility: Rough Skin\nTera Type: Steel\nEVs: 252 Atk / 4 SpD / 252 Spe\nJolly Nature\n- Earthquake\n- Outrage\n- Stone Edge\n- Stealth Rock\n\noppure un link https://pokepast.es/…"))
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(15)
                            .allowsHitTesting(false)
                    }
                }

            if !results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(results) { r in
                            HStack {
                                Image(systemName: r.status == "ok" && r.legal == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(r.status == "ok" && r.legal == true ? .green : .orange)
                                Text(r.name).fontWeight(.semibold)
                                Text(label(r)).foregroundStyle(.secondary)
                                Spacer()
                                if let ref = r.ref { Text(ref.label).font(.caption).foregroundStyle(.tertiary) }
                            }
                            .font(.system(size: 12.5))
                        }
                    }
                }
                .frame(maxHeight: 140)
            }

            HStack {
                Button(L("Incolla dagli appunti")) { text = NSPasteboard.general.string(forType: .string) ?? text }
                    .buttonStyle(.glass)
                Spacer()
                Button(L("Chiudi")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    Task { results = await model.importShowdown(text) }
                } label: { Label(L("Genera"), systemImage: "wand.and.stars") }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    private func label(_ r: ImportResult) -> String {
        switch r.status {
        case "ok": r.legal == true ? "legale" : L("creato, ma non del tutto legale")
        case "timeout": L("tempo scaduto")
        case "nospace": L("nessuno slot libero")
        case "invalid": L("righe non valide: \(r.lines?.joined(separator: ", ") ?? "")")
        case "mismatch": L("versione del core non compatibile")
        default: L("non generato")
        }
    }
}

struct CreatePokemonSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var species: ListItem?
    @State private var info: SpeciesInfo?
    @State private var form = 0
    @State private var shiny = false

    private var filtered: [ListItem] {
        let all = model.lists?.species.filter { $0.v > 0 } ?? []
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.t.localizedCaseInsensitiveContains(q) || "\($0.v)" == q }
    }

    private var target: SlotRef? {
        if let sel = model.selection, sel.isParty == false, model.box?.slots.first(where: { $0.ref == sel })?.empty == true { return sel }
        return model.firstEmptySlot().map { .box(model.currentBox, $0) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField(L("Cerca per nome o numero"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(12)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                        ForEach(filtered.prefix(400)) { s in
                            Button { species = s; form = 0 } label: {
                                VStack(spacing: 2) {
                                    PokemonSprite(key: SpriteKey(species: s.v, formKey: "", shiny: false, female: false, egg: false))
                                        .frame(width: 56, height: 56)
                                    Text(s.t).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                                }
                                .frame(width: 84, height: 82)
                                .background(species?.v == s.v ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 12))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
            }
            .frame(width: 420)
            .background(.primary.opacity(0.03))

            VStack(spacing: 14) {
                if let s = species {
                    let t = PokeType(key: info?.types.first)
                    ZStack {
                        Circle().fill(RadialGradient(colors: [t.glow.opacity(0.7), .clear], center: .center, startRadius: 5, endRadius: 110))
                        if shiny { SparkleField().frame(width: 200, height: 180) }
                        PokemonSprite(key: SpriteKey(species: s.v, formKey: formKey, shiny: shiny, female: false, egg: false, form: form), style: .artwork, tint: t.color)
                            .frame(width: 170, height: 170)
                    }
                    .frame(height: 200)
                    Text(s.t).font(.system(size: 22, weight: .heavy, design: .rounded))
                    HStack { ForEach(info?.types ?? [], id: \.self) { TypePill(type: PokeType(key: $0)) } }
                    if let forms = info?.forms, forms.count > 1 {
                        Picker(L("Forma"), selection: $form) {
                            ForEach(Array(forms.enumerated()), id: \.offset) { i, f in Text(f.isEmpty ? L("Normale") : f).tag(i) }
                        }
                        .frame(width: 240)
                    }
                    Toggle(isOn: $shiny) { Label(L("Cromatico"), systemImage: "sparkles") }.toggleStyle(.switch)
                    if info?.inGame == false {
                        StatusBadge(kind: .warn, text: L("Non presente in questo gioco"))
                    }
                } else {
                    Spacer()
                    Text(L("Scegli una specie")).foregroundStyle(.secondary)
                }
                Spacer()
                Text(target.map { L("Verrà creato in \($0.label)") } ?? L("Nessuno slot libero nel box")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L("Annulla")) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button {
                        guard let s = species, let target else { return }
                        dismiss()
                        Task { await model.createPokemon(species: s.v, form: form, shiny: shiny, at: target) }
                    } label: { Label(L("Crea legale"), systemImage: "wand.and.stars") }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(species == nil || target == nil)
                }
            }
            .padding(20)
            .frame(width: 320)
        }
        .frame(height: 560)
        .task(id: species?.v) {
            guard let s = species else { return }
            info = await model.speciesInfo(s.v, form: 0)
        }
    }

    private var formKey: String {
        guard form > 0, let f = info?.forms, form < f.count else { return "" }
        return f[form]
    }
}

/// Animated checklist shown after every save: what was verified, where the backup went.
struct SaveReportView: View {
    let result: SaveResult
    @Environment(\.dismiss) private var dismiss
    @State private var shown = 0
    @State private var sealed = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(.green.opacity(0.14)).frame(width: 96, height: 96).scaleEffect(sealed ? 1 : 0.6)
                Image(systemName: sealed ? "checkmark.shield.fill" : "shield")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.green)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: sealed)
            }
            Text(L("Salvataggio verificato")).font(.system(size: 22, weight: .heavy, design: .rounded))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(result.steps.enumerated()), id: \.offset) { i, step in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(step).font(.system(size: 13, design: .rounded))
                    }
                    .opacity(i < shown ? 1 : 0)
                    .offset(x: i < shown ? 0 : -12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.primary.opacity(0.04), in: .rect(cornerRadius: 16))

            VStack(spacing: 4) {
                Text(URL(fileURLWithPath: result.path).lastPathComponent).font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text(L("SHA-256 \(result.sha256)…")).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack {
                if let b = result.backup {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: b)]) } label: {
                        Label(L("Mostra backup"), systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.glass)
                }
                Spacer()
                Button(L("Fatto")) { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 460)
        .task {
            for i in 1...max(1, result.steps.count) {
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(Theme.spring) { shown = i }
            }
            withAnimation(Theme.spring) { sealed = true }
        }
    }
}
