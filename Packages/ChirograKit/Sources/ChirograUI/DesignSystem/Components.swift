import ChirograCore
import ChirograData
import SwiftUI

// MARK: - Formato

extension Int64 {
    /// Centavos → "$1,250.00".
    var money: String { Money(minorUnits: self).formatted() }
    /// Centavos → "$1,250": cifras clave del canvas, sin centavos (redondeado).
    var moneyWhole: String {
        Money(minorUnits: self).decimalValue.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
    /// Centavos → "1,250.00": columnas de importes del iPhone, donde el "$" de cada fila quitaba sitio al nombre.
    var amountOnly: String {
        Money(minorUnits: self).decimalValue.formatted(.number.precision(.fractionLength(2)))
    }
}

extension Locale {
    /// Locales de las fechas para un idioma y una región. `numeric` es el idioma con la región del dispositivo,
    /// así el orden de las fechas en cifras sigue la región (DISEÑO §7.4: en EE. UU., «11/16/2026» también en
    /// español). `text`, para fechas con el mes en letra, es igual salvo en español de EE. UU., donde se usa el de
    /// Latinoamérica: escribe «16 nov 2026» como el canvas (es_US escribe «nov 16, 2026»).
    nonisolated static func dateLocales(language: String, region: String) -> (numeric: Locale, text: Locale) {
        let numeric = Locale(identifier: "\(language)_\(region)")
        return (numeric, language == "es" && region == "US" ? Locale(identifier: "es_419") : numeric)
    }

    nonisolated private static let appDates: (numeric: Locale, text: Locale) = {
        let language = (Bundle.main.preferredLocalizations.first ?? Locale.current.language.languageCode?.identifier ?? "es")
            .prefix(2)
        return dateLocales(language: String(language), region: Locale.current.region?.identifier ?? "US")
    }()

    /// Fechas en cifras («11/16/2026»): idioma de la app y región del dispositivo.
    nonisolated static var app: Locale { appDates.numeric }
    /// Fechas con el mes en letra («16 nov 2026»). También va en el entorno de SwiftUI, para que los selectores de
    /// fecha salgan en el idioma de la app y no en el del sistema.
    nonisolated static var appText: Locale { appDates.text }
}

extension FormatStyle where Self == Date.FormatStyle {
    /// Como `.dateTime`, pero con `Locale.appText` (las fechas de la app llevan el mes en letra).
    nonisolated static var appDateTime: Date.FormatStyle { Date.FormatStyle(locale: .appText) }
}

extension Date {
    /// Mes en tres letras como en el canvas («sep», «oct»; la abreviatura del sistema en español es «sept.»).
    var shortMonth: String { formatted(.appDateTime.month(.wide)).prefix(3).lowercased() }
}

extension Date {
    var shortDate: String { formatted(.appDateTime.day().month(.abbreviated).year()) }
    var dayMonth: String { formatted(.appDateTime.day().month(.abbreviated)) }
    /// «Octubre de 2026»: solo la primera letra en mayúscula (`capitalized` daría «Octubre De 2026»).
    var monthYear: String { formatted(.appDateTime.month(.wide).year()).sentenceCased }
    /// «vence Oct 28» con espacios de no separación: en una fila estrecha se parte antes, nunca dentro.
    var dueLabel: String { String(localized: "vence \(dayMonth)").replacingOccurrences(of: " ", with: "\u{00A0}") }
}

extension RawRepresentable where RawValue == String {
    /// Texto visible de un enum cuyo `rawValue` es la etiqueta en español: se busca en el catálogo en tiempo de ejecución.
    /// El compilador no extrae estos textos; están añadidos a mano en `App/Localizable.xcstrings`.
    var localizedTitle: String { String(localized: String.LocalizationValue(rawValue)) }
}

extension String {
    /// Primera letra en mayúscula y el resto tal cual, como se escribe en español.
    nonisolated var sentenceCased: String { prefix(1).uppercased() + dropFirst() }
}

extension View {
    /// Hoja de un editor: en el iPad, alta como una página y de 760 pt de ancho como máximo; con texto de
    /// accesibilidad, del tamaño de página en todas partes. La hoja de formulario del iPad (~580×660 pt) cortaba la
    /// factura por abajo aunque sobraba pantalla. En el iPhone no cambia nada y en el Mac conserva su tamaño.
    func editorSheetSizing() -> some View { modifier(EditorSheetSizing()) }
}

private struct EditorSheetSizing: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Se mira el aparato y no la clase de tamaño: dentro de la hoja de formulario la clase ya es compacta.
    private var isPad: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            content.presentationSizing(.page)
        } else if isPad {
            content.presentationSizing(EditorPageSizing())
        } else {
            content
        }
    }
}

/// Alto de página, ancho de formulario holgado: la hoja de página del iPad en vertical ocupaba casi toda la pantalla.
private struct EditorPageSizing: PresentationSizing {
    static let maxWidth: CGFloat = 760

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        var size = PagePresentationSizing.page.proposedSize(for: root, context: context)
        size.width = min(size.width ?? Self.maxWidth, Self.maxWidth)
        return size
    }
}

/// Testigo de un editor abierto: vive en el estado de la vista, así que desaparece con ella.
final class EditorToken {}

/// Cambios sin guardar de los editores abiertos. Lo consulta la barra lateral antes de cambiar de pantalla: rehacer la
/// vista dividida cierra el editor y se perdería lo escrito. Cada editor se registra con su propio testigo, para que
/// una hoja abierta encima (p. ej. un cliente nuevo desde la factura) no borre el estado del editor de debajo. El
/// registro guarda el testigo de forma débil: si la vista del editor ya no existe, deja de contar aunque `onDisappear`
/// no haya llegado (o haya llegado antes que el último aviso de cambios).
@Observable
final class UnsavedChanges {
    private struct Entry {
        weak var token: EditorToken?
        let discard: () -> Void
    }

    @ObservationIgnored private var entries: [ObjectIdentifier: Entry] = [:]

    /// Solo cuentan los editores que siguen existiendo.
    var hasChanges: Bool { entries.values.contains { $0.token != nil } }

    /// `discard`: lo que hace el editor al descartar (p. ej. borrar el borrador que guardó la vista previa).
    func report(_ editor: EditorToken, hasChanges: Bool, discard: @escaping () -> Void = {}) {
        entries = entries.filter { $0.value.token != nil }
        entries[ObjectIdentifier(editor)] = hasChanges ? Entry(token: editor, discard: discard) : nil
    }

    func remove(_ editor: EditorToken) { entries[ObjectIdentifier(editor)] = nil }

    /// Hasta cuándo puede cambiar el registro por un aviso de «Cancelar»: en el iPad, un toque en la barra lateral
    /// llega antes que la acción de «Descartar», que se ejecuta mientras el aviso se cierra.
    @ObservationIgnored private(set) var settlingUntil: Date?

    /// Un aviso de «Cancelar» se abre (`isOpen`) o se cierra: mientras está abierto, y un momento después, su acción
    /// aún puede retirar el editor.
    func confirmation(isOpen: Bool, settleFor seconds: TimeInterval = 1.2, now: Date = .now) {
        settlingUntil = isOpen ? .distantFuture : now.addingTimeInterval(seconds)
    }

    func isSettling(at now: Date = .now) -> Bool { settlingUntil.map { now < $0 } ?? false }

    func removeAll() { entries = [:]; settlingUntil = nil }

    func discardAll() {
        entries.values.filter { $0.token != nil }.forEach { $0.discard() }
        entries = [:]
    }
}

extension View {
    /// Editor que se puede descartar: compara `value` (lo que escribe el usuario) con lo que había al abrirlo y, si
    /// hay cambios, «Cancelar» pregunta antes de cerrarlo (con el aviso anclado al botón), la hoja no se cierra
    /// deslizando y la barra lateral pregunta antes de cambiar de pantalla.
    ///
    /// `token` es el testigo del editor: al guardar, el editor lo retira de `UnsavedChanges` antes de cerrarse, porque
    /// durante la animación de salida seguiría contando y la barra lateral preguntaría sin ningún editor a la vista.
    func discardableEditor<Value: Equatable>(tracking value: Value, token: EditorToken,
                                             onDiscard: @escaping () -> Void = {}) -> some View {
        modifier(DiscardableEditor(value: value, token: token, onDiscard: onDiscard))
    }

    /// Informa de los cambios de un editor que pone su propio «Cancelar» (la factura, que además conserva borradores).
    func reportsUnsavedChanges(_ hasChanges: Bool, token: EditorToken, onDiscard: @escaping () -> Void = {}) -> some View {
        modifier(UnsavedChangesReporter(hasChanges: hasChanges, token: token, onDiscard: onDiscard))
    }
}

private struct DiscardableEditor<Value: Equatable>: ViewModifier {
    let value: Value
    let token: EditorToken
    let onDiscard: () -> Void
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// El cierre del editor, leído aquí y no dentro del botón de la barra: en una hoja del Mac, el `dismiss` de un
    /// ítem de la barra no cerraba la hoja («Cancelar», «Descartar» y Escape no hacían nada).
    @Environment(\.dismiss) private var dismiss
    @State private var baseline: Value?
    /// Se toma la referencia tras el primer ciclo, cuando el editor ya cargó sus datos y valores por defecto.
    @State private var readyForBaseline = false

    private var hasChanges: Bool { baseline.map { $0 != value } ?? false }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelEditorButton(hasChanges: hasChanges, close: dismiss) { onDiscard(); unsavedChanges?.remove(token) }
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .reportsUnsavedChanges(hasChanges, token: token, onDiscard: onDiscard)
            .onAppear { if baseline == nil { Task { @MainActor in readyForBaseline = true } } }
            .onChange(of: readyForBaseline) { if baseline == nil { baseline = value } }
    }
}

private struct UnsavedChangesReporter: ViewModifier {
    let hasChanges: Bool
    let token: EditorToken
    let onDiscard: () -> Void
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Solo informa mientras el editor está en pantalla, sea cual sea el orden de los avisos.
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .onAppear { isVisible = true; report() }
            .onChange(of: hasChanges) { report() }
            .onDisappear { isVisible = false; unsavedChanges?.remove(token) }
    }

    private func report() {
        unsavedChanges?.report(token, hasChanges: hasChanges && isVisible, discard: onDiscard)
    }
}

/// «Cancelar» de un editor: con cambios, pregunta «¿Descartar los cambios?» antes de cerrarlo. `onDiscard` se llama
/// justo antes de cerrar (y retira el registro de cambios sin esperar a que termine la animación).
struct CancelEditorButton: View {
    let hasChanges: Bool
    /// El cierre del editor que lo pone (ver `DiscardableEditor`).
    let close: DismissAction
    var onDiscard: () -> Void = {}
    @Environment(\.unsavedChanges) private var unsavedChanges
    @State private var confirming = false

    var body: some View {
        Button("Cancelar") { if hasChanges { confirming = true } else { close() } }
            .confirmationDialog("¿Descartar los cambios?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Descartar", role: .destructive) { onDiscard(); close() }
                Button("Seguir editando", role: .cancel) {}
            }
            .onChange(of: confirming) { unsavedChanges?.confirmation(isOpen: confirming) }
            .headerButton()
    }
}

extension EnvironmentValues {
    @Entry var unsavedChanges: UnsavedChanges?
}


// MARK: - Tipografía

/// Estilos del tablero «Sistema nativo» (SF Pro con Dynamic Type): `.largeTitle` para el título de pantalla,
/// `.title3` bold para el título de un grupo, `.body` para filas, `.subheadline` para detalles y `.footnote` para
/// subtítulos de fila, estados y encabezados de sección. En el Mac los mismos estilos dan 13 pt de cuerpo.
extension Font {
    /// Cifras destacadas (efectivo, totales). El tamaño del canvas se traduce al estilo de texto más cercano para que
    /// escale con Dynamic Type.
    static func amount(_ size: CGFloat) -> Font {
        let style: Font.TextStyle = switch size {
        case 34...: .largeTitle
        case 26..<34: .title
        case 21..<26: .title2
        case 18..<21: .title3
        default: .headline
        }
        return .system(style, weight: .bold).monospacedDigit()
    }
    #if os(macOS)
    /// Título de una caja del Mac («Ingresos y gastos · 12 meses»): 13 pt bold.
    static let cardTitle = Font.headline
    /// Cabeceras de tabla y de inspector del Mac: 11 pt semibold.
    static let label = Font.subheadline.weight(.semibold)
    #else
    /// Título de un grupo («Ingresos y gastos», «Por cobrar»): `.title3` bold, fuera de la tarjeta.
    static let cardTitle = Font.title3.weight(.bold)
    /// Encabezados de sección y etiquetas pequeñas: `.footnote` (13 pt), en tipo oración.
    static let label = Font.footnote
    #endif
}

// MARK: - Superficies

extension EnvironmentValues {
    /// Las tarjetas ocupan todo el alto disponible: dos tarjetas lado a lado miden lo mismo (canvas `MacInicio`).
    @Entry var cardFillsHeight = false
}

/// Tarjeta: la celda de una lista agrupada (radio 24, `secondarySystemGroupedBackground`); en el Mac, la caja del
/// canvas (fondo alterno, borde fino de `separator`, radio 12).
struct CardModifier: ViewModifier {
    var padding: CGFloat = Metrics.cardPadding
    @Environment(\.cardFillsHeight) private var fillsHeight

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .background(Palette.surface, in: shape)
            #if os(macOS)
            .overlay(shape.strokeBorder(Palette.separator, lineWidth: 0.5))
            #endif
    }
}

extension View {
    func card(padding: CGFloat = Metrics.cardPadding) -> some View { modifier(CardModifier(padding: padding)) }

    /// Campo con fondo fuera de un `Form` (líneas de la factura y del asiento, fichas del Mac): en iPhone e iPad, el
    /// relleno del sistema (canvas `--fill`); en el Mac, el campo redondeado del sistema (canvas `.tf`).
    func fieldBox() -> some View {
        #if os(macOS)
        textFieldStyle(.roundedBorder)
        #else
        textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        #endif
    }

    /// Fondo de pantalla (`systemGroupedBackground`; en el Mac, el de la ventana), en listas y en vistas con scroll.
    func screenBackground() -> some View {
        scrollContentBackground(.hidden).background(Palette.background)
    }

    /// Título de pantalla (§7.4, decisión del usuario): en el iPad, grande dentro de la barra de vidrio del sistema,
    /// junto al botón de la barra lateral y a los botones, sin franja vacía encima; en el Mac, el de la ventana; en el
    /// iPhone, el título grande de siempre, que se pliega al desplazar. Va en cada pantalla: las que se abren encima no
    /// heredan el modo.
    func headerTitle() -> some View {
        modifier(HeaderTitle())
    }

    /// Título de una ficha (cliente, proveedor): su nombre, pequeño en la barra, y en el Mac la sección debajo, como
    /// las migas de los tableros («Clientes › Hotel Mirador»). Sin título, el botón de volver decía «Chirogra».
    func recordTitle(_ name: String, section: String) -> some View {
        #if os(macOS)
        navigationTitle(name).navigationSubtitle(section)
        #else
        navigationTitle(name).inlineTitle()
        #endif
    }

    @ViewBuilder
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

// MARK: - Botones

/// Botón principal («Enviar factura», «Registrar $…», «Continuar»): la cápsula de vidrio del sistema (`.glass`) SIN
/// relleno de marca, con el texto en `ink` y semibold, a todo el ancho. Decisión del usuario (2-nov): el canvas lo
/// rellena de Tinta, pero se queda en vidrio sin relleno, como en `f21e0bf`. Se distingue del secundario por el
/// vidrio y el peso del texto.
struct PrimaryButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .buttonSizing(.flexible)
            .fontWeight(.semibold)
            .tint(Palette.ink)
    }
}

/// Igual que el principal pero del ancho de su texto (estado vacío: «Importar mi banco», «Crear tu primera factura»).
struct CompactPrimaryButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .fontWeight(.semibold)
            .tint(Palette.ink)
    }
}

/// Botón secundario y destructivo del canvas («Vista previa», «Excluir»): en iPhone e iPad, cápsula con el relleno
/// del sistema (`--fill`) y el texto semibold en Tinta, o en rojo si es destructivo; en el Mac, el botón con borde
/// del sistema (canvas `.pb`).
struct SecondaryButtonStyle: PrimitiveButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        let button = Button(role: destructive ? .destructive : configuration.role) { configuration.trigger() } label: {
            configuration.label
        }
        #if os(macOS)
        button
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .buttonSizing(.flexible)
            .foregroundStyle(destructive ? Palette.negative : Palette.ink)
        #else
        button.buttonStyle(FillCapsuleButtonStyle(foreground: destructive ? Palette.negative : Palette.brand))
        #endif
    }
}

/// Cápsula con el relleno del sistema y texto de color: la forma de `SecondaryButtonStyle` en iPhone e iPad.
struct FillCapsuleButtonStyle: ButtonStyle {
    var foreground: Color = Palette.brand
    var fullWidth = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Metrics.buttonHeight)
            .foregroundStyle(isEnabled ? foreground : Palette.ink2)
            .background(Palette.surface2, in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

extension PrimitiveButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension PrimitiveButtonStyle where Self == CompactPrimaryButtonStyle {
    static var primaryCompact: CompactPrimaryButtonStyle { CompactPrimaryButtonStyle() }
}

extension PrimitiveButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static var destructive: SecondaryButtonStyle { SecondaryButtonStyle(destructive: true) }
}

// MARK: - Estados

/// Punto de color de un estado (canvas: 7 pt, 6 en el Mac), siempre junto a un texto.
struct StatusDot: View {
    let color: Color
    #if os(macOS)
    private let side: CGFloat = 6
    #else
    private let side: CGFloat = 7
    #endif

    var body: some View {
        Circle().fill(color).frame(width: side, height: side).accessibilityHidden(true)
    }
}

/// Estado de un documento como en el canvas: un punto del color del sistema y el texto en su color accesible
/// («● Vencida · 8 días»), sin cápsula. `compact` es el de las filas (`.footnote`); el otro, el de una ficha
/// (`.subheadline` semibold). `background` ya no se dibuja: se conserva para no tocar las pantallas.
struct StatusChip: View {
    let text: String
    let foreground: Color
    let background: Color
    var compact = false
    /// Color del punto (por defecto, el del texto).
    var dot: Color? = nil

    var body: some View {
        HStack(spacing: compact ? 5 : 6) {
            StatusDot(color: dot ?? foreground)
            Text(text).lineLimit(1)
        }
        .font(font)
        .foregroundStyle(foreground)
    }

    private var font: Font {
        #if os(macOS)
        compact ? .subheadline : .body
        #else
        compact ? .footnote : .subheadline.weight(.semibold)
        #endif
    }
}

extension Invoice {
    /// Nombre del estado, igual que en su chip («Vencida», «Pago parcial»…).
    var statusTitle: String {
        if daysOverdue() != nil { return String(localized: "Vencida") }
        return switch status {
        case .draft: String(localized: "Borrador")
        case .sent: String(localized: "Enviada")
        case .partiallyPaid: String(localized: "Pago parcial")
        case .paid: String(localized: "Pagada")
        case .void: String(localized: "Anulada")
        }
    }
}

extension StatusChip {
    /// Estados de factura del canvas (`Ventas`): Borrador (gris), Enviada (azul), Pago parcial (naranja),
    /// Vencida · N días (rojo), Pagada (verde) y Anulada (gris).
    init(invoice: Invoice, compact: Bool = true) {
        if let days = invoice.daysOverdue() {
            self.init(text: String(localized: "Vencida · \(days) días"), foreground: Palette.negative, background: Palette.negativeWash,
                      compact: compact, dot: Palette.red)
            return
        }
        switch invoice.status {
        case .draft: self.init(text: String(localized: "Borrador"), foreground: Palette.ink2, background: Palette.surface2, compact: compact, dot: Palette.gray)
        case .sent: self.init(text: String(localized: "Enviada"), foreground: Palette.ink2, background: Palette.surface2, compact: compact, dot: Palette.blue)
        case .partiallyPaid: self.init(text: String(localized: "Pago parcial"), foreground: Palette.warning, background: Palette.warningWash, compact: compact, dot: Palette.orange)
        case .paid: self.init(text: String(localized: "Pagada"), foreground: Palette.positive, background: Palette.positiveWash, compact: compact, dot: Palette.green)
        case .void: self.init(text: String(localized: "Anulada"), foreground: Palette.ink2, background: Palette.surface2, compact: compact, dot: Palette.gray)
        }
    }

    init(bill: Bill, compact: Bool = true) {
        switch bill.status {
        case .open: self.init(text: String(localized: "Por pagar"), foreground: Palette.ink2, background: Palette.surface2, compact: compact, dot: Palette.blue)
        case .partiallyPaid: self.init(text: String(localized: "Pago parcial"), foreground: Palette.warning, background: Palette.warningWash, compact: compact, dot: Palette.orange)
        case .paid: self.init(text: String(localized: "Pagada"), foreground: Palette.positive, background: Palette.positiveWash, compact: compact, dot: Palette.green)
        case .void: self.init(text: String(localized: "Anulada"), foreground: Palette.ink2, background: Palette.surface2, compact: compact, dot: Palette.gray)
        }
    }
}

// MARK: - Filtros

/// Chip de filtro o de tipo de reporte: cápsula con el relleno del sistema; la elegida, rellena de Tinta con el texto
/// blanco. Área táctil de 44 pt (28 en el Mac) y rasgo de seleccionado. En pantallas nuevas, mejor `FilterPicker`
/// (segmentado del sistema) o `FilterMenu` (botón de filtro de la barra), que son los del canvas.
struct FilterChip: View {
    let title: String
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).fontWeight(.semibold)
                if let count { Text("\(count)").foregroundStyle(isSelected ? Palette.onBrandFill.opacity(0.85) : Palette.ink2) }
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .frame(minHeight: Metrics.target)
            .foregroundStyle(isSelected ? Palette.onBrandFill : Palette.ink)
            .background(isSelected ? Palette.brandFill : Palette.surface2, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Filtro de una opción entre varias (canvas `Gastos`, `iPadVentas`, `ReportePyG`): el control segmentado del sistema
/// si caben (hasta cuatro opciones y sin texto de accesibilidad); si no, un menú desplegable con la opción elegida.
struct FilterPicker<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    var count: ((Option) -> Int)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if options.count <= 4 && !dynamicTypeSize.isAccessibilitySize {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } else {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    if let count { Text("\(label(option)) (\(count(option)))").tag(option) } else { Text(label(option)).tag(option) }
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

/// Filtro de una lista en la barra, como en Mail (canvas `Ventas`): el botón de filtro del sistema, en Tinta cuando
/// hay un filtro puesto, con un menú de opciones y su cuenta. La primera opción es «sin filtro».
struct FilterMenu<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    var count: ((Option) -> Int)? = nil

    private var isFiltering: Bool { selection != options.first }

    var body: some View {
        Menu {
            Picker(String(localized: "Filtrar"), selection: $selection) {
                ForEach(options, id: \.self) { option in
                    if let count { Text(label(option)).badge(count(option)).tag(option) } else { Text(label(option)).tag(option) }
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(String(localized: "Filtrar"), systemImage: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .tint(isFiltering ? Palette.brand : Palette.ink)
        .accessibilityValue(label(selection))
    }
}

// MARK: - Piezas de lista

/// Monograma de cliente o proveedor, como en Contactos: iniciales blancas en un círculo con el degradado gris del
/// sistema (canvas `Clientes`, `FacturaNueva`). `foreground`, `background` y `round` ya no cambian nada: se conservan
/// para no tocar las pantallas.
struct InitialsTile: View {
    let text: String
    var foreground: Color = Palette.brand
    var background: Color = Palette.brandWash
    var round = false
    @ScaledMetric(relativeTo: .subheadline) private var side = Metrics.avatar

    var body: some View {
        Text(text)
            .font(.system(size: side * 0.38, weight: .semibold))
            .frame(width: side, height: side)
            .foregroundStyle(.white)
            .background(Palette.monogram, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Icono de fila como en Ajustes (canvas `Mas`, `Gastos`, `Home` · Cuentas): símbolo blanco en un cuadrado redondeado
/// relleno de color (30 pt, radio 8; 22 pt en el Mac). `foreground` es el color del cuadrado: un color del sistema
/// (`Palette.blue`, `.orange`…) o el de un estado; `background` ya no se dibuja.
struct IconTile: View {
    let systemImage: String
    var foreground: Color = Palette.brand
    var background: Color = Palette.brandWash
    @ScaledMetric(relativeTo: .body) private var side = Metrics.iconTile

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: side * 0.55, weight: .medium))
            .frame(width: side, height: side)
            .foregroundStyle(.white)
            // Tinta oscura bajo el blanco: con la de texto (#9A9EFF en oscuro) el símbolo no se leía.
            .background(foreground == Palette.brand ? Palette.brandFill : foreground,
                        in: RoundedRectangle(cornerRadius: side * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Fecha de vencimiento como hoja de calendario (canvas `Home` · Por pagar): mes en rojo y día debajo.
struct DateTile: View {
    let date: Date
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 38

    var body: some View {
        VStack(spacing: 0) {
            Text(date.shortMonth).textCase(.uppercase).font(.system(size: width * 0.24, weight: .bold)).foregroundStyle(Palette.red)
            Text(date.formatted(.appDateTime.day())).font(.system(size: width * 0.45, weight: .semibold)).foregroundStyle(Palette.ink)
        }
        .monospacedDigit()
        .frame(width: width, height: width * 40 / 38)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Fila de lista del canvas: icono o monograma, título (`.body`), subtítulo (`.footnote`, gris) e importe con el estado
/// debajo. El chevron lo pone la lista cuando la fila abre algo. Con tamaños de accesibilidad icono, texto e importe
/// van en columna.
struct LedgerRow<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String
    /// Líneas del subtítulo: 2 para correos, que recortados por el medio no se leían.
    var subtitleLines = 1
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Todo en columna: el icono crece con el texto y, a su lado, partía el nombre en sílabas.
                VStack(alignment: .leading, spacing: 6) {
                    leading
                    texts
                    trailing
                }
            } else {
                HStack(spacing: 12) {
                    leading
                    texts.layoutPriority(1)
                    Spacer(minLength: 8)
                    trailing.fixedSize()
                }
            }
        }
        // La lista ya pone su margen: con él la fila mide unos 60 pt, como en el canvas.
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// Una línea por dato, como en el canvas («F-1047 · vence 12 nov»). Si no cabe, el subtítulo se encoge un poco
    /// antes de recortarse por el medio, así no se pierde el vencimiento del final. Con tamaños de accesibilidad
    /// se permiten varias líneas.
    private var texts: some View {
        let lines = dynamicTypeSize.isAccessibilitySize ? nil : 1 as Int?
        return VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.body).foregroundStyle(Palette.ink).lineLimit(lines)
            Text(subtitle).font(Self.subtitleFont).foregroundStyle(Palette.ink2)
                .lineLimit(lines.map { _ in subtitleLines })
                .minimumScaleFactor(0.85)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: lines == nil)
        }
    }

    #if os(macOS)
    static var subtitleFont: Font { .subheadline }
    #else
    static var subtitleFont: Font { .footnote }
    #endif
}

/// Texto a la izquierda y valor a la derecha; con tamaños de accesibilidad, uno debajo del otro,
/// para que ni las palabras ni las cifras se partan en varias líneas.
struct AdaptiveRow<Leading: View, Trailing: View>: View {
    var alignment: VerticalAlignment = .center
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                leading
                trailing
            }
        } else {
            HStack(alignment: alignment) {
                leading
                Spacer(minLength: 8)
                trailing
            }
        }
    }
}

extension DynamicTypeSize {
    /// Alineación de la columna de importe de una `LedgerRow`: a la derecha, o a la izquierda cuando la fila va en columna.
    var amountAlignment: HorizontalAlignment { isAccessibilitySize ? .leading : .trailing }
}

/// Encabezado de sección de una lista agrupada, como en Ajustes de iOS 26: `.footnote` gris en tipo oración
/// («Registrar pago», «Actividad»); en el Mac, 11 pt semibold (cabecera de inspector).
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.label)
            .foregroundStyle(Palette.ink2)
            // Sin mayúsculas: las listas agrupadas del sistema las ponían por defecto.
            .textCase(nil)
    }
}

extension Section where Parent == SectionLabel, Footer == EmptyView, Content: View {
    /// Sección de lista con el encabezado del canvas.
    init(title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.init(content: content) { SectionLabel(text: String(localized: title)) }
    }

    /// Igual, para títulos que vienen de los datos (tipo de cuenta, agencia).
    init(heading: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { SectionLabel(text: heading) }
    }
}

/// Título de un grupo fuera de una lista (canvas `Home`: «Ingresos y gastos», «Por cobrar · Ver todo»): `.title3` bold
/// con un enlace opcional en Tinta a la derecha. Con el margen de la tarjeta, para alinearse con su contenido.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.cardTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing.font(.body).tint(Palette.brand)
        }
        .padding(.horizontal, Metrics.cardPadding)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// Fila «etiqueta · valor» con el valor en gris secundario, como las filas del sistema y del canvas («Número F-1049»).
/// Los selectores de menú y los interruptores de los formularios también pasan por este estilo, así que nunca se
/// recorta nada: si etiqueta y valor no caben en una línea, el valor baja a la siguiente (siempre, con tamaños de
/// accesibilidad).
struct InkValueLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: LabeledContentStyleConfiguration
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            if dynamicTypeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    // Centrado: los interruptores y selectores no tienen línea base.
                    HStack(alignment: .center, spacing: 12) {
                        configuration.label.fixedSize()
                        Spacer(minLength: 0)
                        configuration.content.foregroundStyle(Palette.ink2).fixedSize()
                    }
                    stacked
                }
            }
        }

        private var stacked: some View {
            VStack(alignment: .leading, spacing: 4) {
                configuration.label
                configuration.content.foregroundStyle(Palette.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Pestañas de una pantalla (Facturas · Clientes): el control segmentado del sistema (canvas `Gastos`).
struct UnderlineTabs<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        Picker(String(localized: "Sección"), selection: $selection) {
            ForEach(options, id: \.self) { Text(title($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 6)
    }
}

/// Acciones fijas abajo (canvas `FacturaNueva`, `FacturaEnviar`): una barra de vidrio que flota sobre el contenido,
/// con los botones uno al lado del otro; con tamaños de accesibilidad, uno debajo del otro.
struct BottomActionBar<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout { content }
            .padding(8)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Metrics.buttonHeight / 2 + 8, style: .continuous))
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 8)
    }
}

extension View {
    /// Fija `BottomActionBar` sobre el borde inferior, con el efecto de borde del sistema: los botones no se van con
    /// el scroll.
    func bottomActionBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        safeAreaBar(edge: .bottom, spacing: 0) { BottomActionBar(content: content) }
    }
}

// MARK: - Fichas (canvas `ClienteFicha`, `ProveedorFicha`)

/// Cabecera de ficha, como en Contactos: monograma grande (84 pt; 64 en el Mac) o icono en un círculo de color,
/// nombre en `.title` bold y detalle gris, centrados. `round` ya no cambia nada.
struct ProfileHeader: View {
    var initials: String? = nil
    var systemImage: String? = nil
    let name: String
    let detail: String
    var round = false
    var foreground: Color = Palette.brand
    var background: Color = Palette.brandWash
    #if os(macOS)
    @ScaledMetric(relativeTo: .title) private var side: CGFloat = 64
    #else
    @ScaledMetric(relativeTo: .title) private var side: CGFloat = 84
    #endif

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: side * 0.42, weight: .medium))
                        .frame(width: side, height: side)
                        .foregroundStyle(.white)
                        .background(foreground == Palette.brand ? Palette.brandFill : foreground, in: Circle())
                } else {
                    Text(initials ?? "")
                        .font(.system(size: side * 0.4, weight: .semibold))
                        .frame(width: side, height: side)
                        .foregroundStyle(.white)
                        .background(Palette.monogram, in: Circle())
                }
            }
            .accessibilityHidden(true)
            Text(name).font(.title.weight(.bold)).foregroundStyle(Palette.ink).lineLimit(2).minimumScaleFactor(0.8)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            Text(detail).font(.subheadline).foregroundStyle(Palette.ink2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// Acción de la ficha (Llamar, Mensaje, Correo, Factura): círculo de vidrio con el símbolo en Tinta y el nombre debajo.
struct ProfileAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    #if os(macOS)
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 40
    #else
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 54
    #endif

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(isEnabled ? Palette.brand : Palette.ink2)
                    .frame(width: side, height: side)
                    .glassEffect(.regular.interactive(isEnabled), in: Circle())
                    .accessibilityHidden(true)
                Text(title).font(.caption).foregroundStyle(isEnabled ? Palette.ink : Palette.ink2)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: Metrics.target)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Cifra pequeña de ficha (canvas `ProveedorFicha`): etiqueta gris y valor semibold.
struct MiniStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.headline).foregroundStyle(Palette.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .card(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

/// Acción rápida de Inicio (canvas `Home`: Factura · Gasto · Escanear · Cliente): círculo de 58 pt con el símbolo en
/// Tinta y el nombre debajo; la destacada, rellena de Tinta con el símbolo blanco.
struct QuickAction: View {
    let title: String
    let systemImage: String
    var prominent = false
    let action: () -> Void
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 58

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(prominent ? Palette.onBrandFill : Palette.brand)
                    .frame(width: side, height: side)
                    .background(prominent ? Palette.brandFill : Palette.surface, in: Circle())
                    .accessibilityHidden(true)
                Text(title).font(.caption).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Botón de la cabecera (§7.4, decisión del usuario; canvas: botones de vidrio con el símbolo en `label`): el vidrio
    /// que la barra del sistema ya pone a sus ítems, con el texto en tinta y no en el color de marca.
    func headerButton() -> some View {
        tint(Palette.ink)
    }

    /// Botón de vidrio compacto dentro de filas y tarjetas (por ejemplo «Pagar» en una tabla): el `.glass` del sistema
    /// con el texto en tinta, como los de la cabecera.
    func glassActionButton() -> some View {
        buttonStyle(.glass).tint(Palette.ink).fontWeight(.semibold)
    }
}

private struct HeaderTitle: ViewModifier {
    #if os(iOS)
    // El del sistema y no `LayoutSizeClass`: también con la columna estrecha del iPad el título va en la barra.
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbarTitleDisplayMode(sizeClass == .regular ? .inlineLarge : .automatic)
        #else
        // En el Mac, el título de la ventana, con el tamaño que le da el sistema (`.inlineLarge` no lo agranda), en la
        // fila de las acciones y una sola vez: ya no se repite en grande en el contenido.
        content
        #endif
    }
}

/// «+» de la barra: solo el símbolo, en tinta, dentro del vidrio de la barra (canvas `Ventas`, `Gastos`).
struct AddButton: View {
    let title: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(String(localized: title), systemImage: "plus").labelStyle(.iconOnly)
        }
        .headerButton()
    }
}

/// Cifra clave de iPad y Mac (canvas `MacInicio`, `MacVentas`): etiqueta, importe y pie. `isBrand` ya no cambia nada:
/// el canvas no rellena ninguna tarjeta de marca.
struct KPIItem: Identifiable {
    let title: String
    let value: String
    var foot: String? = nil
    var footColor: Color = Palette.ink2
    var isBrand = false
    var id: String { title }
}

/// Rejilla de cifras clave a todo el ancho, como `auto-fit minmax(…, 1fr)` del canvas: todas en una fila si caben
/// al ancho mínimo; si no, cuatro tarjetas van en 2×2 (nunca 3 + 1 sola). `large` usa las medidas de `MacInicio`.
struct KPIGrid: View {
    let items: [KPIItem]
    var large = false
    @State private var width: CGFloat = 0
    @ScaledMetric(relativeTo: .title2) private var minimumWidth: CGFloat = 160

    private var spacing: CGFloat { 12 }

    /// Cifra de las tarjetas: 24 pt en iPad y Mac (`iPadInicio`, `MacInicio`).
    private static let largeAmount: CGFloat = 24

    #if os(macOS)
    private static let titleFont = Font.subheadline.weight(.semibold)
    private static let footFont = Font.subheadline
    #else
    private static let titleFont = Font.footnote
    private static let footFont = Font.footnote
    #endif

    private var columns: Int {
        let available = width + spacing
        let minimum = (large ? minimumWidth * 1.2 : minimumWidth) + spacing
        if available >= CGFloat(items.count) * minimum { return items.count }
        if items.count == 4 { return 2 }
        return max(1, min(items.count, Int(available / minimum)))
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(Self.titleFont).foregroundStyle(Palette.ink2).lineLimit(1)
                    Text(item.value).font(.amount(large ? Self.largeAmount : 22)).minimumScaleFactor(0.6).lineLimit(1)
                        .foregroundStyle(Palette.ink)
                    // Siempre una línea de pie, aunque esté vacía, para que todas las tarjetas midan lo mismo.
                    Text(item.foot ?? " ").font(Self.footFont).lineLimit(1)
                        .foregroundStyle(item.footColor)
                }
                .card(padding: 14)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.title)
                .accessibilityValue([item.value, item.foot].compactMap { $0 }.joined(separator: ", "))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// Cifra de un resumen de tres columnas (canvas `Home`: Ingresos · Gastos · Ganancia): etiqueta gris, importe
/// semibold y una nota de color («▲ 12%»).
struct KPITile: View {
    let title: String
    let value: String
    var note: String? = nil
    var noteColor: Color = Palette.ink2

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote).foregroundStyle(Palette.ink2)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(Palette.ink).minimumScaleFactor(0.7).lineLimit(2)
            // Una línea, como en el canvas («↑ 12% vs. sep»); se encoge un poco antes de cortarse.
            if let note { Text(note).font(.footnote).foregroundStyle(noteColor).lineLimit(1).minimumScaleFactor(0.75) }
        }
        .card(padding: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([value, note.map(Self.spoken)].compactMap { $0 }.joined(separator: ", "))
    }

    /// Las flechas de variación se leen como palabras («sube», «baja»), no como símbolos.
    static func spoken(_ note: String) -> String {
        note.replacingOccurrences(of: "↑", with: String(localized: "sube")).replacingOccurrences(of: "↓", with: String(localized: "baja"))
            .replacingOccurrences(of: "▲", with: String(localized: "sube")).replacingOccurrences(of: "▼", with: String(localized: "baja"))
    }
}

/// Cifra destacada (canvas `Home` · Efectivo disponible, `ReportePyG` · Ganancia neta): una tarjeta del sistema con la
/// etiqueta gris, la cifra grande y, debajo, la variación de color y el detalle. Sin relleno de marca.
struct HeroCard: View {
    let title: String
    let value: String
    var detail: String? = nil
    /// Variación junto a la cifra («+34% vs. sep»): verde si sube, roja si baja.
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).foregroundStyle(Palette.ink2)
            Text(value).font(.amount(36)).foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(2)
            if let badge {
                Text(badge).font(.footnote.weight(.semibold)).foregroundStyle(Self.isDecrease(badge) ? Palette.negative : Palette.positive)
            }
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(Palette.ink2)
            }
        }
        .card(padding: 18)
        .accessibilityElement(children: .combine)
    }

    private static func isDecrease(_ text: String) -> Bool {
        guard let first = text.trimmingCharacters(in: .whitespaces).first else { return false }
        return "-−↓▼".contains(first)
    }
}

/// Estado vacío o sin resultados: el del sistema (`ContentUnavailableView`, canvas `EstadoVacio`), con una acción
/// opcional en el botón principal compacto.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.primaryCompact)
            }
        }
    }
}

/// Logotipo de Chirogra (canvas `Main`, icono de la cabecera): cuadrado en Tinta, «C» abierta blanca y punto de azafrán,
/// igual en claro y en oscuro.
struct LogoMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 9 / 40, style: .continuous).fill(Palette.logoFill)
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(Palette.logoMark, style: StrokeStyle(lineWidth: size * 3.4 / 40, lineCap: .round))
                .frame(width: size * 18 / 40, height: size * 18 / 40)
            Circle().fill(Palette.accent)
                .frame(width: size * 5.4 / 40, height: size * 5.4 / 40)
                .offset(x: size * 8.6 / 40)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Chirogra")
    }
}

// MARK: - Campos

/// Campo de importe en dólares enlazado a centavos.
struct MoneyField: View {
    let title: String
    @Binding var minorUnits: Int64

    var body: some View {
        TextField(title, value: decimal, format: .currency(code: "USD"))
            .monospacedDigit()
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
    }

    private var decimal: Binding<Decimal> {
        Binding(
            get: { Money(minorUnits: minorUnits).decimalValue },
            set: { minorUnits = Money(decimal: $0).minorUnits }
        )
    }
}

/// Selector de cuenta filtrado (p. ej. solo cuentas de dinero o de gasto).
struct AccountPicker: View {
    let title: String
    let accounts: [Account]
    @Binding var selection: UUID?

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Elegir…").tag(UUID?.none)
            ForEach(accounts) { account in
                Text(account.displayName).tag(Optional(account.id))
            }
        }
    }
}

/// Mensaje de error recuperable con texto claro: símbolo y texto en rojo sobre un fondo rojo tenue.
struct ErrorBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.negative)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.negativeWash, in: RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous))
    }
}
