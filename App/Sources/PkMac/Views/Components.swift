import SwiftUI

/// Searchable picker shown in a popover; used for species, moves, items, abilities…
struct SearchPicker: View {
    let title: String
    let items: [ListItem]
    let selected: Int?
    var showsTypes = false
    let onPick: (ListItem) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private var filtered: [ListItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter { $0.t.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Cerca \(title.lowercased())", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit {
                        if let first = filtered.first { onPick(first); dismiss() }
                    }
            }
            .padding(10)
            .background(.primary.opacity(0.05), in: .rect(cornerRadius: 10))
            .padding(10)

            ScrollViewReader { proxy in
                List(filtered) { item in
                    Button {
                        onPick(item)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            if showsTypes, let t = item.type {
                                Circle().fill(PokeType(key: t).color).frame(width: 9, height: 9)
                            }
                            Text(item.t)
                            Spacer()
                            if item.v == selected {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .id(item.v)
                }
                .listStyle(.plain)
                .onAppear { if let selected { proxy.scrollTo(selected, anchor: .center) } }
            }
        }
        .frame(width: 300, height: 380)
        .onAppear { focused = true }
    }
}

/// A row that opens a SearchPicker.
struct PickerRow: View {
    let label: String
    let value: String
    var symbol: String? = nil
    var tint: Color = .accentColor
    let items: [ListItem]
    let selected: Int?
    var showsTypes = false
    var disabled = false
    let onPick: (ListItem) -> Void
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(tint).frame(width: 16)
                }
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(value).fontWeight(.medium).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
            }
            .font(.system(size: 13, design: .rounded))
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(.primary.opacity(open ? 0.08 : 0.04), in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .popover(isPresented: $open, arrowEdge: .leading) {
            SearchPicker(title: label, items: items, selected: selected, showsTypes: showsTypes, onPick: onPick)
        }
    }
}

/// Hexagonal stat chart with animated fill: base stats (soft) under actual stats (vivid).
struct StatRadar: View {
    let values: [Int]
    let base: [Int]
    var tint: Color
    var up: Int = -1
    var down: Int = -1
    @State private var progress: CGFloat = 0

    // Display order around the hexagon: HP, Atk, Def, Spe, SpD, SpA (like the games)
    private let order = [0, 1, 2, 5, 4, 3]

    var body: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2 - 26
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            let maxV = max(10, Double(values.max() ?? 1) * 1.15)
            let maxB = 255
            ZStack {
                ForEach(1...4, id: \.self) { ring in
                    polygon(c: c, r: r * CGFloat(ring) / 4, ratios: Array(repeating: 1, count: 6))
                        .stroke(.primary.opacity(ring == 4 ? 0.14 : 0.06), lineWidth: 1)
                }
                polygon(c: c, r: r, ratios: order.map { CGFloat(base[$0]) / CGFloat(maxB) * progress })
                    .fill(tint.opacity(0.16))
                polygon(c: c, r: r, ratios: order.map { min(1, CGFloat(Double(values[$0]) / maxV)) * progress })
                    .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.3).opacity(0.65), tint.opacity(0.45)], startPoint: .top, endPoint: .bottom))
                polygon(c: c, r: r, ratios: order.map { min(1, CGFloat(Double(values[$0]) / maxV)) * progress })
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                ForEach(0..<6, id: \.self) { i in
                    let idx = order[i]
                    let p = point(c: c, r: r + 16, i: i)
                    VStack(spacing: 0) {
                        HStack(spacing: 1) {
                            Text(Theme.statShort[idx])
                            if idx == up { Image(systemName: "arrowtriangle.up.fill").font(.system(size: 6)).foregroundStyle(.red) }
                            if idx == down { Image(systemName: "arrowtriangle.down.fill").font(.system(size: 6)).foregroundStyle(.blue) }
                        }
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        Text("\(values[idx])")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                    .position(p)
                }
            }
        }
        .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) { progress = 1 } }
        .animation(Theme.spring, value: values)
    }

    private func point(c: CGPoint, r: CGFloat, i: Int) -> CGPoint {
        let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 3
        return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
    }

    private func polygon(c: CGPoint, r: CGFloat, ratios: [CGFloat]) -> Path {
        Path { p in
            for i in 0..<6 {
                let pt = point(c: c, r: r * max(0.02, ratios[i]), i: i)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
        }
    }
}

/// Floating sparkles for shiny Pokémon.
struct SparkleField: View {
    var color: Color = .yellow
    var count = 14

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    let seed = Double(i) * 12.9898
                    let x = (sin(seed) * 0.5 + 0.5) * size.width
                    let speed = 0.25 + (cos(seed * 1.7) * 0.5 + 0.5) * 0.35
                    let phase = (t * speed + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
                    let y = size.height * (1 - phase)
                    let s = 4 + 7 * (sin(seed * 3) * 0.5 + 0.5)
                    let alpha = sin(phase * .pi)
                    var ctx2 = g
                    ctx2.opacity = alpha
                    ctx2.translateBy(x: x + sin(t * 1.3 + seed) * 8, y: y)
                    ctx2.rotate(by: .radians(t + seed))
                    let star = Path { p in
                        p.move(to: CGPoint(x: 0, y: -s))
                        p.addQuadCurve(to: CGPoint(x: s, y: 0), control: .zero)
                        p.addQuadCurve(to: CGPoint(x: 0, y: s), control: .zero)
                        p.addQuadCurve(to: CGPoint(x: -s, y: 0), control: .zero)
                        p.addQuadCurve(to: CGPoint(x: 0, y: -s), control: .zero)
                    }
                    ctx2.fill(star, with: .color(i % 3 == 0 ? .white : color))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Small labelled slider with value readout.
struct ValueSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var tint: Color = .accentColor
    var onCommit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Slider(value: $value, in: range, step: step) { editing in
                if !editing { onCommit() }
            }
            .tint(tint)
            Text("\(Int(value))")
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .frame(width: 30, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }
}

extension View {
    func sectionHeader() -> some View {
        self.font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
    }
}
