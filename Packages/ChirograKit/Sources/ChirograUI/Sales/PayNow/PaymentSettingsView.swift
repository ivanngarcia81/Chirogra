import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Ajustes › Cobro en línea: el enlace de pago propio y las instrucciones que salen en la factura (PDF y correo), con
/// la vista previa del recuadro «Pagar ahora». Se guarda con `Bookkeeper.setPaymentSettings` (valida que el enlace sea
/// una dirección web) al pulsar «Guardar» y al salir, si es válido. El cobro se registra a mano.
struct PaymentSettingsView: View {
    @Bindable var company: Company
    /// Dentro de `SettingsWideView`: el título de la ventana sigue siendo «Ajustes».
    var embedded = false
    @Environment(\.modelContext) private var context
    @State private var link = ""
    @State private var instructions = ""
    @State private var showPayNow = true
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var linkIsValid: Bool {
        trimmedLink.isEmpty || PaymentLinkTemplate.url(trimmedLink, amount: 100, number: "F-1001", customer: "Cliente") != nil
    }
    private var hasChanges: Bool {
        loaded && (trimmedLink != company.paymentLinkURL || instructions != company.paymentInstructions
                   || showPayNow != company.showPayNowOnInvoice)
    }

    /// El recuadro con una factura de ejemplo por $2,558.05.
    private var previewInfo: PayNowInfo? {
        PayNowInfo.preview(link: linkIsValid ? trimmedLink : "", instructions: instructions, amount: 255_805,
                           number: "F-1049", customer: "Café Aurora")
    }

    var body: some View {
        SettingsForm {
            if let errorMessage {
                SettingsSection(plain: true) { ErrorBanner(message: errorMessage) }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            SettingsSection {
                #if os(macOS)
                LabeledContent("Enlace de pago") {
                    TextField("Enlace de pago", text: $link, prompt: Text(verbatim: "https://buy.stripe.com/…"))
                        .textFieldStyle(.plain)
                        .labelsHidden()
                        .foregroundStyle(Palette.ink)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                }
                #else
                TextField("Enlace de pago", text: $link, prompt: Text(verbatim: "https://buy.stripe.com/…"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel(Text("Enlace de pago"))
                #endif
                Toggle("Mostrar «Pagar ahora» en las facturas", isOn: $showPayNow)
            } header: {
                SectionLabel(text: String(localized: "Enlace de pago"))
            } footer: {
                if !linkIsValid {
                    Text("El enlace de pago debe ser una dirección web (https://…).").foregroundStyle(Palette.negative)
                } else {
                    Text("Pega el enlace de tu Stripe Payment Link, Square, PayPal.me u otro. Si tu servicio lo admite, escribe {amount}, {number} o {customer} y cada factura pondrá su saldo, su número y el cliente. Sin «Pagar ahora», la factura no lleva ni el enlace ni las instrucciones.")
                }
            }
            SettingsSection {
                SettingsTextArea(title: "Instrucciones de pago", text: $instructions,
                                 prompt: Text("Ej.: Zelle a pagos@tuempresa.com · Transferencia a la cuenta 1234 del banco…"),
                                 lines: 2...6)
            } header: {
                SectionLabel(text: String(localized: "Instrucciones"))
            } footer: {
                Text("Salen como texto en el PDF de la factura y en el correo.")
            }
            SettingsSection {
                if showPayNow, let previewInfo {
                    PayNowBlock(info: previewInfo, accent: InvoiceTemplate(company: company).accent,
                                soft: InvoiceTemplate(company: company).soft)
                        .foregroundStyle(Color(red: 0.07, green: 0.08, blue: 0.17))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .environment(\.colorScheme, .light)
                        .accessibilityElement(children: .combine)
                } else {
                    Text(showPayNow ? "Añade un enlace o unas instrucciones para ver cómo quedan." : "Las facturas no llevarán el recuadro de pago.")
                        .foregroundStyle(Palette.ink2)
                }
            } header: {
                SectionLabel(text: String(localized: "Vista previa en la factura"))
            } footer: {
                Text("El dinero va directo a tu cuenta de ese servicio; Chirogra no lo toca. Cuando te paguen, registra el cobro en la factura con «Registrar pago».")
            }
            SettingsSection(plain: true) {
                Button(savedMessage ?? String(localized: "Guardar"), action: save)
                    .buttonStyle(.primary)
                    .disabled(!hasChanges || !linkIsValid)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .toggleStyle(.switch)
        .screenBackground()
        .modifier(PaymentTitle(embedded: embedded))
        .onAppear {
            guard !loaded else { return }
            link = company.paymentLinkURL
            instructions = company.paymentInstructions
            showPayNow = company.showPayNowOnInvoice
            loaded = true
            #if DEBUG
            // `-qa.enlacePago <url>` y `-qa.instruccionesPago <texto>` (solo Debug): los escribe y guarda sin teclado.
            let defaults = UserDefaults.standard
            if let qaLink = defaults.string(forKey: "qa.enlacePago") { link = qaLink }
            if let qaText = defaults.string(forKey: "qa.instruccionesPago") { instructions = qaText }
            if defaults.string(forKey: "qa.enlacePago") != nil || defaults.string(forKey: "qa.instruccionesPago") != nil { save() }
            #endif
        }
        .onChange(of: hasChanges) { _, changed in if changed { savedMessage = nil } }
        .onDisappear { if hasChanges && linkIsValid { save() } }
    }

    private func save() {
        do {
            try Bookkeeper(context: context, companyID: company.id)
                .setPaymentSettings(link: trimmedLink, instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
                                    showPayNow: showPayNow)
            link = company.paymentLinkURL
            instructions = company.paymentInstructions
            errorMessage = nil
            savedMessage = String(localized: "Guardado ✓")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PaymentTitle: ViewModifier {
    let embedded: Bool
    func body(content: Content) -> some View {
        if embedded { content } else { content.navigationTitle("Cobro en línea").inlineTitle() }
    }
}
