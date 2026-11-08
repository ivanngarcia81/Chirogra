import Foundation
import Testing
@testable import ChirograCore

@Suite("Extractos bancarios: CSV y OFX/QFX")
struct BankStatementTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    func day(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d))! }

    @Test("Importes como los escriben los bancos")
    func amounts() {
        #expect(BankAmountParser.minorUnits("1,234.56") == 123_456)
        #expect(BankAmountParser.minorUnits("-12.00") == -1_200)
        #expect(BankAmountParser.minorUnits("$12.5") == 1_250)
        #expect(BankAmountParser.minorUnits("-$12.50") == -1_250)
        #expect(BankAmountParser.minorUnits("(45.10)") == -4_510)
        #expect(BankAmountParser.minorUnits("45.10-") == -4_510)
        #expect(BankAmountParser.minorUnits("45.10 DR") == -4_510)
        #expect(BankAmountParser.minorUnits("45.10 CR") == 4_510)
        #expect(BankAmountParser.minorUnits("") == nil)
        #expect(BankAmountParser.minorUnits("abc") == nil)
        #expect(BankAmountParser.minorUnits("1.2.3") == nil)
    }

    @Test("CSV de banco con importe con signo, comillas y cabecera reconocida")
    func signedCSV() throws {
        let text = """
        Date,Description,Amount,Running Bal.
        10/01/2026,"UBER *TRIP, HELP.UBER.COM",-18.40,"1,000.00"
        10/02/2026,DEPOSIT CAFE AURORA,"1,800.00",2800.00
        10/02/2026,STARBUCKS,-5.25,2794.75
        10/02/2026,STARBUCKS,-5.25,2789.50

        """
        let settings = try #require(CSVImportSettings.suggested(for: text))
        #expect(settings.mapping.date == 0 && settings.mapping.details == 1 && settings.mapping.amount == 2)
        #expect(settings.dateFormat == "MM/dd/yyyy" && settings.delimiter == ",")
        let lines = try CSVBankSource(text: text, settings: settings, calendar: calendar).parse()
        #expect(lines.map(\.amount) == [-1_840, 180_000, -525, -525])
        #expect(lines[0].details == "UBER *TRIP, HELP.UBER.COM")
        #expect(lines[1].date == day(2026, 10, 2))
        // Dos cafés iguales el mismo día son dos movimientos, con ids estables y distintos.
        #expect(Set(lines.map(\.externalID)).count == 4)
        let again = try CSVBankSource(text: text, settings: settings, calendar: calendar).parse()
        #expect(again.map(\.externalID) == lines.map(\.externalID))
    }

    @Test("CSV de tarjeta: importe invertido o columnas de cargos y abonos, con punto y coma")
    func cardCSV() throws {
        let inverted = "Transaction Date,Description,Amount\n2026-10-05,AMAZON,25.99\n2026-10-06,PAYMENT THANK YOU,-500.00\n"
        var settings = try #require(CSVImportSettings.suggested(for: inverted))
        #expect(settings.dateFormat == "yyyy-MM-dd")
        settings.amountSign = .inverted
        #expect(try CSVBankSource(text: inverted, settings: settings, calendar: calendar).parse().map(\.amount) == [-2_599, 50_000])

        let split = "Fecha;Concepto;Cargo;Abono;Referencia\n05/10/2026;Renta;1200,00;;A1\n06/10/2026;Depósito;;300.00;A2\n"
        let mapping = CSVColumnMapping(date: 0, details: 1, debit: 2, credit: 3, reference: 4)
        let parsed = try CSVBankSource(text: split.replacingOccurrences(of: "1200,00", with: "1200.00"),
                                       settings: CSVImportSettings(mapping: mapping, dateFormat: "dd/MM/yyyy", delimiter: ";"),
                                       calendar: calendar).parse()
        #expect(parsed.map(\.amount) == [-120_000, 30_000])
        #expect(parsed.map(\.externalID) == ["ref:A1", "ref:A2"])
        #expect(parsed[0].date == day(2026, 10, 5))
    }

    @Test("Una fila ilegible dice cuál es")
    func badRow() throws {
        let text = "Date,Description,Amount\n10/01/2026,Uno,1.00\n31/31/2026,Dos,2.00\n"
        let settings = try #require(CSVImportSettings.suggested(for: "Date,Description,Amount\n10/01/2026,Uno,1.00\n"))
        #expect(throws: BankStatementError.unreadableRow(3)) { try CSVBankSource(text: text, settings: settings, calendar: calendar).parse() }
        #expect(throws: BankStatementError.empty) { try CSVBankSource(text: "Date,Description,Amount\n", settings: settings).parse() }
    }

    @Test("El perfil de CSV se guarda y se lee en JSON")
    func settingsCodable() throws {
        let settings = CSVImportSettings(mapping: CSVColumnMapping(date: 1, details: 2, amount: 3), dateFormat: "M/d/yy",
                                         amountSign: .inverted, delimiter: "\t", hasHeaderRow: false)
        let decoded = try JSONDecoder().decode(CSVImportSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    static let sgml = """
    OFXHEADER:100
    DATA:OFXSGML
    VERSION:102

    <OFX>
    <SIGNONMSGSRSV1><SONRS><STATUS><CODE>0<SEVERITY>INFO</STATUS><DTSERVER>20261031120000</SONRS></SIGNONMSGSRSV1>
    <BANKMSGSRSV1><STMTTRNRS><STMTRS><CURDEF>USD
    <BANKACCTFROM><BANKID>041001039<ACCTID>123454821<ACCTTYPE>CHECKING</BANKACCTFROM>
    <BANKTRANLIST><DTSTART>20261001<DTEND>20261031
    <STMTTRN>
    <TRNTYPE>DEBIT
    <DTPOSTED>20261003120000.000[-5:CDT]
    <TRNAMT>-1200.00
    <FITID>2026100301
    <CHECKNUM>1043
    <NAME>RENTA TALLER
    <MEMO>Cheque 1043
    </STMTTRN>
    <STMTTRN>
    <TRNTYPE>CREDIT
    <DTPOSTED>20261005
    <TRNAMT>1800.00
    <FITID>2026100501
    <NAME>CAFE AURORA &amp; CO
    </STMTTRN>
    </BANKTRANLIST>
    <LEDGERBAL><BALAMT>4321.09<DTASOF>20261031</LEDGERBAL>
    </STMTRS></STMTTRNRS></BANKMSGSRSV1>
    </OFX>
    """

    @Test("OFX 1.x (SGML): movimientos con FITID, cheque, nombre y saldo del extracto")
    func ofxSGML() throws {
        let statement = try OFXBankSource(text: Self.sgml, calendar: calendar).parse()
        #expect(statement.lines.count == 2)
        #expect(statement.lines.map(\.amount) == [-120_000, 180_000])
        #expect(statement.lines.map(\.externalID) == ["fitid:2026100301", "fitid:2026100501"])
        #expect(statement.lines[0].date == day(2026, 10, 3))
        #expect(statement.lines[0].checkNumber == "1043" && statement.lines[0].memo == "Cheque 1043")
        #expect(statement.lines[1].details == "CAFE AURORA & CO")
        #expect(statement.ledgerBalance == 432_109 && statement.balanceDate == day(2026, 10, 31))
        #expect(statement.accountLast4 == "4821" && !statement.isCreditCard && statement.currency == "USD")
    }

    @Test("OFX 2.x (XML) de tarjeta (QFX)")
    func ofxXML() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <?OFX OFXHEADER="200" VERSION="220"?>
        <OFX><CREDITCARDMSGSRSV1><CCSTMTTRNRS><CCSTMTRS><CURDEF>USD</CURDEF>
        <CCACCTFROM><ACCTID>XXXXXXXXXXXX1177</ACCTID></CCACCTFROM>
        <BANKTRANLIST>
        <STMTTRN><TRNTYPE>DEBIT</TRNTYPE><DTPOSTED>20261007</DTPOSTED><TRNAMT>-59.99</TRNAMT><FITID>A-1</FITID><NAME>ADOBE CREATIVE CLD</NAME></STMTTRN>
        <STMTTRN><TRNTYPE>CREDIT</TRNTYPE><DTPOSTED>20261015</DTPOSTED><TRNAMT>500.00</TRNAMT><FITID>A-2</FITID><NAME>PAYMENT - THANK YOU</NAME></STMTTRN>
        </BANKTRANLIST>
        <LEDGERBAL><BALAMT>-1234.56</BALAMT><DTASOF>20261031</DTASOF></LEDGERBAL>
        </CCSTMTRS></CCSTMTTRNRS></CREDITCARDMSGSRSV1></OFX>
        """
        let source = OFXBankSource(text: xml, calendar: calendar)
        let statement = try source.parse()
        #expect(statement.isCreditCard && statement.accountLast4 == "1177")
        #expect(statement.lines.map(\.amount) == [-5_999, 50_000])
        #expect(statement.lines.map(\.details) == ["ADOBE CREATIVE CLD", "PAYMENT - THANK YOU"])
        #expect(statement.ledgerBalance == -123_456)
        #expect(source.kind == .ofx)
        #expect(try await source.statementLines().count == 2)
        #expect(throws: BankStatementError.notOFX) { try OFXBankSource(text: "Date,Amount").parse() }
    }
}
