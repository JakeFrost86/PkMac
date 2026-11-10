import SwiftUI

/// "Everything PKHeX can edit": a reflection browser over the save (and its sub-blocks) plus the SCBlock
/// list of Switch games.
struct AdvancedView: View {
    @Environment(AppModel.self) private var model
    @State private var mode = 0
    @State private var blockTarget: (key: String, name: String)?

    private var hasBlocks: Bool { (model.save?.generation ?? 0) >= 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(title: "Dati avanzati", subtitle: "Ogni valore del salvataggio che PKHeX sa leggere e scrivere", symbol: "slider.horizontal.below.square.and.square.filled", tint: AppSection.advanced.tint)
            HStack {
                Picker("", selection: $mode) {
                    Text("Campi del salvataggio").tag(0)
                    if hasBlocks { Text("Blocchi di gioco").tag(1) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 340)
                Spacer()
                Label("Modifiche annullabili con ⌘Z · verificate al salvataggio", systemImage: "checkmark.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Group {
                if mode == 1, hasBlocks {
                    if let b = blockTarget {
                        VStack(alignment: .leading, spacing: 8) {
                            Button { blockTarget = nil } label: { Label("Tutti i blocchi", systemImage: "chevron.left") }.buttonStyle(.glass)
                            InspectorBrowser(target: ["target": "block", "key": b.key], rootTitle: b.name)
                        }
                    } else {
                        BlocksList { key, name in blockTarget = (key, name) }
                    }
                } else {
                    InspectorBrowser(target: ["target": "save"], rootTitle: model.save?.game ?? "Salvataggio")
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(26)
        .onChange(of: model.save?.path) { _, _ in blockTarget = nil; mode = 0 }
    }
}

// MARK: - Reflection browser

struct InspectorBrowser: View {
    @Environment(AppModel.self) private var model
    let target: [String: Any]
    let rootTitle: String
    var compact = false

    @State private var path: [String] = []
    @State private var props: [InspectProp] = []
    @State private var typeName = ""
    @State private var filter = ""
    @State private var loading = true

    private var targetID: String { target.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "&") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                breadcrumb
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filtra", text: $filter).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.primary.opacity(0.05), in: Capsule())
                .frame(maxWidth: compact ? 140 : 220)
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else {
                let shown = props.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
                let children = shown.filter { $0.kind == "object" }
                let values = shown.filter { $0.kind != "object" }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !children.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 130 : 170), spacing: 8)], spacing: 8) {
                                ForEach(children) { c in
                                    Button { Task { await open(c.name) } } label: {
                                        HStack {
                                            Image(systemName: "folder.fill").foregroundStyle(AppSection.advanced.tint)
                                            Text(pretty(c.name)).lineLimit(1)
                                            Spacer(minLength: 0)
                                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                                        }
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .padding(.horizontal, 10).padding(.vertical, 8)
                                        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 10))
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                    .help(c.type)
                                }
                            }
                        }
                        VStack(spacing: 0) {
                            ForEach(values) { p in
                                PropRow(prop: p, compact: compact) { value in
                                    Task { await set(p.name, value) }
                                }
                                Divider().opacity(0.4)
                            }
                        }
                        .background(.background.secondary.opacity(0.5), in: .rect(cornerRadius: 14))
                    }
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.never)
            }
        }
        .task(id: targetID) { path = []; await load() }
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button(rootTitle) { Task { path = []; await load() } }
                    .buttonStyle(.plain).fontWeight(path.isEmpty ? .bold : .regular)
                ForEach(Array(path.enumerated()), id: \.offset) { i, p in
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    Button(pretty(p)) { Task { path = Array(path.prefix(i + 1)); await load() } }
                        .buttonStyle(.plain).fontWeight(i == path.count - 1 ? .bold : .regular)
                }
            }
            .font(.system(size: 12.5, design: .rounded))
        }
    }

    private func pretty(_ name: String) -> String {
        var out = ""
        for (i, ch) in name.enumerated() {
            if i > 0, ch.isUppercase, let prev = out.last, prev.isLowercase { out.append(" ") }
            out.append(ch)
        }
        return out
    }

    private func load() async {
        loading = props.isEmpty
        if let d = await model.inspect(target: target, path: path) {
            props = d.props; typeName = d.type
        }
        loading = false
    }

    private func open(_ name: String) async {
        path.append(name)
        filter = ""
        await load()
    }

    private func set(_ name: String, _ value: Any) async {
        if let p = await model.inspectSet(target: target, path: path, prop: name, value: value) {
            props = p
        } else {
            await load()
        }
    }
}

private struct PropRow: View {
    let prop: InspectProp
    var compact = false
    let onSet: (Any) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(prop.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if !compact { Text(prop.type).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 8)
            editor
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .opacity(prop.editable ? 1 : 0.6)
        .onAppear { text = prop.value?.text ?? "" }
        .onChange(of: prop.value) { _, v in if !focused { text = v?.text ?? "" } }
    }

    @ViewBuilder private var editor: some View {
        switch prop.kind {
        case "bool":
            Toggle("", isOn: Binding(get: { prop.value?.bool ?? false }, set: { onSet($0) }))
                .toggleStyle(.switch).controlSize(.small).labelsHidden().disabled(!prop.editable)
        case "enum" where prop.options != nil:
            Picker("", selection: Binding(get: { prop.value?.text ?? "" }, set: { onSet($0) })) {
                ForEach(prop.options ?? [], id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(width: compact ? 140 : 200).disabled(!prop.editable)
        default:
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: prop.kind == "string" ? (compact ? 150 : 240) : (compact ? 90 : 130))
                .multilineTextAlignment(prop.kind == "string" ? .leading : .trailing)
                .font(.system(size: 12, design: prop.kind == "string" ? .default : .monospaced))
                .focused($focused)
                .disabled(!prop.editable)
                .onSubmit { if text != prop.value?.text { onSet(text) } }
                .help(prop.min.map { "Intervallo \($0) … \(prop.max ?? "")" } ?? "")
        }
    }
}

// MARK: - SCBlocks

private struct BlocksList: View {
    @Environment(AppModel.self) private var model
    let onOpen: (String, String) -> Void
    @State private var data: BlocksData?
    @State private var query = ""
    @State private var valuesOnly = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Cerca per nome o chiave (es. Money, Badge, Raid, 0x…)", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(.primary.opacity(0.05), in: Capsule())
                Toggle("Solo valori e sezioni", isOn: $valuesOnly).toggleStyle(.switch).controlSize(.small)
                if let d = data { Text("\(d.blocks.count) di \(d.total ?? 0)").font(.caption).foregroundStyle(.secondary) }
            }
            if let d = data {
                List(d.blocks) { b in
                    HStack(spacing: 10) {
                        Image(systemName: b.hasObject ? "folder.fill" : (b.type == "Bool" ? "switch.2" : "number"))
                            .foregroundStyle(b.named ? AppSection.advanced.tint : .secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(b.name).font(.system(size: 12.5, weight: b.named ? .semibold : .regular, design: b.named ? .rounded : .monospaced))
                            Text("\(b.key) · \(b.type)\(b.size > 8 ? " · \(b.size) byte" : "")").font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if b.hasObject {
                            Button("Apri") { onOpen(b.key, b.name) }.buttonStyle(.glass).controlSize(.small)
                        }
                        if b.editable { BlockValue(block: b) }
                    }
                    .padding(.vertical, 1)
                }
                .listStyle(.inset)
                .clipShape(.rect(cornerRadius: 16))
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .task(id: "\(query)|\(valuesOnly)|\(model.save?.path ?? "")") {
            try? await Task.sleep(for: .milliseconds(200))
            data = await model.blocks(query: query, valuesOnly: valuesOnly)
        }
    }
}

private struct BlockValue: View {
    @Environment(AppModel.self) private var model
    let block: BlockRow
    @State private var text = ""
    @State private var on = false

    var body: some View {
        Group {
            if block.type == "Bool" {
                Toggle("", isOn: Binding(get: { on }, set: { v in
                    on = v
                    Task { if !(await model.setBlock(key: block.key, value: v)) { on = !v } }
                }))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
            } else {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder).frame(width: 150)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { Task { _ = await model.setBlock(key: block.key, value: text) } }
            }
        }
        .onAppear { text = block.value?.text ?? ""; on = block.value?.bool ?? false }
    }
}
