import Foundation
import Testing
@testable import ChirograCore

@Suite("Reglas de contabilización")
struct PostingRulesTests {
    let receivable = UUID()
    let payable = UUID()
    let bank = UUID()
    let design = UUID()
    let materials = UUID()
    let supplies = UUID()
    let rent = UUID()
    let texasTax = UUID()
    let austinTax = UUID()
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    let validator = JournalValidator()

    var austin: [TaxComponent] {
        [
            TaxComponent(name: "Texas", rateMillionths: 62_500, liabilityAccountID: texasTax),
            TaxComponent(name: "Austin", rateMillionths: 10_000, liabilityAccountID: austinTax),
            TaxComponent(name: "Austin MTA", rateMillionths: 10_000, liabilityAccountID: austinTax),
        ]
    }

    @Test("Factura con sales tax: débitos = créditos y cuentas correctas")
    func invoiceWithTax() throws {
        let posting = try PostingRules.invoice(
            date: date, memo: "F-1047", receivableAccountID: receivable,
            lines: [
                SalesLine(incomeAccountID: design, amount: 200_000),
                SalesLine(incomeAccountID: materials, amount: 40_000),
                SalesLine(incomeAccountID: design, amount: 10_000, isTaxable: false),
            ],
            taxComponents: austin
        )
        // 8.25 % sobre 2,400.00 gravables = 198.00
        #expect(posting.subtotal == 250_000)
        #expect(posting.taxableSubtotal == 240_000)
        #expect(posting.totalTax == 19_800)
        #expect(posting.total == 269_800)

        let entry = posting.entry
        try validator.validate(entry)
        #expect(entry.totalDebits == entry.totalCredits)
        #expect(entry.lines.first == .debit(receivable, 269_800))
        #expect(entry.lines.contains(.credit(design, 210_000)))
        #expect(entry.lines.contains(.credit(materials, 40_000)))
        #expect(entry.lines.contains(.credit(texasTax, 15_000)))
        #expect(entry.lines.contains(.credit(austinTax, 4_800)))
    }

    @Test("Cliente exento: sin impuesto")
    func exemptCustomer() throws {
        let posting = try PostingRules.invoice(
            date: date, memo: "F-1", receivableAccountID: receivable,
            lines: [SalesLine(incomeAccountID: design, amount: 99_999)],
            taxComponents: austin, customerIsTaxExempt: true
        )
        #expect(posting.totalTax == 0)
        #expect(posting.entry.lines.count == 2)
        try validator.validate(posting.entry)
    }

    @Test("Nota de crédito: inverso exacto de la factura")
    func creditNote() throws {
        let lines = [SalesLine(incomeAccountID: design, amount: 12_345)]
        let invoice = try PostingRules.invoice(date: date, memo: "F", receivableAccountID: receivable, lines: lines, taxComponents: austin)
        let credit = try PostingRules.creditNote(date: date, memo: "NC", receivableAccountID: receivable, lines: lines, taxComponents: austin)
        try validator.validate(credit.entry)
        #expect(credit.entry.lines == invoice.entry.lines.map(\.swapped))
        #expect(credit.entry.source == .creditNote)
    }

    @Test("Cobro, factura de proveedor, pago y gasto generan asientos cuadrados")
    func otherDocuments() throws {
        let entries = [
            try PostingRules.paymentReceived(date: date, memo: "Cobro", amount: 269_800, depositAccountID: bank, receivableAccountID: receivable),
            try PostingRules.bill(date: date, memo: "B-221", payableAccountID: payable, lines: [
                CostLine(accountID: supplies, amount: 84_230), CostLine(accountID: rent, amount: 120_000),
            ]),
            try PostingRules.billPayment(date: date, memo: "Pago B-221", amount: 204_230, payableAccountID: payable, paymentAccountID: bank),
            try PostingRules.expense(date: date, memo: "Uber", paymentAccountID: bank, lines: [CostLine(accountID: supplies, amount: 1_840)]),
            try PostingRules.salesTaxPayment(date: date, memo: "Texas Q3", amount: 19_800, liabilityAccountID: texasTax, paymentAccountID: bank),
        ]
        for entry in entries {
            #expect(entry.totalDebits == entry.totalCredits, "\(entry.memo) descuadrado")
            try validator.validate(entry)
        }
        #expect(entries[1].lines.last == .credit(payable, 204_230))
    }

    @Test("Documentos sin líneas, con importes no positivos o a la misma cuenta se rechazan")
    func invalidDocuments() {
        #expect(throws: PostingError.noLines) {
            try PostingRules.invoice(date: date, memo: "", receivableAccountID: receivable, lines: [], taxComponents: [])
        }
        #expect(throws: PostingError.nonPositiveAmount) {
            try PostingRules.expense(date: date, memo: "", paymentAccountID: bank, lines: [CostLine(accountID: rent, amount: 0)])
        }
        #expect(throws: PostingError.sameAccount) {
            try PostingRules.paymentReceived(date: date, memo: "", amount: 1, depositAccountID: bank, receivableAccountID: bank)
        }
    }

    @Test("Propiedad: miles de documentos aleatorios siempre cuadran", arguments: [7, 42, 2026])
    func randomDocumentsAlwaysBalance(seed: UInt64) throws {
        var rng = SeededGenerator(seed: seed)
        let incomeAccounts = [design, materials]
        let costAccounts = [supplies, rent]
        for _ in 0..<1_000 {
            let lines = (0..<Int.random(in: 1...6, using: &rng)).map { _ in
                SalesLine(incomeAccountID: incomeAccounts.randomElement(using: &rng)!,
                          amount: Int64.random(in: 1...5_000_000, using: &rng),
                          isTaxable: Bool.random(using: &rng))
            }
            let components = (0..<Int.random(in: 0...4, using: &rng)).map { _ in
                TaxComponent(name: "t", rateMillionths: Int64.random(in: 0...100_000, using: &rng),
                             liabilityAccountID: [texasTax, austinTax].randomElement(using: &rng)!)
            }
            let invoice = try PostingRules.invoice(date: date, memo: "", receivableAccountID: receivable,
                                                   lines: lines, taxComponents: components)
            #expect(invoice.entry.isBalanced)
            #expect(validator.isValid(invoice.entry))

            let costs = (0..<Int.random(in: 1...5, using: &rng)).map { _ in
                CostLine(accountID: costAccounts.randomElement(using: &rng)!, amount: Int64.random(in: 1...900_000, using: &rng))
            }
            let expense = try PostingRules.expense(date: date, memo: "", paymentAccountID: bank, lines: costs)
            #expect(expense.isBalanced)
        }
    }
}

/// Generador determinista (SplitMix64) para que las pruebas aleatorias sean reproducibles.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("Descuento en facturas")
struct InvoiceDiscountTests {
    let receivable = UUID(), discountAccount = UUID(), services = UUID(), materials = UUID(), tax = UUID()
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    var texas: [TaxComponent] { [TaxComponent(name: "TX", rateMillionths: 82_500, liabilityAccountID: tax)] }

    @Test("El descuento reduce la base gravable en proporción y el asiento cuadra")
    func discountBeforeTax() throws {
        // $1,800 de servicio no gravable + $200 de materiales gravables; descuento de $100 (5 %).
        let posting = try PostingRules.invoice(
            date: date, memo: "", receivableAccountID: receivable,
            lines: [SalesLine(incomeAccountID: services, amount: 180_000, isTaxable: false),
                    SalesLine(incomeAccountID: materials, amount: 20_000, isTaxable: true)],
            taxComponents: texas, discount: 10_000, discountAccountID: discountAccount
        )
        #expect(posting.taxableSubtotal == 20_000)
        #expect(posting.taxableBase == 19_000)      // 200 − 5 % de 200
        #expect(posting.totalTax == 1_568)          // 8.25 % de 190.00 = 15.675 → 15.68
        #expect(posting.total == 200_000 - 10_000 + 1_568)
        #expect(posting.entry.isBalanced)
        #expect(posting.entry.lines.contains(.debit(discountAccount, 10_000)))
        #expect(posting.entry.lines.contains(.credit(services, 180_000)))
        try JournalValidator().validate(posting.entry)
    }

    @Test("Descuento total: sin cuenta por cobrar y aún cuadrado")
    func fullDiscount() throws {
        let posting = try PostingRules.invoice(date: date, memo: "", receivableAccountID: receivable,
                                               lines: [SalesLine(incomeAccountID: services, amount: 5_000)],
                                               taxComponents: texas, discount: 5_000, discountAccountID: discountAccount)
        #expect(posting.total == 0)
        #expect(posting.entry.lines == [.debit(discountAccount, 5_000), .credit(services, 5_000)])
    }

    @Test("Descuento mayor que el subtotal, negativo o sin cuenta se rechaza", arguments: [Int64(5_001), -1])
    func invalidDiscount(discount: Int64) {
        #expect(throws: PostingError.invalidDiscount) {
            try PostingRules.invoice(date: date, memo: "", receivableAccountID: receivable,
                                     lines: [SalesLine(incomeAccountID: services, amount: 5_000)],
                                     taxComponents: [], discount: discount, discountAccountID: discountAccount)
        }
        #expect(throws: PostingError.invalidDiscount) {
            try PostingRules.invoice(date: date, memo: "", receivableAccountID: receivable,
                                     lines: [SalesLine(incomeAccountID: services, amount: 5_000)],
                                     taxComponents: [], discount: 100)
        }
    }
}
