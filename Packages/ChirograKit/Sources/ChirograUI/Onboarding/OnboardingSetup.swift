import ChirograCore
import ChirograData
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Idioma de la app

/// Idioma en que se ve la app y cómo cambiarlo. La app no fuerza el idioma por código (`AppleLanguages`): el cambio
/// solo se aplica al volver a abrirla y deja la app desacompasada con el sistema (formatos de fecha, Ajustes, el
/// idioma de las notificaciones). El sistema ya tiene un idioma por app: en iOS en Ajustes › Chirogra › Idioma (al
/// cambiarlo, iOS vuelve a abrir la app en ese idioma) y en el Mac en Ajustes del Sistema › General › Idioma y
/// región › Aplicaciones.
enum AppLanguage {
    /// Idioma con que la app se está viendo (el que eligió el sistema entre los del catálogo).
    static var current: String {
        (Bundle.main.preferredLocalizations.first ?? "es").hasPrefix("en") ? "English" : "Español"
    }

    #if os(iOS)
    /// Página de la app en Ajustes, donde está «Idioma».
    static let settingsURL = URL(string: UIApplication.openSettingsURLString)
    #else
    /// Ajustes del Sistema › General › Idioma y región.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")
    #endif
}

/// Fila del alta con el idioma de la app y el botón para cambiarlo, con una línea de qué hacer en Ajustes.
struct AppLanguageSection: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            #if os(iOS)
            Button { if let url = AppLanguage.settingsURL { openURL(url) } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "globe").foregroundStyle(Palette.brand).accessibilityHidden(true)
                    Text("Idioma de la app").foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    Text(verbatim: AppLanguage.current).foregroundStyle(Palette.ink2)
                    Image(systemName: "arrow.up.forward.app").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chevron)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Metrics.target)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Idioma de la app"))
            .accessibilityValue(Text(verbatim: AppLanguage.current))
            .accessibilityHint(Text("Abre Ajustes para cambiarlo"))
            #else
            LabeledContent("Idioma de la app") {
                HStack(spacing: 10) {
                    Text(verbatim: AppLanguage.current).foregroundStyle(Palette.ink2)
                    Button("Cambiar…") { if let url = AppLanguage.settingsURL { openURL(url) } }
                }
            }
            #endif
        } header: {
            SectionLabel(text: String(localized: "Idioma"))
        } footer: {
            #if os(iOS)
            Text("En Ajustes › Apps › Chirogra, toca «Idioma» y elige Español o English; la app vuelve a abrirse en ese idioma.")
            #else
            Text("En Ajustes del Sistema › General › Idioma y región, en «Aplicaciones» pulsa «+», elige Chirogra y el idioma, y vuelve a abrir Chirogra.")
            #endif
        }
    }
}

// MARK: - Sales tax del estado

/// Lo que el alta hará con el sales tax del estado elegido, en una frase para el pie de «Detalles».
enum StateTaxNote {
    static func text(for code: String) -> String? {
        guard let info = StateSalesTax.forState(code) else { return nil }
        if let millionths = info.rateMillionths {
            return String(localized: "Tus facturas cobrarán la tasa estatal de \(info.name) (\(percent(millionths))). Si tu ciudad o condado cobra más, añade su parte en Impuestos › Nueva tasa y la sumamos. Revisa que las tasas sean las de tu negocio.")
        }
        if info.hasLocalTaxOnly {
            return String(localized: "\(info.name) no tiene sales tax estatal, pero muchas ciudades y boroughs sí: añade la tasa local en Impuestos.")
        }
        return String(localized: "\(info.name) no tiene sales tax estatal, así que no creamos ninguna tasa. Si vendes en otro estado, añade su tasa en Impuestos.")
    }

    /// En el alta: con la tasa de la ciudad escrita, lo que cobrarán las facturas y de qué se compone («8.25%: Texas
    /// 6.25% + Austin 2%»); si no, de dónde sale la de la ciudad (lo que pasa de la del estado en un recibo de ahí).
    static func text(for code: String, localMillionths: Int64, localName: String) -> String? {
        guard let info = StateSalesTax.forState(code), let state = info.rateMillionths else { return text(for: code) }
        let trimmed = localName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard localMillionths > 0 else {
            if !trimmed.isEmpty {
                return String(localized: "Escribe cuánto cobra \(trimmed): en el recibo de cualquier tienda de ahí, lo que pase del \(percent(state)) de \(info.name).")
            }
            return String(localized: "Tus facturas cobrarán la tasa de \(info.name) (\(percent(state))). Si tu ciudad o condado cobra su parte, escribe su nombre y te pedimos su tasa.")
        }
        let local = trimmed.isEmpty ? String(localized: "tu ciudad") : trimmed
        var note = String(localized: "Tus facturas cobrarán \(percent(state + localMillionths)): \(info.name) \(percent(state)) + \(local) \(percent(localMillionths)). Lo cambias cuando quieras en Impuestos.")
        if separateLocalAgencyStates.contains(info.code) {
            note += " " + String(localized: "En \(info.name) algunas ciudades cobran su parte por separado: si es tu caso, cambia su agencia en Impuestos.")
        }
        return note
    }

    /// Estados donde algunas ciudades o parroquias recaudan su sales tax ellas mismas, no la agencia del estado.
    static let separateLocalAgencyStates: Set<String> = ["AL", "AZ", "CO", "LA"]

    /// «6.25 %» / «6.25%».
    static func percent(_ millionths: Int64) -> String {
        (Decimal(millionths) / 1_000_000).formatted(.percent.precision(.fractionLength(0...4)))
    }
}

// MARK: - Saldos de apertura

/// Campos de los saldos con que empiezan los libros: lo que hay hoy en la cuenta del banco, su fecha y, opcional,
/// lo que se debe en la tarjeta de crédito. Se usan en el paso 3 del alta y en la hoja «Pon el saldo de tu banco» de
/// Inicio; se registran con `Bookkeeper.recordOpeningBalances` contra 3900 · Saldos de apertura.
/// `header` es el encabezado del grupo del banco (el del paso del alta lleva el título grande).
struct OpeningBalanceFields<Header: View>: View {
    @Binding var bank: Int64
    @Binding var card: Int64
    @Binding var date: Date
    @ViewBuilder var header: Header

    var body: some View {
        Section {
            moneyRow("Saldo del banco", amount: $bank)
            DatePicker("Fecha del saldo", selection: $date, in: ...Date.now, displayedComponents: .date)
        } header: {
            header
        } footer: {
            Text("El saldo de la cuenta que usas para el negocio en esa fecha. Si empiezas los libros en una fecha pasada (por ejemplo, el 1 de octubre), cambia la fecha y copia el saldo de ese día de tu extracto.")
        }
        Section {
            moneyRow("Lo que debes en esa fecha", amount: $card)
        } header: {
            SectionLabel(text: String(localized: "Tarjeta de crédito (opcional)"))
        } footer: {
            Text("Déjalo vacío si no usas tarjeta. Los saldos se registran como asiento de apertura contra «Saldos de apertura» (3900); lo verás en Contabilidad. Tu contador suele pasar ese saldo a «Capital del dueño» al cerrar el año.")
        }
    }

    /// En iOS el título de un campo de un formulario no se ve: va en un `LabeledContent`, con la cifra a la derecha.
    @ViewBuilder
    private func moneyRow(_ title: LocalizedStringResource, amount: Binding<Int64>) -> some View {
        #if os(macOS)
        MoneyField(title: String(localized: title), minorUnits: amount)
        #else
        LabeledContent {
            MoneyField(title: String(localized: title), minorUnits: amount)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(Text(title))
        } label: {
            Text(title)
        }
        .labeledContentStyle(.automatic)
        #endif
    }
}

/// «Pon el saldo de tu banco» desde los primeros pasos de Inicio (si no se puso en el alta).
struct OpeningBalanceSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    @State private var editorToken = EditorToken()
    @State private var bank: Int64 = 0
    @State private var card: Int64 = 0
    @State private var date = Date()
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                Text("Así «Efectivo disponible» empieza con el dinero que de verdad tienes, y Banca y los reportes cuadran con tu banco.")
                    .font(.subheadline).foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            OpeningBalanceFields(bank: $bank, card: $card, date: $date) {
                SectionLabel(text: String(localized: "Cuenta del banco"))
            }
        }
        .formStyle(.grouped)
        .keyboardDoneButton()
        .screenBackground()
        .navigationTitle("Saldo del banco")
        .inlineTitle()
        .discardableEditor(tracking: "\(bank)|\(card)|\(date)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save).disabled(bank <= 0 && card <= 0).headerButton()
            }
        }
    }

    private func save() {
        do {
            try Bookkeeper(context: context).recordOpeningBalances(bank: bank, creditCard: card, on: Calendar.current.startOfDay(for: date))
            unsavedChanges?.remove(editorToken)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
