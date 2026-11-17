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

enum RecorridoID: String, CaseIterable {
    case home, sales, expenses, banking, more

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
            Paso(objetivo: "more.tabs", icono: "dock.rectangle",
                 titulo: String(localized: "Ponla a tu gusto"),
                 mensaje: String(localized: "Elige qué herramientas van en la barra de abajo."),
                 desplazar: true, enLista: true),
        ]
        }
    }

    var seenKey: String { "recorrido.visto.\(rawValue)" }

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
    private(set) var tarjetaVisible = false
    /// Lo que la lista tiene que mostrar antes de iluminarlo (`RecorridoID.Paso.desplazar`).
    private(set) var desplazarA: String?
    /// Los recorridos ya vistos: las pistas de TipKit de esa pestaña esperan a que esté aquí.
    private(set) var vistos: Set<RecorridoID> = []
    /// «Reducir movimiento» y el alto de la pantalla (los pone `RecorridoOverlay`).
    var reduceMotion = false
    var altoPantalla: CGFloat = 0
    private var cambiando = false
    /// Capturas y pruebas con argumentos `-qa.*`: sin recorrido, salvo con `-qa.recorrido`.
    private var desactivado = false

    init() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "qa.recorrido") == "reset" { Self.olvidarTodo() }
        let usaQA = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-qa.") }
        desactivado = usaQA && defaults.object(forKey: "qa.recorrido") == nil
        #endif
        vistos = Set(RecorridoID.allCases.filter { desactivado || Self.visto($0) })
    }

    private static func visto(_ id: RecorridoID) -> Bool {
        UserDefaults.standard.bool(forKey: id.seenKey) || NSUbiquitousKeyValueStore.default.bool(forKey: id.seenKey)
    }

    private static func olvidarTodo() {
        for id in RecorridoID.allCases {
            UserDefaults.standard.removeObject(forKey: id.seenKey)
            NSUbiquitousKeyValueStore.default.removeObject(forKey: id.seenKey)
        }
    }

    /// «Ver el recorrido otra vez»: cada pestaña lo vuelve a enseñar al abrirla; la de ahora, enseguida.
    func repetirTodo(desde id: RecorridoID) {
        guard activo == nil else { return }
        Self.olvidarTodo()
        vistos = []
        empezarSiHaceFalta(id)
    }

    /// Al entrar en una pestaña: si no se ha visto, espera a que la pantalla se coloque y empieza.
    func empezarSiHaceFalta(_ id: RecorridoID?) {
        guard let id, activo == nil, !desactivado, !Self.visto(id) else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard activo == nil else { return }
            #if os(iOS)
            for objetivo in id.pasos.compactMap(\.objetivo) where objetivo.hasPrefix("ax:") {
                marcos[objetivo] = Self.marcoEnVentana(etiqueta: String(objetivo.dropFirst(3)))
            }
            #endif
            // Solo los pasos cuyo objetivo está a la vista (sin facturas no hay «Por cobrar», por ejemplo); los que
            // están más abajo se buscan al llegar.
            pasos = id.pasos.filter { $0.objetivo == nil || $0.enLista || tieneMarco($0) }
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
        guard let objetivo = paso.objetivo, let marco = marcos[objetivo], marco.width > 0, altoPantalla > 0 else { return false }
        return marco.minY >= 100 && marco.maxY <= altoPantalla - 110
    }

    /// Al menos una parte en la pantalla (con letra grande, la tarjeta de Inicio no cabe entera).
    private func asoma(_ paso: RecorridoID.Paso) -> Bool {
        guard let objetivo = paso.objetivo, let marco = marcos[objetivo], marco.width > 0, altoPantalla > 0 else { return false }
        return marco.maxY > 100 && marco.minY < altoPantalla - 110
    }

    private func tieneMarco(_ paso: RecorridoID.Paso) -> Bool {
        guard let objetivo = paso.objetivo else { return true }
        return (marcos[objetivo]?.width ?? 0) > 0
    }

    func siguiente() {
        guard !cambiando, activo != nil else { return }
        guard paso + 1 < pasos.count else { terminar(); return }
        cambiando = true
        Task {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeIn(duration: 0.12)) { tarjetaVisible = false }
            var proximo = paso + 1
            // En una `List` el marco guardado puede ser de antes (la fila deja de medirse al salir de la pantalla):
            // ahí se desplaza siempre.
            if pasos[proximo].desplazar, pasos[proximo].enLista || !aLaVista(pasos[proximo]) {
                desplazarA = pasos[proximo].objetivo
                try? await Task.sleep(for: .milliseconds(450))
                desplazarA = nil
                if !asoma(pasos[proximo]) { proximo += 1 }
            }
            guard proximo < pasos.count else { cambiando = false; terminar(); return }
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.2)) { paso = proximo; tarjetaVisible = true }
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { paso = proximo }
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeOut(duration: 0.24)) { tarjetaVisible = true }
            }
            cambiando = false
        }
    }

    func terminar() {
        guard let activo else { return }
        UserDefaults.standard.set(true, forKey: activo.seenKey)
        NSUbiquitousKeyValueStore.default.set(true, forKey: activo.seenKey)
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

    /// Desplaza la lista o el `ScrollView` hasta lo que el recorrido va a iluminar (la vista lleva `.id` igual al
    /// objetivo).
    func siguiendoRecorrido(_ proxy: ScrollViewProxy) -> some View {
        modifier(SiguiendoRecorrido(proxy: proxy))
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

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { recorrido?.marcos[id] = $0 }
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
    @Environment(Recorrido.self) private var recorrido
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var focoEnTarjeta: Bool
    /// Alto de la tarjeta, para que quepa entera en la pantalla (con letra grande lo iluminado puede ocupar casi todo).
    @State private var altoTarjeta: CGFloat = 150

    var body: some View {
        GeometryReader { geo in
            if recorrido.activo != nil, recorrido.pasos.indices.contains(recorrido.paso) {
                contenido(geo: geo)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { recorrido.altoPantalla = $0 }
        .onChange(of: reduceMotion, initial: true) { recorrido.reduceMotion = reduceMotion }
        .onChange(of: recorrido.tarjetaVisible) { if recorrido.tarjetaVisible { focoEnTarjeta = true } }
    }

    @ViewBuilder
    private func contenido(geo: GeometryProxy) -> some View {
        let paso = recorrido.pasos[recorrido.paso]
        let origen = geo.frame(in: .global).origin
        let centro = CGRect(x: geo.size.width / 2, y: geo.size.height / 2, width: 0, height: 0)
        let hueco = paso.objetivo.flatMap { recorrido.marcos[$0] }
            .map { $0.offsetBy(dx: -origen.x, dy: -origen.y).insetBy(dx: -6, dy: -6) }
        let radio = min((hueco?.height ?? 0) / 2, 22)
        let ancho = min(geo.size.width - 32, 380)

        ZStack(alignment: .topLeading) {
            VeloConHueco(hueco: hueco ?? centro, radio: radio)
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                // Con VoiceOver, el velo no es un botón: así no atrapa el foco.
                .onTapGesture { if !voiceOver { recorrido.siguiente() } }
                .accessibilityHidden(true)
                .id(reduceMotion ? recorrido.paso : 0)

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
        let izquierda = (geo.size.width - ancho) / 2
        if let hueco {
            // Debajo o encima, donde haya más sitio; si no cabe entera, se queda dentro de la pantalla (sin flecha,
            // tapando parte de lo iluminado).
            let debajo = geo.size.height - hueco.maxY >= hueco.minY
            let deseado = debajo ? hueco.maxY + 16 : hueco.minY - 16 - altoTarjeta
            let arriba = min(max(deseado, 54), geo.size.height - altoTarjeta - 34)
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
            .offset(x: izquierda, y: conFlecha && debajo ? arriba - 10 : arriba)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: debajo ? -8 : 8)),
                removal: .opacity.combined(with: .scale(scale: 0.97))))
        } else {
            presentacion(paso: paso)
                .frame(width: ancho)
                .frame(width: geo.size.width, height: geo.size.height)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.94)),
                    removal: .opacity.combined(with: .scale(scale: 0.97))))
        }
    }

    private var esUltimo: Bool { recorrido.paso + 1 >= recorrido.pasos.count }

    /// «Paso 2 de 5»: los puntos con letra normal; con letra de accesibilidad, el texto.
    @ViewBuilder
    private var indicador: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text("Paso \(recorrido.paso + 1) de \(recorrido.pasos.count)")
                .font(.subheadline).foregroundStyle(Palette.ink2)
        } else {
            Puntos(total: recorrido.pasos.count, actual: recorrido.paso)
        }
    }

    /// Primer paso: centrado, con el icono que se anima, «Empezar» a todo el ancho y «Saltar» debajo.
    private func presentacion(paso: RecorridoID.Paso) -> some View {
        VStack(spacing: 0) {
            Image(systemName: paso.icono)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Palette.brand)
                .frame(width: 76, height: 76)
                .background(Palette.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .symbolEffect(.bounce, options: .repeat(2), isActive: !reduceMotion)
                .accessibilityHidden(true)
            Text(paso.titulo).font(.title2.bold()).foregroundStyle(Palette.ink)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focoEnTarjeta)
            Text(paso.mensaje).font(.body).foregroundStyle(Palette.ink2)
                .padding(.top, 8)
            indicador.padding(.top, 18)
            Button(esUltimo ? String(localized: "Entendido") : String(localized: "Empezar")) { recorrido.siguiente() }
                .buttonStyle(.primary)
                .padding(.top, 18)
            if !esUltimo {
                Button("Saltar") { recorrido.terminar() }
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .frame(minHeight: 44)
                    .padding(.top, 4)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
        .modifier(TarjetaAccesible())
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
                Button(esUltimo ? String(localized: "Entendido") : String(localized: "Siguiente")) { recorrido.siguiente() }
                    .buttonStyle(.primary)
                    .padding(.top, 12)
                if !esUltimo {
                    Button("Saltar") { recorrido.terminar() }
                        .foregroundStyle(Palette.ink2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            } else {
                HStack(spacing: 8) {
                    indicador
                    Spacer(minLength: 8)
                    if !esUltimo {
                        Button("Saltar") { recorrido.terminar() }
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink2)
                            .frame(minHeight: 44)
                            .padding(.horizontal, 6)
                    }
                    Button(esUltimo ? String(localized: "Entendido") : String(localized: "Siguiente")) { recorrido.siguiente() }
                        .buttonStyle(.primaryCompact)
                        .controlSize(.regular)
                }
                .padding(.top, 12)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
            .accessibilityAddTraits(.isModal)
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

private struct Puntos: View {
    let total: Int
    let actual: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { indice in
                Capsule()
                    .fill(indice == actual ? Palette.brand : Palette.ink2.opacity(0.35))
                    .frame(width: indice == actual ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Paso \(actual + 1) de \(total)"))
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
