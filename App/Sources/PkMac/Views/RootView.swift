import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
            AmbientBackground(type: model.save == nil ? nil : model.accentType)
                .ignoresSafeArea()

            switch model.engineState {
            case .failed(let msg) where model.save == nil:
                EngineFailedView(message: msg)
            default:
                if model.save == nil {
                    WelcomeView()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    MainView()
                        .transition(.opacity)
                }
            }

            if model.isDropTargeted {
                DropHint()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            VStack {
                Spacer()
                ToastStack(toasts: model.toasts)
            }
            .padding(.bottom, 22)
            .allowsHitTesting(false)

            if let busy = model.busy {
                BusyOverlay(message: busy, progress: model.progress)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(Theme.spring, value: model.save == nil)
        .animation(Theme.spring, value: model.busy)
        .onDrop(of: [.fileURL], isTargeted: $model.isDropTargeted) { providers in
            Task { @MainActor in
                let urls = await providers.loadURLs()
                await model.handleDrop(urls, onto: nil)
            }
            return true
        }
        .sheet(item: $model.zipChoice) { choice in
            ZipChoiceSheet(choice: choice)
        }
        .sheet(isPresented: $model.showSaveReport) {
            if let r = model.lastSave { SaveReportView(result: r) }
        }
    }
}

extension Array where Element == NSItemProvider {
    func loadURLs() async -> [URL] {
        var urls: [URL] = []
        for p in self where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await withCheckedContinuation({ (c: CheckedContinuation<URL?, Never>) in
                _ = p.loadObject(ofClass: URL.self) { url, _ in c.resume(returning: url) }
            }) {
                urls.append(url)
            }
        }
        return urls
    }
}

/// Slow-moving mesh gradient tinted by the selected Pokémon's type.
struct AmbientBackground: View {
    var type: PokeType?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let c = type?.color ?? Color(hex: 0xA066FF)
            let g = type?.glow ?? Color(hex: 0x3FB6FF)
            let w = Float(sin(t / 7) * 0.12)
            let v = Float(cos(t / 9) * 0.12)
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5 + w, 0], [1, 0],
                    [0, 0.5 - v], [0.5 + v, 0.5 + w], [1, 0.5 + v],
                    [0, 1], [0.5 - w, 1], [1, 1],
                ],
                colors: [
                    c.opacity(0.22), .clear, g.opacity(0.16),
                    .clear, c.opacity(0.10), .clear,
                    g.opacity(0.14), .clear, c.opacity(0.18),
                ]
            )
            .background(.background)
            .animation(.easeInOut(duration: 1.2), value: type)
        }
    }
}

struct ToastStack: View {
    let toasts: [Toast]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toasts) { t in
                HStack(spacing: 10) {
                    Image(systemName: symbol(t.kind))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color(t.kind))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.system(size: 13, weight: .semibold, design: .rounded))
                        if let m = t.message {
                            Text(m).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .frame(maxWidth: 460, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
            }
        }
    }

    private func symbol(_ k: Toast.Kind) -> String {
        switch k {
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }
    private func color(_ k: Toast.Kind) -> Color {
        switch k {
        case .success: .green
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}

struct BusyOverlay: View {
    let message: String
    let progress: ProgressInfo?
    @State private var spin = false

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.12)).ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle().stroke(.primary.opacity(0.08), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress.map { max(0.06, $0.fraction) } ?? 0.28)
                        .stroke(Theme.brand, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(progress == nil ? (spin ? 360 : 0) : -90))
                        .animation(progress == nil ? .linear(duration: 1).repeatForever(autoreverses: false) : Theme.spring, value: spin)
                    OrbGlyph()
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                }
                .frame(width: 64, height: 64)
                Text(message)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                if let p = progress, p.total > 0 {
                    Text("\(p.done) / \(p.total)")
                        .font(.system(size: 12, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
        }
        .onAppear { spin = true }
    }
}

struct DropHint: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(Theme.brand, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
            .background(RoundedRectangle(cornerRadius: 28).fill(.background.opacity(0.35)))
            .overlay(
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc.fill").font(.system(size: 42))
                        .foregroundStyle(Theme.brand)
                    Text(L("Rilascia per aprire")).font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(L("Salvataggi o file .pk")).foregroundStyle(.secondary)
                }
            )
            .padding(18)
    }
}

struct EngineFailedView: View {
    @Environment(AppModel.self) private var model
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
            Text(L("Il motore PKHeX non è partito")).font(.title2.bold())
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
            HStack {
                Button(L("Riprova")) { Task { await model.startEngine() } }
                    .buttonStyle(.glassProminent)
                Button(L("Usa il motore incluso")) {
                    EngineManager.resetToBundled()
                    Task { await model.startEngine() }
                }
                .buttonStyle(.glass)
            }
        }
        .padding(40)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

extension OpenChoice: Identifiable { var id: String { path } }

/// A full Azurii backup can hold several Pokémon saves: pick one.
struct ZipChoiceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let choice: OpenChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "doc.zipper")
                    .font(.system(size: 26))
                    .foregroundStyle(Color(hex: 0x3FB6FF))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Backup di Azurii")).font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(URL(fileURLWithPath: choice.path).lastPathComponent).font(.callout).foregroundStyle(.secondary)
                }
            }
            Text(L("Contiene \(choice.saves.count) salvataggi Pokémon. Scegli quello da aprire: quando salvi, PkMac aggiorna solo lui dentro lo zip."))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(choice.saves) { s in
                    Button {
                        dismiss()
                        Task { await model.open(URL(fileURLWithPath: choice.path), entry: s.entry) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "gamecontroller.fill").foregroundStyle(Theme.brand)
                                .frame(width: 34, height: 34)
                                .background(.primary.opacity(0.06), in: .rect(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.game).font(.system(size: 14, weight: .semibold, design: .rounded))
                                Text(L("Title ID \(s.titleId) · \(ByteCountFormatter.string(fromByteCount: Int64(s.size), countStyle: .file))"))
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(10)
                        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 14))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack { Spacer(); Button(L("Annulla")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24)
        .frame(width: 480)
    }
}
