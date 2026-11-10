import SwiftUI

/// Colors, radii and type styling shared by the whole app.
enum Theme {
    static let corner: CGFloat = 22
    static let cardCorner: CGFloat = 18
    static let cellCorner: CGFloat = 16
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)

    /// Signature brand gradient from the logo (cherry red → cosmic violet → indigo).
    static let brand = LinearGradient(
        colors: [Color(hex: 0xFF3B4E), Color(hex: 0xB04DFF), Color(hex: 0x5B5BFF)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static func stat(_ index: Int) -> Color {
        [Color(hex: 0x7BD389), Color(hex: 0xFF8A65), Color(hex: 0xFFC94D),
         Color(hex: 0x6FA8FF), Color(hex: 0xB08CFF), Color(hex: 0xFF7EB6)][max(0, min(5, index))]
    }

    static let statShort = ["PS", L("Att"), L("Dif"), "AtSp", "DiSp", L("Vel")]
    static let statLong = ["PS", L("Attacco"), L("Difesa"), L("Attacco Sp."), L("Difesa Sp."), L("Velocità")]
}

/// Pokémon type colors: soft, saturated pastels tuned to read well in light and dark mode.
enum PokeType: String, CaseIterable, Sendable {
    case normal, fire, water, grass, electric, ice, fighting, poison, ground,
         flying, psychic, bug, rock, ghost, dragon, dark, steel, fairy, stellar

    init(key: String?) {
        self = PokeType(rawValue: (key ?? "normal").lowercased()) ?? .normal
    }

    var color: Color {
        switch self {
        case .normal: Color(hex: 0xA8A77A)
        case .fire: Color(hex: 0xFF7A3D)
        case .water: Color(hex: 0x4A90FF)
        case .grass: Color(hex: 0x5CC85A)
        case .electric: Color(hex: 0xF7C531)
        case .ice: Color(hex: 0x6ED6E0)
        case .fighting: Color(hex: 0xD2453A)
        case .poison: Color(hex: 0xA552CC)
        case .ground: Color(hex: 0xD9A94E)
        case .flying: Color(hex: 0x8FA8FF)
        case .psychic: Color(hex: 0xFF5C93)
        case .bug: Color(hex: 0x9DBA2A)
        case .rock: Color(hex: 0xB89B4A)
        case .ghost: Color(hex: 0x7A63B8)
        case .dragon: Color(hex: 0x6A4CFF)
        case .dark: Color(hex: 0x6B5A52)
        case .steel: Color(hex: 0x8DB1C4)
        case .fairy: Color(hex: 0xF29CE0)
        case .stellar: Color(hex: 0x4FD1C5)
        }
    }

    /// A lighter companion color for gradients.
    var glow: Color { color.mix(with: .white, by: 0.35) }
    var deep: Color { color.mix(with: .black, by: 0.25) }

    var symbol: String {
        switch self {
        case .normal: "circle.circle"
        case .fire: "flame.fill"
        case .water: "drop.fill"
        case .grass: "leaf.fill"
        case .electric: "bolt.fill"
        case .ice: "snowflake"
        case .fighting: "figure.boxing"
        case .poison: "testtube.2"
        case .ground: "mountain.2.fill"
        case .flying: "wind"
        case .psychic: "eye.fill"
        case .bug: "ladybug.fill"
        case .rock: "circle.hexagongrid.fill"
        case .ghost: "moon.haze.fill"
        case .dragon: "lizard.fill"
        case .dark: "moon.fill"
        case .steel: "shield.lefthalf.filled"
        case .fairy: "sparkles"
        case .stellar: "star.circle.fill"
        }
    }

    var italian: String {
        switch self {
        case .normal: L("Normale")
        case .fire: L("Fuoco")
        case .water: L("Acqua")
        case .grass: L("Erba")
        case .electric: L("Elettro")
        case .ice: L("Ghiaccio")
        case .fighting: L("Lotta")
        case .poison: L("Veleno")
        case .ground: L("Terra")
        case .flying: L("Volante")
        case .psychic: L("Psico")
        case .bug: L("Coleottero")
        case .rock: L("Roccia")
        case .ghost: "Spettro"
        case .dragon: L("Drago")
        case .dark: L("Buio")
        case .steel: L("Acciaio")
        case .fairy: L("Folletto")
        case .stellar: L("Astrale")
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

// MARK: - Reusable styling

struct TypePill: View {
    let type: PokeType
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: type.symbol)
                .font(.system(size: compact ? 9 : 11, weight: .bold))
            if !compact {
                Text(type.italian)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 6 : 9)
        .padding(.vertical, compact ? 4 : 5)
        .background(
            Capsule().fill(LinearGradient(colors: [type.glow, type.color], startPoint: .top, endPoint: .bottom))
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        .shadow(color: type.color.opacity(0.35), radius: 4, y: 2)
        .help(type.italian)
    }
}

struct Card<Content: View>: View {
    var title: String?
    var symbol: String?
    var tint: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 7) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary.opacity(0.55), in: .rect(cornerRadius: Theme.cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct StatusBadge: View {
    enum Kind { case ok, warn, bad, info }
    let kind: Kind
    let text: String

    private var color: Color {
        switch kind {
        case .ok: .green
        case .warn: .orange
        case .bad: .red
        case .info: .blue
        }
    }
    private var symbol: String {
        switch kind {
        case .ok: "checkmark.seal.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .bad: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }
}

extension View {
    /// Soft hover lift used on interactive tiles.
    func hoverLift(_ hovering: Bool) -> some View {
        self.scaleEffect(hovering ? 1.04 : 1)
            .animation(Theme.snappy, value: hovering)
    }
}

/// Diagnostic switches (environment variables) used to isolate layout problems.
enum Diag {
    static let env = ProcessInfo.processInfo.environment
    static func off(_ name: String) -> Bool { env["PKMAC_NO_\(name)"] == "1" }
}
