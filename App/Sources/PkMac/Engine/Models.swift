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

    var label: String { isParty ? "Squadra · \(slot + 1)" : "Box \((box ?? 0) + 1) · \(slot + 1)" }
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
    var ot: String
    var maxOtLength: Int
    var gender: Int
    var tid: UInt32
    var sid: UInt32
    var money: UInt32
    var maxMoney: Int
    var hours: Int
    var minutes: Int
    var seconds: Int
    var language: Int
    var game: String
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
