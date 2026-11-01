import Foundation
import Testing

/// El catálogo de la app (`App/Localizable.xcstrings`) tiene el español como idioma de origen y debe traer
/// el inglés de cada texto, con los mismos marcadores de formato. Si falla, ejecuta `scripts/sync-strings.sh`
/// y traduce los textos nuevos.
@Suite("Catálogo de textos")
struct StringCatalogTests {
    struct Catalog: Decodable {
        struct Unit: Decodable { let value: String }
        struct Localization: Decodable {
            let stringUnit: [String: String]?
            let variations: [String: [String: [String: [String: String]]]]?
        }
        struct Entry: Decodable {
            let shouldTranslate: Bool?
            let localizations: [String: Localization]?
        }
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    static let url = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "App/Localizable.xcstrings")

    static func specifiers(_ text: String) -> [String] {
        text.matches(of: /%(?:\d+\$)?(?:lld|ld|d|@|lf|f|%)/).map { String($0.output) }.sorted()
    }

    @Test("Todo texto traducible tiene su versión en inglés con los mismos marcadores")
    func englishIsComplete() throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: Self.url))
        #expect(catalog.sourceLanguage == "es")
        #expect(catalog.strings.count > 400)
        var missing: [String] = [], mismatched: [String] = []
        for (key, entry) in catalog.strings where entry.shouldTranslate != false {
            guard let en = entry.localizations?["en"] else { missing.append(key); continue }
            let values = en.stringUnit.map { [$0["value"] ?? ""] }
                ?? en.variations?["plural"]?.values.compactMap { $0["stringUnit"]?["value"] } ?? []
            if values.isEmpty { missing.append(key) }
            if values.contains(where: { Self.specifiers($0) != Self.specifiers(key) }) { mismatched.append(key) }
        }
        #expect(missing.isEmpty, "Sin inglés: \(missing.sorted())")
        #expect(mismatched.isEmpty, "Marcadores distintos: \(mismatched.sorted())")
    }
}
