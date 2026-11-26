import SwiftUI

// Recorrido guiado la primera vez que se abre cada pestaña del iPhone (build 51, tras los testers de Userbrain;
// dirección A «Foco» del canvas «Chirogra — First-run tour» de Claude Design, 17-nov). La pantalla se oscurece, se
// ilumina una parte cada vez y una tarjeta con flecha explica para qué sirve. «Saltar» o el último paso lo dan por
// visto, en este aparato y en iCloud (no vuelve a salir en otro aparato). Se repite desde «Más › Ayuda › Ver el
// recorrido otra vez». Los pasos cuyo objetivo no está (sin facturas no hay «Por cobrar») se saltan.
//
// Cómo se marca un objetivo: `.recorridoObjetivo("id")` en la vista (su marco en la ventana). Los botones de la barra de
// navegación viven en UIKit y su marco de SwiftUI no sirve: se buscan por su nombre de accesibilidad (`ax:`). Lo que
// está más abajo de la pantalla (`desplazar`) se pone a la vista con `desplazarA` y un `ScrollViewReader` de la
// pantalla (`.id` igual al del objetivo).
//
// Tiempos (ficha «Motion spec» del canvas): al pasar de paso, la tarjeta se va (120 ms), el foco se desliza (muelle de
// 450 ms) y la tarjeta nueva entra a los 300 ms (240 ms). El anillo late 2 veces y se para. Con «Reducir movimiento»,
// solo un fundido de 200 ms. Con VoiceOver, el foco va a la tarjeta y tocar fuera no avanza.
//
// La tarjeta se desliza como la bienvenida: a la izquierda, el paso siguiente; a la derecha, el anterior (Eric, Beta
// Family, build 55). Con VoiceOver, lo mismo ajustando el indicador «2 de 5» (deslizar arriba o abajo).

/// Hacia dónde lleva deslizar la tarjeta del recorrido.
nonisolated enum Deslizamiento: Equatable, Sendable { case siguiente, anterior }

enum RecorridoID: String, CaseIterable {
    case home, sales, expenses, banking, more
    /// Pantallas que solo se explican con el «Tutorial completo» (`RecorridoAFondo.swift`).
    case invoiceDetail, estimateDetail, invoiceEditor, expenseEditor, reports, taxes
    /// iPad a pantalla completa (barra lateral, lista y detalle; build 60, pedido del usuario del 21-nov): el corto de la
    /// primera vez en cada sección, con sus propios pasos y su propio «visto» (el del iPhone no vale: es otra pantalla).
    case padHome, padSales, padExpenses, padBanking, padReports
    /// 1.4: el tutorial de seguir (`RecorridoGuiado.swift`): al crear su empresa, la persona toca y crea de verdad su
    /// primer cliente, su primera factura y un gasto, y ve sus impuestos. Igual en iPhone, iPad y Mac.
    case guiado

    /// Las 5 pestañas, que tienen también el recorrido corto de la primera vez (y las secciones del iPad).
    var esPestana: Bool { [.home, .sales, .expenses, .banking, .more].contains(self) || esIPad }

    /// Recorrido del iPad a pantalla completa.
    var esIPad: Bool { [.padHome, .padSales, .padExpenses, .padBanking, .padReports].contains(self) }

    /// Se abre en una hoja (los editores): la dibuja el velo de la hoja, no el de las pestañas.
    var enHoja: Bool { self == .invoiceEditor || self == .expenseEditor }

    /// El corto en las pestañas; con el «Tutorial completo», el largo (en las demás pantallas, solo ese).
    func pasos(aFondo: Bool) -> [Paso] {
        if self == .guiado { return Self.pasosGuiado }
        return aFondo ? pasosAFondo : esPestana ? pasos : []
    }

    /// Qué espera un paso del tutorial de seguir para pasar al siguiente (sin espera: «Siguiente», como el recorrido).
    enum Espera: Equatable {
        /// Que aparezca ese objetivo: la persona tocó lo iluminado y se abrió la pantalla que sigue.
        case aparece(String)
        /// Que pase algo en la app (`Recorrido.ocurrio`): se guardó el cliente, se emitió la factura.
        case evento(String)
        /// «Siguiente» se enciende cuando la pantalla lo da por hecho (`recorridoCumple`): escribió el nombre.
        case listo(String)
    }

    struct Paso {
        /// Lo que se ilumina; `nil` = presentación de la pestaña, centrada. `ax:` = un botón de la barra de
        /// navegación, buscado en UIKit por el principio de su nombre de accesibilidad.
        let objetivo: String?
        let icono: String
        let titulo: String
        let mensaje: String
        /// Puede quedar fuera de la pantalla (más abajo, o con letra grande): primero se desplaza hasta él.
        var desplazar = false
        /// Vive en una `List`, que no dibuja (ni mide) las filas fuera de la pantalla: se cuenta aunque aún no tenga
        /// marco, y se salta si al desplazarse no aparece.
        var enLista = false
        /// Tutorial de seguir: lo que espera para pasar al siguiente.
        var espera: Espera? = nil
        /// Tutorial de seguir: el paso vive en un editor (hoja); lo dibuja el velo de la hoja.
        var enHoja = false
        /// Tutorial de seguir: los pasos de un mismo grupo (cliente, factura, gasto…). Si el primero no está en la
        /// pantalla (ya hay cliente: su fila de «Primeros pasos» no se puede tocar), se salta el grupo entero.
        var grupo: String? = nil
        /// Tutorial de seguir: solo si se saltó ese grupo (el sales tax, cuando no hay «Apartado para impuestos»).
        var siSeSalto: String? = nil
        /// Tutorial de seguir: la tarjeta de despedida, con la guía y el tutorial completo.
        var final = false
        /// Tutorial de seguir: el paso pide escribir; en los demás el teclado se cierra (tapaba lo iluminado).
        var escribe = false
    }

    var pasos: [Paso] {
        switch self {
        case .home: [
            Paso(objetivo: nil, icono: "house",
                 titulo: String(localized: "Inicio: tu negocio hoy"),
                 mensaje: String(localized: "El dinero que tienes y cómo va el mes, de un vistazo.")),
            Paso(objetivo: "home.summary", icono: "chart.bar",
                 titulo: String(localized: "Tu mes en cifras"),
                 mensaje: String(localized: "Lo que entró, lo que pagaste y lo que ganaste este mes."),
                 desplazar: true),
            Paso(objetivo: "home.quick", icono: "plus",
                 titulo: String(localized: "Lo más rápido"),
                 mensaje: String(localized: "Crea una factura, un gasto o un cliente con un toque."),
                 desplazar: true),
            // Empresa nueva, sin movimientos: Inicio enseña la lista de «Primeros pasos» en vez de las cifras.
            Paso(objetivo: "home.firstSteps", icono: "checklist",
                 titulo: String(localized: "Primeros pasos"),
                 mensaje: String(localized: "Sigue esta lista para dejar tu empresa lista."),
                 desplazar: true),
            Paso(objetivo: "ax:" + String(localized: "Avisos"), icono: "bell",
                 titulo: String(localized: "Avisos"),
                 mensaje: String(localized: "Aquí te avisamos de facturas vencidas y pagos por hacer.")),
        ]
        case .sales: [
            Paso(objetivo: nil, icono: "doc.text",
                 titulo: String(localized: "Ventas: lo que te pagan"),
                 mensaje: String(localized: "Aquí le cobras a tus clientes y ves quién te debe.")),
            Paso(objetivo: "ax:" + String(localized: "Nueva factura"), icono: "plus",
                 titulo: String(localized: "Crea una factura"),
                 mensaje: String(localized: "Toca + para cobrarle a un cliente. Se la mandas por correo o mensaje.")),
            Paso(objetivo: "sales.menu", icono: "list.clipboard",
                 titulo: String(localized: "Facturas, estimados y clientes"),
                 mensaje: String(localized: "Aquí cambias entre tus facturas, los presupuestos y tu lista de clientes.")),
            Paso(objetivo: "sales.receivable", icono: "dollarsign.circle",
                 titulo: String(localized: "Lo que te deben"),
                 mensaje: String(localized: "El total que tus clientes todavía no te han pagado.")),
            Paso(objetivo: "sales.firstRow", icono: "checkmark.circle",
                 titulo: String(localized: "¿Ya te pagaron?"),
                 mensaje: String(localized: "Abre la factura y toca «Marcar como pagada».")),
        ]
        case .expenses: [
            Paso(objetivo: nil, icono: "wallet.bifold",
                 titulo: String(localized: "Gastos: lo que pagas"),
                 mensaje: String(localized: "Aquí anotas todo lo que pagas por el negocio.")),
            Paso(objetivo: "ax:" + String(localized: "Nuevo gasto"), icono: "plus",
                 titulo: String(localized: "Anota un gasto"),
                 mensaje: String(localized: "Toca + cada vez que pagues algo. Puedes añadir la foto del recibo.")),
            Paso(objetivo: "expenses.segment", icono: "arrow.trianglehead.2.clockwise",
                 titulo: String(localized: "Por pagar y Recurrentes"),
                 mensaje: String(localized: "Facturas de proveedores que aún debes, y lo que se repite cada mes, como la renta.")),
            Paso(objetivo: "expenses.month", icono: "chart.pie",
                 titulo: String(localized: "Tu mes de un vistazo"),
                 mensaje: String(localized: "Así se reparte por categoría lo que gastaste este mes.")),
        ]
        case .banking: [
            Paso(objetivo: nil, icono: "building.columns",
                 titulo: String(localized: "Banca: tus cuentas"),
                 mensaje: String(localized: "El dinero de cada cuenta y lo que llega del banco.")),
            Paso(objetivo: "banking.account", icono: "creditcard",
                 titulo: String(localized: "Tus saldos"),
                 mensaje: String(localized: "Cuánto tiene cada cuenta. Tócala para ver sus movimientos.")),
            Paso(objetivo: "ax:" + String(localized: "Importar CSV u OFX"), icono: "square.and.arrow.down",
                 titulo: String(localized: "Trae tu banco"),
                 mensaje: String(localized: "Importa el extracto y Chirogra te propone cómo anotar cada movimiento.")),
        ]
        case .more: [
            Paso(objetivo: nil, icono: "ellipsis.circle",
                 titulo: String(localized: "Más: todo lo demás"),
                 mensaje: String(localized: "Reportes, impuestos, contabilidad y ajustes.")),
            Paso(objetivo: "more.reports", icono: "chart.bar.doc.horizontal",
                 titulo: String(localized: "Reportes"),
                 mensaje: String(localized: "Estado de resultados, balance y más, listos para tu contador."),
                 desplazar: true, enLista: true),
            // Eric (Beta Family, build 55): nadie le contó cómo se protegen sus datos. Se señala Seguridad una vez.
            Paso(objetivo: "more.security", icono: "lock.shield",
                 titulo: String(localized: "Tus libros, protegidos"),
                 mensaje: String(localized: "En Seguridad ves dónde se guardan tus datos, el bloqueo con Face ID y la bitácora de cambios."),
                 desplazar: true, enLista: true),
            Paso(objetivo: "more.tabs", icono: "dock.rectangle",
                 titulo: String(localized: "Ponla a tu gusto"),
                 mensaje: String(localized: "Elige qué herramientas van en la barra de abajo."),
                 desplazar: true, enLista: true),
        ]
        case .padHome: [
            Paso(objetivo: nil, icono: "house",
                 titulo: String(localized: "Inicio: tu negocio hoy"),
                 mensaje: String(localized: "El dinero que tienes y cómo va el mes, de un vistazo.")),
            Paso(objetivo: "pad.sidebar", icono: "sidebar.left",
                 titulo: String(localized: "Todas las secciones"),
                 mensaje: String(localized: "A la izquierda tienes todo: ventas, gastos, banca, reportes e impuestos. Toca una para abrirla.")),
            Paso(objetivo: "pad.home.column", icono: "chart.bar",
                 titulo: String(localized: "Tu negocio por partes"),
                 mensaje: String(localized: "El dinero, los resultados, lo que te deben y lo que debes. Toca una para verla en detalle al lado.")),
            Paso(objetivo: "ax:" + String(localized: "Nueva factura"), icono: "plus",
                 titulo: String(localized: "Lo más rápido"),
                 mensaje: String(localized: "Crea una factura o anota un gasto con un toque.")),
            Paso(objetivo: "ax:" + String(localized: "Avisos"), icono: "bell",
                 titulo: String(localized: "Avisos"),
                 mensaje: String(localized: "Aquí te avisamos de facturas vencidas y pagos por hacer.")),
        ]
        case .padSales: [
            Paso(objetivo: nil, icono: "doc.text",
                 titulo: String(localized: "Ventas: lo que te pagan"),
                 mensaje: String(localized: "Aquí le cobras a tus clientes y ves quién te debe.")),
            Paso(objetivo: "ax:" + String(localized: "Nueva factura"), icono: "plus",
                 titulo: String(localized: "Crea una factura"),
                 mensaje: String(localized: "Toca + para cobrarle a un cliente. Se la mandas por correo o mensaje.")),
            Paso(objetivo: "pad.sales.filter", icono: "line.3.horizontal.decrease",
                 titulo: String(localized: "Abiertas, vencidas o todas"),
                 mensaje: String(localized: "Filtra la lista para ver primero lo que tienes que cobrar.")),
            Paso(objetivo: "pad.sales.firstRow", icono: "checkmark.circle",
                 titulo: String(localized: "Ábrela al lado"),
                 mensaje: String(localized: "Toca una factura para verla a la derecha: desde ella la mandas, le pones un recordatorio o la marcas como pagada.")),
        ]
        case .padExpenses: [
            Paso(objetivo: nil, icono: "wallet.bifold",
                 titulo: String(localized: "Gastos: lo que pagas"),
                 mensaje: String(localized: "Aquí anotas todo lo que pagas por el negocio.")),
            Paso(objetivo: "ax:" + String(localized: "Nuevo gasto"), icono: "plus",
                 titulo: String(localized: "Anota un gasto"),
                 mensaje: String(localized: "Toca + cada vez que pagues algo. Puedes añadir la foto del recibo.")),
            Paso(objetivo: "pad.expenses.firstRow", icono: "doc.text.magnifyingglass",
                 titulo: String(localized: "El detalle, al lado"),
                 mensaje: String(localized: "Toca un gasto para ver su recibo, su categoría y su historial.")),
        ]
        case .padBanking: [
            Paso(objetivo: nil, icono: "building.columns",
                 titulo: String(localized: "Banca: tus cuentas"),
                 mensaje: String(localized: "El dinero de cada cuenta y lo que llega del banco.")),
            Paso(objetivo: "pad.banking.firstRow", icono: "creditcard",
                 titulo: String(localized: "Tus saldos"),
                 mensaje: String(localized: "Cuánto tiene cada cuenta. Tócala para ver sus movimientos.")),
            Paso(objetivo: "pad.banking.inbox", icono: "tray",
                 titulo: String(localized: "Lo que llega del banco"),
                 mensaje: String(localized: "Revisa los movimientos importados, concilia con el extracto y crea reglas para que se anoten solos.")),
            Paso(objetivo: "ax:" + String(localized: "Nuevo movimiento"), icono: "plus",
                 titulo: String(localized: "Anota un movimiento"),
                 mensaje: String(localized: "Un gasto, un traspaso entre cuentas o un asiento a mano.")),
        ]
        case .padReports: [
            Paso(objetivo: nil, icono: "chart.bar.doc.horizontal",
                 titulo: String(localized: "Reportes: listos para tu contador"),
                 mensaje: String(localized: "Resultados, balance, flujo de efectivo, antigüedad y sales tax, siempre al día.")),
            Paso(objetivo: "pad.sidebar", icono: "list.bullet",
                 titulo: String(localized: "Elige el reporte"),
                 mensaje: String(localized: "Cada reporte está en la barra lateral, debajo de Reportes.")),
            Paso(objetivo: "ax:" + String(localized: "Exportar"), icono: "square.and.arrow.up",
                 titulo: String(localized: "Para tu contador"),
                 mensaje: String(localized: "Exporta el reporte en PDF o CSV, o el paquete completo para tu contador.")),
        ]
        default: []
        }
    }

    var seenKey: String { "recorrido.visto.\(rawValue)" }
    /// Visto con el «Tutorial completo» (solo en este aparato: se activa en cada uno).
    var fondoKey: String { "recorrido.fondo.\(rawValue)" }

    /// La pestaña del iPhone que lo enseña.
    init?(tab: String) {
        switch tab {
        case "home": self = .home
        case "more": self = .more
        default:
            switch PhoneTool(id: tab)?.section {
            case .sales: self = .sales
            case .expenses: self = .expenses
            case .banking: self = .banking
            default: return nil
            }
        }
    }
}

@MainActor @Observable
final class Recorrido {
    var marcos: [String: CGRect] = [:]
    private(set) var activo: RecorridoID?
    private(set) var pasos: [RecorridoID.Paso] = []
    private(set) var paso = 0
    /// La tarjeta a la vista (se esconde mientras el foco se desliza al paso siguiente).
    private(set) var tarjetaVisible = false {
        didSet { if tarjetaVisible && !oldValue { visibleDesde = .now } }
    }
    @ObservationIgnored private var visibleDesde = Date.distantPast
    /// Lo que la lista tiene que mostrar antes de iluminarlo (`RecorridoID.Paso.desplazar`).
    private(set) var desplazarA: String?
    /// Los recorridos ya vistos: las pistas de TipKit de esa pestaña esperan a que esté aquí.
    private(set) var vistos: Set<RecorridoID> = []
    /// «Reducir movimiento» y el alto de la pantalla (los pone `RecorridoOverlay`).
    var reduceMotion = false
    var altoPantalla: CGFloat = 0
    /// Lo que tapa abajo: la barra de pestañas (100) o, en una hoja, solo el borde (34). Con 110, la última fila de un
    /// editor («Recibo») nunca contaba como a la vista y se saltaba.
    var margenAbajo: CGFloat = 100
    private var cambiando = false
    /// Capturas y pruebas con argumentos `-qa.*`: sin recorrido, salvo con `-qa.recorrido`.
    private var desactivado = false
    /// iPad a pantalla completa (lo pone `RootView`): solo los recorridos del iPad, sin «Tutorial completo» (sus pasos
    /// son los de las pantallas del iPhone), y nada tapa abajo.
    var esIPad = false

    // MARK: Tutorial de seguir (1.4)

    /// El recorrido a la vista es el tutorial de seguir.
    var esGuiado: Bool { activo == .guiado }
    var pasoActual: RecorridoID.Paso? { pasos.indices.contains(paso) ? pasos[paso] : nil }
    /// Qué capa dibuja el paso a la vista: la de la hoja (editores) o la de la pantalla.
    var capaEnHoja: Bool { esGuiado ? pasoActual?.enHoja ?? false : activo?.enHoja ?? false }
    /// Lo que la pantalla da por hecho (`Espera.listo`: escribió el nombre del cliente).
    private(set) var cumplidos: Set<String> = []
    /// Lo que ya pasó en este tutorial (`Espera.evento`), por si pasa mientras la tarjeta cambia de paso.
    @ObservationIgnored private var ocurridos: Set<String> = []
    /// Grupos saltados porque su primer paso no estaba (ya había cliente, por ejemplo).
    @ObservationIgnored private var gruposSaltados: Set<String> = []
    /// Alto del teclado a la vista: la tarjeta no se pone detrás de él.
    var teclado: CGFloat = 0
    /// Editores abiertos en hojas: un paso de la pantalla de detrás espera a que se cierren («Factura emitida» sigue
    /// encima de Inicio hasta que la persona responde).
    @ObservationIgnored private var hojasAbiertas = 0
    func hojaAbierta() { hojasAbiertas += 1 }
    /// Mientras un paso de la pantalla de detrás espera a que se cierren las hojas, el tutorial no dibuja nada: si no,
    /// la hoja que la persona abre entonces (enviar la factura recién emitida) quedaba cubierta por el velo, en gris y
    /// sin tarjeta (lo vio el usuario en el Mac, 26-nov).
    private(set) var esperandoHojas = false
    /// Al crear su empresa (`OnboardingView`), el tutorial de seguir queda pedido: empieza en Inicio.
    static let guiadoKey = "recorrido.guiado.pendiente"
    static var guiadoPendiente: Bool { UserDefaults.standard.bool(forKey: guiadoKey) }
    static func pedirGuiado() { UserDefaults.standard.set(true, forKey: guiadoKey) }

    /// Empieza el tutorial de seguir (al llegar a Inicio con la empresa recién creada, o desde Ayuda).
    func empezarGuiado() {
        guard activo == nil else { return }
        UserDefaults.standard.set(false, forKey: Self.guiadoKey)
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard activo == nil else { return }
            pasos = RecorridoID.guiado.pasos(aFondo: false)
            cumplidos = []
            ocurridos = []
            gruposSaltados = []
            activoAFondo = false
            paso = 0
            tarjetaVisible = false
            withAnimation(.easeOut(duration: 0.25)) { activo = .guiado }
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.8)) {
                tarjetaVisible = true
            }
        }
    }

    /// «Aprende haciendo» en Ayuda: el tutorial de seguir otra vez, desde Inicio (que lo empieza al ver el pedido). Lo ya
    /// hecho se toca con los botones rápidos de Inicio cuando su fila de «Primeros pasos» ya no está.
    func repetirGuiado() {
        guard activo == nil else { return }
        Self.pedirGuiado()
        pedidoInicio += 1
    }

    /// Lo pide Inicio al aparecer (el Mac no tiene recorrido por secciones que lo empiece).
    func empezarGuiadoSiHaceFalta() {
        guard Self.guiadoPendiente, !desactivado || Self.qaGuiado else { return }
        empezarGuiado()
    }

    private static var qaGuiado: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "qa.recorrido") == "guiado"
        #else
        false
        #endif
    }

    /// El marco de un objetivo. En el tutorial de seguir, si es lo que el paso espera que aparezca, pasa al siguiente.
    func ponerMarco(_ id: String, _ marco: CGRect?) {
        marcos[id] = marco
        guard esGuiado, let marco, marco.width > 0, case .aparece(let esperado) = pasoActual?.espera,
              esperado.split(separator: "|").contains(Substring(id)) else { return }
        siguiente()
    }

    /// Pasó algo en la app (se guardó el cliente, se emitió la factura). Si un paso lo espera, el tutorial sigue
    /// después de él (también si la persona se adelantó: guardó sin tocar «Siguiente»).
    func ocurrio(_ evento: String) {
        guard esGuiado else { return }
        ocurridos.insert(evento)
        revisarEspera()
    }

    /// Lo que la pantalla da por hecho (o deja de dar): enciende o apaga «Siguiente».
    func marcar(_ clave: String, _ hecho: Bool) {
        guard esGuiado || !hecho else { return }
        if hecho { cumplidos.insert(clave) } else { cumplidos.remove(clave) }
    }

    /// Tras cambiar de paso (o al pasar algo): lo ya hecho no se vuelve a pedir.
    private func revisarEspera() {
        guard esGuiado, !cambiando else { return }
        let hechos = pasos.indices.filter { indice in
            guard indice >= paso, case .evento(let evento) = pasos[indice].espera else { return false }
            return ocurridos.contains(evento)
        }
        if let ultimo = hechos.last {
            paso = ultimo
            siguiente()
            return
        }
        if case .aparece(let esperado) = pasoActual?.espera, marco(de: esperado) != nil { siguiente() }
    }

    /// Se cerró una hoja. Si el paso a la vista vivía en ella (la persona canceló el editor), el tutorial vuelve al
    /// primer paso de su grupo, el que lo abre, en vez de quedarse con la tarjeta dentro de una hoja que ya no está.
    func hojaCerrada() {
        hojasAbiertas = max(hojasAbiertas - 1, 0)
        guard esGuiado else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard esGuiado, !cambiando, let actual = pasoActual, actual.enHoja, !objetivoPresente(actual) else { return }
            guard let inicio = pasos.indices.first(where: { pasos[$0].grupo == actual.grupo && pasos[$0].grupo != nil }),
                  inicio < paso else { return }
            // Lo hecho en ese editor ya no vale: el nuevo empieza vacío.
            for candidato in pasos where candidato.grupo == actual.grupo {
                if case .evento(let evento) = candidato.espera { ocurridos.remove(evento) }
            }
            paso = inicio - 1
            ir(adelante: true)
        }
    }

    /// «3 de 15»: en el tutorial de seguir no cuentan los pasos que no se van a ver (grupos saltados y el sales tax
    /// cuando sí hay apartado para impuestos).
    var numeracion: (actual: Int, total: Int) {
        guard esGuiado else { return (paso + 1, pasos.count) }
        let cuentan = pasos.indices.filter { indice in
            let candidato = pasos[indice]
            if let grupo = candidato.grupo, gruposSaltados.contains(grupo) { return false }
            if let otro = candidato.siSeSalto, !gruposSaltados.contains(otro) { return false }
            return true
        }
        return ((cuentan.firstIndex { $0 >= paso } ?? cuentan.count - 1) + 1, cuentan.count)
    }

    /// El marco de un objetivo del tutorial de seguir: puede llevar alternativas separadas por «|» (la barra de abajo
    /// del iPhone o el botón de arriba de la hoja ancha); vale la primera que esté.
    func marco(de objetivo: String) -> CGRect? {
        objetivo.split(separator: "|").lazy.compactMap { self.marcos[String($0)] }.first { $0.width > 0 }
    }

    private func objetivoPresente(_ paso: RecorridoID.Paso) -> Bool {
        guard let objetivo = paso.objetivo else { return true }
        #if os(iOS)
        for parte in objetivo.split(separator: "|") where parte.hasPrefix("ax:") {
            if Self.marcoEnVentana(etiqueta: String(parte.dropFirst(3))) != nil { return true }
        }
        #endif
        return marco(de: objetivo) != nil
    }

    /// Espera a que el objetivo aparezca (la pantalla de detrás se rehace al cerrar la hoja); `false` si no llega.
    private func esperarObjetivo(_ paso: RecorridoID.Paso, intentos: Int = 12) async -> Bool {
        for _ in 0..<intentos {
            if objetivoPresente(paso) { return true }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return objetivoPresente(paso)
    }

    private func cerrarTeclado() {
        #if os(iOS)
        guard teclado > 0 else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    #if os(iOS)
    /// Los botones de la barra de una hoja (`ax:`) se buscan mientras su paso está a la vista: la hoja tarda en subir.
    private func seguirBotonDeBarra() {
        let botones = (pasoActual?.objetivo ?? "").split(separator: "|").map(String.init).filter { $0.hasPrefix("ax:") }
        guard !botones.isEmpty else { return }
        let indice = paso
        Task {
            for _ in 0..<40 {
                guard esGuiado, paso == indice else { return }
                for boton in botones {
                    let marco = Self.marcoEnVentana(etiqueta: String(boton.dropFirst(3)))
                    if marcos[boton] != marco { marcos[boton] = marco }
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
    #endif

    /// «Más › Ayuda › Tutorial completo»: cada pantalla explica todos sus botones la primera vez que se abre (tester de
    /// Beta Family, 18-nov: «too short»). No sale solo; el recorrido corto de la primera vez no cambia.
    private(set) var aFondo = UserDefaults.standard.bool(forKey: Recorrido.aFondoKey)
    /// El recorrido a la vista es el del «Tutorial completo».
    private(set) var activoAFondo = false
    private static let aFondoKey = "recorrido.aFondo"

    init() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "qa.recorrido") == "reset" {
            Self.olvidarTodo()
            defaults.set(false, forKey: Self.aFondoKey)
            aFondo = false
        }
        // `-qa.recorrido afondo`: el «Tutorial completo» desde el principio, sin pantallas vistas.
        if defaults.string(forKey: "qa.recorrido") == "afondo" {
            Self.olvidarAFondo()
            aFondo = true
        }
        // `-qa.recorrido guiado`: el tutorial de seguir al llegar a Inicio (con `-qa.alta 1 -qa.altaCrear 1`, recién
        // creada la empresa).
        if defaults.string(forKey: "qa.recorrido") == "guiado" { Self.pedirGuiado() }
        let usaQA = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-qa.") }
        desactivado = usaQA && defaults.object(forKey: "qa.recorrido") == nil
        #endif
        vistos = Set(RecorridoID.allCases.filter { desactivado || Self.visto($0) })
    }

    private static func olvidarAFondo() {
        for id in RecorridoID.allCases { UserDefaults.standard.removeObject(forKey: id.fondoKey) }
    }

    /// Enciende el «Tutorial completo» desde el principio: lleva a Inicio, que lo empieza.
    func activarAFondo() {
        guard activo == nil else { return }
        Self.olvidarAFondo()
        aFondo = true
        UserDefaults.standard.set(true, forKey: Self.aFondoKey)
        pedidoInicio += 1
    }

    func apagarAFondo() {
        aFondo = false
        UserDefaults.standard.set(false, forKey: Self.aFondoKey)
    }

    private static func visto(_ id: RecorridoID) -> Bool {
        UserDefaults.standard.bool(forKey: id.seenKey) || NSUbiquitousKeyValueStore.default.bool(forKey: id.seenKey)
    }

    /// También al borrar los datos de ejemplo («Empezar con mi empresa»): quien exploró la empresa inventada vuelve a
    /// ver el recorrido con la suya, que es cuando más le sirve (tester de Beta Family, 18-nov).
    static func olvidarTodo() {
        for id in RecorridoID.allCases {
            UserDefaults.standard.removeObject(forKey: id.seenKey)
            NSUbiquitousKeyValueStore.default.removeObject(forKey: id.seenKey)
        }
    }

    /// Sube con «Ver el recorrido otra vez»: `RootView` lleva a Inicio, que empieza el recorrido.
    private(set) var pedidoInicio = 0

    /// «Ver el recorrido otra vez»: desde el principio, en Inicio (empezar por el de Más, que es el último, hacía creer
    /// que solo salía el final; tester de Beta Family, 18-nov). Las demás pestañas lo vuelven a enseñar al abrirlas.
    func repetirTodo() {
        guard activo == nil else { return }
        Self.olvidarTodo()
        vistos = []
        apagarAFondo()   // «otra vez» es el corto
        pedidoInicio += 1
    }

    /// Al entrar en una pestaña: si no se ha visto, espera a que la pantalla se coloque y empieza.
    func empezarSiHaceFalta(_ id: RecorridoID?) {
        guard let id, activo == nil else { return }
        // Empresa recién creada: en Inicio, el tutorial de seguir en vez del recorrido corto.
        if id == .home || id == .padHome, Self.guiadoPendiente {
            empezarGuiadoSiHaceFalta()
            return
        }
        guard !desactivado, id.esIPad == esIPad else { return }
        let fondo = aFondo && !esIPad
        if fondo {
            guard !UserDefaults.standard.bool(forKey: id.fondoKey) else { return }
        } else {
            guard id.esPestana, !Self.visto(id) else { return }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard activo == nil else { return }
            let todos = id.pasos(aFondo: fondo)
            #if os(iOS)
            for objetivo in todos.compactMap(\.objetivo) where objetivo.hasPrefix("ax:") {
                marcos[objetivo] = Self.marcoEnVentana(etiqueta: String(objetivo.dropFirst(3)))
            }
            #endif
            // Solo los pasos cuyo objetivo está a la vista (sin facturas no hay «Por cobrar», por ejemplo); los que
            // están más abajo se buscan al llegar.
            pasos = todos.filter { $0.objetivo == nil || $0.enLista || tieneMarco($0) }
            guard !pasos.isEmpty else { return }
            activoAFondo = fondo
            paso = 0
            tarjetaVisible = false
            withAnimation(.easeOut(duration: 0.25)) { activo = id }
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.8)) {
                tarjetaVisible = true
            }
        }
    }

    /// Entero en la pantalla, sin la barra de navegación de arriba ni la de pestañas de abajo.
    private func aLaVista(_ paso: RecorridoID.Paso) -> Bool {
        guard let objetivo = paso.objetivo, let marco = marco(de: objetivo), altoPantalla > 0 else { return false }
        // Con el teclado a la vista, lo que queda detrás no cuenta (el tutorial de seguir pide escribir).
        return marco.minY >= 100 && marco.maxY <= altoPantalla - max(margenAbajo, teclado + 8)
    }

    /// Al menos una parte en la pantalla (con letra grande, la tarjeta de Inicio no cabe entera).
    private func asoma(_ paso: RecorridoID.Paso) -> Bool {
        guard let objetivo = paso.objetivo, let marco = marco(de: objetivo), altoPantalla > 0 else { return false }
        return marco.maxY > 100 && marco.minY < altoPantalla - max(margenAbajo, teclado + 8)
    }

    private func tieneMarco(_ paso: RecorridoID.Paso) -> Bool {
        guard let objetivo = paso.objetivo else { return true }
        return marco(de: objetivo) != nil
    }

    /// Fuera de la pantalla del todo, o sin medir (una fila de `List` que ya no se dibuja). Lo de arriba no lleva
    /// `desplazar`: solo pasa al volver atrás después de bajar (por eso lleva también su `.id`).
    private func fuera(_ paso: RecorridoID.Paso) -> Bool {
        guard let objetivo = paso.objetivo else { return false }
        guard let marco = marco(de: objetivo) else { return true }
        guard altoPantalla > 0 else { return false }
        return marco.maxY <= 100 || marco.minY >= altoPantalla
    }

    /// Desplaza la pantalla hasta el objetivo si hace falta; `false` si no aparece (y el paso se salta).
    private func ponerALaVista(_ paso: RecorridoID.Paso) async -> Bool {
        guard let objetivo = paso.objetivo, !objetivo.hasPrefix("ax:") else { return true }
        // En una `List` el marco guardado puede ser de antes (la fila deja de medirse al salir de la pantalla):
        // ahí se desplaza siempre.
        let haceFalta = paso.desplazar ? paso.enLista || !aLaVista(paso) : fuera(paso)
        guard haceFalta else { return true }
        let visible = { paso.desplazar ? self.asoma(paso) : !self.fuera(paso) }
        // Con alternativas («fila|botón»), se desplaza a la que esté (o a la primera).
        desplazarA = objetivo.split(separator: "|").map(String.init).first { (marcos[$0]?.width ?? 0) > 0 }
            ?? String(objetivo.split(separator: "|").first ?? Substring(objetivo))
        try? await Task.sleep(for: .milliseconds(450))
        desplazarA = nil
        // La última fila de una lista larga tarda más en dibujarse (y medirse) al llegar: se espera un poco.
        for _ in 0..<4 where !visible() { try? await Task.sleep(for: .milliseconds(150)) }
        return visible()
    }

    /// Adónde lleva deslizar la tarjeta: horizontal y de al menos `umbral` pt, o un golpe rápido que lo pasaría
    /// de largo; lo vertical o corto no cuenta.
    nonisolated static func deslizamiento(_ traslacion: CGSize, previsto: CGSize,
                                          umbral: CGFloat = 50) -> Deslizamiento? {
        func horizontal(_ t: CGSize, _ minimo: CGFloat) -> CGFloat? {
            abs(t.width) >= minimo && abs(t.width) > abs(t.height) * 1.5 ? t.width : nil
        }
        let golpe = traslacion.width * previsto.width > 0 ? horizontal(previsto, umbral * 2) : nil
        guard let dx = horizontal(traslacion, umbral) ?? golpe else { return nil }
        return dx < 0 ? .siguiente : .anterior
    }

    /// El paso al que lleva deslizar, sin salirse: en el primero no hay anterior y en el último no termina (para eso,
    /// «Entendido»; deslizar no cierra el recorrido sin querer).
    nonisolated static func pasoTras(_ deslizamiento: Deslizamiento, actual: Int, total: Int) -> Int? {
        let destino = deslizamiento == .siguiente ? actual + 1 : actual - 1
        return (0..<total).contains(destino) ? destino : nil
    }

    /// La tarjeta deslizada, o ajustada con VoiceOver.
    func deslizar(_ deslizamiento: Deslizamiento) {
        // En el tutorial de seguir se avanza haciendo, no deslizando.
        guard !esGuiado else { return }
        guard Self.pasoTras(deslizamiento, actual: paso, total: pasos.count) != nil else { return }
        if deslizamiento == .siguiente { siguiente() } else { anterior() }
    }

    /// Tocar fuera de la tarjeta pasa al siguiente, salvo en la presentación recién salida: ese toque iba para la app
    /// (abrir la sección otra vez, una subsección de la barra) y se saltaba el primer paso sin leerlo (Yurii S., iPad,
    /// build 65: «en Gastos empecé en el paso 2»).
    func tocarVelo() {
        guard !esGuiado else { return }
        guard paso > 0 || Date.now.timeIntervalSince(visibleDesde) > 1 else { return }
        siguiente()
    }

    func siguiente() {
        guard !cambiando, activo != nil else { return }
        guard paso + 1 < pasos.count else { terminar(); return }
        ir(adelante: true)
    }

    /// El paso anterior (deslizando la tarjeta a la derecha); en el primero no hace nada.
    func anterior() {
        guard !cambiando, activo != nil, paso > 0 else { return }
        ir(adelante: false)
    }

    private func ir(adelante: Bool) {
        cambiando = true
        let salto = adelante ? 1 : -1
        Task {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeIn(duration: 0.12)) { tarjetaVisible = false }
            var proximo = paso + salto
            // Lo que no se pone a la vista se salta (hacia atrás para en la presentación, que siempre está).
            while pasos.indices.contains(proximo) {
                if esGuiado {
                    if await sirveGuiado(proximo) { break }
                } else if await ponerALaVista(pasos[proximo]) {
                    break
                }
                proximo += salto
            }
            guard pasos.indices.contains(proximo) else {
                cambiando = false
                if adelante { terminar() } else { withAnimation(.easeOut(duration: 0.24)) { tarjetaVisible = true } }
                return
            }
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.2)) { paso = proximo; tarjetaVisible = true }
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { paso = proximo }
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeOut(duration: 0.24)) { tarjetaVisible = true }
            }
            cambiando = false
            if esGuiado {
                #if os(iOS)
                seguirBotonDeBarra()
                #endif
                revisarEspera()
            }
        }
    }

    /// Tutorial de seguir: si el paso se enseña. El primero de un grupo espera a que su objetivo esté (si no llega, se
    /// salta el grupo entero); los demás se enseñan aunque su objetivo aún no esté (la hoja que lo trae está subiendo).
    private func sirveGuiado(_ indice: Int) async -> Bool {
        let candidato = pasos[indice]
        if let grupo = candidato.grupo, gruposSaltados.contains(grupo) { return false }
        if let otro = candidato.siSeSalto, !gruposSaltados.contains(otro) { return false }
        // Lo que explica sin pedir que se escriba: el teclado se cierra, que tapaba el impuesto y la barra de «Emitir».
        if !candidato.escribe { cerrarTeclado() }
        let empiezaGrupo = candidato.grupo != nil && (indice == 0 || pasos[indice - 1].grupo != candidato.grupo)
        guard empiezaGrupo else {
            if candidato.desplazar { _ = await ponerALaVista(candidato) }
            return true
        }
        // Un paso de la pantalla de detrás espera a que se cierren las hojas (y lo que abren: enviar la factura).
        if !candidato.enHoja {
            if hojasAbiertas > 0 { withAnimation(.easeOut(duration: 0.2)) { esperandoHojas = true } }
            while hojasAbiertas > 0, esGuiado { try? await Task.sleep(for: .milliseconds(300)) }
            esperandoHojas = false
            try? await Task.sleep(for: .milliseconds(400))
        }
        // Lo que se toca en Inicio puede estar más abajo: primero se desplaza (si ya se ve, no hace nada).
        if candidato.desplazar { _ = await ponerALaVista(candidato) }
        if await esperarObjetivo(candidato), await ponerALaVista(candidato) { return true }
        if let grupo = candidato.grupo { gruposSaltados.insert(grupo) }
        return false
    }

    func terminar() {
        guard let activo else { return }
        // El tutorial de seguir enseña Inicio: su recorrido corto ya no hace falta.
        if activo == .guiado {
            for id in [RecorridoID.home, .padHome] {
                UserDefaults.standard.set(true, forKey: id.seenKey)
                NSUbiquitousKeyValueStore.default.set(true, forKey: id.seenKey)
                vistos.insert(id)
            }
            cumplidos = []
        }
        if activoAFondo { UserDefaults.standard.set(true, forKey: activo.fondoKey) }
        // El largo de una pestaña vale también por el corto (no sale después).
        if activo.esPestana {
            UserDefaults.standard.set(true, forKey: activo.seenKey)
            NSUbiquitousKeyValueStore.default.set(true, forKey: activo.seenKey)
        }
        vistos.insert(activo)
        desplazarA = nil
        withAnimation(.easeOut(duration: 0.25)) {
            tarjetaVisible = false
            self.activo = nil
        }
    }

    #if os(iOS)
    /// Los botones de la barra de navegación viven en vistas de UIKit: su marco de SwiftUI no es el de la ventana.
    private static func marcoEnVentana(etiqueta: String) -> CGRect? {
        func buscar(_ vista: UIView) -> CGRect? {
            guard !vista.isHidden, vista.alpha > 0.01 else { return nil }
            if let label = vista.accessibilityLabel, label.hasPrefix(etiqueta), vista.bounds.width > 0 {
                let marco = vista.convert(vista.bounds, to: nil)
                if vista.window?.bounds.intersects(marco) ?? false { return marco }
            }
            // iOS 27: el botón de la barra ya no lleva la etiqueta en su vista, sino en un elemento de accesibilidad
            // dentro de ella (`UIKitBarItemHost` › `AccessibilityNode`); su marco viene en coordenadas de la pantalla.
            if let ventana = vista.window {
                for case let elemento as NSObject in vista.accessibilityElements ?? [] where !(elemento is UIView) {
                    guard let label = elemento.accessibilityLabel, label.hasPrefix(etiqueta) else { continue }
                    let marco = ventana.convert(elemento.accessibilityFrame, from: ventana.screen.coordinateSpace)
                    if marco.width > 0, ventana.bounds.intersects(marco) { return marco }
                }
            }
            for sub in vista.subviews { if let marco = buscar(sub) { return marco } }
            return nil
        }
        let ventanas = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        for ventana in ventanas where ventana.isKeyWindow { if let marco = buscar(ventana) { return marco } }
        return nil
    }
    #endif
}

extension View {
    /// Marca una parte de la pantalla como paso del recorrido.
    func recorridoObjetivo(_ id: String) -> some View { modifier(RecorridoObjetivo(id: id)) }

    /// Lo mismo, solo si `condicion` (la primera fila de una lista).
    @ViewBuilder
    func recorridoObjetivo(_ id: String, si condicion: Bool) -> some View {
        if condicion { recorridoObjetivo(id) } else { self }
    }

    /// Tutorial de seguir: la pantalla da por hecho un paso (`Espera.listo`) mientras `hecho` sea cierto.
    func recorridoCumple(_ clave: String, _ hecho: Bool) -> some View { modifier(RecorridoCumple(clave: clave, hecho: hecho)) }

    /// Desplaza la lista o el `ScrollView` hasta lo que el recorrido va a iluminar (la vista lleva `.id` igual al
    /// objetivo).
    func siguiendoRecorrido(_ proxy: ScrollViewProxy) -> some View {
        modifier(SiguiendoRecorrido(proxy: proxy))
    }

    /// Lo mismo, para una lista o un formulario sin `ScrollViewReader` propio.
    func recorridoDesplazable() -> some View {
        ScrollViewReader { proxy in siguiendoRecorrido(proxy) }
    }
}

private struct RecorridoCumple: ViewModifier {
    let clave: String
    let hecho: Bool
    @Environment(Recorrido.self) private var recorrido: Recorrido?

    func body(content: Content) -> some View {
        content
            .onChange(of: hecho, initial: true) { recorrido?.marcar(clave, hecho) }
            .onChange(of: recorrido?.esGuiado) { recorrido?.marcar(clave, hecho) }
            .onDisappear { recorrido?.marcar(clave, false) }
    }
}

private struct SiguiendoRecorrido: ViewModifier {
    let proxy: ScrollViewProxy
    @Environment(Recorrido.self) private var recorrido: Recorrido?

    func body(content: Content) -> some View {
        content.onChange(of: recorrido?.desplazarA) { _, id in
            guard let id else { return }
            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
        }
    }
}

/// `ScrollView` que se desplaza hasta lo que el recorrido va a iluminar.
struct RecorridoScrollView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { content }.siguiendoRecorrido(proxy)
        }
    }
}

private struct RecorridoObjetivo: ViewModifier {
    let id: String
    @Environment(Recorrido.self) private var recorrido: Recorrido?
    /// Sube al aparecer: así se vuelve a medir aunque el marco sea el mismo de antes (al volver a una pestaña, el
    /// marco no cambia y `onGeometryChange` no avisaba; sin esto, Inicio se quedaba sin sus pasos).
    @State private var apariciones = 0
    /// El último marco que midió esta vista: al desaparecer solo borra el suyo. Con el mismo objetivo en dos sitios
    /// (la fila de «Primeros pasos» de la primera vez y la del tablero), la vieja se iba después de llegar la nueva y
    /// borraba su marco: el tutorial de seguir no encontraba la fila.
    @State private var ultimo: CGRect?

    nonisolated private struct Medida: Equatable, Sendable {
        var marco: CGRect
        var aparicion: Int
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Medida.self) { Medida(marco: $0.frame(in: .global), aparicion: apariciones) } action: {
                ultimo = $0.marco
                recorrido?.ponerMarco(id, $0.marco)
            }
            .onAppear { apariciones += 1 }
            // Al cerrar una pantalla su marco no sirve: la factura siguiente puede no tener «Registrar pago».
            .onDisappear {
                guard let recorrido, recorrido.marcos[id] == nil || recorrido.marcos[id] == ultimo else { return }
                recorrido.ponerMarco(id, nil)
            }
    }
}

extension View {
    /// Pantalla con recorrido propio (solo con el «Tutorial completo»): lo empieza al aparecer. En el iPad y el Mac no
    /// hay `Recorrido` y no hace nada.
    func recorridoPantalla(_ id: RecorridoID) -> some View { modifier(RecorridoPantalla(id: id)) }

    /// El velo del recorrido de una hoja (los editores), encima de su barra de navegación. Va en `editorSheetSizing`.
    func recorridoEnHoja() -> some View { modifier(RecorridoEnHoja()) }
}

private struct RecorridoPantalla: ViewModifier {
    let id: RecorridoID
    @Environment(Recorrido.self) private var recorrido: Recorrido?

    func body(content: Content) -> some View {
        content.onAppear { recorrido?.empezarSiHaceFalta(id) }
    }
}

private struct RecorridoEnHoja: ViewModifier {
    @Environment(Recorrido.self) private var recorrido: Recorrido?

    func body(content: Content) -> some View {
        content.overlay {
            if let recorrido, recorrido.capaEnHoja { RecorridoOverlay(enHoja: true).environment(recorrido) }
        }
        .onAppear { recorrido?.hojaAbierta() }
        .onDisappear { recorrido?.hojaCerrada() }
    }
}

/// Velo oscuro con un hueco redondeado; el hueco (y su radio) se animan de un paso al siguiente.
nonisolated private struct VeloConHueco: Shape {
    var hueco: CGRect
    var radio: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(hueco.origin.x, hueco.origin.y),
                           AnimatablePair(AnimatablePair(hueco.width, hueco.height), radio))
        }
        set {
            hueco = CGRect(x: newValue.first.first, y: newValue.first.second,
                           width: newValue.second.first.first, height: newValue.second.first.second)
            radio = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: hueco, cornerSize: CGSize(width: radio, height: radio), style: .continuous)
        return path
    }
}

struct RecorridoOverlay: View {
    /// El de una hoja (editores) o el de las pestañas: cada uno dibuja solo los recorridos de su capa.
    var enHoja = false
    @Environment(Recorrido.self) private var recorrido
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var focoEnTarjeta: Bool
    /// Alto de la tarjeta, para que quepa entera en la pantalla (con letra grande lo iluminado puede ocupar casi todo).
    @State private var altoTarjeta: CGFloat = 150
    @State private var alto: CGFloat = 0

    /// El alto de la capa del recorrido a la vista (la hoja es más baja que la pantalla).
    private func ponerAlto() {
        if recorrido.capaEnHoja == enHoja, alto > 0 {
            // Los marcos son de la ventana: el alto también (el del velo salía 81 pt más bajo y la última fila de
            // «Más», «Ayuda», contaba como tapada aunque se veía).
            #if os(iOS)
            let ventana = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first(where: \.isKeyWindow)?.bounds.height
            recorrido.altoPantalla = ventana ?? alto
            #else
            recorrido.altoPantalla = alto
            #endif
            // En el iPad a pantalla completa no hay barra de pestañas abajo.
            recorrido.margenAbajo = enHoja ? 34 : recorrido.esIPad ? 24 : 100
        }
    }

    var body: some View {
        GeometryReader { geo in
            if recorrido.activo != nil, !recorrido.esperandoHojas, recorrido.capaEnHoja == enHoja,
               recorrido.pasos.indices.contains(recorrido.paso) {
                contenido(geo: geo)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { alto = $0; ponerAlto() }
        .onChange(of: recorrido.activo, initial: true) { ponerAlto() }
        .onChange(of: recorrido.capaEnHoja) { ponerAlto() }
        #if os(iOS)
        // El tutorial de seguir pide escribir: la tarjeta se queda encima del teclado.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { aviso in
            guard let fin = aviso.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let pantalla = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.height ?? fin.maxY
            recorrido.teclado = max(0, pantalla - fin.minY)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            recorrido.teclado = 0
        }
        #endif
        .onChange(of: reduceMotion, initial: true) { recorrido.reduceMotion = reduceMotion }
        .onChange(of: recorrido.tarjetaVisible) { if recorrido.tarjetaVisible { focoEnTarjeta = true } }
    }

    @ViewBuilder
    private func contenido(geo: GeometryProxy) -> some View {
        let paso = recorrido.pasos[recorrido.paso]
        let origen = geo.frame(in: .global).origin
        let centro = CGRect(x: geo.size.width / 2, y: geo.size.height / 2, width: 0, height: 0)
        let hueco = paso.objetivo.flatMap { recorrido.esGuiado ? recorrido.marco(de: $0) : recorrido.marcos[$0] }
            .map { $0.offsetBy(dx: -origen.x, dy: -origen.y).insetBy(dx: -6, dy: -6) }
        let radio = min((hueco?.height ?? 0) / 2, 22)
        let ancho = min(geo.size.width - 32, 380)

        ZStack(alignment: .topLeading) {
            // Los pasos sin nada iluminado (la presentación de cada recorrido) difuminan la pantalla: con el velo
            // solo, en oscuro casi no se distinguía de la app y la tarjeta no destacaba (Yurii S., build 54).
            if hueco == nil {
                Rectangle().fill(.ultraThinMaterial)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
            if recorrido.esGuiado && paso.objetivo != nil {
                // Tutorial de seguir: lo iluminado se toca de verdad (el toque pasa por el hueco). En una hoja el velo
                // no detiene nada: hay que escribir, elegir en menús y tocar «Guardar» en la barra, que vive en UIKit.
                // En la pantalla de detrás, el resto queda tapado para no perderse por otro camino.
                let velo = VeloConHueco(hueco: hueco ?? CGRect(x: geo.size.width / 2, y: -40, width: 0, height: 0), radio: radio)
                velo.fill(Color.black.opacity(paso.enHoja ? 0.35 : 0.5), style: FillStyle(eoFill: true))
                    .contentShape(velo, eoFill: true)
                    .allowsHitTesting(!paso.enHoja && hueco != nil)
                    .accessibilityHidden(true)
            } else {
                VeloConHueco(hueco: hueco ?? centro, radio: radio)
                    .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                    .contentShape(Rectangle())
                    // Con VoiceOver, el velo no es un botón: así no atrapa el foco.
                    .onTapGesture { if !voiceOver { recorrido.tocarVelo() } }
                    .accessibilityHidden(true)
                    .id(reduceMotion ? recorrido.paso : 0)
            }

            if let hueco {
                Anillo(radio: radio, late: !reduceMotion)
                    .frame(width: hueco.width, height: hueco.height)
                    .offset(x: hueco.minX, y: hueco.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .id(recorrido.paso)
            }

            if recorrido.tarjetaVisible {
                globo(paso: paso, hueco: hueco, ancho: ancho, geo: geo)
            }
        }
    }

    @ViewBuilder
    private func globo(paso: RecorridoID.Paso, hueco: CGRect?, ancho: CGFloat, geo: GeometryProxy) -> some View {
        // Lo que queda a la vista encima del teclado (el tutorial de seguir pide escribir).
        let altoUtil = max(geo.size.height - recorrido.teclado, altoTarjeta + 120)
        if recorrido.esGuiado && paso.objetivo != nil && hueco == nil {
            // Tutorial de seguir con lo iluminado aún sin medir (la hoja sube, el teclado tapa «Emitir»): la tarjeta
            // abajo, sin flecha; el hueco aparece cuando el objetivo esté.
            tarjeta(paso: paso)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { altoTarjeta = $0 }
                .frame(width: ancho)
                .offset(x: (geo.size.width - ancho) / 2, y: altoUtil - altoTarjeta - 34)
                .transition(.opacity)
        } else if let hueco, hueco.height > geo.size.height * 0.5, geo.size.width - hueco.maxX >= ancho + 40 {
            // iPad: lo iluminado ocupa casi todo el alto (la barra lateral) y a su derecha cabe la tarjeta: al lado, a
            // media altura, sin flecha.
            tarjeta(paso: paso)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { altoTarjeta = $0 }
                .frame(width: ancho)
                .modifier(TarjetaDeslizable(reduceMotion: reduceMotion))
                .offset(x: hueco.maxX + 20, y: max((geo.size.height - altoTarjeta) / 2, 54))
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: -8)))
        } else if let hueco {
            // Centrada sobre lo iluminado y dentro de la pantalla: en el iPhone ocupa casi todo el ancho y queda igual
            // que antes; en el iPad la flecha llega a lo que está a la izquierda (la lista, la barra lateral).
            let izquierda = min(max(hueco.midX - ancho / 2, 16), geo.size.width - ancho - 16)
            // Debajo o encima, donde haya más sitio; si no cabe entera, se queda dentro de la pantalla (sin flecha,
            // tapando parte de lo iluminado).
            let debajo = altoUtil - hueco.maxY >= hueco.minY
            let deseado = debajo ? hueco.maxY + 16 : hueco.minY - 16 - altoTarjeta
            let arriba = min(max(deseado, 54), altoUtil - altoTarjeta - (recorrido.teclado > 0 ? 8 : 34))
            let conFlecha = abs(arriba - deseado) < 1
            let flecha = min(max(hueco.midX - izquierda, 30), ancho - 30)
            VStack(spacing: 0) {
                if conFlecha && debajo {
                    Flecha().fill(Palette.surface).frame(width: 22, height: 10)
                        .frame(width: ancho, alignment: .leading).offset(x: flecha - 11)
                }
                tarjeta(paso: paso)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { altoTarjeta = $0 }
                if conFlecha && !debajo {
                    Flecha().fill(Palette.surface).frame(width: 22, height: 10).rotationEffect(.degrees(180))
                        .frame(width: ancho, alignment: .leading).offset(x: flecha - 11)
                }
            }
            .frame(width: ancho)
            .modifier(TarjetaDeslizable(reduceMotion: reduceMotion))
            .offset(x: izquierda, y: conFlecha && debajo ? arriba - 10 : arriba)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: debajo ? -8 : 8)),
                removal: .opacity.combined(with: .scale(scale: 0.97))))
        } else {
            presentacion(paso: paso)
                .frame(width: ancho)
                .modifier(TarjetaDeslizable(reduceMotion: reduceMotion))
                .frame(width: geo.size.width, height: geo.size.height)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.94)),
                    removal: .opacity.combined(with: .scale(scale: 0.97))))
        }
    }

    private var esUltimo: Bool { recorrido.paso + 1 >= recorrido.pasos.count }

    /// «2 de 5» en todos los recorridos, también en la presentación; con letra de accesibilidad, «Paso 2 de 5». Antes,
    /// puntos hasta 7 pasos y números en el «Tutorial completo» (12; los puntos partían «Siguiente» en tres líneas):
    /// dos estilos en la misma app (Eric, Beta Family, build 55). Con VoiceOver se ajusta para cambiar de paso.
    /// El mismo `PasoIndicador` que la bienvenida y el alta (repaso visual, build 56).
    private var indicador: some View {
        PasoIndicador(actual: recorrido.numeracion.actual, total: recorrido.numeracion.total)
            .accessibilityAdjustableAction { direccion in
                switch direccion {
                case .increment: recorrido.deslizar(.siguiente)
                case .decrement: recorrido.deslizar(.anterior)
                @unknown default: break
                }
            }
    }

    /// Primer paso: centrado, con el icono que se anima, «Empezar» a todo el ancho y «Saltar» debajo.
    private func presentacion(paso: RecorridoID.Paso) -> some View {
        VStack(spacing: 0) {
            Image(systemName: paso.icono)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Palette.brand)
                .frame(width: 76, height: 76)
                .background(Palette.brandWash, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .symbolEffect(.bounce, options: .repeat(2), isActive: !reduceMotion)
                .accessibilityHidden(true)
            Text(paso.titulo).font(.title2.bold()).foregroundStyle(Palette.ink)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focoEnTarjeta)
            Text(paso.mensaje).font(.body).foregroundStyle(Palette.ink2)
                .padding(.top, 8)
            indicador.padding(.top, 18)
            if paso.final {
                despedida
            } else {
                Button(esUltimo ? String(localized: "Entendido") : String(localized: "Empezar")) { recorrido.siguiente() }
                    .buttonStyle(.primary)
                    .padding(.top, 18)
                if !esUltimo {
                    Button(recorrido.esGuiado ? String(localized: "Ahora no") : String(localized: "Saltar")) { recorrido.terminar() }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                        .frame(minHeight: 44)
                        .padding(.top, 4)
                }
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        // Arriba, más aire para el icono.
        .padding(.horizontal, Self.margenTarjeta)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .modifier(FondoDeTarjeta())
    }

    /// Pasos con foco: título, una frase, y abajo el indicador, «Saltar» y «Siguiente».
    private func tarjeta(paso: RecorridoID.Paso) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(paso.titulo).font(.headline).foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focoEnTarjeta)
            Text(paso.mensaje).font(.subheadline).foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if dynamicTypeSize.isAccessibilitySize {
                // Letra grande: uno debajo del otro, a todo el ancho.
                indicador.padding(.top, 14)
                if muestraSiguiente(paso) {
                    Button(esUltimo ? String(localized: "Entendido") : String(localized: "Siguiente")) { recorrido.siguiente() }
                        .buttonStyle(.primary)
                        .disabled(!siguienteActivo(paso))
                        .padding(.top, 12)
                }
                if !esUltimo {
                    Button(textoSaltar) { recorrido.terminar() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Palette.ink2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            } else {
                HStack(spacing: 8) {
                    indicador
                    Spacer(minLength: 8)
                    if !esUltimo {
                        Button(textoSaltar) { recorrido.terminar() }
                            .buttonStyle(.borderless)
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink2)
                            .frame(minHeight: 44)
                            .padding(.horizontal, 6)
                    }
                    if muestraSiguiente(paso) {
                        Button(esUltimo ? String(localized: "Entendido") : String(localized: "Siguiente")) { recorrido.siguiente() }
                            .buttonStyle(.primaryCompact)
                            .controlSize(.regular)
                            .fixedSize()
                            .disabled(!siguienteActivo(paso))
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, Self.margenTarjeta)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FondoDeTarjeta())
    }

    /// En el tutorial de seguir, «Saltar» sale del tutorial entero.
    private var textoSaltar: String { recorrido.esGuiado ? String(localized: "Salir") : String(localized: "Saltar") }

    /// Tutorial de seguir: sin «Siguiente» mientras espera que la persona toque lo iluminado o guarde.
    private func muestraSiguiente(_ paso: RecorridoID.Paso) -> Bool {
        switch paso.espera {
        case .aparece, .evento: false
        case .listo, nil: true
        }
    }

    /// Tutorial de seguir: «Siguiente» se enciende cuando la pantalla da el paso por hecho (escribió el nombre).
    private func siguienteActivo(_ paso: RecorridoID.Paso) -> Bool {
        guard case .listo(let clave) = paso.espera else { return true }
        return recorrido.cumplidos.contains(clave)
    }

    /// Despedida del tutorial de seguir: «Terminar», la guía de chirogra.com y, en el iPhone, el tutorial completo
    /// (pantalla por pantalla) para lo demás.
    @ViewBuilder
    private var despedida: some View {
        Button(String(localized: "Terminar")) { recorrido.terminar() }
            .buttonStyle(.primary)
            .padding(.top, 18)
        Link(destination: ChirograLinks.guide) {
            Label(String(localized: "Guía de uso en chirogra.com"), systemImage: "safari")
        }
        .font(.subheadline)
        .foregroundStyle(Palette.brand)
        .frame(minHeight: 44)
        .padding(.top, 4)
        #if os(iOS)
        if !recorrido.esIPad {
            Button(String(localized: "Encender el tutorial completo")) {
                recorrido.terminar()
                recorrido.activarAFondo()
            }
            .font(.subheadline)
            .foregroundStyle(Palette.brand)
            .frame(minHeight: 44)
        }
        #endif
    }

    /// Margen lateral de las dos tarjetas (antes 24 en la presentación y 20/16 en los pasos; repaso visual, build 56).
    private static let margenTarjeta: CGFloat = 20
}

/// Fondo, radio y sombra de las dos tarjetas del recorrido: antes radio 30 con sombra 0.3/30 en la presentación y radio
/// 22 con 0.28/24 en los pasos; ahora `Metrics.cardRadius` y la sombra de los pasos en las dos (repaso visual, build 56).
private struct FondoDeTarjeta: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 24, y: 8)
            .modifier(TarjetaAccesible())
    }
}

/// La tarjeta es una ventana modal para VoiceOver; el gesto de escape cierra el recorrido.
private struct TarjetaAccesible: ViewModifier {
    @Environment(Recorrido.self) private var recorrido

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .contain)
            // En el tutorial de seguir, lo iluminado se toca: con VoiceOver tiene que poder alcanzarse (modal lo
            // escondía), salvo en la presentación y la despedida.
            .accessibilityAddTraits(recorrido.esGuiado && recorrido.pasoActual?.objetivo != nil ? [] : .isModal)
            .accessibilityAction(.escape) { recorrido.terminar() }
    }
}

/// Anillo blanco alrededor de lo iluminado; cuando el foco llega, late 2 veces y se queda quieto.
private struct Anillo: View {
    let radio: CGFloat
    let late: Bool
    @State private var fuera = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radio, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 2)
            if late {
                RoundedRectangle(cornerRadius: radio, style: .continuous)
                    .stroke(Color.white, lineWidth: 2)
                    .scaleEffect(fuera ? 1.1 : 1)
                    .opacity(fuera ? 0 : 0.85)
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.4).repeatCount(2, autoreverses: false).delay(0.5)) { fuera = true }
                    }
            }
        }
    }
}

/// Deslizar la tarjeta, como en la bienvenida (Eric, Beta Family, build 55): a la izquierda, el paso siguiente; a la
/// derecha, el anterior. Solo la tarjeta: el velo y lo iluminado siguen con el toque, y los botones con el suyo (el
/// arrastre empieza a los 20 pt). Mientras se arrastra, la tarjeta sigue un poco al dedo, y menos si no hay adónde ir;
/// con «Reducir movimiento», quieta.
private struct TarjetaDeslizable: ViewModifier {
    let reduceMotion: Bool
    @Environment(Recorrido.self) private var recorrido
    @State private var arrastre: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: arrastre)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { valor in
                        let t = valor.translation
                        guard !reduceMotion, abs(t.width) > abs(t.height) else { return }
                        let hacia: Deslizamiento = t.width < 0 ? .siguiente : .anterior
                        let hay = Recorrido.pasoTras(hacia, actual: recorrido.paso, total: recorrido.pasos.count) != nil
                        arrastre = t.width * (hay ? 0.35 : 0.12)
                    }
                    .onEnded { valor in
                        if arrastre != 0 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { arrastre = 0 }
                        }
                        if let hacia = Recorrido.deslizamiento(valor.translation, previsto: valor.predictedEndTranslation) {
                            recorrido.deslizar(hacia)
                        }
                    }
            )
    }
}

nonisolated private struct Flecha: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX + 3, y: rect.minY + 1))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.midX - 3, y: rect.minY + 1))
        path.closeSubpath()
        return path
    }
}
