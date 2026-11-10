import Foundation

struct SlotRef: Codable, Hashable, Sendable {
    var kind: String
    var box: Int?
    var slot: Int

    static func box(_ b: Int, _ s: Int) -> SlotRef { SlotRef(kind: "box", box: b, slot: s) }
    static func party(_ s: Int) -> SlotRef { SlotRef(kind: "party", box: nil, slot: s) }
    var isParty: Bool { kind == "party" }

    var json: [String: Any] {
        var d: [String: Any] = ["kind": kind, "slot": slot]
        if let box { d["box"] = box }
        return d
    }

    var label: String { isParty ? L("Squadra · \(slot + 1)") : L("Box \((box ?? 0) + 1) · \(slot + 1)") }
}

struct SlotSummary: Codable, Hashable, Identifiable, Sendable {
    var ref: SlotRef
    var empty: Bool
    var locked: Bool?
    var species: Int?
    var form: Int?
    var formKey: String?
    var speciesName: String?
    var nickname: String?
    var isNicknamed: Bool?
    var level: Int?
    var shiny: Bool?
    var gender: Int?
    var isEgg: Bool?
    var alpha: Bool?
    var gmax: Bool?
    var heldItem: Int?
    var heldItemName: String?
    var heldItemKey: String?
    var types: [String]?
    var ball: Int?
    var ballKey: String?
    var legal: Bool?

    var id: SlotRef { ref }
    var primaryType: String { types?.first ?? "normal" }
    var displayName: String { nickname ?? speciesName ?? "" }
    var sprite: SpriteKey? {
        guard !empty, let species else { return nil }
        return SpriteKey(species: species, formKey: formKey ?? "", shiny: shiny ?? false, female: gender == 1, egg: isEgg ?? false)
    }
}

struct BoxData: Codable, Sendable {
    var box: Int
    var name: String
    var slots: [SlotSummary]
}

struct BoxListItem: Codable, Hashable, Identifiable, Sendable {
    var box: Int
    var name: String
    var count: Int
    var shiny: Int
    var id: Int { box }
}

struct ContainerInfo: Codable, Hashable, Sendable {
    var kind: String          // "save" | "backup"
    var entry: String
    var titleId: String?
    var title: String?
    var zipName: String
    var isBackup: Bool { kind == "backup" }
}

struct ZipSave: Codable, Hashable, Identifiable, Sendable {
    var entry: String
    var titleId: String
    var game: String
    var size: Int
    var id: String { entry }
}

struct OpenChoice: Codable, Sendable {
    var needsChoice: Bool
    var path: String
    var saves: [ZipSave]
}

struct SaveInfo: Codable, Sendable {
    var path: String?
    var fileName: String?
    var container: ContainerInfo?
    var game: String
    var version: Int
    var versionKey: String
    var generation: Int
    var context: String
    var ot: String
    var gender: Int
    var tid: UInt32
    var sid: UInt32
    var playTime: String
    var money: UInt32
    var hasBox: Bool
    var hasParty: Bool
    var boxCount: Int
    var boxSlotCount: Int
    var partyCount: Int
    var boxNames: [String]
    var canRenameBoxes: Bool
    var checksumValid: Bool
    var checksumInfo: String
    var dirty: Bool
    var undo: String?
    var redo: String?
    var liveHex: Bool
    var liveHexSwitch: Bool
    var homeCompatible: Bool
}

struct MoveSlot: Codable, Hashable, Sendable {
    var id: Int
    var name: String?
    var type: String?
    var pp: Int
    var ppUps: Int
}

struct AbilityOption: Codable, Hashable, Identifiable, Sendable {
    var index: Int
    var id: Int
    var name: String
    var hidden: Bool
}

struct LegalityInfo: Codable, Hashable, Sendable {
    var valid: Bool
    var report: String
    var verbose: String
    var problems: [String]
}

struct PokemonDetail: Codable, Sendable {
    var summary: SlotSummary
    var format: Int
    var generation: Int
    var pid: String
    var encryptionConstant: String
    var nature: Int
    var natureName: String
    var statNature: Int
    var natureUp: Int
    var natureDown: Int
    var hasNatures: Bool
    var ability: Int
    var abilityName: String?
    var abilityNumber: Int
    var abilities: [AbilityOption]
    var moves: [MoveSlot]
    var ivs: [Int]
    var evs: [Int]
    var stats: [Int]
    var baseStats: [Int]
    var maxIV: Int
    var maxEV: Int
    var evTotalMax: Int
    var ot: String
    var otGender: Int
    var tid: UInt32
    var sid: UInt32
    var ballName: String
    var metLocation: String
    var metLevel: Int
    var version: Int
    var versionName: String
    var language: Int
    var origin: OriginData?
    var friendship: Int
    var exp: UInt32
    var teraType: String?
    var teraTypeIndex: Int?
    var pokerus: Bool
    var legality: LegalityInfo
    var showdown: String
    var fileName: String
    var canEdit: Bool
    var genderRatio: Int
}

struct ListItem: Codable, Hashable, Identifiable, Sendable {
    var v: Int
    var t: String
    var key: String?
    var type: String?
    var id: Int { v }
}

struct DataLists: Codable, Sendable {
    var language: String
    var species: [ListItem]
    var moves: [ListItem]
    var items: [ListItem]
    var natures: [ListItem]
    var balls: [ListItem]
    var languages: [ListItem]
    var types: [ListItem]

    func name(_ list: KeyPath<DataLists, [ListItem]>, _ v: Int) -> String {
        self[keyPath: list].first { $0.v == v }?.t ?? "—"
    }
}

struct SpeciesInfo: Codable, Sendable {
    var species: Int
    var form: Int
    var name: String
    var forms: [String]
    var types: [String]
    var baseStats: [Int]
    var abilities: [AbilityOption]
    var genderRatio: Int
    var inGame: Bool
}

struct Overview: Codable, Sendable {
    struct TypeCount: Codable, Hashable, Sendable { var type: String; var count: Int }
    var total: Int
    var shiny: Int
    var illegal: Int
    var eggs: Int
    var uniqueSpecies: Int
    var maxSpecies: Int
    var capacity: Int
    var types: [TypeCount]
    var levels: [Int]
}

struct SaveResult: Codable, Sendable {
    var path: String
    var backup: String?
    var steps: [String]
    var sha256: String
}

struct ChecksumStatus: Codable, Sendable {
    var loaded: Bool
    var loadedInfo: String
    var export: Bool
    var exportInfo: String
}

struct BackupItem: Codable, Hashable, Identifiable, Sendable {
    var path: String
    var date: String
    var size: Int
    var reason: String
    var id: String { path }
    var dateValue: Date { ISO8601DateFormatter.flexible.date(from: date) ?? .distantPast }
}

extension ISO8601DateFormatter {
    static let flexible: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

struct Versions: Codable, Sendable {
    var engine: String
    var core: String
    var alm: String
}

struct PluginInfo: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var source: String
}

struct Hello: Codable, Sendable {
    var versions: Versions
    var plugins: [PluginInfo]
}

struct ImportResult: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var status: String
    var legal: Bool?
    var ref: SlotRef?
    var lines: [String]?
    var id: String { "\(name)-\(ref?.slot ?? -1)-\(ref?.box ?? -1)-\(status)" }
}

struct LegalizeResult: Codable, Sendable {
    var before: Bool
    var after: Bool
    var applied: Bool
    var detail: PokemonDetail
}

struct CreateResult: Codable, Sendable {
    var status: String
    var legal: Bool
    var detail: PokemonDetail
}

struct LivingDexResult: Codable, Sendable {
    var generated: Int
    var placed: Int
    var skipped: Int
}

struct SortOption: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var group: String
}

struct SpecialFinding: Codable, Hashable, Identifiable, Sendable {
    var kind: String
    var label: String
    var hint: String
    var pokemon: SlotSummary
    var id: SlotRef { pokemon.ref }
}

struct SpecialReport: Codable, Sendable {
    struct Totals: Codable, Sendable { var dunsparce: Int; var tandemaus: Int; var wurmple: Int }
    var found: [SpecialFinding]
    var totals: Totals
}

struct NamerOptions: Codable, Sendable {
    var current: String
    var regular: String
    var gameboy: String
    var namers: [String]
    var keywords: [String]
}

struct LiveStatus: Codable, Sendable {
    var connected: Bool
    var game: String
    var gameVersion: String
    var version: String?
}

struct HomeConnectResult: Codable, Sendable {
    var connected: Bool
    var boxes: Int
    var slots: Int
    var supportedVersion: String
}

struct HomeSlot: Codable, Hashable, Identifiable, Sendable {
    var ref: SlotRef
    var empty: Bool
    var pokemon: SlotSummary?
    var transferable: Bool?
    var tracker: String?
    var id: SlotRef { ref }
}

struct HomeBox: Codable, Sendable {
    var box: Int
    var slots: [HomeSlot]
}

struct HomeDumpResult: Codable, Sendable {
    var files: Int
    var dir: String
}

struct TrainerData: Codable, Sendable {
    struct Lang: Codable, Hashable, Sendable { var v: Int; var t: String }
    struct Badges: Codable, Hashable, Sendable { var value: Int; var count: Int }
    var ot: String
    var maxOtLength: Int
    var gender: Int
    var hasGender: Bool?
    var tid: UInt32
    var sid: UInt32
    var tidMax: UInt32?
    var sidMax: UInt32?
    var hasSid: Bool?
    var idFormat: String?
    var money: UInt32
    var maxMoney: Int
    var hours: Int
    var minutes: Int
    var seconds: Int
    var maxHours: Int?
    var language: Int
    var languages: [Lang]?
    var game: String
    var versionKey: String?
    var generation: Int?
    var seenCount: Int?
    var caughtCount: Int?
    var badges: Badges?
}

struct UndoResult: Codable, Sendable {
    var applied: String?
    var whole: Bool
    var ref: SlotRef?
    var undo: String?
    var redo: String?
}

struct EventsStatus: Codable, Sendable {
    var installed: Bool
    var files: Int
    var date: String?
}

struct SelfTestReport: Codable, Sendable {
    struct Check: Codable, Sendable { var name: String; var ok: Bool; var detail: String? }
    var ok: Bool
    var versions: Versions
    var checks: [Check]
}


// MARK: - Bag

struct BagItem: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var count: Int
    var name: String
    var key: String?
    var max: Int
}

struct AllowedItem: Codable, Hashable, Identifiable, Sendable {
    var v: Int
    var t: String
    var key: String?
    var id: Int { v }
}

struct BagPouch: Codable, Hashable, Identifiable, Sendable {
    var index: Int
    var type: String
    var name: String
    var symbol: String
    var capacity: Int
    var maxCount: Int
    var items: [BagItem]
    var allowed: [AllowedItem]
    var id: Int { index }
}

struct BagData: Codable, Sendable {
    var pouches: [BagPouch]
    var supported: Bool
}

// MARK: - Events

struct NamedFlag: Codable, Hashable, Identifiable, Sendable {
    var i: Int
    var name: String
    var category: String
    var id: Int { i }
}

struct NamedWork: Codable, Hashable, Identifiable, Sendable {
    struct Option: Codable, Hashable, Sendable { var v: Int; var t: String }
    var i: Int
    var name: String
    var category: String
    var options: [Option]
    var id: Int { i }
}

struct EventsData: Codable, Sendable {
    var supported: Bool
    var useBlocks: Bool?
    var message: String?
    var game: String?
    var flagCount: Int?
    var workCount: Int?
    var systemCount: Int?
    var workMax: Int?
    var flags: [Bool]?
    var work: [Int]?
    var system: [Bool]?
    var namedFlags: [NamedFlag]?
    var namedSystem: [NamedFlag]?
    var namedWork: [NamedWork]?
}

// MARK: - Pokédex

struct DexEntry: Codable, Hashable, Identifiable, Sendable {
    var species: Int
    var name: String
    var seen: Bool
    var caught: Bool
    var types: [String]
    var formKey: String
    var id: Int { species }
}

struct DexData: Codable, Sendable {
    var supported: Bool
    var seen: Int?
    var caught: Int?
    var total: Int?
    var entries: [DexEntry]
}

// MARK: - Mystery gifts

struct GiftCard: Codable, Hashable, Sendable {
    var slot: Int?
    var id: Int?
    var empty: Bool
    var type: String?
    var generation: Int?
    var cardId: Int?
    var title: String?
    var isEntity: Bool?
    var isItem: Bool?
    var species: Int?
    var speciesName: String?
    var form: Int?
    var formKey: String?
    var level: Int?
    var shiny: Bool?
    var egg: Bool?
    var heldItem: String?
    var item: String?
    var itemKey: String?
    var quantity: Int?
    var ot: String?
    var used: Bool?
    var canAlbum: Bool?
    var canReceive: Bool?

    var sprite: SpriteKey? {
        guard isEntity == true, let species, species > 0 else { return nil }
        return SpriteKey(species: species, formKey: formKey ?? "", shiny: shiny ?? false, female: false, egg: egg ?? false)
    }
    var displayTitle: String {
        let t = (title ?? "").trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { return t }
        return speciesName ?? item ?? L("Dono")
    }
}

struct AlbumEntry: Codable, Hashable, Sendable {
    var card: GiftCard
    var lines: [String]
}

struct GiftAlbum: Codable, Sendable {
    var supported: Bool
    var message: String?
    var capacity: Int?
    var lockCapsuleSlot: Int?
    var cards: [AlbumEntry]?
    var hasFlags: Bool?
    var flagMax: Int?
    var received: [Int]?
    var canToggleUsed: Bool?
}

struct GiftDb: Codable, Sendable {
    var total: Int
    var shown: Int
    var hasAlbum: Bool
    var items: [GiftCard]
}

struct GiftDetail: Codable, Sendable {
    var card: GiftCard
    var lines: [String]
}

// MARK: - Blocks & inspector

struct BlockRow: Codable, Hashable, Identifiable, Sendable {
    var key: String
    var index: Int
    var name: String
    var named: Bool
    var type: String
    var size: Int
    var value: JSONScalar?
    var editable: Bool
    var hasObject: Bool
    var id: String { key }
}

struct BlocksData: Codable, Sendable {
    var supported: Bool
    var total: Int?
    var blocks: [BlockRow]
}

/// A JSON value that is a bool, number or string.
enum JSONScalar: Codable, Hashable, Sendable {
    case bool(Bool), string(String), number(Double), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else { self = .string(try c.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let b): try c.encode(b)
        case .string(let s): try c.encode(s)
        case .number(let d): try c.encode(d)
        case .null: try c.encodeNil()
        }
    }

    var text: String {
        switch self {
        case .bool(let b): b ? "true" : "false"
        case .string(let s): s
        case .number(let d): d == d.rounded() ? String(Int64(d)) : String(d)
        case .null: ""
        }
    }
    var bool: Bool { if case .bool(let b) = self { return b }; return text == "true" || text == "1" }
}

struct InspectProp: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var kind: String
    var type: String
    var value: JSONScalar?
    var editable: Bool
    var min: String?
    var max: String?
    var options: [String]?
    var id: String { name }
}

struct InspectData: Codable, Sendable {
    var type: String
    var props: [InspectProp]
}

struct InspectSetResult: Codable, Sendable {
    var ok: Bool
    var props: [InspectProp]
}

// MARK: - Ribbons

struct RibbonRow: Codable, Hashable, Identifiable, Sendable {
    var prop: String
    var name: String
    var mark: Bool
    var count: Bool
    var value: Int
    var max: Int
    var id: String { prop }
}

struct RibbonsData: Codable, Sendable {
    var ribbons: [RibbonRow]
    var affixed: Int?
    var ribbonsValid: Bool
    var owned: Int
}

struct RibbonsSetResult: Codable, Sendable {
    var ribbons: RibbonsData
}

// MARK: - Transfer

struct TransferCheck: Codable, Sendable {
    var ok: Bool
    var problem: String?
    var format: String?
}

/// Drag payload: which open save a slot belongs to.
struct SlotDrag: Codable, Hashable, Sendable {
    var save: String
    var ref: SlotRef
}


struct OriginData: Codable, Hashable, Sendable {
    var ball: Int
    var version: Int
    var metLocation: Int
    var metLevel: Int
    var metDate: String?
    var eggLocation: Int
    var eggDate: String?
    var wasEgg: Bool
    var isEgg: Bool
    var fateful: Bool
    var hasFateful: Bool
    var hasDates: Bool
    var hasEgg: Bool
    var hasVersion: Bool
    var hasMet: Bool
    var otGender: Int
    var hasOtGender: Bool
    var tid: UInt32
    var sid: UInt32
    var hasSid: Bool
    var tidMax: Int
    var sidMax: Int
    var language: Int
    var hasHandler: Bool
    var htName: String
    var htGender: Int
    var currentHandler: Int
    var pid: String
    var ec: String
    var hasEc: Bool
    var maxOt: Int
}

struct OriginLists: Codable, Sendable {
    var games: [ListItem]
    var locations: [ListItem]
}
