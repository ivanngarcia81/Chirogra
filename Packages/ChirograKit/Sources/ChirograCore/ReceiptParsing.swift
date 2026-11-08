import Foundation

// MARK: - Lectura de recibos por reglas (fase 2, «Escanear recibos», CONTEXTO 4-nov)
//
// Lo que la app saca de un recibo sin Apple Intelligence: el texto ya leído (Vision, en el aparato) entra aquí como
// renglones en orden de lectura y salen comercio, fecha, total, impuesto incluido y una pista de categoría. Son reglas
// sencillas y prudentes: si algo no está claro, se deja vacío (el usuario revisa siempre antes de guardar). Con Apple
// Intelligence, la app pide lo mismo al modelo del aparato y usa esto para comprobar sus cifras.

/// Qué tipo de gasto parece el recibo, por palabras del comercio o del texto. La app lo convierte en una cuenta del plan.
public enum ReceiptCategoryHint: String, CaseIterable, Sendable {
    case meals, vehicle, office, materials, supplies, travel, utilities, software, phone, repairs, advertising, shipping
}

/// Lo que las reglas encontraron en un recibo. Importes en centavos.
public struct ReceiptRuleResult: Equatable, Sendable {
    public var merchant: String?
    public var date: Date?
    public var total: Int64?
    public var salesTax: Int64?
    public var categoryHint: ReceiptCategoryHint?
    /// Todos los importes que aparecen en el texto (para comprobar los del modelo).
    public var amounts: [Int64]

    public init(merchant: String? = nil, date: Date? = nil, total: Int64? = nil, salesTax: Int64? = nil,
                categoryHint: ReceiptCategoryHint? = nil, amounts: [Int64] = []) {
        self.merchant = merchant
        self.date = date
        self.total = total
        self.salesTax = salesTax
        self.categoryHint = categoryHint
        self.amounts = amounts
    }
}

public enum ReceiptRules {

    /// Lee los renglones de un recibo. `now` acota las fechas posibles (ni del futuro ni de hace más de 3 años).
    public static func parse(lines rawLines: [String], now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> ReceiptRuleResult {
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var result = ReceiptRuleResult()
        result.amounts = lines.flatMap { amounts(in: $0) }
        result.total = total(in: lines)
        if let total = result.total, let tax = salesTax(in: lines), tax > 0, tax < total { result.salesTax = tax }
        result.date = date(in: lines, now: now, calendar: calendar)
        result.merchant = merchant(in: lines)
        result.categoryHint = categoryHint(merchant: result.merchant, text: lines.joined(separator: " "))
        return result
    }

    /// Lo mismo a partir de un texto con saltos de línea.
    public static func parse(text: String, now: Date = Date()) -> ReceiptRuleResult {
        parse(lines: text.components(separatedBy: .newlines), now: now)
    }

    // MARK: Importes

    /// Importes con centavos de un renglón («$1,234.56», «12.00», «12,00» con coma decimal, «-3.50»), sin los
    /// porcentajes («8.25%») ni lo que parece una hora o un teléfono.
    public static func amounts(in line: String) -> [Int64] {
        let pattern = #"(?<![\d.,/:])(-?)\$?\s?((?:\d{1,3}(?:,\d{3})+|\d+)\.\d{2}|\d+,\d{2})(?![\d%/:])(?!\s?%)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let numberRange = Range(match.range(at: 2), in: line) else { return nil }
            var number = String(line[numberRange])
            if number.contains(".") { number = number.replacingOccurrences(of: ",", with: "") }
            else { number = number.replacingOccurrences(of: ",", with: ".") }
            guard let value = Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            var cents = value * 100
            var rounded = Decimal()
            NSDecimalRound(&rounded, &cents, 0, .plain)
            let amount = NSDecimalNumber(decimal: rounded).int64Value
            let negative = Range(match.range(at: 1), in: line).map { !line[$0].isEmpty } ?? false
            return negative ? -amount : amount
        }
    }

    /// Texto sin mayúsculas ni acentos, para buscar palabras.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func containsWord(_ text: String, _ words: [String]) -> Bool {
        words.contains { word in
            text.range(of: #"(?<![a-z])"# + NSRegularExpression.escapedPattern(for: word) + #"(?![a-z])"#, options: .regularExpression) != nil
        }
    }

    // MARK: Total

    /// Palabras de total, de la más segura a la menos.
    static let totalKeywords: [[String]] = [
        ["grand total", "amount due", "balance due", "total due", "total a pagar", "importe total", "total amount", "amount paid"],
        ["total", "importe", "monto"],
    ]
    /// Renglones con «total» que no son el total del recibo.
    static let notTotal = ["subtotal", "sub total", "sub-total", "total tax", "tax total", "total savings", "you saved",
                           "total items", "items total", "total discount", "total de articulos", "articulos", "ahorro",
                           "pre-tax", "before tax", "total qty", "total quantity", "taxable"]

    static func total(in lines: [String]) -> Int64? {
        for keywords in totalKeywords {
            var candidates: [Int64] = []
            for (index, line) in lines.enumerated() {
                let text = folded(line)
                guard containsWord(text, keywords), !notTotal.contains(where: { text.contains($0) }) else { continue }
                // El importe va en el mismo renglón o, si no, en el siguiente («TOTAL» / «$284.17»).
                if let amount = amounts(in: line).last {
                    candidates.append(amount)
                } else if index + 1 < lines.count, let amount = amounts(in: lines[index + 1]).first {
                    candidates.append(amount)
                }
            }
            if let best = candidates.filter({ $0 > 0 }).max() { return best }
        }
        // Sin palabra de total: el importe mayor (el total suele serlo, o el pago con tarjeta, que es igual).
        let all = lines.filter { !containsWord(folded($0), ["change", "cambio", "cash", "efectivo"]) }.flatMap { amounts(in: $0) }
        return all.filter { $0 > 0 }.max()
    }

    // MARK: Impuesto

    static let taxKeywords = ["tax", "sales tax", "impuesto", "impuestos", "iva", "state tax", "city tax", "county tax", "hst", "gst"]
    static let notTax = ["taxable", "tax id", "tax exempt", "non-tax", "nontax", "pre-tax", "before tax", "no tax",
                         "without tax", "excl", "tax invoice", "total amount"]

    /// El impuesto del recibo: el renglón «total tax» si lo hay; si no, la suma de los renglones de impuesto.
    static func salesTax(in lines: [String]) -> Int64? {
        var parts: [Int64] = []
        for line in lines {
            let text = folded(line)
            guard containsWord(text, taxKeywords), !notTax.contains(where: { text.contains($0) }) else { continue }
            guard let amount = amounts(in: line).last, amount > 0 else { continue }
            if text.contains("total tax") || text.contains("tax total") || text.contains("total impuesto") { return amount }
            // «TOTAL incl. tax 284.17»: es el total, no el impuesto.
            if containsWord(text, ["total", "grand total", "balance", "amount due"]) { continue }
            parts.append(amount)
        }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }

    // MARK: Fecha

    private static let monthNames: [String: Int] = [
        "jan": 1, "january": 1, "ene": 1, "enero": 1,
        "feb": 2, "february": 2, "febrero": 2,
        "mar": 3, "march": 3, "marzo": 3,
        "apr": 4, "april": 4, "abr": 4, "abril": 4,
        "may": 5, "mayo": 5,
        "jun": 6, "june": 6, "junio": 6,
        "jul": 7, "july": 7, "julio": 7,
        "aug": 8, "august": 8, "ago": 8, "agosto": 8,
        "sep": 9, "sept": 9, "september": 9, "septiembre": 9, "set": 9,
        "oct": 10, "october": 10, "octubre": 10,
        "nov": 11, "november": 11, "noviembre": 11,
        "dec": 12, "december": 12, "dic": 12, "diciembre": 12,
    ]

    /// La primera fecha posible del recibo: «10/29/2026», «10/29/26», «2026-10-29», «29/10/2026» (si el primer número
    /// pasa de 12), «Oct 29, 2026», «29 oct 2026». En EE. UU. el mes va primero.
    static func date(in lines: [String], now: Date, calendar: Calendar) -> Date? {
        let earliest = calendar.date(byAdding: .year, value: -3, to: now) ?? now
        let latest = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        for line in lines {
            for candidate in dates(in: folded(line), calendar: calendar) where candidate >= earliest && candidate <= latest {
                return candidate
            }
        }
        return nil
    }

    static func dates(in text: String, calendar: Calendar) -> [Date] {
        var found: [(Int, Date)] = []
        func make(_ year: Int, _ month: Int, _ day: Int) -> Date? {
            let fullYear = year < 100 ? 2000 + year : year
            guard (1...12).contains(month), (1...31).contains(day), (2000...2100).contains(fullYear) else { return nil }
            var components = DateComponents(year: fullYear, month: month, day: day, hour: 12)
            components.calendar = calendar
            guard let date = calendar.date(from: components), calendar.component(.day, from: date) == day else { return nil }
            return date
        }
        func each(_ pattern: String, _ body: ([String], Int) -> Date?) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let groups = (1..<match.numberOfRanges).map { index in
                    Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
                }
                if let date = body(groups, match.range.location) { found.append((match.range.location, date)) }
            }
        }
        // 2026-10-29
        each(#"(?<!\d)(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)"#) { g, _ in make(Int(g[0]) ?? 0, Int(g[1]) ?? 0, Int(g[2]) ?? 0) }
        // 10/29/2026, 10-29-26, 29/10/2026
        each(#"(?<![\d/.-])(\d{1,2})[/.-](\d{1,2})[/.-](\d{4}|\d{2})(?![\d/.-])"#) { g, _ in
            let first = Int(g[0]) ?? 0, second = Int(g[1]) ?? 0, year = Int(g[2]) ?? 0
            return first > 12 ? make(year, second, first) : make(year, first, second)
        }
        // Oct 29, 2026 · October 29 2026
        each(#"(?<![a-z])([a-z]{3,10})\.?\s+(\d{1,2}),?\s+(\d{4})(?!\d)"#) { g, _ in
            guard let month = monthNames[g[0]] else { return nil }
            return make(Int(g[2]) ?? 0, month, Int(g[1]) ?? 0)
        }
        // 29 oct 2026 · 29 de octubre de 2026 · 29-oct-2026
        each(#"(?<!\d)(\d{1,2})(?:\s+de)?[\s-]+([a-z]{3,10})\.?(?:\s+de)?[\s-]+(\d{4})(?!\d)"#) { g, _ in
            guard let month = monthNames[g[1]] else { return nil }
            return make(Int(g[2]) ?? 0, month, Int(g[0]) ?? 0)
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    // MARK: Comercio

    /// Renglones del principio que no son el comercio.
    static let notMerchant = ["welcome", "bienvenido", "receipt", "recibo", "ticket", "invoice", "factura",
                              "thank you", "gracias", "customer copy", "copia", "duplicate", "order", "orden",
                              "cashier", "cajero", "register", "tel", "phone", "telefono", "date", "fecha", "www", "http"]
    /// Trozos (con signos) que delatan una web o un correo.
    static let notMerchantFragments = [".com", ".net", ".org", "@"]

    /// El nombre del comercio: el primer renglón de los primeros que tiene letras y no parece dirección, teléfono, fecha
    /// ni saludo. En mayúsculas se pasa a «The Home Depot».
    static func merchant(in lines: [String]) -> String? {
        for line in lines.prefix(6) {
            let text = folded(line)
            let letters = line.filter(\.isLetter).count
            let digits = line.filter(\.isNumber).count
            guard letters >= 3, digits <= letters / 2 else { continue }
            guard !containsWord(text, notMerchant), !notMerchantFragments.contains(where: { text.contains($0) }) else { continue }
            // Dirección: empieza por el número de la calle.
            if text.range(of: #"^\d+\s+\w+"#, options: .regularExpression) != nil { continue }
            if !amounts(in: line).isEmpty { continue }
            return cleanMerchant(line)
        }
        return nil
    }

    /// Quita el número de tienda («#4410»), los signos sueltos y pasa las mayúsculas a «The Home Depot».
    public static func cleanMerchant(_ name: String) -> String {
        var text = name.replacingOccurrences(of: #"(?:#|no\.?\s?|store\s?)\s?\d+"#, with: "", options: [.regularExpression, .caseInsensitive])
        text = text.trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "&'")))
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        let isShouting = text == text.uppercased() && text != text.lowercased()
        guard isShouting else { return text }
        return text.split(separator: " ").map { word -> String in
            let upper = String(word)
            if ["LLC", "INC", "USA", "US", "CVS", "UPS", "BBQ", "TX", "CA", "NY", "AT&T"].contains(upper) { return upper }
            return upper.prefix(1) + upper.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    // MARK: Categoría

    static let categoryWords: [(ReceiptCategoryHint, [String])] = [
        (.vehicle, ["shell", "chevron", "exxon", "mobil", "valero", "texaco", "citgo", "sunoco", "marathon", "phillips 66",
                    "fuel", "gasoline", "unleaded", "diesel", "gallons", "pump", "car wash", "autozone", "o'reilly",
                    "jiffy lube", "parking", "toll", "estacionamiento", "gasolina"]),
        (.meals, ["restaurant", "restaurante", "cafe", "coffee", "starbucks", "mcdonald", "chipotle", "pizza", "grill",
                  "taqueria", "bistro", "diner", "kitchen", "bar & grill", "subway", "panera", "gratuity", "propina",
                  "mesero"]),
        (.materials, ["home depot", "lowe's", "lowes", "menards", "lumber", "hardware", "ferreteria", "ace hardware",
                      "plywood", "drywall", "tornillo", "screws", "mdf", "barniz", "paint"]),
        (.office, ["office depot", "officemax", "staples", "paper", "toner", "ink cartridge", "papeleria"]),
        (.travel, ["airlines", "airline", "delta", "united", "american airlines", "southwest", "hotel", "inn", "marriott",
                   "hilton", "airbnb", "uber", "lyft", "taxi", "boarding"]),
        (.utilities, ["electric", "energy", "water utility", "gas company", "utility", "austin energy", "pg&e"]),
        (.software, ["adobe", "microsoft", "google workspace", "dropbox", "subscription", "suscripcion", "apple.com/bill", "github"]),
        (.phone, ["verizon", "t-mobile", "at&t", "comcast", "xfinity", "spectrum", "internet", "wireless"]),
        (.shipping, ["usps", "fedex", "ups store", "dhl", "postage", "shipping", "envio"]),
        (.advertising, ["facebook ads", "meta ads", "google ads", "yelp", "printing", "imprenta", "flyers"]),
        (.supplies, ["walmart", "target", "costco", "sam's club", "dollar", "supplies", "suministros"]),
    ]

    static func categoryHint(merchant: String?, text: String) -> ReceiptCategoryHint? {
        let name = folded(merchant ?? "")
        let all = folded(text)
        for (hint, words) in categoryWords where containsWord(name, words) { return hint }
        for (hint, words) in categoryWords where containsWord(all, words) { return hint }
        return nil
    }

    /// Nombre de comercio para comparar con los proveedores: sin mayúsculas, acentos, signos, «the», «inc», «llc»…
    public static func comparableName(_ name: String) -> String {
        let text = folded(cleanMerchant(name)).replacingOccurrences(of: #"[^a-z0-9 ]"#, with: "", options: .regularExpression)
        let skip: Set<String> = ["the", "inc", "llc", "co", "corp", "company", "store", "stores", "de", "la", "el"]
        return text.split(separator: " ").map(String.init).filter { !skip.contains($0) }.joined(separator: " ")
    }
}
