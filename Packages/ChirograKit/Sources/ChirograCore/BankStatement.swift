import CryptoKit
import Foundation

// Extractos bancarios (DISEÑO §4.6): cada formato es una **fuente** (`BankTransactionSource`) que produce movimientos
// normalizados (`BankStatementLine`). La deduplicación, las reglas, la bandeja «Por revisar» y la conciliación
// (`Bookkeeper+Banking.swift`) no saben de qué fuente viene cada uno, así que Plaid (fase 3) será una fuente más.

/// De dónde viene un movimiento bancario. Plaid (fase 3) será otro caso más.
public enum BankSourceKind: String, CaseIterable, Sendable, Codable {
    case csv, ofx, plaid, manual
}

/// Movimiento de un extracto, ya normalizado.
public struct BankStatementLine: Hashable, Sendable {
    /// Día del movimiento (inicio del día en el calendario de la importación).
    public var date: Date
    /// Efecto en la cuenta contable como debe − haber: en un banco, positivo = depósito; en una tarjeta, negativo =
    /// compra y positivo = pago o devolución. En centavos.
    public var amount: Int64
    public var details: String
    public var payee: String
    public var memo: String
    public var checkNumber: String
    /// Identificador del banco (OFX `FITID`, columna de referencia del CSV) o, si no hay, `stableID`.
    public var externalID: String

    public init(date: Date, amount: Int64, details: String, payee: String = "", memo: String = "", checkNumber: String = "",
                externalID: String = "") {
        self.date = date
        self.amount = amount
        self.details = details
        self.payee = payee
        self.memo = memo
        self.checkNumber = checkNumber
        self.externalID = externalID
    }

    /// Identificador estable para un movimiento sin id del banco: fecha, importe, descripción normalizada y el número
    /// de repetición dentro del mismo archivo (dos cafés iguales el mismo día son dos movimientos). Volver a importar
    /// el mismo archivo, o uno que se solapa, da los mismos ids.
    public static func stableID(date: Date, amount: Int64, details: String, occurrence: Int, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let text = "\(day)|\(amount)|\(normalized(details))|\(occurrence)"
        let digest = SHA256.hash(data: Data(text.utf8))
        return "h:" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Minúsculas, sin acentos y con los espacios colapsados.
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Pone `stableID` a los que no traen id del banco.
    public static func assigningStableIDs(_ lines: [BankStatementLine], calendar: Calendar = .current) -> [BankStatementLine] {
        var seen: [String: Int] = [:]
        return lines.map { line in
            guard line.externalID.isEmpty else { return line }
            var line = line
            let key = "\(calendar.startOfDay(for: line.date).timeIntervalSinceReferenceDate)|\(line.amount)|\(normalized(line.details))"
            let occurrence = seen[key, default: 0]
            seen[key] = occurrence + 1
            line.externalID = stableID(date: line.date, amount: line.amount, details: line.details, occurrence: occurrence, calendar: calendar)
            return line
        }
    }
}

/// Una fuente de movimientos bancarios. CSV y OFX/QFX leen un archivo; Plaid (fase 3) los pedirá a su servicio.
public protocol BankTransactionSource: Sendable {
    var kind: BankSourceKind { get }
    /// Los movimientos, con `externalID` siempre relleno.
    func statementLines() async throws -> [BankStatementLine]
}

public enum BankStatementError: Error, Equatable, Sendable {
    /// El archivo no tiene movimientos legibles.
    case empty
    /// Fila (1 = la primera del archivo) con una fecha o un importe que no se entiende.
    case unreadableRow(Int)
    /// Falta la columna de fecha, descripción o importe en el mapeo.
    case missingColumn(String)
    /// No es un OFX/QFX.
    case notOFX
}

// MARK: - Importes y fechas

public enum BankAmountParser {
    /// Lee importes como «1,234.56», «-12.00», «$12.00», «(12.00)», «12.00-», «12.00 CR» / «DR». `nil` si no es un
    /// importe. Devuelve centavos con el signo escrito (los paréntesis, el «-» final y «DR» son negativos).
    public static func minorUnits(_ raw: String) -> Int64? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var negative = false
        let upper = text.uppercased()
        if upper.hasSuffix("CR") { text = String(text.dropLast(2)) }
        else if upper.hasSuffix("DR") { text = String(text.dropLast(2)); negative = true }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("("), text.hasSuffix(")") { negative.toggle(); text = String(text.dropFirst().dropLast()) }
        if text.hasSuffix("-") { negative.toggle(); text = String(text.dropLast()) }
        if text.hasPrefix("-") { negative.toggle(); text = String(text.dropFirst()) }
        if text.hasPrefix("+") { text = String(text.dropFirst()) }
        text = text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: "USD", with: "")
            .replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("-") { negative.toggle(); text = String(text.dropFirst()) }
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), text.filter({ $0 == "." }).count <= 1,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let cents = Money(decimal: value).minorUnits
        return negative ? -cents : cents
    }
}

// MARK: - CSV

/// Columnas del CSV (índices desde 0). Importe en una columna con signo, o en dos: cargos (`debit`, salidas) y
/// abonos (`credit`, entradas).
public struct CSVColumnMapping: Codable, Hashable, Sendable {
    public var date: Int
    public var details: Int
    public var amount: Int?
    public var debit: Int?
    public var credit: Int?
    public var payee: Int?
    public var memo: Int?
    /// Identificador del movimiento, si el banco lo da (se usa como `externalID`).
    public var reference: Int?
    public var checkNumber: Int?

    public init(date: Int, details: Int, amount: Int? = nil, debit: Int? = nil, credit: Int? = nil, payee: Int? = nil,
                memo: Int? = nil, reference: Int? = nil, checkNumber: Int? = nil) {
        self.date = date
        self.details = details
        self.amount = amount
        self.debit = debit
        self.credit = credit
        self.payee = payee
        self.memo = memo
        self.reference = reference
        self.checkNumber = checkNumber
    }
}

/// Signo de la columna de importe del CSV.
public enum CSVAmountSign: String, CaseIterable, Sendable, Codable {
    /// Positivo = entra dinero (depósito, pago a la tarjeta). Lo habitual en bancos.
    case signed
    /// Positivo = sale dinero (cargo, compra). Lo habitual en las exportaciones de tarjetas.
    case inverted
}

/// Cómo leer un CSV de un banco (se guarda por cuenta en `BankImportProfile`).
public struct CSVImportSettings: Codable, Hashable, Sendable {
    public var mapping: CSVColumnMapping
    /// Formato de `DateFormatter` («MM/dd/yyyy», «yyyy-MM-dd», «M/d/yy»…).
    public var dateFormat: String
    public var amountSign: CSVAmountSign
    public var delimiter: Character
    public var hasHeaderRow: Bool

    public init(mapping: CSVColumnMapping, dateFormat: String = "MM/dd/yyyy", amountSign: CSVAmountSign = .signed,
                delimiter: Character = ",", hasHeaderRow: Bool = true) {
        self.mapping = mapping
        self.dateFormat = dateFormat
        self.amountSign = amountSign
        self.delimiter = delimiter
        self.hasHeaderRow = hasHeaderRow
    }

    enum CodingKeys: String, CodingKey { case mapping, dateFormat, amountSign, delimiter, hasHeaderRow }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mapping = try container.decode(CSVColumnMapping.self, forKey: .mapping)
        dateFormat = try container.decodeIfPresent(String.self, forKey: .dateFormat) ?? "MM/dd/yyyy"
        amountSign = try container.decodeIfPresent(CSVAmountSign.self, forKey: .amountSign) ?? .signed
        delimiter = (try container.decodeIfPresent(String.self, forKey: .delimiter))?.first ?? ","
        hasHeaderRow = try container.decodeIfPresent(Bool.self, forKey: .hasHeaderRow) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mapping, forKey: .mapping)
        try container.encode(dateFormat, forKey: .dateFormat)
        try container.encode(amountSign, forKey: .amountSign)
        try container.encode(String(delimiter), forKey: .delimiter)
        try container.encode(hasHeaderRow, forKey: .hasHeaderRow)
    }

    /// Propuesta a partir de la cabecera y las primeras filas: columnas por su nombre (Date, Description, Amount,
    /// Debit/Credit, Payee, Memo, Check Number, Transaction ID…, también en español), el formato de fecha que lee todas
    /// las filas de muestra y el delimitador (coma, punto y coma o tabulador). `nil` si no encuentra fecha, descripción e
    /// importe. El usuario la confirma o corrige antes de importar.
    public static func suggested(for text: String) -> CSVImportSettings? {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let candidates: [Character] = [",", ";", "\t"]
        let delimiter = candidates.max { a, b in firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count } ?? ","
        let rows = CSVBankSource.rows(text, delimiter: delimiter)
        guard let header = rows.first else { return nil }
        let names = header.map { BankStatementLine.normalized($0) }
        func column(_ candidates: [String], excluding: Set<Int> = []) -> Int? {
            for candidate in candidates {
                if let index = names.indices.first(where: { !excluding.contains($0) && names[$0] == candidate }) { return index }
            }
            for candidate in candidates {
                if let index = names.indices.first(where: { !excluding.contains($0) && names[$0].contains(candidate) }) { return index }
            }
            return nil
        }
        guard let date = column(["date", "transaction date", "posted date", "posting date", "fecha", "fecha de operacion"]) else { return nil }
        guard let details = column(["description", "descripcion", "details", "detalle", "concepto", "name", "transaction"], excluding: [date]) else { return nil }
        let amount = column(["amount", "importe", "monto", "transaction amount"], excluding: [date, details])
        let debit = column(["debit", "withdrawal", "withdrawals", "cargo", "cargos", "retiro"], excluding: [date, details])
        let credit = column(["credit", "deposit", "deposits", "abono", "abonos", "deposito"], excluding: [date, details])
        guard amount != nil || (debit != nil && credit != nil) else { return nil }
        let used: Set<Int> = Set([date, details, amount, debit, credit].compactMap { $0 })
        let mapping = CSVColumnMapping(
            date: date, details: details, amount: amount, debit: amount == nil ? debit : nil, credit: amount == nil ? credit : nil,
            payee: column(["payee", "beneficiario", "merchant"], excluding: used),
            memo: column(["memo", "notes", "nota"], excluding: used),
            reference: column(["transaction id", "reference", "referencia", "fitid", "id"], excluding: used),
            checkNumber: column(["check number", "check", "cheque", "numero de cheque"], excluding: used)
        )
        let samples = rows.dropFirst().prefix(20).compactMap { $0.indices.contains(date) ? $0[date] : nil }.filter { !$0.isEmpty }
        let formats = ["MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "M/d/yy", "yyyy-MM-dd", "dd/MM/yyyy", "yyyyMMdd", "MM-dd-yyyy", "dd-MM-yyyy"]
        let dateFormat = formats.first { format in
            !samples.isEmpty && samples.allSatisfy { CSVBankSource.parseDate($0, format: format) != nil }
        } ?? "MM/dd/yyyy"
        return CSVImportSettings(mapping: mapping, dateFormat: dateFormat, amountSign: .signed, delimiter: delimiter, hasHeaderRow: true)
    }
}

/// Fuente CSV: un archivo exportado del banco con un `CSVImportSettings`.
public struct CSVBankSource: BankTransactionSource {
    public var text: String
    public var settings: CSVImportSettings
    public var calendar: Calendar

    public init(text: String, settings: CSVImportSettings, calendar: Calendar = .current) {
        self.text = text
        self.settings = settings
        self.calendar = calendar
    }

    public init(data: Data, settings: CSVImportSettings, calendar: Calendar = .current) {
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        self.init(text: text, settings: settings, calendar: calendar)
    }

    public var kind: BankSourceKind { .csv }

    public func statementLines() async throws -> [BankStatementLine] { try parse() }

    /// Lee el archivo. Las filas vacías se saltan; una fila con fecha o importe ilegible es un error (con su número).
    public func parse() throws -> [BankStatementLine] {
        let mapping = settings.mapping
        guard mapping.amount != nil || (mapping.debit != nil || mapping.credit != nil) else { throw BankStatementError.missingColumn("amount") }
        var lines: [BankStatementLine] = []
        for (index, row) in Self.rows(text, delimiter: settings.delimiter).enumerated() {
            if index == 0, settings.hasHeaderRow { continue }
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            func cell(_ column: Int?) -> String {
                guard let column, row.indices.contains(column) else { return "" }
                return row[column].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let day = Self.parseDate(cell(mapping.date), format: settings.dateFormat, calendar: calendar) else {
                throw BankStatementError.unreadableRow(index + 1)
            }
            var amount: Int64
            if mapping.amount != nil {
                guard let value = BankAmountParser.minorUnits(cell(mapping.amount)) else { throw BankStatementError.unreadableRow(index + 1) }
                amount = value
            } else {
                let out = cell(mapping.debit).isEmpty ? 0 : BankAmountParser.minorUnits(cell(mapping.debit))
                let into = cell(mapping.credit).isEmpty ? 0 : BankAmountParser.minorUnits(cell(mapping.credit))
                guard let out, let into else { throw BankStatementError.unreadableRow(index + 1) }
                // Las columnas de cargos a veces traen el signo negativo: cuenta su magnitud.
                amount = into.magnitude == 0 ? -Int64(out.magnitude) : Int64(into.magnitude) - Int64(out.magnitude)
            }
            if settings.amountSign == .inverted, mapping.amount != nil { amount = -amount }
            lines.append(BankStatementLine(date: day, amount: amount, details: cell(mapping.details), payee: cell(mapping.payee),
                                           memo: cell(mapping.memo), checkNumber: cell(mapping.checkNumber),
                                           externalID: cell(mapping.reference).isEmpty ? "" : "ref:" + cell(mapping.reference)))
        }
        guard !lines.isEmpty else { throw BankStatementError.empty }
        return BankStatementLine.assigningStableIDs(lines, calendar: calendar)
    }

    /// Filas y celdas de un CSV (RFC 4180: comillas dobles, comillas escapadas, saltos de línea dentro de comillas).
    public static func rows(_ text: String, delimiter: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?
        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else { inQuotes = false }
                } else {
                    field.append(char)
                }
            } else if char == "\"" {
                inQuotes = true
            } else if char == delimiter {
                row.append(field)
                field = ""
            } else if char == "\n" || char == "\r\n" || char == "\r" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if char != "\u{FEFF}" {
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    static func parseDate(_ raw: String, format: String, calendar: Calendar = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        formatter.isLenient = false
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let date = formatter.date(from: text) else { return nil }
        // Años de dos cifras: DateFormatter ya los lleva al siglo cercano; se descartan años absurdos.
        let year = calendar.component(.year, from: date)
        guard (1970...2100).contains(year) else { return nil }
        return calendar.startOfDay(for: date)
    }
}

// MARK: - OFX / QFX

/// Extracto OFX/QFX leído: movimientos y, si los trae, el saldo del extracto (para proponer la conciliación).
public struct OFXStatement: Sendable, Equatable {
    public var lines: [BankStatementLine]
    /// `LEDGERBAL`: saldo del extracto como lo da el banco (en una tarjeta suele ser negativo = deuda) y su fecha.
    public var ledgerBalance: Int64?
    public var balanceDate: Date?
    /// Últimos 4 dígitos de `ACCTID`, para proponer la cuenta.
    public var accountLast4: String
    public var currency: String
    /// Es un extracto de tarjeta (`CCSTMTRS`).
    public var isCreditCard: Bool
}

/// Fuente OFX/QFX (SGML 1.x y XML 2.x): un movimiento por cada `STMTTRN`, con `FITID` como id.
public struct OFXBankSource: BankTransactionSource {
    public var text: String
    public var calendar: Calendar

    public init(text: String, calendar: Calendar = .current) {
        self.text = text
        self.calendar = calendar
    }

    public init(data: Data, calendar: Calendar = .current) {
        self.init(text: String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? "", calendar: calendar)
    }

    public var kind: BankSourceKind { .ofx }

    public func statementLines() async throws -> [BankStatementLine] { try parse().lines }

    public func parse() throws -> OFXStatement {
        let upper = text.uppercased()
        guard upper.contains("<OFX>") else { throw BankStatementError.notOFX }
        var lines: [BankStatementLine] = []
        for block in Self.blocks(named: "STMTTRN", in: text) {
            let fields = Self.leafValues(in: block)
            guard let posted = fields["DTPOSTED"].flatMap({ Self.parseDate($0, calendar: calendar) }),
                  let amount = fields["TRNAMT"].flatMap(BankAmountParser.minorUnits) else { continue }
            let name = fields["NAME"] ?? ""
            let memo = fields["MEMO"] ?? ""
            let fitid = fields["FITID"] ?? ""
            lines.append(BankStatementLine(date: posted, amount: amount, details: name.isEmpty ? memo : name, payee: name,
                                           memo: name.isEmpty ? "" : memo, checkNumber: fields["CHECKNUM"] ?? "",
                                           externalID: fitid.isEmpty ? "" : "fitid:" + fitid))
        }
        guard !lines.isEmpty else { throw BankStatementError.empty }
        let balance = Self.blocks(named: "LEDGERBAL", in: text).first.map(Self.leafValues(in:))
        let account = Self.leafValues(in: text)["ACCTID"] ?? ""
        return OFXStatement(
            lines: BankStatementLine.assigningStableIDs(lines, calendar: calendar),
            ledgerBalance: balance?["BALAMT"].flatMap(BankAmountParser.minorUnits),
            balanceDate: balance?["DTASOF"].flatMap { Self.parseDate($0, calendar: calendar) },
            accountLast4: String(account.filter(\.isNumber).suffix(4)),
            currency: Self.leafValues(in: text)["CURDEF"] ?? "USD",
            isCreditCard: upper.contains("<CCSTMTRS>")
        )
    }

    /// Contenido entre `<NAME>` y `</NAME>` (los agregados siempre se cierran, también en SGML).
    static func blocks(named name: String, in text: String) -> [String] {
        var result: [String] = []
        var rest = text[...]
        while let open = rest.range(of: "<\(name)>", options: .caseInsensitive) {
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "</\(name)>", options: .caseInsensitive) else { break }
            result.append(String(after[..<close.lowerBound]))
            rest = after[close.upperBound...]
        }
        return result
    }

    /// Elementos hoja `<TAG>valor` (SGML, sin cierre) o `<TAG>valor</TAG>` (XML): el primero de cada nombre.
    static func leafValues(in text: String) -> [String: String] {
        var values: [String: String] = [:]
        var index = text.startIndex
        while let open = text[index...].firstIndex(of: "<") {
            guard let close = text[open...].firstIndex(of: ">") else { break }
            let tag = text[text.index(after: open)..<close]
            index = text.index(after: close)
            guard !tag.hasPrefix("/"), !tag.hasPrefix("?"), !tag.hasPrefix("!") else { continue }
            let end = text[index...].firstIndex { $0 == "<" || $0 == "\n" || $0 == "\r" } ?? text.endIndex
            let value = text[index..<end].trimmingCharacters(in: .whitespaces)
            let key = tag.uppercased()
            if !value.isEmpty, values[key] == nil { values[key] = decodeEntities(value) }
        }
        return values
    }

    static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// `YYYYMMDD[HHMMSS[.XXX]][[-5:EST]]` → el día, sin mover la fecha por la zona horaria.
    static func parseDate(_ raw: String, calendar: Calendar) -> Date? {
        let digits = raw.prefix { $0.isNumber }
        guard digits.count >= 8, let year = Int(digits.prefix(4)), let month = Int(digits.dropFirst(4).prefix(2)),
              let day = Int(digits.dropFirst(6).prefix(2)) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
