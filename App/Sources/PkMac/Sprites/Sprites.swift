import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
import ImageIO
#endif

/// What to draw for a Pokémon.
struct SpriteKey: Hashable, Sendable {
    var species: Int
    var formKey: String
    var shiny: Bool
    var female: Bool
    var egg: Bool
    /// Form number (-1 = unknown) and form argument (Alcremie's sweet), for exact form sprites.
    var form: Int = -1
    var formArg: Int = 0
}

enum SpriteSettings {
    static let key = "sprites.style"
    enum Mode: String, CaseIterable, Identifiable {
        case threeD = "3d", twoD = "2d"
        var id: String { rawValue }
        var title: String { self == .threeD ? L("3D · Pokémon HOME") : L("2D · pixel art") }
        var detail: String {
            self == .threeD
                ? L("Render 3D di Pokémon HOME nei box e artwork ufficiale nei dettagli.")
                : L("Sprite in pixel art classici, nitidi a qualsiasi dimensione.")
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
    /// PKHeX's own sprites (github.com/kwsch/PKHeX), used when PokeAPI has no image for an item.
    private let pkhexBase = URL(string: "https://raw.githubusercontent.com/kwsch/PKHeX/master/PKHeX.Drawing.PokeSprite/Resources/img/")!
    private let cacheDir: URL
    private var memory: [String: NSImage] = [:]
    private var misses: Set<String> = []
    private var inflight: [String: Task<NSImage?, Never>] = [:]
    private let forms: [Int: [(String, Int)]]
    /// Cosmetic forms PokeAPI stores as "<species>-<slug>.png" (Vivillon patterns, Unown letters, Alcremie…).
    private let cosmetic: [Int: [String]]
    private let session: URLSession

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = caches.appendingPathComponent("PkMac/Sprites", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        forms = SpriteStore.loadForms()
        cosmetic = SpriteStore.loadCosmetic()
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

    private static func loadCosmetic() -> [Int: [String]] {
        guard let url = Bundle.main.url(forResource: "pokeapi-cosmetic", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        var out: [Int: [String]] = [:]
        for (k, v) in raw { if let sp = Int(k) { out[sp] = v } }
        return out
    }

    /// Alcremie's sweet (form argument), in PKHeX order.
    private static let alcremieSweets = ["strawberry", "berry", "love", "star", "clover", "flower", "ribbon"]

    /// PokeAPI file slug for a cosmetic form ("666-icy-snow"), matched on the full set of words.
    func cosmeticSlug(_ key: SpriteKey) -> String? {
        guard let slugs = cosmetic[key.species], !key.formKey.isEmpty else { return nil }
        var want: Set<String>
        switch key.formKey {
        case "!": want = ["exclamation"]
        case "?": want = ["question"]
        default: want = Self.tokens(key.formKey)
        }
        if key.species == 869 {
            let i = max(0, min(Self.alcremieSweets.count - 1, key.formArg))
            want.formUnion([Self.alcremieSweets[i], "sweet"])
        }
        guard !want.isEmpty else { return nil }
        return slugs.first { Self.tokens($0) == want }
    }

    /// PKHeX's own sprite name ("666-3", "869-0-4") for forms PokeAPI doesn't have.
    private static func pkhexName(_ key: SpriteKey) -> String? {
        guard key.form > 0 || key.species == 869 else { return nil }
        var n = "\(key.species)"
        if key.form > 0 { n += "-\(key.form)" }
        if key.species == 869 {
            if key.form <= 0 { n += "-0" }
            n += "-\(max(0, key.formArg))"
        }
        return n
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
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        for raw in folded.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
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
        // Form 0 names (e.g. Basculin "Red-Striped") must not be fuzzy-matched to another form's id.
        let id = key.form == 0 ? key.species : pokeAPIID(species: key.species, formKey: key.formKey)
        let shiny = key.shiny ? "shiny/" : ""
        // 1) Cosmetic form files on PokeAPI ("666-polar.png").
        if let slug = cosmeticSlug(key) {
            let paths: [String]
            switch style {
            case .home: paths = ["pokemon/other/home/\(shiny)\(key.species)-\(slug).png", "pokemon/\(shiny)\(key.species)-\(slug).png"]
            case .pixel: paths = ["pokemon/\(shiny)\(key.species)-\(slug).png"]
            case .artwork: paths = ["pokemon/other/official-artwork/\(shiny)\(key.species)-\(slug).png", "pokemon/other/home/\(shiny)\(key.species)-\(slug).png"]
            case .animated: paths = ["pokemon/other/showdown/\(shiny)\(key.species)-\(slug).gif"]
            }
            for path in paths {
                if let img = await loadStyled(path, style: style) { return img }
            }
        }
        // 2) Forms with their own PokeAPI id.
        let all = candidates(key, style: style, id: id)
        let idPaths = id != key.species ? all.filter { $0.contains("/\(id).") } : []
        for path in idPaths {
            if let img = await loadStyled(path, style: style) { return img }
        }
        // 3) PKHeX's own sprite for that exact form, before falling back to the base species.
        if style != .animated, let name = Self.pkhexName(key) {
            var paths: [String] = []
            if style == .artwork {
                if key.shiny { paths.append("Artwork Shiny Sprites/a_\(name)s.png") }
                paths.append("Artwork Pokemon Sprites/a_\(name).png")
            }
            if key.shiny { paths.append("Big Shiny Sprites/b_\(name)s.png") }
            paths.append("Big Pokemon Sprites/b_\(name).png")
            for path in paths {
                let art = path.hasPrefix("Artwork")
                if let img = await load(path: path, thumbnail: nil, trim: !art, root: pkhexBase) { return img }
            }
        }
        // 4) Base species.
        for path in all {
            if let img = await loadStyled(path, style: style) { return img }
        }
        return nil
    }

    private func loadStyled(_ path: String, style: SpriteStyle) async -> NSImage? {
        if style == .pixel { return await load(path: path, thumbnail: nil, trim: true) }
        return await load(path: path, thumbnail: style == .home ? 220 : nil)
    }

    func item(_ key: String) async -> NSImage? {
        await load(path: "items/\(key).png", thumbnail: nil)
    }

    /// Item sprite from PKHeX by item ID (today's numbering): big item, then artwork item; TMs and TRs share one image.
    func pkhexItem(_ id: Int) async -> NSImage? {
        guard id > 0 else { return nil }
        switch id {
        case 328...425, 618...620, 690...694, 737, 2160...2289:
            return await load(path: "Big Items/bitem_tm.png", thumbnail: nil, root: pkhexBase)
        case 1130...1229:
            return await load(path: "Big Items/bitem_tr.png", thumbnail: nil, root: pkhexBase)
        default:
            if let img = await load(path: "Big Items/bitem_\(id).png", thumbnail: nil, root: pkhexBase) { return img }
            return await load(path: "Artwork Items/aitem_\(id).png", thumbnail: 96, root: pkhexBase)
        }
    }

    /// Official gym badge (PokeAPI sprites/badges/N.png).
    func badge(_ id: Int) async -> NSImage? {
        await load(path: "badges/\(id).png", thumbnail: 96)
    }

    private func load(path: String, thumbnail: CGFloat?, trim: Bool = false, root: URL? = nil) async -> NSImage? {
        let base = root ?? self.base
        let prefix = root == nil ? "" : "pkhex/"
        let cacheKey = prefix + path.replacingOccurrences(of: " ", with: "-") + (thumbnail.map { "@\(Int($0))" } ?? "") + (trim ? "@trim" : "")
        if let img = memory[cacheKey] { return img }
        if misses.contains(prefix + path) { return nil }
        if let t = inflight[cacheKey] { return await t.value }

        let file = cacheDir.appendingPathComponent(cacheKey.replacingOccurrences(of: "/", with: "_"))
        let task = Task<NSImage?, Never> { [session, base] in
            if let data = try? Data(contentsOf: file), let img = decodeSprite(data) { return img }
            guard let result = try? await session.data(from: base.appendingPathComponent(path)),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200,
                  let img = decodeSprite(result.0) else { return nil }
            let data = result.0
            var stored = data
            if trim, let cut = img.trimmedTransparent(), let png = cut.pngBytes {
                try? png.write(to: file)
                return cut
            }
            if let side = thumbnail, !path.hasSuffix(".gif"), let thumb = img.resized(maxSide: side), let png = thumb.pngBytes {
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
        if let result { memory[cacheKey] = result } else { misses.insert(prefix + path) }
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

#if os(macOS)
/// Decodes a downloaded sprite (NSImage keeps every GIF frame, NSImageView animates them).
func decodeSprite(_ data: Data) -> NSImage? { NSImage(data: data) }

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

    /// PNG bytes on both platforms (UIImage already has a `pngData()` method).
    var pngBytes: Data? { pngData }
}
#else
/// Decodes a downloaded sprite. UIImage(data:) keeps only the first frame of a GIF, so animated GIFs
/// (Showdown sprites) are rebuilt as an animated UIImage that UIImageView plays on its own.
func decodeSprite(_ data: Data) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
    let count = CGImageSourceGetCount(source)
    guard count > 1 else { return UIImage(data: data) }
    var frames: [UIImage] = []
    var total: Double = 0
    for i in 0..<count {
        guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
        frames.append(UIImage(cgImage: cg))
        var delay = 0.1
        if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
           let gif = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
            let d = (gif[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                ?? (gif[kCGImagePropertyGIFDelayTime as String] as? Double) ?? 0.1
            delay = d < 0.02 ? 0.1 : d
        }
        total += delay
    }
    guard !frames.isEmpty else { return UIImage(data: data) }
    return UIImage.animatedImage(with: frames, duration: total)
}

extension UIImage {
    private var pixelSize: CGSize {
        if let cg = cgImage { return CGSize(width: cg.width, height: cg.height) }
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func resized(maxSide: CGFloat) -> UIImage? {
        let w = pixelSize.width, h = pixelSize.height
        guard w > 0, h > 0 else { return nil }
        let k = min(1, maxSide / max(w, h))
        let target = CGSize(width: max(1, (w * k).rounded()), height: max(1, (h * k).rounded()))
        // Plain Core Graphics: safe off the main thread (SpriteStore is an actor).
        guard let cg = cgImage,
              let ctx = CGContext(data: nil, width: Int(target.width), height: Int(target.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(origin: .zero, size: target))
        guard let out = ctx.makeImage() else { return nil }
        return UIImage(cgImage: out)
    }

    /// Crops fully transparent borders (classic sprites have lots of empty padding).
    func trimmedTransparent() -> UIImage? {
        guard let cg = cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        // Row 0 of the buffer is the top of the image, like NSBitmapImageRep.colorAt on the Mac.
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w where pixels[row + x * 4 + 3] > 5 {   // alpha > 0.02
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // Keep it square-ish with a 1px margin so sprites keep their proportions in square cells.
        let cw = maxX - minX + 1, ch = maxY - minY + 1
        let side = max(cw, ch) + 2
        let ox = minX - (side - cw) / 2, oy = minY - (side - ch) / 2
        guard let cropped = cg.cropping(to: CGRect(x: max(0, ox), y: max(0, oy), width: min(side, w - max(0, ox)), height: min(side, h - max(0, oy)))) else { return nil }
        return UIImage(cgImage: cropped)
    }

    /// PNG bytes on both platforms.
    var pngBytes: Data? { pngData() }
}
#endif

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
    private var taskID: String { key.map { "\($0.species)-\($0.form)-\($0.formArg)-\($0.formKey)-\($0.shiny)-\($0.female)-\(effective.rawValue)" } ?? "" }

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
    /// Item ID in today's numbering: when PokeAPI has no image, PKHeX's own sprite is used.
    var id: Int? = nil
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
            } else {
                Color.clear
            }
        }
        .task(id: "\(key ?? "")#\(id ?? 0)") {
            guard let key else {
                image = await SpriteStore.shared.pkhexItem(id ?? 0)
                return
            }
            if let img = await SpriteStore.shared.item(key) { image = img; return }
            if let id, let img = await SpriteStore.shared.pkhexItem(id) { image = img; return }
            // Fallbacks for names PokeAPI files differently (TMs/HMs/TRs, records…).
            let lower = key.lowercased()
            let fallback: String? =
                lower.hasPrefix("hm") ? "hm-normal" :
                (lower.hasPrefix("tm") || lower.hasPrefix("tr")) ? "tm-normal" :
                lower.contains("berry") ? "oran-berry" :
                lower.contains("ball") ? "poke-ball" :
                lower.contains("mail") ? "grass-mail" : nil
            if let fallback { image = await SpriteStore.shared.item(fallback) }
        }
    }
}

#if os(macOS)
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
#else
/// UIImageView plays the animated UIImage built by decodeSprite.
struct AnimatedImage: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.clipsToBounds = true
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        return v
    }
    func updateUIView(_ v: UIImageView, context: Context) {
        if v.image !== image { v.image = image }
    }
    /// Fill the space SwiftUI offers instead of the GIF's own pixel size.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        guard let w = proposal.width, let h = proposal.height, w.isFinite, h.isFinite else { return nil }
        return CGSize(width: w, height: h)
    }
}
#endif

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
