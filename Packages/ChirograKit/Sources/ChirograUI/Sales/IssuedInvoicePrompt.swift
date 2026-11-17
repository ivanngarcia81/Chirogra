import ChirograData
import SwiftUI

/// Después de emitir una factura: «Factura F-1001 emitida» con «Enviar a Casa Gómez» (abre `SendDocumentView`) y
/// «Ahora no». Antes, al emitir desde el editor la hoja se cerraba y no pasaba nada visible (recorrido «cliente nuevo»,
/// 5-nov). Lo usan el editor (que se cierra al terminar), el detalle del borrador y el inspector del Mac.
private struct IssuedInvoicePrompt: ViewModifier {
    @Binding var invoice: Invoice?
    /// Al terminar (con «Ahora no» o al cerrar la hoja de envío, se haya enviado o no).
    let onFinish: () -> Void
    @State private var presented = false
    @State private var sending: Invoice?

    func body(content: Content) -> some View {
        content
            .alert(Text(title), isPresented: $presented) {
                Button(sendTitle) { sending = invoice }
                Button("Ahora no", role: .cancel) { finish() }
            } message: {
                Text(message)
            }
            .sheet(item: $sending, onDismiss: finish) { invoice in
                NavigationStack { SendDocumentView(source: .invoice(invoice)) }.editorSheetSizing()
            }
            .onChange(of: invoice?.id) { _, id in if id != nil { presented = true } }
    }

    private var title: String {
        String(localized: "Factura \(invoice?.number ?? "") emitida")
    }

    private var customerName: String? {
        guard let name = invoice?.customer?.name.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        return name
    }

    private var sendTitle: String {
        customerName.map { String(localized: "Enviar a \($0)") } ?? String(localized: "Enviar al cliente")
    }

    private var message: String {
        String(localized: "Ya está en tus libros. ¿Se la mandas ahora por correo con el PDF?")
    }

    private func finish() {
        invoice = nil
        onFinish()
    }
}

extension View {
    /// Cuando `invoice` tiene una factura recién emitida, ofrece enviarla (ver `IssuedInvoicePrompt`).
    func offerToSendIssued(_ invoice: Binding<Invoice?>, onFinish: @escaping () -> Void = {}) -> some View {
        modifier(IssuedInvoicePrompt(invoice: invoice, onFinish: onFinish))
    }
}

/// Antes de emitir una factura de $0: «El total de la factura es $0.00» con «Emitir de todos modos» y «Cancelar»
/// (2.º tester de Userbrain, 16-nov: emitió una de $0 sin darse cuenta y tuvo que duplicarla). Lo usan las tres
/// pantallas que emiten: el editor, el detalle del borrador y la tabla de facturas del Mac.
private struct ZeroTotalIssueConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let issueAnyway: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("El total de la factura es \(Int64(0).money)", isPresented: $isPresented) {
                Button("Emitir de todos modos", action: issueAnyway)
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Revisa el precio de las líneas. Una factura emitida no se borra: solo se anula.")
            }
    }
}

extension View {
    /// Pregunta antes de emitir una factura cuyo total es $0 (`ZeroTotalIssueConfirmation`).
    func confirmsZeroTotalIssue(_ isPresented: Binding<Bool>, issueAnyway: @escaping () -> Void) -> some View {
        modifier(ZeroTotalIssueConfirmation(isPresented: isPresented, issueAnyway: issueAnyway))
    }
}
