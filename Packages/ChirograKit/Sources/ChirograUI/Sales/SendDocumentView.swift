import ChirograCore
import ChirograData
import SwiftData
import SwiftUI
#if canImport(MessageUI)
import MessageUI
#endif
#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif

/// Qué se manda: la factura (o el estimado) o un recordatorio de pago.
enum SendPurpose {
    case send, reminder
}

/// Enviar factura, estimado o recordatorio (canvas `FacturaEnviar`): la página del PDF, el grupo «Enviar por correo» con
/// Para, Asunto, Mensaje y «Enviarme una copia», «Compartir PDF…» e «Imprimir», y la barra con el importe y «Enviar».
/// «Enviar» abre el correo del sistema con el PDF adjunto (`MFMailComposeViewController` en el iPhone y el iPad; sin
/// cuenta de Mail, la hoja de compartir; en el Mac, el servicio de correo del sistema). Al volver con el correo enviado
/// se anota el envío (`InvoiceEvent`) o el recordatorio, y un estimado en borrador pasa a «Enviado».
struct SendDocumentView: View {
    let source: SalesDocumentSource
    var purpose: SendPurpose = .send

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    @Query private var companies: [Company]
    @State private var editorToken = EditorToken()
    @State private var recipient = ""
    @State private var subject = ""
    @State private var message = ""
    @AppStorage("sendCopyToMe") private var copyToMe = true
    @State private var pdf: InvoicePDFFile?
    @State private var width: CGFloat = 0
    @State private var loaded = false
    @State private var errorMessage: String?
    #if os(iOS)
    @State private var composingMail = false
    @State private var sharingFile: SharedFile?
    #endif

    private var company: Company? { companies.first }
    private var document: SalesDocument { source.document }
    private var companyName: String { company?.displayName ?? "" }
    private var companyEmail: String { company?.email.trimmingCharacters(in: .whitespaces) ?? "" }
    private var trimmedRecipient: String { recipient.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var title: String {
        switch (source, purpose) {
        case (.invoice, .send): String(localized: "Enviar factura")
        case (.invoice, .reminder): String(localized: "Enviar recordatorio")
        case (.estimate, _): String(localized: "Enviar estimado")
        }
    }

    /// Destinatarios del correo: los de «Para» (separados por comas) y, con «Enviarme una copia», el de la empresa.
    private var recipients: [String] {
        trimmedRecipient.split(whereSeparator: { $0 == "," || $0 == ";" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        Form {
            if let errorMessage {
                Section { ErrorBanner(message: errorMessage) }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            Section {
                preview
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
            }
            Section {
                LabeledContent("Para") {
                    TextField("Para", text: $recipient, prompt: Text("correo@cliente.com"))
                        .labelsHidden()
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .multilineTextAlignment(.leading)
                        #endif
                }
                LabeledContent("Asunto") {
                    TextField("Asunto", text: $subject).labelsHidden()
                        #if os(iOS)
                        .multilineTextAlignment(.leading)
                        #endif
                }
                TextField("Mensaje", text: $message, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityLabel("Mensaje")
                Toggle("Enviarme una copia", isOn: $copyToMe)
                    .disabled(companyEmail.isEmpty)
            } header: {
                SectionLabel(text: String(localized: "Enviar por correo"))
            } footer: {
                if companyEmail.isEmpty {
                    Text("Para recibir una copia, añade el correo de la empresa en Ajustes › Perfil de la empresa.")
                } else if copyToMe {
                    Text("La copia va a \(companyEmail). El PDF va adjunto.")
                } else {
                    Text("El PDF va adjunto.")
                }
            }
            Section {
                ShareAndPrintGroup(pdf: pdf)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .screenBackground()
        .navigationTitle(title)
        .inlineTitle()
        .discardableEditor(tracking: "\(recipient)|\(subject)|\(message)", token: editorToken)
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enviar", action: send).disabled(!canSend)
            }
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 620, idealHeight: 760)
        #else
        .bottomActionBar {
            VStack(alignment: .leading, spacing: 0) {
                Text("Para \(document.customerName.isEmpty ? String(localized: "Sin cliente") : document.customerName)")
                    .font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
                Text(document.amount.money).font(.headline).monospacedDigit().foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)
            .accessibilityElement(children: .combine)
            Button(action: send) { Label("Enviar", systemImage: "paperplane") }
                .buttonStyle(.primaryCompact)
                .disabled(!canSend)
        }
        .sheet(isPresented: $composingMail) {
            if let pdf {
                MailComposer(recipients: recipients, bcc: copyToMe && !companyEmail.isEmpty ? [companyEmail] : [],
                             subject: subject, body: message, attachment: pdf) { sent in
                    composingMail = false
                    if sent { record() }
                }
                .ignoresSafeArea()
            }
        }
        .sheet(item: $sharingFile) { file in
            ActivitySheet(items: [MailMessageItem(subject: subject, message: message), file.url]) { completed in
                sharingFile = nil
                if completed { record() }
            }
            .ignoresSafeArea()
            .presentationDetents([.medium, .large])
        }
        #endif
        .task {
            guard !loaded else { return }
            loaded = true
            fillDefaults()
            pdf = InvoicePDFFile(document: document, company: company)
            #if DEBUG
            // `-qa.pulsarEnviar 1`: pulsa «Enviar» solo, para llegar a la hoja del correo sin tocar la pantalla.
            if UserDefaults.standard.bool(forKey: "qa.pulsarEnviar") {
                try? await Task.sleep(for: .seconds(1.5))
                send()
            }
            #endif
        }
    }

    private var canSend: Bool { pdf != nil && !recipients.isEmpty && !subject.trimmingCharacters(in: .whitespaces).isEmpty }

    /// La primera página, pequeña, como en el canvas (la hoja entera está en «Compartir PDF…»).
    private var preview: some View {
        let document = document
        let pages = InvoicePDF.pages(for: document, company: company)
        return VStack(spacing: 8) {
            Color.clear.frame(height: 0).frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            DocumentPageThumbnail(document: document, company: company, lines: pages.first ?? [], pageCount: pages.count,
                                  width: min(max(width - 56, 120), 340))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Vista previa de \(document.number.isEmpty ? title : document.number)"))
            Text(pages.count == 1 ? String(localized: "Página 1 de 1 · PDF") : String(localized: "\(pages.count) páginas · PDF"))
                .font(.footnote).foregroundStyle(Palette.ink2)
        }
        .padding(.vertical, 8)
    }

    // MARK: Textos por defecto

    private func fillDefaults() {
        recipient = source.customer?.email ?? ""
        let customer = source.customer?.contactName.isEmpty == false ? source.customer?.contactName ?? "" : source.customer?.name ?? ""
        let signature = companyName.isEmpty ? "" : "\n\n\(companyName)"
        switch source {
        case .invoice(let invoice):
            if purpose == .reminder {
                subject = String(localized: "Recordatorio de pago · Factura \(invoice.number)") + (companyName.isEmpty ? "" : " · \(companyName)")
                message = invoice.reminderText + signature
            } else {
                subject = String(localized: "Factura \(invoice.number)") + (companyName.isEmpty ? "" : " · \(companyName)")
                message = String(localized: "Hola, \(customer): te enviamos la factura \(invoice.number) por \(invoice.balanceDue.money), con vencimiento el \(invoice.dueDate.dayMonth). La encontrarás adjunta en PDF.")
                    + signature
            }
        case .estimate(let estimate):
            subject = String(localized: "Estimado \(estimate.number)") + (companyName.isEmpty ? "" : " · \(companyName)")
            message = String(localized: "Hola, \(customer): te enviamos el estimado \(estimate.number) por \(estimate.total.money), válido hasta el \(estimate.expirationDate.dayMonth). Lo encontrarás adjunto en PDF.")
                + signature
        }
    }

    // MARK: Enviar

    private func send() {
        guard let pdf else { return }
        errorMessage = nil
        #if os(iOS)
        if MFMailComposeViewController.canSendMail() {
            composingMail = true
        } else if let url = pdf.temporaryURL() {
            // Sin cuenta en Mail (o en el simulador): la hoja de compartir con el PDF y el mensaje.
            sharingFile = SharedFile(url: url)
        }
        #else
        var to = recipients
        if copyToMe, !companyEmail.isEmpty, !to.contains(companyEmail) { to.append(companyEmail) }
        guard let url = pdf.temporaryURL() else { return }
        let sent = MacMailSender.compose(recipients: to, subject: subject, message: message, attachment: url) { record() }
        if !sent {
            errorMessage = String(localized: "No hay una app de correo configurada en este Mac. Usa «Compartir PDF…».")
        }
        #endif
    }

    /// Deja anotado el envío y cierra la hoja.
    private func record() {
        let books = Bookkeeper(context: context)
        let to = recipients.joined(separator: ", ")
        do {
            switch source {
            case .invoice(let invoice):
                if purpose == .reminder, invoice.isOpen {
                    try books.recordReminder(invoice, to: to, subject: subject, message: message)
                } else {
                    try books.recordInvoiceSent(invoice, to: to, subject: subject, message: message)
                }
            case .estimate(let estimate):
                if estimate.status == .draft || estimate.status == .expired {
                    try books.setStatus(.sent, of: estimate)
                }
            }
            unsavedChanges?.remove(editorToken)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Archivo que se comparte con la hoja del sistema.
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

#if os(iOS)
/// Redactor de Mail del sistema con el PDF adjunto. `onFinish(true)` si se envió (o quedó en la bandeja de salida).
struct MailComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let bcc: [String]
    let subject: String
    let body: String
    let attachment: InvoicePDFFile
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setBccRecipients(bcc)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        controller.addAttachmentData(attachment.data, mimeType: "application/pdf", fileName: attachment.filename)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result == .sent)
        }
    }
}

/// Hoja de compartir del sistema (cuando no hay cuenta de Mail). `onFinish(true)` si se completó la acción elegida.
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in onFinish(completed) }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Texto del correo para la hoja de compartir, con el asunto para Mail.
final class MailMessageItem: NSObject, UIActivityItemSource {
    let subject: String
    let message: String

    init(subject: String, message: String) {
        self.subject = subject
        self.message = message
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { message }

    func activityViewController(_ controller: UIActivityViewController, itemForActivityType type: UIActivity.ActivityType?) -> Any? {
        message
    }

    func activityViewController(_ controller: UIActivityViewController, subjectForActivityType type: UIActivity.ActivityType?) -> String {
        subject
    }
}
#endif

#if os(macOS)
/// Correo del Mac: el servicio «Redactar correo» del sistema (Mail u otra app de correo) con el PDF adjunto. El servicio
/// no admite copia oculta, así que «Enviarme una copia» añade el correo de la empresa a los destinatarios.
@MainActor
enum MacMailSender {
    private static var delegate: Delegate?

    /// `false` si no hay app de correo que pueda redactarlo.
    static func compose(recipients: [String], subject: String, message: String, attachment: URL, onSent: @escaping () -> Void) -> Bool {
        guard let service = NSSharingService(named: .composeEmail) else { return false }
        let items: [Any] = [message, attachment]
        guard service.canPerform(withItems: items) else { return false }
        service.recipients = recipients
        service.subject = subject
        let delegate = Delegate(onSent: onSent)
        self.delegate = delegate
        service.delegate = delegate
        #if DEBUG
        // `-qa.correo simular`: no abre Mail (para no tocar el correo del Mac en las pruebas); se da por enviado.
        if UserDefaults.standard.string(forKey: "qa.correo") == "simular" {
            onSent()
            return true
        }
        #endif
        service.perform(withItems: items)
        return true
    }

    private final class Delegate: NSObject, NSSharingServiceDelegate {
        let onSent: () -> Void
        init(onSent: @escaping () -> Void) { self.onSent = onSent }

        func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
            Task { @MainActor in onSent() }
        }
    }
}
#endif
