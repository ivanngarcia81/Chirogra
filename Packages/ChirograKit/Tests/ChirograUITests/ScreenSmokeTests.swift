import ChirograData
import SwiftData
import SwiftUI
import Testing
@testable import ChirograUI

/// Prueba de humo: cada pantalla principal se construye con los datos de ejemplo sin fallar.
/// No es una prueba visual: `ImageRenderer` no dibuja el contenido de `ScrollView` ni de `List`.
@MainActor
@Suite("Pantallas principales")
struct ScreenSmokeTests {
    let container = SampleData.makeContainer()

    func render<V: View>(_ view: V) -> Bool {
        // Sin el inspector nativo del Mac: `ImageRenderer` no puede alojarlo (en la app sí se ve).
        ImageRenderer(content: view.environment(\.macReportInspectorEnabled, false).modelContainer(container)
            .frame(width: 390, height: 844)).nsImage != nil
    }

    @Test func home() { #expect(render(HomeView())) }
    @Test func invoices() { #expect(render(InvoiceListView(query: .constant("")))) }
    @Test func sales() { #expect(render(NavigationStack { SalesView() })) }
    @Test func ledgerBrowser() { #expect(render(NavigationStack { LedgerBrowserView() })) }
    @Test func newInvoice() { #expect(render(InvoiceEditorView())) }
    @Test func expenses() { #expect(render(ExpenseListView())) }
    @Test func reports() { #expect(render(ReportsView())) }
    @Test func chartOfAccounts() { #expect(render(ChartOfAccountsView())) }
    @Test func journalEditor() { #expect(render(JournalEntryEditorView())) }
    @Test func taxes() { #expect(render(TaxesView())) }
    @Test func onboarding() throws {
        let empty = try ChirograStore.makeContainer(inMemory: true)
        #expect(ImageRenderer(content: OnboardingView().modelContainer(empty).frame(width: 390, height: 844)).nsImage != nil)
    }
}

@MainActor
@Suite("PDF de la factura")
struct InvoicePDFTests {
    @Test("Genera un PDF tamaño carta y pagina las facturas largas")
    func pdf() throws {
        let container = SampleData.makeContainer()
        let context = container.mainContext
        let company = try context.fetch(FetchDescriptor<Company>()).first
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>()).first { $0.status != .draft })

        let data = InvoicePDF.render(invoice, company: company)
        #expect(data.starts(with: Data("%PDF".utf8)))
        // Para revisarlo a ojo: CHIROGRA_PDF_PATH=/ruta/factura.pdf swift test --filter InvoicePDFTests
        if let path = ProcessInfo.processInfo.environment["CHIROGRA_PDF_PATH"] {
            try data.write(to: URL(fileURLWithPath: path))
        }
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(document.numberOfPages == 1)
        #expect(document.page(at: 1)?.getBoxRect(.mediaBox).size == CGSize(width: 612, height: 792))

        for index in 0..<40 {
            let line = InvoiceLine(details: "Línea \(index)", unitPrice: 1_000, incomeAccountID: nil, order: 100 + index)
            line.invoice = invoice
            context.insert(line)
        }
        let long = try #require(CGPDFDocument(CGDataProvider(data: InvoicePDF.render(invoice, company: company) as CFData)!))
        #expect(long.numberOfPages == InvoicePDF.pages(for: invoice).count)
        #expect(long.numberOfPages == 3)   // 41 o 42 líneas a 16 por página
    }
}
