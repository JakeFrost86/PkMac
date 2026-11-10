import SwiftUI
import AppKit

/// The PkMac logo without its tile: the sphere from the artwork (Sphere.png) with a Saturn-like ring
/// drawn live around it. A bright glint travels around the ring (passing behind and in front of the
/// sphere), the ring breathes with a soft glow and the stars twinkle.
struct AnimatedLogo: View {
    var width: CGFloat = 300
    var showText = true

    // Geometry in the coordinates of the original 1254 px artwork.
    private let box = CGRect(x: 150, y: 190, width: 960, height: 720)
    private let sphereCenter = CGPoint(x: 615, y: 548)
    private let sphereRadius: CGFloat = 321
    private let ringCenter = CGPoint(x: 627, y: 563)
    private let ringA: CGFloat = 462
    private let ringB: CGFloat = 150
    private let ringAngle: CGFloat = -15.65 * .pi / 180

    private static let sphere: NSImage? = Bundle.main.url(forResource: "Sphere", withExtension: "png").flatMap(NSImage.init(contentsOf:))

    var body: some View {
        let k = width / box.width
        VStack(spacing: width * 0.02) {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let float = sin(t * 1.1) * 6 * k
                ZStack {
                    ringLayer(t: t, k: k, front: false)
                    if let img = Self.sphere {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: sphereRadius * 2 * k, height: sphereRadius * 2 * k)
                            .position(p(sphereCenter, k))
                            .shadow(color: Color(hex: 0xFF2D3A).opacity(0.35), radius: 30 * k, y: 18 * k)
                    } else {
                        HeroOrb()
                            .frame(width: sphereRadius * 2 * k, height: sphereRadius * 2 * k)
                            .position(p(sphereCenter, k))
                    }
                    ringLayer(t: t, k: k, front: true)
                    sparkles(t: t, k: k)
                }
                .offset(y: float)
            }
            .frame(width: width, height: box.height * k)

            if showText {
                HStack(spacing: 0) {
                    Text("Pk").foregroundStyle(.primary)
                    Text("Mac").foregroundStyle(Color(hex: 0xFF2D3A))
                }
                .font(.system(size: width * 0.19, weight: .heavy, design: .rounded))
                .shadow(color: Color(hex: 0xFF2D3A).opacity(0.25), radius: 12)
            }
        }
    }

    // MARK: ring

    private func p(_ pt: CGPoint, _ k: CGFloat) -> CGPoint {
        CGPoint(x: (pt.x - box.minX) * k, y: (pt.y - box.minY) * k)
    }

    /// Point of the ring ellipse at parameter θ (θ in 0…π is the front half, nearer the viewer).
    private func ringPoint(_ theta: CGFloat, _ k: CGFloat) -> CGPoint {
        let x = ringA * cos(theta), y = ringB * sin(theta)
        let rx = x * cos(ringAngle) - y * sin(ringAngle)
        let ry = x * sin(ringAngle) + y * cos(ringAngle)
        return p(CGPoint(x: ringCenter.x + rx, y: ringCenter.y + ry), k)
    }

    private func arc(_ from: CGFloat, _ to: CGFloat, _ k: CGFloat) -> Path {
        Path { path in
            let steps = 64
            for i in 0...steps {
                let th = from + (to - from) * CGFloat(i) / CGFloat(steps)
                let pt = ringPoint(th, k)
                i == 0 ? path.move(to: pt) : path.addLine(to: pt)
            }
        }
    }

    @ViewBuilder
    private func ringLayer(t: Double, k: CGFloat, front: Bool) -> some View {
        let range: (CGFloat, CGFloat) = front ? (0, .pi) : (.pi, 2 * .pi)
        let breathe = 0.78 + 0.22 * sin(t * 2.2)
        let lw = 22 * k
        // Travelling glint, one lap every 3.2 s (goes behind the sphere, then in front of it).
        let head = CGFloat((t / 3.2).truncatingRemainder(dividingBy: 1)) * 2 * .pi
        let glintLen: CGFloat = 0.9
        Canvas { g, _ in
            let base = arc(range.0, range.1, k)
            var glow = g
            glow.addFilter(.blur(radius: 14 * k))
            glow.opacity = 0.9 * breathe
            glow.stroke(base, with: .color(Color(hex: 0xC9A6FF)), style: StrokeStyle(lineWidth: lw * 2.4, lineCap: .round))
            g.opacity = front ? 1 : 0.85
            g.stroke(base, with: .linearGradient(
                Gradient(colors: [.white, Color(hex: 0xEDE4FF), .white]),
                startPoint: ringPoint(.pi, k), endPoint: ringPoint(0, k)),
                style: StrokeStyle(lineWidth: lw, lineCap: .round))

            // Glint segments that fall inside this half.
            for shift in [0, 2 * CGFloat.pi, -2 * CGFloat.pi] {
                let a = head + shift - glintLen, b = head + shift
                let lo = max(a, range.0), hi = min(b, range.1)
                guard hi > lo else { continue }
                let seg = arc(lo, hi, k)
                var bloom = g
                bloom.opacity = 1
                bloom.addFilter(.blur(radius: 10 * k))
                bloom.stroke(seg, with: .color(Color(hex: 0xFF7AB6)), style: StrokeStyle(lineWidth: lw * 2.2, lineCap: .round))
                var core = g
                core.opacity = 1
                core.stroke(seg, with: .color(.white), style: StrokeStyle(lineWidth: lw * 1.15, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: stars

    private func sparkles(t: Double, k: CGFloat) -> some View {
        let stars: [(CGFloat, CGFloat, CGFloat, Double)] = [
            (928, 213, 70, 0), (1007, 300, 30, 1.3), (343, 853, 34, 2.1), (958, 815, 30, 0.7),
            (210, 345, 9, 1.7), (308, 222, 7, 0.4), (1034, 722, 9, 2.6), (190, 480, 6, 3.1),
        ]
        return ZStack {
            ForEach(Array(stars.enumerated()), id: \.offset) { _, s in
                let tw = 0.55 + 0.45 * sin(t * 2.4 + s.3)
                Group {
                    if s.2 > 20 {
                        Spark().fill(.white)
                    } else {
                        Circle().fill(.white)
                    }
                }
                .frame(width: s.2 * k * (0.8 + 0.2 * tw), height: s.2 * k * (0.8 + 0.2 * tw))
                .opacity(tw)
                .shadow(color: .white.opacity(0.8), radius: 6 * k)
                .position(p(CGPoint(x: s.0, y: s.1), k))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Alternate app icons

enum AppIconManager {
    static let key = "app.icon"
    static let defaultID = "pianeta"

    static let all: [(id: String, name: String)] = [
        ("pianeta", "Pianeta"), ("neon", "Neon"), ("classica", "Classica"), ("officina", "Officina"),
        ("neon-mini", "Neon compatta"), ("pixel", "Pixel"), ("floppy", "Floppy"), ("pianeta-mini", "Pianeta compatta"),
        ("apertura", "Apertura"), ("finder", "Finder"), ("matita", "Matita"), ("scritta", "Scritta"),
    ]

    static var current: String { UserDefaults.standard.string(forKey: key) ?? defaultID }

    static func image(_ id: String) -> NSImage? {
        Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "Icons").flatMap(NSImage.init(contentsOf:))
    }

    /// Dock icon right away, Finder icon of the app bundle too (the default removes the custom one).
    @MainActor
    static func apply(_ id: String, persist: Bool = true) {
        if persist { UserDefaults.standard.set(id, forKey: key) }
        let path = Bundle.main.bundlePath
        if id == defaultID {
            NSApp.applicationIconImage = nil
            NSWorkspace.shared.setIcon(nil, forFile: path, options: [])
        } else if let img = image(id) {
            NSApp.applicationIconImage = img
            NSWorkspace.shared.setIcon(img, forFile: path, options: [])
        }
    }
}
