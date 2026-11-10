import SwiftUI
import AppKit

/// What to draw for a Pokémon.
struct SpriteKey: Hashable, Sendable {
    var species: Int
    var formKey: String
    var shiny: Bool
    var female: Bool
    var egg: Bool
}

enum SpriteSettings {
    static let key = "sprites.style"
    enum Mode: String, CaseIterable, Identifiable {
        case threeD = "3d", twoD = "2d"
        var id: String { rawValue }
        var title: String { self == .threeD ? "3D · Pokémon HOME" : "2D · pixel art" }
        var detail: String {
            self == .threeD
                ? "Render 3D di Pokémon HOME nei box e artwork ufficiale nei dettagli."
                : "Sprite in pixel art classici, nitidi a qualsiasi dimensione."
        }
    }
}

enum SpriteStyle: String, Sendable {
    case pixel         // classic 2D sprites
    case home          // Pokémon HOME renders (box grid)
    case artwork       // official artwork (detail hero)
    case animated      // Showdown GIFs (hover / detail)
}

/// Sprites come from github.com/PokeAPI/sprites, downloaded on demand and cached on disk.
/// Forms are matched to PokeAPI's "pokemon" ids with a bundled map; anything missing falls back
/// to the base form, so a new species added to PokeAPI shows up without updating PkMac.
actor SpriteStore {
    static let shared = SpriteStore()

    private let base = URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/")!
    private let cacheDir: URL
    private var memory: [String: NSImage] = [:]
    private var misses: Set<String> = []
    private var inflight: [String: Task<NSImage?, Never>] = [:]
    private let forms: [Int: [(String, Int)]]
    private let session: URLSession

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = caches.appendingPathComponent("PkMac/Sprites", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        forms = SpriteStore.loadForms()
        let cfg = URLSessionConfiguration.default
        cfg.httpMaximumConnectionsPerHost = 8
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: cfg)
    }

    private static func loadForms() -> [Int: [(String, Int)]] {
        let override = AppPaths.support.appendingPathComponent("pokeapi-forms.json")
        let url = FileManager.default.fileExists(atPath: override.path) ? override : Bundle.main.url(forResource: "pokeapi-forms", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [[Any]]] else { return [:] }
        var out: [Int: [(String, Int)]] = [:]
        for (k, v) in raw {
            guard let sp = Int(k) else { continue }
            out[sp] = v.compactMap { pair in
                guard pair.count == 2, let s = pair[0] as? String, let id = pair[1] as? Int else { return nil }
                return (s, id)
            }
        }
        return out
    }

    /// PokeAPI "pokemon" id for a species + PKHeX English form name.
    func pokeAPIID(species: Int, formKey: String) -> Int {
        guard !formKey.isEmpty, let candidates = forms[species] else { return species }
        let want = Self.tokens(formKey)
        guard !want.isEmpty else { return species }
        var best: (score: Int, id: Int)? = nil
        for (suffix, id) in candidates {
            let have = Self.tokens(suffix)
            let score = want.intersection(have).count * 10 - abs(have.count - want.count)
            if want.intersection(have).isEmpty { continue }
            if best == nil || score > best!.score { best = (score, id) }
        }
        return best?.id ?? species
    }

    private static func tokens(_ s: String) -> Set<String> {
        var out: Set<String> = []
        for raw in s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            var t = String(raw)
            // "alolan" -> "alola", "galarian" -> "galar", "hisuian" -> "hisui", "paldean" -> "paldea"
            for (suffix, repl) in [("ian", ""), ("an", "a")] where t.hasSuffix(suffix) && t.count > 5 {
                let stem = String(t.dropLast(suffix.count)) + repl
                if ["alola", "galar", "hisui", "paldea", "kanto", "johto"].contains(stem) { t = stem; break }
            }
            if t == "gigantamax" { t = "gmax" }
            if ["form", "forme", "mode", "style", "the", "of", "pokemon"].contains(t) { continue }
            out.insert(t)
        }
        return out
    }

    private func candidates(_ key: SpriteKey, style: SpriteStyle, id: Int) -> [String] {
        let shiny = key.shiny ? "shiny/" : ""
        var list: [String] = []
        switch style {
        case .home:
            if key.female { list.append("pokemon/other/home/\(shiny)female/\(id).png") }
            list.append("pokemon/other/home/\(shiny)\(id).png")
            if id != key.species { list.append("pokemon/other/home/\(shiny)\(key.species).png") }
            list.append("pokemon/\(shiny)\(id).png")
        case .pixel:
            if key.female { list.append("pokemon/\(shiny)female/\(id).png") }
            list.append("pokemon/\(shiny)\(id).png")
            if id != key.species { list.append("pokemon/\(shiny)\(key.species).png") }
        case .artwork:
            list.append("pokemon/other/official-artwork/\(shiny)\(id).png")
            list.append("pokemon/other/home/\(shiny)\(id).png")
            if id != key.species { list.append("pokemon/other/official-artwork/\(shiny)\(key.species).png") }
        case .animated:
            if key.female { list.append("pokemon/other/showdown/\(shiny)female/\(id).gif") }
            list.append("pokemon/other/showdown/\(shiny)\(id).gif")
        }
        return list
    }

    func image(for key: SpriteKey, style: SpriteStyle) async -> NSImage? {
        if key.egg { return nil }
        let id = pokeAPIID(species: key.species, formKey: key.formKey)
        for path in candidates(key, style: style, id: id) {
            if style == .pixel {
                if let img = await load(path: path, thumbnail: nil, trim: true) { return img }
            } else if let img = await load(path: path, thumbnail: style == .home ? 220 : nil) { return img }
        }
        return nil
    }

    func item(_ key: String) async -> NSImage? {
        await load(path: "items/\(key).png", thumbnail: nil)
    }

    private func load(path: String, thumbnail: CGFloat?, trim: Bool = false) async -> NSImage? {
        let cacheKey = path + (thumbnail.map { "@\(Int($0))" } ?? "") + (trim ? "@trim" : "")
        if let img = memory[cacheKey] { return img }
        if misses.contains(path) { return nil }
        if let t = inflight[cacheKey] { return await t.value }

        let file = cacheDir.appendingPathComponent(cacheKey.replacingOccurrences(of: "/", with: "_"))
        let task = Task<NSImage?, Never> { [session, base] in
            if let data = try? Data(contentsOf: file), let img = NSImage(data: data) { return img }
            guard let result = try? await session.data(from: base.appendingPathComponent(path)),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200,
                  let img = NSImage(data: result.0) else { return nil }
            let data = result.0
            var stored = data
            if trim, let cut = img.trimmedTransparent(), let png = cut.pngData {
                try? png.write(to: file)
                return cut
            }
            if let side = thumbnail, !path.hasSuffix(".gif"), let thumb = img.resized(maxSide: side), let png = thumb.pngData {
                stored = png
                try? stored.write(to: file)
                return thumb
            }
            try? stored.write(to: file)
            return img
        }
        inflight[cacheKey] = task
        let result = await task.value
        inflight[cacheKey] = nil
        if let result { memory[cacheKey] = result } else { misses.insert(path) }
        return result
    }

    func clearCache() {
        memory.removeAll()
        misses.removeAll()
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func cacheSize() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

extension NSImage {
    func resized(maxSide: CGFloat) -> NSImage? {
        guard let rep = bestRepresentation(for: NSRect(origin: .zero, size: size), context: nil, hints: nil) else { return nil }
        let w = CGFloat(rep.pixelsWide > 0 ? rep.pixelsWide : Int(size.width))
        let h = CGFloat(rep.pixelsHigh > 0 ? rep.pixelsHigh : Int(size.height))
        let scale = min(1, maxSide / max(w, h))
        let target = NSSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: target)
        out.addRepresentation(bitmap)
        return out
    }

    /// Crops fully transparent borders (classic sprites have lots of empty padding).
    func trimmedTransparent() -> NSImage? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil),
              let rep = Optional(NSBitmapImageRep(cgImage: cg)) else { return nil }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.02 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // Keep it square-ish with a 1px margin so sprites keep their proportions in square cells.
        let cw = maxX - minX + 1, ch = maxY - minY + 1
        let side = max(cw, ch) + 2
        let ox = minX - (side - cw) / 2, oy = minY - (side - ch) / 2
        guard let cropped = cg.cropping(to: CGRect(x: max(0, ox), y: max(0, oy), width: min(side, w - max(0, ox)), height: min(side, h - max(0, oy)))) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }

    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - Views

struct PokemonSprite: View {
    let key: SpriteKey?
    var style: SpriteStyle = .home
    var tint: Color = .gray

    @State private var image: NSImage?
    @State private var loadedKey: String?
    @AppStorage(SpriteSettings.key) private var mode = SpriteSettings.Mode.threeD.rawValue

    private var effective: SpriteStyle {
        mode == SpriteSettings.Mode.twoD.rawValue && style != .animated ? .pixel : style
    }
    private var taskID: String { key.map { "\($0.species)-\($0.formKey)-\($0.shiny)-\($0.female)-\(effective.rawValue)" } ?? "" }

    var body: some View {
        ZStack {
            if key?.egg == true {
                EggView(tint: tint)
            } else if let image {
                if effective == .animated {
                    AnimatedImage(image: image)
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(effective == .pixel ? .none : .high)
                        .scaledToFit()
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            } else if key != nil {
                OrbGlyph()
                    .foregroundStyle(tint.opacity(0.35))
                    .padding(8)
                    .modifier(Shimmer())
            }
        }
        .task(id: taskID) {
            guard let key, loadedKey != taskID else { return }
            let id = taskID
            let img = await SpriteStore.shared.image(for: key, style: effective)
            withAnimation(.easeOut(duration: 0.25)) {
                image = img
                loadedKey = id
            }
        }
    }
}

struct ItemIcon: View {
    let key: String?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
            } else {
                Color.clear
            }
        }
        .task(id: key) {
            guard let key else { image = nil; return }
            image = await SpriteStore.shared.item(key)
        }
    }
}

/// NSImageView animates GIFs natively.
struct AnimatedImage: NSViewRepresentable {
    let image: NSImage
    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.animates = true
        v.imageScaling = .scaleProportionallyUpOrDown
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }
    func updateNSView(_ v: NSImageView, context: Context) {
        if v.image !== image { v.image = image }
    }
}

struct EggView: View {
    var tint: Color
    var body: some View {
        Ellipse()
            .fill(LinearGradient(colors: [.white, Color(hex: 0xF4EBD0)], startPoint: .top, endPoint: .bottom))
            .overlay(
                ZStack {
                    Circle().fill(tint.opacity(0.55)).frame(width: 9).offset(x: -6, y: -4)
                    Circle().fill(tint.opacity(0.45)).frame(width: 6).offset(x: 7, y: 5)
                    Circle().fill(tint.opacity(0.4)).frame(width: 5).offset(x: 2, y: -10)
                }
            )
            .aspectRatio(0.78, contentMode: .fit)
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            .padding(10)
    }
}

/// Neutral placeholder glyph: a ring with a small spark.
struct OrbGlyph: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                Circle().stroke(lineWidth: s * 0.07)
                Spark().frame(width: s * 0.34, height: s * 0.34)
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .opacity(0.55 + 0.45 * Double(sin(phase)))
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { phase = .pi / 2 }
            }
    }
}
