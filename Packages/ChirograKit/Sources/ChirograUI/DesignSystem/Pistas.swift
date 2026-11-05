import Foundation
import SwiftUI
import TipKit

// Pistas de una sola vez (TipKit, build 4): señalan lo que no se ve a simple vista la primera vez. Van como recuadro
// dentro del contenido (no tapan nada), se cierran con la «×» o al usar lo que señalan, y no vuelven (TipKit guarda
// que se vieron). Solo en iPhone e iPad: en el Mac los botones ya llevan su texto («Nueva factura», «Registrar pago…»)
// y los estados vacíos de las tablas explican cada página.
//
// Dónde va cada una:
// - `NewInvoiceTip`, `NewExpenseTip`: globo en «+ Factura» y «+ Gasto» de la columna maestro del iPad, mientras la
//   sección está vacía. En el «+» del iPhone no se pone: el globo de TipKit (`popoverTip`) no salía en ese botón de la
//   barra (probado en el simulador del iPhone 17; en el iPad sí sale), y el estado vacío ya ofrece el botón para empezar.
// - `RecordPaymentTip`: recuadro dentro de «Registrar pago» en el detalle de una factura abierta.
// - `RecurringTip`: recuadro en Gastos cuando ya hay algún gasto, con un botón que abre Recurrentes.
// - `TaxesTip`: recuadro arriba de «Más» del iPhone, con un botón que abre Impuestos.

/// Arranque de TipKit. Se llama una vez desde `ChirograApp.init`.
///
/// Argumentos de QA (solo Debug): `-qa.pistas reset` borra lo visto (vuelven a salir todas una vez);
/// `-qa.pistas todas` las muestra todas aunque ya se hayan visto o sus reglas no se cumplan; `-qa.pistas ocultas`
/// no muestra ninguna. Con otros argumentos `-qa.*` y sin `-qa.pistas`, tampoco salen: así las capturas de la
/// App Store y de las pruebas no las llevan.
public enum ChirograTips {
    public static func configure() {
        #if os(iOS)
        #if DEBUG
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "qa.pistas") {
        case "reset":
            try? Tips.resetDatastore()
        case "todas":
            try? Tips.resetDatastore()
            Tips.showAllTipsForTesting()
        case "ocultas":
            Tips.hideAllTipsForTesting()
        default:
            let usesQA = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-qa.") }
            if usesQA { Tips.hideAllTipsForTesting() }
        }
        #endif
        try? Tips.configure([.displayFrequency(.immediate)])
        #endif
    }
}

/// «+ Factura» del iPad: mientras no haya ninguna factura.
struct NewInvoiceTip: Tip {
    @Parameter static var hasInvoices: Bool = false

    var title: Text { Text("Crea tu primera factura") }
    var message: Text? { Text("Toca + para cobrarle a un cliente. Chirogra te avisa cuando vence y anota el pago cuando llegue.") }
    var image: Image? { Image(systemName: "doc.text") }
    var rules: [Rule] { #Rule(Self.$hasInvoices) { $0 == false } }
}

/// «+ Gasto» del iPad: mientras no haya ningún gasto.
struct NewExpenseTip: Tip {
    @Parameter static var hasExpenses: Bool = false

    var title: Text { Text("Anota lo que pagas") }
    var message: Text? { Text("Toca + cada vez que pagues algo del negocio y adjunta la foto del recibo.") }
    var image: Image? { Image(systemName: "wallet.bifold") }
    var rules: [Rule] { #Rule(Self.$hasExpenses) { $0 == false } }
}

extension View {
    /// Globo de una pista (iPad); en el Mac, nada.
    @ViewBuilder
    func onboardingTip(_ tip: (any Tip)?) -> some View {
        #if os(iOS)
        if let tip { popoverTip(tip, arrowEdge: .top) } else { self }
        #else
        self
        #endif
    }
}

/// «Registrar pago» de una factura abierta.
struct RecordPaymentTip: Tip {
    var title: Text { Text("¿Ya te pagaron?") }
    var message: Text? { Text("Cuando el cliente te pague, regístralo aquí: la factura queda pagada y el dinero entra en tu cuenta.") }
    var image: Image? { Image(systemName: "checkmark.circle") }
}

/// Recurrentes, cuando ya se anotó algún gasto (antes no tiene sentido hablar de los que se repiten).
struct RecurringTip: Tip {
    @Parameter static var hasExpenses: Bool = false

    var title: Text { Text("¿Pagas algo cada mes?") }
    var message: Text? { Text("La renta, el seguro, una suscripción: créala una vez en Recurrentes y Chirogra la registra por ti.") }
    var image: Image? { Image(systemName: "arrow.trianglehead.2.clockwise") }
    var rules: [Rule] { #Rule(Self.$hasExpenses) { $0 == true } }
    var actions: [Action] { [Action(id: "abrir", title: String(localized: "Abrir Recurrentes"))] }
}

/// Impuestos en «Más» del iPhone: el grupo queda abajo, después de Reportes y Contabilidad.
struct TaxesTip: Tip {
    var title: Text { Text("¿Cobras sales tax?") }
    var message: Text? { Text("En Impuestos, más abajo, configuras tus tasas y ves cuánto le debes al estado.") }
    var image: Image? { Image(systemName: "percent") }
    var actions: [Action] { [Action(id: "abrir", title: String(localized: "Abrir Impuestos"))] }
}

/// Recuadro de una pista dentro del contenido (no tapa nada: empuja lo de abajo). En el Mac no se muestra.
struct InlineTip<T: Tip>: View {
    let tip: T
    var action: ((Tips.Action) -> Void)? = nil

    var body: some View {
        #if os(iOS)
        TipView(tip, arrowEdge: nil) { action?($0) }
            .tipViewStyle(ChirograTipStyle())
            .tipBackground(Palette.surface)
        #endif
    }
}

#if os(iOS)
/// Estilo del recuadro de una pista: el del sistema rellenaba el botón de la acción de morado; aquí va en el botón
/// principal de la app (vidrio sin relleno, decisión del usuario), con la «×» de 44 pt para cerrarla.
private struct ChirograTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            configuration.image?
                .font(.title2)
                .foregroundStyle(Palette.brand)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                configuration.title?.font(.headline).foregroundStyle(Palette.ink)
                configuration.message?.font(.subheadline).foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(configuration.actions) { action in
                    Button(action: action.handler) { action.label() }
                        .buttonStyle(.primaryCompact)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { configuration.tip.invalidate(reason: .tipClosed) } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: Metrics.target, height: Metrics.target)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar")
            .padding(.top, -10)
            .padding(.trailing, -10)
        }
        .padding(16)
    }
}
#endif
