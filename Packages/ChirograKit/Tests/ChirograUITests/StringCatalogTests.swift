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

    /// Las etiquetas de los enums de las pantallas (`case x = "Con recibo"`) se traducen con `localizedTitle` en
    /// tiempo de ejecución y el compilador no las extrae: si falta una en el catálogo, sale en español con la app
    /// en inglés (pasó con «Con recibo» del filtro de Gastos).
    @Test("Las etiquetas de los enums de las pantallas están en el catálogo")
    func enumLabelsAreInCatalog() throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: Self.url))
        let sources = Self.url.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Packages/ChirograKit/Sources/ChirograUI")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        #expect(files.count > 50)
        var missing: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for enumMatch in source.matches(of: /enum \w+\s*:\s*String[^{]*\{([\s\S]*?)\n\}/) {
                for label in enumMatch.output.1.matches(of: /(?:case\s+|,\s*)\w+\s*=\s*"([^"]+)"/)
                where catalog.strings[String(label.output.1)] == nil {
                    missing.append("\(file.lastPathComponent): \(label.output.1)")
                }
            }
        }
        #expect(missing.isEmpty, "Etiquetas sin entrada en el catálogo: \(missing.sorted())")
    }
}
