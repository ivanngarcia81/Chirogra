import Foundation

/// Iniciales para avatares: la primera letra de las dos primeras palabras, en mayúscula y sin acentos.
/// Se saltan las palabras que no empiezan por letra o número («&», «-», «·»…).
public enum Initials {
    public static func from(_ name: String, limit: Int = 2) -> String {
        let letters = name
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "/" })
            .compactMap { word in word.first(where: { $0.isLetter || $0.isNumber }) }
            .prefix(limit)
            .map { String($0).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}
