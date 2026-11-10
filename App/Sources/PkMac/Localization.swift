import Foundation
import AppKit

/// A user-facing text with its interpolated values kept apart, so the template can be translated
/// (`"Box \(n)"` → key `"Box %@"`).
struct Loc: ExpressibleByStringInterpolation, Sendable {
    var key: String
    var args: [String]

    init(stringLiteral value: String) { key = value; args = [] }

    init(stringInterpolation: Interpolation) {
        key = stringInterpolation.key
        args = stringInterpolation.args
    }

    struct Interpolation: StringInterpolationProtocol {
        var key = ""
        var args: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ literal: String) { key += literal.replacingOccurrences(of: "%", with: "%%") }
        mutating func appendInterpolation<T>(_ value: T) {
            key += "%@"
            args.append(String(describing: value))
        }
        mutating func appendInterpolation<T>(_ value: T?) {
            key += "%@"
            args.append(value.map { String(describing: $0) } ?? "")
        }
    }
}

/// Translates a user-facing text into the app language (Italian is the source language).
func L(_ text: Loc) -> String {
    let template = Lang.table[text.key] ?? text.key
    return Lang.fill(template, text.args)
}

/// Translates a text that is already a plain String (e.g. coming from the engine) when an exact
/// translation exists.
func L(raw: String) -> String { Lang.table[raw.replacingOccurrences(of: "%", with: "%%")].map { Lang.fill($0, []) } ?? raw }

enum Lang {
    static let key = "pkmac.language"   // "system" | "it" | "en"

    static var choice: String {
        get { UserDefaults.standard.string(forKey: key) ?? "system" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Language actually used: Italian or English (any other system language falls back to English).
    static var current: String {
        switch choice {
        case "it", "en": return choice
        default:
            let pref = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return pref.hasPrefix("it") ? "it" : "en"
        }
    }

    nonisolated(unsafe) static var table: [String: String] = load()

    static func load() -> [String: String] {
        guard current != "it",
              let url = Bundle.main.url(forResource: current, withExtension: "json", subdirectory: "Lang") ?? Bundle.main.url(forResource: current, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    /// Replaces `%@` (in order) or `%1$@` (by position) with the arguments, and `%%` with `%`.
    static func fill(_ template: String, _ args: [String]) -> String {
        var out = ""
        var i = template.startIndex
        var next = 0
        while i < template.endIndex {
            let c = template[i]
            if c == "%" {
                let j = template.index(after: i)
                if j < template.endIndex {
                    if template[j] == "%" { out.append("%"); i = template.index(after: j); continue }
                    if template[j] == "@" {
                        out += next < args.count ? args[next] : ""
                        next += 1
                        i = template.index(after: j); continue
                    }
                    // positional %N$@
                    var k = j; var digits = ""
                    while k < template.endIndex, template[k].isNumber { digits.append(template[k]); k = template.index(after: k) }
                    if !digits.isEmpty, k < template.endIndex, template[k] == "$" {
                        let at = template.index(after: k)
                        if at < template.endIndex, template[at] == "@", let n = Int(digits) {
                            out += n - 1 < args.count ? args[n - 1] : ""
                            i = template.index(after: at); continue
                        }
                    }
                }
            }
            out.append(c)
            i = template.index(after: i)
        }
        return out
    }

    /// Engine language code for Pokémon/move/item names and legality messages.
    static var engineCode: String { current }

    /// Saves the choice and relaunches the app so every screen uses the new language.
    @MainActor static func switchTo(_ choice: String) {
        guard choice != Lang.choice else { return }
        Lang.choice = choice
        let path = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 0.7; open -n \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
