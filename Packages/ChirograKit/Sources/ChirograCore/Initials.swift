import Foundation

/// Iniciales para avatares: la primera letra de las dos primeras palabras, en mayúscula y sin acentos.
/// Se saltan las palabras que no empiezan por letra o número («&», «-», «·»…) y los conectores escritos en
/// minúscula («Maderas del Norte» → «MN»); si van en mayúscula forman parte del nombre («Clínica Del Valle» →
/// «CD», como en el canvas).
public enum Initials {
    static let connectors: Set<String> = ["de", "del", "la", "las", "los", "el", "y", "e", "of", "the", "and"]

    public static func from(_ name: String, limit: Int = 2) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "/" })
        let significant = words.filter { !connectors.contains(String($0)) }
        let letters = (significant.isEmpty ? words : significant)
            .compactMap { word in word.first(where: { $0.isLetter || $0.isNumber }) }
            .prefix(limit)
            .map { String($0).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}
