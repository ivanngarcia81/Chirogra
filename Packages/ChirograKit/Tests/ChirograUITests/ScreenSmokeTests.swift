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
        ImageRenderer(content: view.modelContainer(container).frame(width: 390, height: 844)).nsImage != nil
    }

    @Test func home() { #expect(render(HomeView())) }
    @Test func invoices() { #expect(render(InvoiceListView())) }
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
