import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var float = false
    @State private var appear = false

    var body: some View {
        GeometryReader { g in
            content(logo: min(330, max(150, g.size.height * 0.3)))
                .frame(width: g.size.width, height: g.size.height)
        }
        .overlay(alignment: .topTrailing) {
            LanguageMenu().padding(18)
        }
        .onAppear {
            float = true
            withAnimation(.easeOut(duration: 0.8).delay(0.1)) { appear = true }
        }
    }

    private func content(logo: CGFloat) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 54)

            AnimatedLogo(width: logo)
                .scaleEffect(appear ? 1 : 0.9)
                .opacity(appear ? 1 : 0)

            VStack(spacing: 8) {
                Text(Platform.isMac ? L("L'editor di salvataggi Pokémon, nato per il Mac.") : L("L'editor di salvataggi Pokémon, ora anche su iPhone e iPad."))
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 12)

            PKGlassContainer(spacing: 14) {
                HStack(spacing: 14) {
                    Button {
                        model.openPanel()
                    } label: {
                        Label(L("Apri salvataggio"), systemImage: "folder.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.pkGlassProminent)
                    .keyboardShortcut("o")
                    .disabled(model.engineState != .ready)

                    SettingsButton {
                        Label(L("Impostazioni"), systemImage: "gearshape.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.pkGlass)
                }
            }

            Text(L("oppure trascina qui main, .sav, .dsv, .dat, .gci, .bin, o uno zip di salvataggio o di backup di Azurii"))
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(.tertiary)

            if !model.recentFiles.isEmpty {
                RecentFilesBox(paths: model.recentFiles)
                    .frame(maxWidth: 520)
                    .layoutPriority(-1)
                    .opacity(appear ? 1 : 0)
            }

            Spacer(minLength: 10)
            EngineStatusLine()
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 40)
    }
}

/// Recent saves in their own scrolling box: the rest of the welcome screen stays in view at any window size.
private struct RecentFilesBox: View {
    let paths: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Recenti")).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 10)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(paths, id: \.self) { path in
                        RecentRow(path: path)
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 6)
            }
            .scrollIndicators(.automatic)
        }
        // Up to about four rows; smaller when the window is short, never taller than its content.
        .frame(minHeight: 70, maxHeight: min(CGFloat(paths.count) * 54 + 40, 260))
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.08)))
    }
}

private struct RecentRow: View {
    @Environment(AppModel.self) private var model
    let path: String
    @State private var hover = false

    var body: some View {
        Button {
            Task { await model.open(URL(fileURLWithPath: path)) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(Theme.brand)
                    .frame(width: 30, height: 30)
                    .background(.background.secondary, in: .rect(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    Text(URL(fileURLWithPath: path).lastPathComponent).font(.system(size: 13, weight: .semibold))
                    Text(URL(fileURLWithPath: path).deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(.tertiary).opacity(hover ? 1 : 0)
            }
            .padding(10)
            .contentShape(.rect)
            .pkGlassEffect(hover ? .interactive : .clear, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Theme.snappy, value: hover)
        .disabled(model.engineState != .ready)
    }
}

struct EngineStatusLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.engineState == .ready ? Color.green : (model.engineState == .starting ? .orange : .red))
                .frame(width: 7, height: 7)
            switch model.engineState {
            case .starting: Text(L("Avvio del motore PKHeX…"))
            case .failed(let m): Text(m).lineLimit(1)
            case .ready:
                if let v = model.hello?.versions {
                    Text(L("PKHeX.Core \(v.core) · Auto Legality \(v.alm) · motore \(v.engine)"))
                }
            }
        }
        .font(.system(size: 11.5, design: .rounded))
        .foregroundStyle(.secondary)
    }
}

/// The PkMac logo (bundle resource Logo.png), with the drawn orb as fallback.
struct AppLogo: View {
    private static let image: NSImage? = Bundle.main.url(forResource: "Logo", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    var body: some View {
        if let img = Self.image {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .shadow(color: Color(hex: 0xE23D4D).opacity(0.35), radius: 24, y: 12)
        } else {
            HeroOrb()
        }
    }
}

/// PkMac's emblem: a glossy gradient orb circled by a tilted ring, with a four-point spark.
struct HeroOrb: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0xFF7A8A), Color(hex: 0xA066FF), Color(hex: 0x3FB6FF)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: s * 0.72, height: s * 0.72)
                    .shadow(color: Color(hex: 0xA066FF).opacity(0.45), radius: s * 0.16, y: s * 0.08)
                Ellipse()
                    .fill(.white.opacity(0.55))
                    .frame(width: s * 0.28, height: s * 0.14)
                    .rotationEffect(.degrees(-30))
                    .offset(x: -s * 0.14, y: -s * 0.18)
                    .blur(radius: s * 0.015)
                Ellipse()
                    .stroke(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.25)], startPoint: .leading, endPoint: .trailing),
                            lineWidth: s * 0.035)
                    .frame(width: s * 0.98, height: s * 0.3)
                    .rotationEffect(.degrees(-18))
                Spark()
                    .fill(.white)
                    .frame(width: s * 0.2, height: s * 0.2)
                    .offset(x: s * 0.3, y: -s * 0.3)
                    .shadow(color: .white.opacity(0.8), radius: s * 0.04)
            }
            .frame(width: s, height: s)
        }
    }
}

/// Four-point star.
struct Spark: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        return Path { p in
            p.move(to: CGPoint(x: c.x, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: c.y), control: c)
            p.addQuadCurve(to: CGPoint(x: c.x, y: r.maxY), control: c)
            p.addQuadCurve(to: CGPoint(x: r.minX, y: c.y), control: c)
            p.addQuadCurve(to: CGPoint(x: c.x, y: r.minY), control: c)
        }
    }
}


/// Language switch on the first screen: Automatic (macOS language), Italiano, English.
struct LanguageMenu: View {
    private let options: [(id: String, title: String)] = [
        ("system", Platform.isMac ? L("Automatica (lingua di macOS)") : L("Automatica (lingua del sistema)")), ("it", "Italiano"), ("en", "English"),
    ]

    var body: some View {
        Menu {
            ForEach(options, id: \.id) { o in
                Button {
                    Lang.switchTo(o.id)
                } label: {
                    if Lang.choice == o.id { Label(o.title, systemImage: "checkmark") } else { Text(o.title) }
                }
            }
            if Platform.isMac {
                Divider()
                Text(L("Cambiando lingua PkMac si riavvia."))
            }
        } label: {
            Label(Lang.current == "it" ? "Italiano" : "English", systemImage: "globe")
                .font(.system(size: 13, weight: .medium, design: .rounded))
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .buttonStyle(.pkGlass)
        .help(L("Lingua dell'app"))
    }
}
