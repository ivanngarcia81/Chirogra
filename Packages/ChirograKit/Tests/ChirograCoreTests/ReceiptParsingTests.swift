import Foundation
import Testing
@testable import ChirograCore

/// Recibos de ejemplo (inventados, con la forma que les da el texto leído por Vision: un renglón por línea del papel).
@Suite("Lectura de recibos por reglas")
struct ReceiptParsingTests {
    let calendar = Calendar(identifier: .gregorian)
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12))! }

    func day(_ year: Int, _ month: Int, _ day: Int) -> DateComponents { DateComponents(year: year, month: month, day: day) }
    func components(_ date: Date?) -> DateComponents? {
        date.map { calendar.dateComponents([.year, .month, .day], from: $0) }
    }

    @Test("Ferretería con subtotal, impuesto con % y total; fecha día/mes")
    func hardwareStore() {
        let text = """
        THE HOME DEPOT
        #4410 · AUSTIN, TX
        29/10/2026 14:32
        TORNILLO 2" X100   12.98
        BISAGRA OCULTA X6  38.40
        TABLERO MDF 18MM  146.00
        BARNIZ MATE 1GAL   65.13
        SUBTOTAL  262.51
        TAX 8.25%  21.66
        TOTAL  284.17
        VISA ••1177
        """
        let result = ReceiptRules.parse(text: text, now: now)
        #expect(result.merchant == "The Home Depot")
        #expect(result.total == 28_417)
        #expect(result.salesTax == 2_166)
        #expect(components(result.date) == day(2026, 10, 29))
        #expect(result.categoryHint == .materials)
    }

    @Test("Restaurante: el total con propina va después del subtotal y el impuesto; fecha con el mes en letras")
    func restaurant() {
        let lines = [
            "Café Aurora", "1200 E 6th St", "Austin, TX 78702", "Tel (512) 555-0100",
            "Oct 30, 2026  7:45 PM", "Server: Ana   Table 4",
            "2 Tacos al pastor    14.00", "1 Agua fresca    3.50",
            "Subtotal    17.50", "Sales Tax    1.44", "Total    18.94", "Tip    3.00", "Amount Paid   $21.94",
        ]
        let result = ReceiptRules.parse(lines: lines, now: now)
        #expect(result.merchant == "Café Aurora")
        // «Amount paid» manda sobre «Total»: es lo que salió de la cuenta.
        #expect(result.total == 2_194)
        #expect(result.salesTax == 144)
        #expect(components(result.date) == day(2026, 10, 30))
        #expect(result.categoryHint == .meals)
    }

    @Test("Gasolinera: impuesto incluido en el precio (no hay renglón de impuesto) y fecha mes/día/año corto")
    func gasStation() {
        let text = """
        SHELL
        4501 S CONGRESS AVE
        11/02/26  08:12
        PUMP 07 UNLEADED
        12.441 GAL @ 3.059
        FUEL TOTAL  $38.06
        CREDIT  38.06
        """
        let result = ReceiptRules.parse(text: text, now: now)
        #expect(result.merchant == "Shell")
        #expect(result.total == 3_806)
        #expect(result.salesTax == nil)
        #expect(components(result.date) == day(2026, 11, 2))
        #expect(result.categoryHint == .vehicle)
    }

    @Test("Total en el renglón siguiente, varios impuestos que se suman y fecha ISO")
    func totalOnNextLine() {
        let text = """
        Office Depot Store 1023
        2026-09-15
        Copy paper 10 ream   54.90
        Toner HP 26A        129.99
        SUBTOTAL 184.89
        STATE TAX 11.56
        CITY TAX 3.70
        TOTAL
        $200.15
        """
        let result = ReceiptRules.parse(text: text, now: now)
        #expect(result.merchant == "Office Depot")
        #expect(result.total == 20_015)
        #expect(result.salesTax == 1_526)
        #expect(components(result.date) == day(2026, 9, 15))
        #expect(result.categoryHint == .office)
    }

    @Test("«Total tax» manda sobre los impuestos por partes; «Total savings» no es el total")
    func totalTaxAndSavings() {
        let lines = ["TARGET", "Expect More. Pay Less.", "10/05/2026", "SUBTOTAL 50.00", "TX STATE 3.13",
                     "TX LOCAL 1.00", "TOTAL TAX 4.13", "TOTAL SAVINGS 5.00", "TOTAL 54.13"]
        let result = ReceiptRules.parse(lines: lines, now: now)
        #expect(result.total == 5_413)
        #expect(result.salesTax == 413)
        #expect(result.merchant == "Target")
    }

    @Test("Recibo en español con coma decimal")
    func spanishCommaDecimals() {
        let text = """
        Ferretería El Clavo
        Fecha: 3 de noviembre de 2026
        Clavos 2,50
        Martillo 18,90
        IMPUESTO 1,77
        TOTAL A PAGAR 23,17
        """
        let result = ReceiptRules.parse(text: text, now: now)
        #expect(result.merchant == "Ferretería El Clavo")
        #expect(result.total == 2_317)
        #expect(result.salesTax == 177)
        #expect(components(result.date) == day(2026, 11, 3))
    }

    @Test("Sin palabra de total: el importe mayor; fechas imposibles o del futuro no valen")
    func fallbacks() {
        let lines = ["Joe's Lumber Yard", "Date 13/45/2026", "12/31/2027", "2x4 stud 8ft  4.25", "Plywood  38.75", "Paid  43.00"]
        let result = ReceiptRules.parse(lines: lines, now: now)
        #expect(result.total == 4_300)
        #expect(result.date == nil)
        #expect(result.merchant == "Joe's Lumber Yard")
        #expect(result.categoryHint == .materials)
    }

    @Test("El impuesto nunca es mayor que el total ni se toma un porcentaje por importe")
    func taxSanity() {
        #expect(ReceiptRules.amounts(in: "TAX 8.25% 21.66") == [2_166])
        #expect(ReceiptRules.amounts(in: "Tel 512.555.0100 14:32") == [])
        #expect(ReceiptRules.amounts(in: "TOTAL $1,234.56") == [123_456])
        #expect(ReceiptRules.amounts(in: "Descuento -3.50") == [-350])
        let result = ReceiptRules.parse(lines: ["Shop", "TAX 99.00", "TOTAL 10.00"], now: now)
        #expect(result.total == 1_000)
        #expect(result.salesTax == nil)
    }

    @Test("Comercio: se salta el saludo, la dirección y el teléfono; el nombre se compara sin «The», «Inc» ni signos")
    func merchantCleanup() {
        let result = ReceiptRules.parse(lines: ["Welcome to", "1500 Main St", "LOWE'S HOME CENTERS, LLC", "TOTAL 9.99"], now: now)
        #expect(result.merchant == "Lowe's Home Centers, LLC")
        #expect(ReceiptRules.comparableName("THE HOME DEPOT #4410") == "home depot")
        #expect(ReceiptRules.comparableName("Home Depot Inc.") == "home depot")
        #expect(ReceiptRules.comparableName("Café Aurora, LLC") == "cafe aurora")
    }

    @Test("Un texto sin recibo no inventa nada")
    func emptyText() {
        let result = ReceiptRules.parse(text: "", now: now)
        #expect(result == ReceiptRuleResult())
    }
}
