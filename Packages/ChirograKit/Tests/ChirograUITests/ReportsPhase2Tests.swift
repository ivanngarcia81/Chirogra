import ChirograCore
import ChirograData
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import ChirograUI

/// Pantallas de reportes de la fase 2 (1.3): flujo de efectivo, base caja/devengado, presupuestos, deducibles y el
/// paquete para el contador.
@MainActor
@Suite("Reportes de la fase 2", .serialized)
struct ReportsPhase2Tests {
    let container = SampleData.makeContainer()
    var context: ModelContext { container.mainContext }

    func render<V: View>(_ view: V) -> Bool {
        ImageRenderer(content: view.environment(\.macReportInspectorEnabled, false).modelContainer(container)
            .frame(width: 390, height: 844)).nsImage != nil
    }

    // MARK: Pantallas

    @Test func cashFlowScreen() { #expect(render(NavigationStack { ReportsView(fixedKind: .cashFlow) })) }
    @Test func budgetScreen() { #expect(render(NavigationStack { ReportsView(fixedKind: .budget) })) }
    @Test func deductionsScreen() { #expect(render(NavigationStack { DeductionsView() })) }
    @Test func deductionsTab() { #expect(render(NavigationStack { TaxesView(tab: .deductions) })) }
    @Test func exportSheet() { #expect(render(NavigationStack { AccountantExportView() })) }
    @Test func budgetEditors() throws {
        let books = Bookkeeper(context: context)
        let budget = try #require(try books.budgets().first)
        let account = try #require(try books.accounts().first { $0.type == .expense })
        #expect(render(NavigationStack { BudgetEditorView(budget: budget) }))
        #expect(render(NavigationStack { BudgetAccountEditor(budget: budget, account: account) }))
        #expect(render(NavigationStack { BudgetCreateView(budgets: [budget], suggestedYear: budget.fiscalYear) { _ in } }))
        #expect(render(NavigationStack { TaxLinePickerView(account: account, form: .scheduleC) }))
    }

    // MARK: Base caja / devengado

    @Test("La base se recuerda por empresa, sin mezclar una con otra")
    func basisPerCompany() {
        let first = UUID(), second = UUID()
        var raw = ""
        #expect(ReportBasisStore.basis(in: raw, company: first) == nil)
        raw = ReportBasisStore.storing(.cash, in: raw, company: first)
        raw = ReportBasisStore.storing(.accrual, in: raw, company: second)
        #expect(ReportBasisStore.basis(in: raw, company: first) == .cash)
        #expect(ReportBasisStore.basis(in: raw, company: second) == .accrual)
        raw = ReportBasisStore.storing(.accrual, in: raw, company: first)
        #expect(ReportBasisStore.basis(in: raw, company: first) == .accrual)
        #expect(raw.components(separatedBy: first.uuidString).count == 2)   // una sola entrada por empresa
        #expect(ReportBasisStore.storing(.cash, in: raw, company: nil) == raw)
    }

    @Test("En devengo las cifras son las de siempre; en caja cambian y la balanza sigue cuadrando")
    func basisFigures() throws {
        let books = Bookkeeper(context: context)
        let year = try #require(Calendar.current.dateInterval(of: .year, for: .now))
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let lines = try context.fetch(FetchDescriptor<JournalLine>())
        // La vista calcula el devengo con `Ledger` (lo de antes de la fase 2): mismas cifras que `Bookkeeper`.
        let screen = Ledger(accounts: accounts, lines: lines).incomeStatement(year)
        let accrual = try books.incomeStatement(from: year.start, to: year.end, basis: .accrual)
        #expect(screen.netIncome == accrual.netIncome)
        #expect(screen.totalIncome == accrual.totalIncome)
        let cash = try books.incomeStatement(from: year.start, to: year.end, basis: .cash)
        #expect(cash.totalIncome != accrual.totalIncome)   // los datos de ejemplo tienen facturas sin cobrar
        #expect(try books.trialBalance(asOf: .now, basis: .cash).isBalanced)
        #expect(try books.balanceSheet(asOf: .now, basis: .cash).isBalanced)
    }

    // MARK: Flujo de efectivo

    @Test("El flujo presentado suma lo mismo que el estado: secciones, totales y conciliación con el efectivo")
    func cashFlowLayout() throws {
        let books = Bookkeeper(context: context)
        let year = try #require(Calendar.current.dateInterval(of: .year, for: .now))
        for basis in AccountingBasis.allCases {
            let report = ReportBuilder.cashFlow(accounts: try books.ledgerAccounts(), lines: try books.ledgerLines(basis: basis),
                                                from: year.start, to: year.end)
            #expect(report.isReconciled)
            let sections = CashFlowLayout.sections(report)
            #expect(sections.count == 4)
            let operating = sections[0].lines
            #expect(operating.filter { $0.style == .line }.reduce(0) { $0 + $1.amount } == report.operatingTotal)
            #expect(operating.last?.amount == report.operatingTotal)
            #expect(sections[3].lines.map(\.amount) == [report.netCashChange, report.beginningCash, report.endingCash])
            #expect(Set(sections.flatMap(\.lines).map(\.id)).count == sections.flatMap(\.lines).count)   // claves únicas
        }
    }

    // MARK: PDF

    @Test("El PDF pagina los reportes largos y lleva la portada")
    func pdf() throws {
        let rows = (0..<100).map { ReportDocument.Row(label: "Cuenta \($0)", values: ["$1.00"]) }
        let document = ReportDocument(title: "Prueba", subtitle: "2026", columns: ["2026"], rows: rows)
        let pages = ReportPDF.pages(for: document)
        #expect(pages.count == 3)
        #expect(pages.flatMap { $0 }.count == 100)
        let cover = ReportCover(title: "Paquete", period: "2026", basis: "base caja", contents: ["Prueba"], note: "Aviso")
        let data = ReportPDF.render([document], companyName: "Empresa", cover: cover)
        #expect(data.starts(with: Data("%PDF".utf8)))
        let pdf = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(pdf.numberOfPages == 4)
        #expect(pdf.page(at: 1)?.getBoxRect(.mediaBox).size == ReportPDF.pageSize)
        #expect(ReportPDF.pages(for: ReportDocument(title: "Vacío", subtitle: "", columns: [], rows: [])).count == 1)
    }

    // MARK: Paquete para el contador

    @Test("El paquete escribe el PDF y los CSV en una carpeta y la comprime", arguments: AccountingBasis.allCases)
    func package(basis: AccountingBasis) throws {
        let books = Bookkeeper(context: context)
        let year = try #require(Calendar.current.dateInterval(of: .year, for: .now))
        let to = year.end.addingTimeInterval(-1)
        let package = try books.accountantPackage(from: year.start, to: to, basis: basis)
        let cashFlow = ReportBuilder.cashFlow(accounts: try books.ledgerAccounts(), lines: try books.ledgerLines(basis: basis),
                                              from: year.start, to: to)
        let parent = FileManager.default.temporaryDirectory.appending(path: "chirogra-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: parent) }
        let prepared = try AccountantPackageWriter.prepare(package, cashFlow: cashFlow, currency: "USD", in: parent)
        let names = try FileManager.default.contentsOfDirectory(atPath: prepared.folder.path(percentEncoded: false))
        #expect(Set(names) == Set(prepared.files))
        #expect(names.contains { $0.hasSuffix(".pdf") })
        #expect(names.filter { $0.hasSuffix(".csv") }.count == package.files.count)
        let pdf = try Data(contentsOf: prepared.folder.appending(path: prepared.files[0]))
        #expect(pdf.starts(with: Data("%PDF".utf8)))
        let zip = try #require(prepared.zip)
        let zipData = try Data(contentsOf: zip)
        #expect(zipData.starts(with: Data([0x50, 0x4B])))   // «PK»
        // El CSV del flujo va en la base elegida, como el PDF.
        let flow = try String(contentsOf: prepared.folder.appending(path: String(localized: "Flujo de efectivo") + ".csv"), encoding: .utf8)
        #expect(flow == CSVExport.cashFlow(cashFlow))
    }

    @Test("Los nombres de la carpeta y los archivos no llevan barras ni dos puntos")
    func safeNames() {
        #expect(AccountantPackageWriter.safeName("Ríos/Obra: 2026") == "Ríos-Obra- 2026")
        let name = AccountantPackageWriter.folderName(company: "A/B", from: .now, to: .now)
        #expect(!name.contains("/") && !name.contains(":"))
    }

    // MARK: Deducibles

    @Test("Cambiar la línea de una cuenta mueve su importe y «Sugerida» la devuelve")
    func taxLineChoice() throws {
        let books = Bookkeeper(context: context)
        let year = try #require(Calendar.current.dateInterval(of: .year, for: .now))
        let before = try books.taxSummary(from: year.start, to: year.end, form: .scheduleC)
        let row = try #require(before.rows.first { $0.line.kind == .deduction && !$0.accounts.isEmpty })
        let item = try #require(row.accounts.first)
        let account = try #require(try books.accounts().first { $0.id == item.account.id })
        #expect(TaxLineChoice.current(for: account, form: .scheduleC) == TaxLineChoice.suggested)
        let target = row.line.number == "27b" ? "scheduleC:18" : "scheduleC:27b"
        try books.setTaxLine(target, for: account)
        #expect(TaxLineChoice.current(for: account, form: .scheduleC) == target)
        #expect(TaxLineChoice.current(for: account, form: .form1120S) == TaxLineChoice.suggested)   // otra línea de otro formulario
        let after = try books.taxSummary(from: year.start, to: year.end, form: .scheduleC)
        #expect(after.rows.first { $0.id == target }?.accounts.contains { $0.account.id == account.id } == true)
        try books.setTaxLine(TaxFormCatalog.none, for: account)
        #expect(try books.taxSummary(from: year.start, to: year.end, form: .scheduleC).excluded.contains { $0.account.id == account.id })
        try books.setTaxLine(nil, for: account)
        #expect(TaxLineChoice.current(for: account, form: .scheduleC) == TaxLineChoice.suggested)
    }

    @Test("El periodo de los deducibles: del primer día al último instante")
    func deductionsPeriod() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 8)))
        let year = DeductionsPeriod.yearToDate.range(calendar: calendar, now: now)
        #expect(calendar.dateComponents([.year, .month, .day], from: year.from) == DateComponents(year: 2026, month: 1, day: 1))
        #expect(calendar.dateComponents([.year, .month, .day], from: year.to) == DateComponents(year: 2026, month: 11, day: 8))
        let quarter = DeductionsPeriod.lastQuarter.range(calendar: calendar, now: now)
        #expect(calendar.component(.month, from: quarter.from) == 7)
        #expect(calendar.component(.month, from: quarter.to) == 9)
    }
}
