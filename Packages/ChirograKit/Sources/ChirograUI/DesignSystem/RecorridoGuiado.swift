import SwiftUI

// Tutorial de seguir (1.4, pedido del usuario del 26-nov): «en vez de poner por escrito lo que hay que hacer, uno sigue
// las instrucciones: si dice presione aquí, va y presiona». Sale una vez, al crear su propia empresa (no con los datos de
// ejemplo), y enseña lo más importante haciéndolo de verdad: su primer cliente, su primera factura, un gasto y sus
// impuestos. Lo que crea se queda en sus libros. Lo demás está en el tutorial completo (iPhone) y en la guía de
// chirogra.com, que ofrece la despedida.
//
// Usa el recorrido de la primera vez (`Recorrido`): el mismo velo con hueco, anillo y tarjeta. Lo nuevo:
// - Lo iluminado se toca de verdad: el toque pasa por el hueco (en las hojas el velo no detiene nada).
// - Cada paso espera algo (`Espera`): que aparezca la pantalla que abre lo tocado, que pase algo (`Recorrido.ocurrio`:
//   se guardó el cliente) o que la pantalla dé el paso por hecho (`recorridoCumple`: escribió el nombre).
// - Los pasos van en grupos. Todo se empieza desde «Primeros pasos» de Inicio, que es igual en iPhone, iPad y Mac: si la
//   fila de un grupo ya no se puede tocar (ya había un cliente), el grupo se salta.
// - Si la persona cierra un editor sin guardar, vuelve al primer paso de su grupo (`Recorrido.hojaCerrada`).
//
// QA: `-qa.alta 1 -qa.altaCrear 1 -qa.recorrido guiado` crea la empresa y lo empieza.

extension RecorridoID {
    /// «Toca» en iPhone y iPad, «Haz clic» en el Mac.
    private static func toca(_ ios: String, mac: String) -> String {
        #if os(macOS)
        mac
        #else
        ios
        #endif
    }

    /// El botón «Guardar» de la barra de un editor (en el iPad ancho, el del gasto se llama «Guardar gasto»).
    private static var guardarCliente: String { "ax:" + String(localized: "Guardar") }
    private static var guardarGasto: String {
        "ax:" + String(localized: "Guardar gasto") + "|ax:" + String(localized: "Guardar")
    }
    /// «Emitir» en la barra de abajo de la factura del iPhone; en la hoja ancha, arriba («Emitir factura»).
    private static var emitirFactura: String { "editor.emitir|ax:" + String(localized: "Emitir factura") }

    private static var tieneTutorialCompleto: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    static var pasosGuiado: [Paso] {
        [
            Paso(objetivo: nil, icono: "hand.tap",
                 titulo: String(localized: "Aprende haciendo"),
                 mensaje: String(localized: "Tu empresa ya está creada. Ahora haz tú lo más importante: tu primer cliente, tu primera factura, un gasto y tus impuestos. Te vamos señalando dónde tocar.")),

            // Cliente
            Paso(objetivo: "home.paso.customer|home.rapido.customer", icono: "person.badge.plus",
                 titulo: String(localized: "Tu primer cliente"),
                 mensaje: toca(String(localized: "Toca aquí para añadir a quien le vendes."),
                               mac: String(localized: "Haz clic aquí para añadir a quien le vendes.")),
                 desplazar: true, espera: .aparece("cliente.nombre"), grupo: "cliente"),
            Paso(objetivo: "cliente.nombre", icono: "character.cursor.ibeam",
                 titulo: String(localized: "Escribe su nombre"),
                 mensaje: String(localized: "El de la persona o la empresa. El correo y el teléfono son opcionales: puedes ponerlos ahora o después."),
                 espera: .listo("cliente.nombre"), enHoja: true, grupo: "cliente", escribe: true),
            Paso(objetivo: guardarCliente, icono: "checkmark",
                 titulo: String(localized: "Guárdalo"),
                 mensaje: toca(String(localized: "Toca «Guardar». Ya podrás hacerle facturas."),
                               mac: String(localized: "Haz clic en «Guardar». Ya podrás hacerle facturas.")),
                 espera: .evento("cliente.guardado"), enHoja: true, grupo: "cliente"),

            // Factura
            Paso(objetivo: "home.paso.invoice|home.rapido.invoice", icono: "doc.text",
                 titulo: String(localized: "Tu primera factura"),
                 mensaje: toca(String(localized: "Toca aquí para cobrarle a tu cliente."),
                               mac: String(localized: "Haz clic aquí para cobrarle a tu cliente.")),
                 desplazar: true, espera: .aparece("editor.customer"), grupo: "factura"),
            Paso(objetivo: "editor.customer", icono: "person",
                 titulo: String(localized: "Elige el cliente"),
                 mensaje: toca(String(localized: "Toca aquí y elige el cliente que acabas de crear."),
                               mac: String(localized: "Haz clic aquí y elige el cliente que acabas de crear.")),
                 espera: .evento("factura.cliente"), enHoja: true, grupo: "factura"),
            Paso(objetivo: "factura.linea", icono: "cart",
                 titulo: String(localized: "Qué vendiste y a cuánto"),
                 mensaje: String(localized: "Escribe el producto o servicio y su precio. Después toca «Siguiente»."),
                 espera: .listo("factura.precio"), enHoja: true, grupo: "factura", escribe: true),
            Paso(objetivo: "editor.tax", icono: "percent",
                 titulo: String(localized: "El sales tax, solo"),
                 mensaje: String(localized: "Chirogra le suma el impuesto de tu estado. Si esta venta no lleva impuesto, cámbialo aquí."),
                 desplazar: true, enHoja: true, grupo: "factura"),
            Paso(objetivo: emitirFactura, icono: "paperplane",
                 titulo: String(localized: "Emítela"),
                 mensaje: toca(String(localized: "Toca «Emitir»: queda registrada y por cobrar. Luego puedes mandársela a tu cliente."),
                               mac: String(localized: "Haz clic en «Emitir factura»: queda registrada y por cobrar. Luego puedes mandársela a tu cliente.")),
                 espera: .evento("factura.emitida"), enHoja: true, grupo: "factura"),

            // Gasto
            Paso(objetivo: "home.paso.expense|home.rapido.expense", icono: "wallet.bifold",
                 titulo: String(localized: "Anota un gasto"),
                 mensaje: toca(String(localized: "Toca aquí cada vez que pagues algo del negocio."),
                               mac: String(localized: "Haz clic aquí cada vez que pagues algo del negocio.")),
                 desplazar: true, espera: .aparece("expense.amount"), grupo: "gasto"),
            Paso(objetivo: "expense.amount", icono: "dollarsign",
                 titulo: String(localized: "¿Cuánto pagaste?"),
                 mensaje: String(localized: "Escribe el monto del recibo. Después toca «Siguiente»."),
                 espera: .listo("gasto.monto"), enHoja: true, grupo: "gasto", escribe: true),
            Paso(objetivo: "gasto.pagadoA", icono: "storefront",
                 titulo: String(localized: "¿A quién le pagaste?"),
                 mensaje: String(localized: "Escribe la tienda o la persona. Después toca «Siguiente»."),
                 desplazar: true, espera: .listo("gasto.pagadoA"), enHoja: true, grupo: "gasto", escribe: true),
            Paso(objetivo: "expense.category", icono: "tag",
                 titulo: String(localized: "¿En qué se fue?"),
                 mensaje: String(localized: "Elige la categoría: así tus reportes y tus impuestos salen bien."),
                 desplazar: true, espera: .listo("gasto.categoria"), enHoja: true, grupo: "gasto"),
            Paso(objetivo: guardarGasto, icono: "checkmark",
                 titulo: String(localized: "Guárdalo"),
                 mensaje: toca(String(localized: "Toca «Guardar». El gasto queda registrado y resta de tu ganancia."),
                               mac: String(localized: "Haz clic en «Guardar gasto». Queda registrado y resta de tu ganancia.")),
                 espera: .evento("gasto.guardado"), enHoja: true, grupo: "gasto"),

            // Impuestos: el apartado para el IRS (dueño único y LLC); si no sale (corporación), el sales tax.
            Paso(objetivo: "tarjeta.apartado|pad.apartado", icono: "building.columns",
                 titulo: String(localized: "Tu apartado para impuestos"),
                 mensaje: toca(String(localized: "Con cada venta y cada gasto, Chirogra calcula cuánto apartar para el IRS. Tócala."),
                               mac: String(localized: "Con cada venta y cada gasto, Chirogra calcula cuánto apartar para el IRS. Haz clic en ella.")),
                 desplazar: true, espera: .aparece("apartado.resumen|pad.apartado.detalle"), grupo: "apartado"),
            Paso(objetivo: "apartado.resumen|pad.apartado.detalle", icono: "banknote",
                 titulo: String(localized: "Lo que toca apartar"),
                 mensaje: String(localized: "Es lo que conviene guardar para el pago al IRS de este trimestre. Cuando pagues, anótalo en «Registrar pago al IRS»."),
                 grupo: "apartado"),
            Paso(objetivo: "home.paso.tax", icono: "percent",
                 titulo: String(localized: "Tu sales tax"),
                 mensaje: toca(String(localized: "Toca aquí para ver el impuesto de tus ventas."),
                               mac: String(localized: "Haz clic aquí para ver el impuesto de tus ventas.")),
                 desplazar: true, espera: .aparece("taxes.owed"), grupo: "ventas", siSeSalto: "apartado"),
            Paso(objetivo: "taxes.owed", icono: "dollarsign.circle",
                 titulo: String(localized: "Lo que le debes al estado"),
                 mensaje: String(localized: "Cada factura suma aquí el sales tax que cobraste. Es lo que declaras y pagas."),
                 grupo: "ventas", siSeSalto: "apartado"),

            Paso(objetivo: nil, icono: "checkmark.seal",
                 titulo: String(localized: "¡Ya sabes lo principal!"),
                 mensaje: tieneTutorialCompleto
                    ? String(localized: "Clientes, facturas, gastos e impuestos. Para lo demás, sigue con la guía de chirogra.com o con el tutorial completo, que explica cada pantalla.")
                    : String(localized: "Clientes, facturas, gastos e impuestos. Para lo demás, sigue con la guía de chirogra.com."),
                 final: true),
        ]
    }
}
