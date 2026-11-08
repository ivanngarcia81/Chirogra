import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

@MainActor
@Suite("Base caja, flujo de efectivo, presupuestos, deducibles y paquete del contador")
struct PhaseTwoReportsTests {
    let container: ModelContainer
    let books: Bookkeeper
    let today = Calendar.current.startOfDay(for: Date())

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        try books.setUpCompany(legalName: "Caja LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
    }

    var context: ModelContext { container.mainContext }

    func account(_ code: String) throws -> Account {
        try #require(try books.accounts().first { $0.code == code })
    }

    func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: today)! }

    func balance(_ code: String, _ lines: [LedgerLine], from: Date = .distantPast, to: Date = .distantFuture) throws -> Int64 {
        ReportBuilder.balance(of: try account(code).ledgerAccount, lines: lines.filter { $0.date >= from && $0.date <= to })
    }

    func taxGroup() throws -> TaxGroup {
        let agency = TaxAgency(name: "Texas Comptroller", liabilityAccountID: try account("2200").id)
        books.insert(agency)
        let rate = TaxRate(name: "Texas", rateMillionths: 82_500, agency: agency)
        books.insert(rate)
        let group = TaxGroup(name: "Austin", rates: [rate])
        books.insert(group)
        try context.save()
        return group
    }

    func issue(amount: Int64, on date: Date, tax: TaxGroup? = nil, discount: Int64 = 0) throws -> Invoice {
        let customer = Customer(name: "Cliente")
        books.insert(customer)
        let invoice = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: date, dueDate: date, taxGroupID: tax?.id, discount: discount,
                                                            lines: [.init(details: "Servicio", unitPrice: amount, incomeAccountID: try account("4000").id)]))
        try books.issue(invoice)
        return invoice
    }

    @Test("Base caja: el ingreso se reconoce al cobrar, prorrateado entre las líneas de la factura")
    func cashBasisSales() throws {
        let checking = try account("1010")
        let tax = try taxGroup()
        let paid = try issue(amount: 100_000, on: day(-60), tax: tax, discount: 10_000)   // 90 000 + 7 425 de impuesto
        let partial = try issue(amount: 50_000, on: day(-40))
        _ = try issue(amount: 70_000, on: day(-20))                                    // sin cobrar
        try books.recordPayment(for: paid, amount: paid.total, date: day(-30), depositAccount: checking)
        try books.recordPayment(for: partial, amount: 20_000, date: day(-10), depositAccount: checking)

        let accrual = try books.ledgerLines()
        let cash = try books.cashBasisLedgerLines()
        #expect(try balance("4000", accrual) == 220_000)
        #expect(try balance("4000", cash) == 100_000 + 20_000)
        #expect(try balance("4900", cash) == -10_000)                 // el descuento, también al cobrar
        #expect(try balance("2200", cash) == 7_425)
        #expect(try balance("1100", cash) == 0)                       // sin cuentas por cobrar en base caja
        #expect(try balance("1010", cash) == (try balance("1010", accrual)))
        // Por fechas: lo de la factura pagada cae el día del cobro.
        #expect(try balance("4000", cash, from: day(-31), to: day(-29)) == 100_000)
        #expect(try books.trialBalance(asOf: .distantFuture, basis: .cash).isBalanced)
        #expect(try books.balanceSheet(asOf: today, basis: .cash).isBalanced)
        #expect(try books.incomeStatement(from: day(-90), to: today, basis: .cash).netIncome == 110_000)
        #expect(try books.incomeStatement(from: day(-90), to: today, basis: .accrual).netIncome == 210_000)
    }

    @Test("Base caja: compras al pagar; gastos al momento igual; nota de crédito y reembolso")
    func cashBasisPurchasesAndCredits() throws {
        let checking = try account("1010")
        let vendor = Vendor(name: "Maderas")
        books.insert(vendor)
        let bill = Bill(vendor: vendor, vendorNumber: "B-1", billDate: day(-50))
        books.insert(bill)
        for (code, amount) in [("5000", 60_000), ("6500", 40_000)] {
            let line = BillLine(details: code, amount: Int64(amount), accountID: try account(code).id)
            line.bill = bill
            books.insert(line)
        }
        try books.record(bill)
        try books.pay(bill, amount: 25_000, date: day(-5), from: checking)
        _ = try books.createExpense(ExpenseInput(date: day(-3), payee: "Uber", paymentAccountID: checking.id,
                                                 lines: [.init(amount: 1_840, accountID: try account("6050").id)]))
        let cash = try books.cashBasisLedgerLines()
        #expect(try balance("5000", cash) == 15_000 && balance("6500", cash) == 10_000)
        #expect(try balance("2000", cash) == 0)
        #expect(try balance("6050", cash) == 1_840)

        // Factura pagada, nota de crédito sobre ella (saldo a favor) y reembolso: el ingreso neto en caja baja.
        let invoice = try issue(amount: 30_000, on: day(-30))
        try books.recordPayment(for: invoice, amount: 30_000, date: day(-29), depositAccount: checking)
        let customer = try #require(invoice.customer)
        try books.issueCreditNote(for: invoice, amount: 5_000, isTaxable: false, reason: "Devolución", date: day(-20))
        try books.refundCustomerCredit(customer, amount: 5_000, date: day(-19), from: checking)
        let after = try books.cashBasisLedgerLines()
        #expect(try balance("4000", after) == 25_000)
        #expect(try balance("1100", after) == 0)
        #expect(ReportBuilder.trialBalance(accounts: try books.ledgerAccounts(), lines: after, asOf: .distantFuture).isBalanced)
    }

    @Test("Con los datos de ejemplo: base caja y flujo de efectivo cuadran")
    func sampleBooks() throws {
        let sample = try ChirograStore.makeContainer(inMemory: true)
        try SampleData.populate(sample.mainContext)
        let books = Bookkeeper(context: sample.mainContext)
        let today = Date()
        #expect(try books.trialBalance(asOf: .distantFuture, basis: .cash).isBalanced)
        #expect(try books.balanceSheet(asOf: today, basis: .cash).isBalanced)
        let flow = try books.cashFlowStatement(from: Calendar.current.date(byAdding: .year, value: -1, to: today)!, to: today)
        #expect(flow.isReconciled)
        #expect(flow.netIncome == (try books.incomeStatement(from: flow.from, to: flow.to).netIncome))
        #expect(flow.endingCash > 0)
        // Base caja ≤ devengo en ventas (hay facturas sin cobrar).
        let cashIncome = try books.incomeStatement(from: .distantPast, to: .distantFuture, basis: .cash).totalIncome
        let accrualIncome = try books.incomeStatement(from: .distantPast, to: .distantFuture).totalIncome
        #expect(cashIncome < accrualIncome && cashIncome > 0)
    }

    @Test("Presupuestos: por mes del año fiscal, reparto anual, copia y real contra presupuesto")
    func budgets() throws {
        let company = try #require(try books.company())
        company.fiscalYearStartMonth = 7
        try context.save()
        let year = Calendar.current.component(.year, from: today)
        let budget = try books.createBudget(name: "Base", fiscalYear: year)
        let months = try books.months(ofFiscalYear: year)
        #expect(months.count == 12 && months.first?.month == 7 && months.first?.year == year && months.last?.year == year + 1)
        let sales = try account("4000")
        let supplies = try account("6500")
        try books.setAnnualBudget(1_200_001, account: sales, in: budget)
        #expect(budget.total == 1_200_001)
        #expect(budget.amount(accountID: sales.id, month: 7) == 100_001)
        try books.setBudgetAmount(5_000, account: supplies, month: 8, in: budget)
        try books.setBudgetAmount(6_000, account: supplies, month: 8, in: budget)
        #expect(budget.amount(accountID: supplies.id, month: 8) == 6_000)
        try books.setBudgetAmount(0, account: supplies, month: 8, in: budget)
        #expect((budget.lines ?? []).filter { $0.accountID == supplies.id }.isEmpty)
        #expect(throws: BookkeepingError.self) { try books.setBudgetAmount(1, account: supplies, month: 13, in: budget) }
        #expect((budget.lines ?? []).allSatisfy { $0.companyID == company.id })

        // Real: una venta en el primer mes del año fiscal.
        let first = try #require(months.first)
        _ = try issue(amount: 80_000, on: first.start.addingTimeInterval(86_400 * 3))
        let monthly = try books.budgetVsActual(budget)
        #expect(monthly.periods.count == 12)
        let row = try #require(monthly.income.first { $0.account.id == sales.id })
        #expect(row.actual[0] == 80_000 && row.budget[0] == 100_001)
        let quarterly = try books.budgetVsActual(budget, grouping: .quarter)
        #expect(quarterly.periods.count == 4 && quarterly.income.first?.budget[0] == 300_001)
        #expect(try books.budgetVsActual(budget, grouping: .year).income.first?.totalBudget == 1_200_001)

        let copy = try books.createBudget(name: "Optimista", fiscalYear: year + 1, copying: budget, factorPercent: 110)
        #expect(copy.amount(accountID: sales.id, month: 7) == 110_001)
        let fromActuals = try books.createBudget(name: "Real", fiscalYear: year + 1, fromActualsOf: year)
        #expect(fromActuals.amount(accountID: sales.id, month: first.month) == 80_000)
        #expect(try books.budgets().map(\.name) == ["Optimista", "Real", "Base"])
        try books.deleteBudget(copy)
        #expect(try context.fetch(FetchDescriptor<BudgetLine>()).allSatisfy { $0.budget != nil })
    }

    @Test("Deducibles: cada cuenta de resultados de las plantillas tiene línea en los dos formularios")
    func defaultMapping() {
        for sector in BusinessSector.allCases {
            for entry in sector.template.entries where !entry.subtype.accountType.isBalanceSheet {
                for form in TaxForm.allCases {
                    let number = TaxFormCatalog.defaultLineNumber(code: entry.code, subtype: entry.subtype, sector: sector, form: form)
                    #expect(number.flatMap { TaxFormCatalog.line($0, in: form) } != nil, "\(sector) \(entry.code) \(form)")
                }
            }
        }
        #expect(TaxFormCatalog.defaultLineNumber(code: "1010", subtype: .bank, sector: .services, form: .scheduleC) == nil)
        #expect(TaxFormCatalog.defaultLineNumber(code: "5000", subtype: .costOfGoodsSold, sector: .retail, form: .scheduleC) == "36")
        #expect(TaxFormCatalog.defaultLineNumber(code: "5000", subtype: .costOfGoodsSold, sector: .construction, form: .scheduleC) == "38")
        #expect(TaxFormCatalog.defaultLineNumber(code: "9999", subtype: .operatingExpense, sector: .services, form: .form1120S) == "20")
        #expect(TaxForm.forEntity(.llc) == .scheduleC && TaxForm.forEntity(.sCorp) == .form1120S && TaxForm.forEntity(.cCorp) == nil)
    }

    @Test("Deducibles: totales por línea, cambiar o excluir una cuenta y el formulario de la empresa")
    func taxSummary() throws {
        let checking = try account("1010")
        _ = try issue(amount: 100_000, on: day(-10))
        for (code, amount) in [("6500", 20_000), ("6650", 5_001), ("6750", 3_000)] {
            _ = try books.createExpense(ExpenseInput(date: day(-5), payee: code, paymentAccountID: checking.id,
                                                     lines: [.init(amount: Int64(amount), accountID: try account(code).id)]))
        }
        #expect(try books.taxForm() == .scheduleC)
        var summary = try books.taxSummary(from: day(-30), to: today)
        #expect(summary.total(of: "1") == 100_000 && summary.total(of: "22") == 20_000)
        #expect(summary.total(of: "24b") == 2_501 && summary.total(of: "24b", deductible: false) == 5_001)
        #expect(summary.total(of: "27b") == 3_000)
        #expect(summary.totalDeductions == 20_000 + 2_501 + 3_000)

        let software = try account("6750")
        try books.setTaxLine("scheduleC:18", for: software)
        #expect(try books.taxLine(for: software, form: .scheduleC)?.number == "18")
        try books.setTaxLine(TaxFormCatalog.none, for: try account("6650"))
        summary = try books.taxSummary(from: day(-30), to: today)
        #expect(summary.total(of: "18") == 3_000 && summary.total(of: "24b") == 0)
        #expect(summary.excluded.map(\.account.code) == ["6650"])
        #expect(throws: BookkeepingError.self) { try books.setTaxLine("scheduleC:99", for: software) }
        try books.setTaxLine(nil, for: software)
        #expect(software.taxFormLineRaw.isEmpty)

        // Una S corp usa el 1120-S; una línea elegida del otro formulario no cuenta.
        try #require(try books.company()).entityType = .sCorp
        try books.setTaxLine("scheduleC:18", for: software)
        summary = try books.taxSummary(from: day(-30), to: today)
        #expect(summary.form == .form1120S && summary.total(of: "1a") == 100_000 && summary.total(of: "20") == 23_000)
    }

    @Test("Paquete para el contador: reportes en la base pedida y sus CSV")
    func accountantPackage() throws {
        let checking = try account("1010")
        let invoice = try issue(amount: 50_000, on: day(-10))
        try books.recordPayment(for: invoice, amount: 20_000, date: day(-5), depositAccount: checking)
        let package = try books.accountantPackage(from: day(-30), to: today, basis: .cash)
        #expect(package.companyName == "Caja LLC" && package.basis == .cash)
        #expect(package.incomeStatement.totalIncome == 20_000)
        #expect(package.balanceSheet.isBalanced && package.trialBalance.isBalanced && package.cashFlow.isReconciled)
        #expect(package.taxSummary?.total(of: "1") == 20_000)
        #expect(package.files.count == 6)
        #expect(package.files.allSatisfy { $0.name.hasSuffix(".csv") && !$0.data.isEmpty })
        let journal = try #require(package.files.first { $0.contents.contains("F-1001") })
        #expect(journal.contents.split(separator: "\n").count == 1 + 4)   // cabecera + 2 asientos de 2 líneas
    }

    @Test("Sales tax por código postal: sugiere con origen o destino y crea el grupo si falta")
    func postalSalesTax() throws {
        let table = PostalTaxTable(rates: [
            PostalTaxRate(postalCode: "78702", state: "TX", region: "Austin", stateRateMillionths: 62_500, localRateMillionths: 20_000),
            PostalTaxRate(postalCode: "77002", state: "TX", region: "Houston", stateRateMillionths: 62_500, localRateMillionths: 20_000),
            PostalTaxRate(postalCode: "90012", state: "CA", region: "Los Angeles", stateRateMillionths: 72_500, localRateMillionths: 22_500),
        ])
        #expect(table.rate(for: "78702-1234")?.combinedRateMillionths == 82_500)
        #expect(PostalTaxTable.normalized("7870") == nil)
        let company = try #require(try books.company())
        let customer = Customer(name: "Cliente en Houston")
        customer.postalCode = "77002"
        books.insert(customer)
        // La empresa aún sin ZIP: la del cliente.
        #expect(try books.suggestedSalesTax(for: customer, table: table)?.basis == .destination)
        #expect(try books.suggestedSalesTax(for: nil, table: table) == nil)
        company.postalCode = "78702"
        var suggestion = try #require(try books.suggestedSalesTax(for: customer, table: table))
        #expect(suggestion.basis == .origin && suggestion.rate.region == "Austin" && suggestion.existingTaxCodeID == nil)
        customer.postalCode = "90012"
        #expect(try books.suggestedSalesTax(for: customer, table: table)?.basis == .destination)   // otro estado
        company.salesTaxSourcing = .destination
        customer.postalCode = "77002"
        suggestion = try #require(try books.suggestedSalesTax(for: customer, table: table))
        #expect(suggestion.rate.region == "Houston")

        let code = try books.createTaxCode(for: suggestion)
        #expect(code.name == "Houston, TX" && code.rateMillionths == 82_500 && code.rates.count == 2)
        #expect(try books.suggestedSalesTax(for: customer, table: table)?.existingTaxCodeID == code.id)
        #expect(try books.createTaxCode(for: suggestion).id == code.id)
        #expect(try #require(try books.company()).defaultTaxGroupID == nil)
        #expect(try books.fetch(TaxAgency.self).count == 1)
    }

    @Test("Enlace de pago: plantilla con importe, número y cliente; solo con saldo pendiente")
    func paymentLink() throws {
        let invoice = try issue(amount: 125_050, on: day(-1))
        #expect(try books.paymentLink(for: invoice) == nil)
        #expect(throws: BookkeepingError.self) { try books.setPaymentSettings(link: "no es una url", instructions: "", showPayNow: true) }
        try books.setPaymentSettings(link: "https://paypal.me/riosdiseno/{amount}?note={number}%20{customer}", instructions: "Zelle a pagos@rios.com",
                                     showPayNow: true)
        #expect(try books.paymentLink(for: invoice)?.absoluteString == "https://paypal.me/riosdiseno/1250.50?note=F-1001%20Cliente")
        try books.setPaymentSettings(link: "https://buy.stripe.com/abc", instructions: "", showPayNow: false)
        #expect(try books.paymentLink(for: invoice) == nil)
        try books.setPaymentSettings(link: "https://buy.stripe.com/abc", instructions: "", showPayNow: true)
        try books.recordPayment(for: invoice, amount: invoice.balanceDue, depositAccount: try account("1010"))
        #expect(try books.paymentLink(for: invoice) == nil)
        #expect(PaymentLinkTemplate.url("https://x.com/pay?c={customer}", amount: 1, number: "F-1", customer: "A&B Co")?.absoluteString
                == "https://x.com/pay?c=A%26B%20Co")
    }
}
