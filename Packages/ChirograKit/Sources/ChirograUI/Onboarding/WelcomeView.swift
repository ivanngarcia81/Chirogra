import ChirograData
import SwiftData
import SwiftUI

/// Bienvenida de la primera vez (canvas «Chirogra — Bienvenida», opción B: `Carrusel`, `iPadCarrusel`, `MacCarrusel`).
/// Cinco páginas (Bienvenida, Facturas, Gastos, Reportes, Privada) que se pasan deslizando o con «Continuar»; «Saltar» va
/// a la última, con «Crear mi empresa» (paso 1 del alta), «Probar con datos de ejemplo» y «¿Ya usas Chirogra en otro
/// aparato?» (hoja con el aviso de iCloud, que antes estaba en el paso 1 del alta).
/// Cada ilustración se anima al llegar a su página (la χ se dibuja, la factura se marca como pagada, el recibo cae en su
/// gasto, las barras crecen, el candado se cierra). Con «Reducir movimiento» todo aparece quieto.
/// Los botones siguen la decisión del usuario (vidrio en Tinta, sin relleno morado) y no los del canvas.
struct WelcomeView: View {
    static let pageCount = 5
    /// Ajuste de este aparato: la bienvenida ya se pasó («Crear mi empresa» o los datos de ejemplo).
    static let seenKey = "welcome.seen"

    /// «Crear mi empresa».
    let onCreate: () -> Void
    /// «Probar con datos de ejemplo» (después de crear los libros de ejemplo).
    let onSample: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @AppStorage(ChirograStore.syncEnabledKey) private var iCloudSyncEnabled = true
    @State private var page: Int
    @State private var showsOtherDevice = false
    @State private var errorMessage: String?

    init(startPage: Int = 0, onCreate: @escaping () -> Void, onSample: @escaping () -> Void) {
        _page = State(initialValue: min(max(startPage, 0), Self.pageCount - 1))
        self.onCreate = onCreate
        self.onSample = onSample
    }

    private var isLast: Bool { page == Self.pageCount - 1 }

    private func go(_ target: Int) {
        let clamped = min(max(target, 0), Self.pageCount - 1)
        if reduceMotion { page = clamped } else { withAnimation(.smooth(duration: 0.45)) { page = clamped } }
    }

    var body: some View {
        pages
            .background(Palette.background)
            #if os(iOS)
            .overlay(alignment: .top) { topBar }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            #else
            .safeAreaInset(edge: .bottom, spacing: 0) { macFooter }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.rightArrow) { go(page + 1); return .handled }
            .onKeyPress(.leftArrow) { go(page - 1); return .handled }
            #endif
            .sheet(isPresented: $showsOtherDevice) { OtherDeviceSheet() }
            .alert("No se pudieron crear los datos de ejemplo", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    // MARK: Páginas

    @ViewBuilder
    private var pages: some View {
        #if os(iOS)
        // El carrusel del sistema: se pasa deslizando, como en el canvas; los puntos son los propios, en la barra.
        TabView(selection: Binding(get: { page }, set: { go($0) })) {
            ForEach(0..<Self.pageCount, id: \.self) { index in
                WelcomePage(index: index, isCurrent: page == index, otherDevice: otherDeviceAction(for: index))
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(edges: .top)
        #else
        // En el Mac no hay carrusel del sistema: la página entra de lado, con las flechas o los botones del pie.
        ZStack {
            WelcomePage(index: page, isCurrent: true, otherDevice: nil)
                .id(page)
                .transition(reduceMotion ? .identity : .push(from: .trailing))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        #endif
    }

    /// El enlace de iCloud va debajo del texto de la última página (en el Mac, en el pie). Solo con iCloud encendido:
    /// apagado, los libros no llegarían de otro aparato.
    private func otherDeviceAction(for index: Int) -> (() -> Void)? {
        guard index == Self.pageCount - 1, iCloudSyncEnabled else { return nil }
        return { showsOtherDevice = true }
    }

    // MARK: Acciones

    private func loadSample() {
        do {
            try SampleData.populate(context)
            onSample()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Puntos de página: la actual alargada y en Tinta; las demás al 25 % (canvas).
    private var dots: some View {
        HStack(spacing: Self.dotSpacing) {
            ForEach(0..<Self.pageCount, id: \.self) { index in
                Capsule()
                    .fill(Palette.ink)
                    .frame(width: index == page ? Self.dotSide * 2.75 : Self.dotSide, height: Self.dotSide)
                    .opacity(index == page ? 1 : 0.25)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Página \(page + 1) de \(Self.pageCount)"))
    }

    #if os(macOS)
    private static let dotSide: CGFloat = 7
    private static let dotSpacing: CGFloat = 6
    #else
    private static let dotSide: CGFloat = 8
    private static let dotSpacing: CGFloat = 7
    #endif

    // MARK: iPhone e iPad

    #if os(iOS)
    private var isCompact: Bool { sizeClass != .regular }

    /// «Atrás» (círculo de vidrio) a la izquierda y «Saltar» a la derecha.
    private var topBar: some View {
        HStack {
            if page > 0 {
                Button { go(page - 1) } label: {
                    Image(systemName: "chevron.left").font(.title3.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(Palette.ink)
                .accessibilityLabel("Atrás")
            }
            Spacer()
            if !isLast {
                Button("Saltar") { go(Self.pageCount - 1) }
                    .font(.body)
                    .frame(minHeight: Metrics.target)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, isCompact ? 16 : 24)
        .padding(.top, isCompact ? 4 : 16)
    }

    /// iPhone: barra de vidrio que flota abajo, como la del alta. iPad: los puntos y el botón, sin barra (`iPadCarrusel`).
    @ViewBuilder
    private var bottomBar: some View {
        let content = VStack(spacing: 12) {
            dots
            if isLast {
                Button("Crear mi empresa", action: onCreate)
                    .buttonStyle(.primary)
                Button("Probar con datos de ejemplo", action: loadSample)
                    .font(.body.weight(.semibold))
                    .frame(minHeight: Metrics.target)
            } else {
                Button("Continuar") { go(page + 1) }
                    .buttonStyle(.primary)
            }
        }
        if isCompact {
            content
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, isLast ? 2 : 12)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        } else {
            content
                .frame(width: 360)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
        }
    }
    #endif

    // MARK: Mac

    #if os(macOS)
    /// Pie de la ventana (`MacCarrusel`): puntos e iCloud a la izquierda; «Saltar» o los datos de ejemplo, «Atrás» y
    /// «Continuar» o «Crear mi empresa» a la derecha, con Retorno.
    private var macFooter: some View {
        HStack(spacing: 12) {
            dots
            if isLast, iCloudSyncEnabled {
                Button { showsOtherDevice = true } label: {
                    Label("¿Ya usas Chirogra en otro aparato?", systemImage: "icloud")
                }
                .buttonStyle(.link)
                .padding(.leading, 12)
            }
            Spacer(minLength: 12)
            if isLast {
                Button("Probar con datos de ejemplo", action: loadSample)
            } else {
                Button("Saltar") { go(Self.pageCount - 1) }.buttonStyle(.link)
            }
            Button("Atrás") { go(page - 1) }
                .disabled(page == 0)
            if isLast {
                Button("Crear mi empresa", action: onCreate)
                    .buttonStyle(.primaryCompact)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continuar") { go(page + 1) }
                    .buttonStyle(.primaryCompact)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 22)
    }
    #endif
}

// MARK: - Una página

/// Ilustración, título y frase de una página. `isCurrent` dispara su animación cada vez que se llega a ella.
private struct WelcomePage: View {
    let index: Int
    let isCurrent: Bool
    let otherDevice: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    /// 0 = todo escondido; 1 = todo en su sitio. Cada pieza entra con su propio retraso (`appear`).
    @State private var shown = false

    private var isRegular: Bool {
        #if os(iOS)
        sizeClass == .regular
        #else
        true
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // En el iPad, un 20 % más grandes (`iPadCarrusel`).
                illustration
                    .scaleEffect(isRegular && !Self.isMac ? 1.2 : 1)
                    .frame(height: isRegular && !Self.isMac ? 264 : 220)
                    .accessibilityHidden(index != 0)
                texts
                    .padding(.top, 28)
                if let otherDevice {
                    Button(action: otherDevice) {
                        Label("¿Ya usas Chirogra en otro aparato?", systemImage: "icloud")
                            .font(.subheadline)
                            .frame(minHeight: Metrics.target)
                    }
                    .padding(.top, 12)
                    .appear(shown, delay: 0.6, reduceMotion: reduceMotion)
                }
            }
            .frame(maxWidth: Self.textWidth)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
            .padding(.top, Self.topPadding)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(isRegular ? .center : .top)
        // Con `onChange(initial:)` el cambio caía en la misma pasada en que la página aparece y SwiftUI lo pintaba ya
        // terminado: hay que esperar a que esté en pantalla. Al irse se esconde sin animar, lista para la próxima vez.
        .task(id: isCurrent) {
            guard isCurrent else {
                var hide = Transaction()
                hide.disablesAnimations = true
                withTransaction(hide) { shown = false }
                return
            }
            if reduceMotion { shown = true; return }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            shown = true
        }
        .accessibilityElement(children: .contain)
    }

    #if os(macOS)
    private static let topPadding: CGFloat = 40
    private static let textWidth: CGFloat = 440
    #else
    private static let topPadding: CGFloat = 110
    private static let textWidth: CGFloat = 500
    #endif

    // MARK: Textos

    private var title: LocalizedStringKey {
        switch index {
        case 1: "Facturas que se cobran"
        case 2: "Gastos con su recibo"
        case 3: "Reportes para tu contador"
        default: "Privada por diseño"
        }
    }

    private var message: LocalizedStringKey {
        switch index {
        case 0: "La contabilidad completa de tu negocio, clara desde el primer día."
        case 1: "Envía facturas y estimados con tu sales tax, manda recordatorios y registra cada cobro, completo o parcial."
        #if os(macOS)
        case 2: "Arrastra la foto o el PDF del recibo a cada gasto. Paga a tus proveedores a tiempo."
        #else
        case 2: "Toma la foto o guarda el PDF del recibo junto a cada gasto. Paga a tus proveedores a tiempo."
        #endif
        case 3: "Estado de resultados, balance general y sales tax por periodo, listos para exportar."
        default: "Sin cuenta, sin anuncios y sin rastreo. Tus libros viven en tus aparatos y, si quieres, en tu iCloud."
        }
    }

    @ViewBuilder
    private var texts: some View {
        VStack(spacing: 12) {
            if index == 0 {
                VStack(spacing: 2) {
                    Text("Te damos la bienvenida a")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink2)
                    Text(verbatim: "Chirogra")
                        .font(.system(size: isRegular && !Self.isMac ? 48 : 40, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            } else {
                Text(title)
                    .font(isRegular && !Self.isMac ? .largeTitle.bold() : .title.bold())
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(message)
                .font(.body)
                .foregroundStyle(Palette.ink2)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .appear(shown, delay: 0.3, reduceMotion: reduceMotion, offset: 18)
    }

    private static var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    // MARK: Ilustraciones

    @ViewBuilder
    private var illustration: some View {
        switch index {
        case 0: LogoDrawing(shown: shown, reduceMotion: reduceMotion, size: isRegular && !Self.isMac ? 150 : 128)
        case 1: InvoiceArt(shown: shown, reduceMotion: reduceMotion)
        case 2: ReceiptArt(shown: shown, reduceMotion: reduceMotion)
        case 3: ReportArt(shown: shown, reduceMotion: reduceMotion)
        default: PrivacyArt(shown: shown, reduceMotion: reduceMotion)
        }
    }
}

// MARK: - Animación de entrada

private extension View {
    /// Aparece (opacidad y un poco desde abajo) con su retraso cuando `shown` pasa a `true`; quieto con «Reducir movimiento».
    func appear(_ shown: Bool, delay: Double, reduceMotion: Bool, offset: CGFloat = 0) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : offset)
            .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.15).delay(delay), value: shown)
    }

    /// Entra creciendo desde el 30 % con un pequeño rebote (`pop` del canvas).
    func pop(_ shown: Bool, delay: Double, reduceMotion: Bool) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.3)
            .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.45).delay(delay), value: shown)
    }
}

/// Tarjeta blanca de las ilustraciones, con la sombra del canvas.
private struct ArtCard<Content: View>: View {
    var width: CGFloat
    var height: CGFloat
    var padding: EdgeInsets
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            #if os(macOS)
            .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).strokeBorder(Palette.separator, lineWidth: 0.5))
            #endif
            .shadow(color: .black.opacity(0.10), radius: 15, y: 10)
    }

    #if os(macOS)
    private static var radius: CGFloat { 16 }
    #else
    private static var radius: CGFloat { 20 }
    #endif
}

/// Raya gris que hace de texto en las ilustraciones.
private struct Bar: View {
    var width: CGFloat
    var height: CGFloat = 8
    var color: Color = Palette.fill2

    var body: some View {
        Capsule().fill(color).frame(width: width, height: height)
    }
}

// MARK: Página 1: la χ se dibuja

private struct LogoDrawing: View {
    let shown: Bool
    let reduceMotion: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).fill(Palette.logoFill)
            ChiStroke(part: .curve)
                .trim(from: 0, to: shown ? 1 : 0)
                .stroke(Palette.logoMark, style: stroke)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.9).delay(0.15), value: shown)
            ChiStroke(part: .line)
                .trim(from: 0, to: shown ? 1 : 0)
                .stroke(Palette.logoMark, style: stroke)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.9).delay(0.45), value: shown)
            Circle().fill(Palette.accent)
                .frame(width: size * 80 / 1024, height: size * 80 / 1024)
                .pop(shown, delay: 0.8, reduceMotion: reduceMotion)
                .position(x: size * 540 / 1024, y: size * 250 / 1024)
        }
        .frame(width: size, height: size)
        .pop(shown, delay: 0, reduceMotion: reduceMotion)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "Chirogra"))
    }

    private var stroke: StrokeStyle {
        StrokeStyle(lineWidth: size * 104 / 1024, lineCap: .round, lineJoin: .round)
    }
}

/// Uno de los dos trazos de la χ (los mismos de `LogoMark`), para dibujarlos por separado.
nonisolated private struct ChiStroke: Shape {
    enum Part { case curve, line }
    let part: Part

    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 1024, y: rect.minY + rect.height * y / 1024)
        }
        var path = Path()
        switch part {
        case .curve:
            path.move(to: p(292, 298))
            path.addCurve(to: p(512, 512), control1: p(392, 280), control2: p(440, 360))
            path.addCurve(to: p(732, 722), control1: p(584, 664), control2: p(632, 740))
        case .line:
            path.move(to: p(320, 740))
            path.addLine(to: p(704, 284))
        }
        return path
    }
}

// MARK: Página 2: la factura se marca como pagada

private struct InvoiceArt: View {
    let shown: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            ArtCard(width: 168, height: 208, padding: EdgeInsets(top: 22, leading: 20, bottom: 22, trailing: 20)) {
                VStack(alignment: .leading, spacing: 12) {
                    LogoMark(size: 28).accessibilityHidden(true)
                    Bar(width: 90)
                    Bar(width: 64)
                    Rectangle().fill(Palette.separator).frame(height: 0.5).padding(.vertical, 6)
                    Bar(width: 115)
                    Bar(width: 102)
                    Spacer(minLength: 0)
                    HStack {
                        Spacer()
                        Bar(width: 70, height: 12, color: Palette.brand)
                    }
                }
            }
            .appear(shown, delay: 0, reduceMotion: reduceMotion, offset: 18)

            Circle().fill(Palette.green)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "checkmark").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.10), radius: 15, y: 10)
                .pop(shown, delay: 0.6, reduceMotion: reduceMotion)
                .offset(x: 82, y: -60)
        }
        .frame(width: 340, height: 220)
    }
}

// MARK: Página 3: el recibo cae en su gasto

private struct ReceiptArt: View {
    let shown: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            ArtCard(width: 220, height: 120, padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                HStack(alignment: .bottom, spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.orange)
                        .frame(width: 36, height: 36)
                        .overlay { Image(systemName: "camera").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white) }
                    VStack(alignment: .leading, spacing: 8) {
                        Bar(width: 120)
                        Bar(width: 84)
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .appear(shown, delay: 0, reduceMotion: reduceMotion, offset: 18)
            .offset(y: 40)

            ReceiptPaper()
                .frame(width: 110, height: 150)
                .shadow(color: .black.opacity(0.14), radius: 8, y: 8)
                .opacity(shown ? 1 : 0)
                .rotationEffect(.degrees(shown ? -4 : -14))
                .offset(x: shown ? -5 : -45, y: shown ? -29 : -89)
                .animation(reduceMotion ? nil : .spring(duration: 0.8, bounce: 0.2).delay(0.3), value: shown)
        }
        .frame(width: 340, height: 220)
    }
}

/// El recibo del canvas: papel blanco con el borde de abajo en zigzag, rayas grises y el total en naranja.
private struct ReceiptPaper: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            ZigzagPaper().fill(Color.white)
            VStack(alignment: .leading, spacing: 0) {
                Bar(width: 56, height: 7, color: Color(white: 0.82)).padding(.top, 20)
                Bar(width: 70, height: 6, color: Color(white: 0.9)).padding(.top, 13)
                Bar(width: 62, height: 6, color: Color(white: 0.9)).padding(.top, 8)
                Bar(width: 68, height: 6, color: Color(white: 0.9)).padding(.top, 8)
                Rectangle().fill(Color(white: 0.82)).frame(width: 70, height: 1).padding(.top, 18)
                HStack {
                    Spacer()
                    Bar(width: 34, height: 9, color: Color(red: 1, green: 0.584, blue: 0))
                }
                .frame(width: 70)
                .padding(.top, 9)
            }
            .padding(.leading, 16)
        }
    }
}

nonisolated private struct ZigzagPaper: Shape {
    func path(in rect: CGRect) -> Path {
        let teeth = 10
        let depth: CGFloat = rect.height * 7 / 150
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - depth))
        let step = rect.width / CGFloat(teeth)
        for tooth in 0..<teeth {
            let x = rect.maxX - step * CGFloat(tooth)
            path.addLine(to: CGPoint(x: x - step / 2, y: rect.maxY))
            path.addLine(to: CGPoint(x: x - step, y: rect.maxY - depth))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: Página 4: las barras crecen

private struct ReportArt: View {
    let shown: Bool
    let reduceMotion: Bool

    private static let bars: [(height: CGFloat, income: Bool, delay: Double)] = [
        (0.45, true, 0.2), (0.28, false, 0.2), (0.70, true, 0.3), (0.36, false, 0.3), (0.95, true, 0.45), (0.40, false, 0.45),
    ]

    var body: some View {
        ArtCard(width: 240, height: 190, padding: EdgeInsets(top: 20, leading: 22, bottom: 18, trailing: 22)) {
            VStack(alignment: .leading, spacing: 12) {
                Bar(width: 88)
                GeometryReader { proxy in
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(Self.bars.indices, id: \.self) { index in
                            let bar = Self.bars[index]
                            UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5)
                                .fill(bar.income ? Palette.brand : Palette.orange)
                                .frame(height: proxy.size.height * bar.height)
                                .scaleEffect(x: 1, y: shown ? 1 : 0, anchor: .bottom)
                                .opacity(shown ? 1 : 0)
                                .animation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.1).delay(bar.delay), value: shown)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.separator).frame(height: 0.5) }
                HStack(spacing: 8) {
                    chip("PDF").pop(shown, delay: 0.6, reduceMotion: reduceMotion)
                    chip("CSV").pop(shown, delay: 0.8, reduceMotion: reduceMotion)
                }
            }
        }
        .appear(shown, delay: 0, reduceMotion: reduceMotion, offset: 18)
        .frame(width: 340, height: 220)
    }

    private func chip(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.brand)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Palette.brandWash, in: Capsule())
    }
}

// MARK: Página 5: el candado se cierra

private struct PrivacyArt: View {
    let shown: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle().fill(Palette.brandWash)
                .frame(width: 180, height: 180)
                .overlay { lock }
                .pop(shown, delay: 0, reduceMotion: reduceMotion)

            Circle().fill(Palette.surface)
                .frame(width: 56, height: 56)
                #if os(macOS)
                .overlay(Circle().strokeBorder(Palette.separator, lineWidth: 0.5))
                #endif
                .overlay { Image(systemName: "icloud").font(.system(size: 24, weight: .medium)).foregroundStyle(Palette.blue) }
                .shadow(color: .black.opacity(0.10), radius: 15, y: 10)
                .pop(shown, delay: 0.6, reduceMotion: reduceMotion)
                .offset(x: 76, y: -58)
        }
        .frame(width: 340, height: 220)
    }

    /// Candado de 96 pt: el arco baja hasta cerrarse sobre el cuerpo.
    private var lock: some View {
        let unit: CGFloat = 96 / 24
        return ZStack(alignment: .topLeading) {
            LockShackle()
                .stroke(Palette.brand, style: StrokeStyle(lineWidth: 1.6 * unit, lineCap: .round, lineJoin: .round))
                .frame(width: 7 * unit, height: 7.5 * unit)
                .offset(x: 8.5 * unit, y: 3.5 * unit + (shown ? 0 : -7 * unit / 2.5))
                .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.45).delay(0.45), value: shown)
            RoundedRectangle(cornerRadius: 2.5 * unit, style: .continuous).fill(Palette.brand)
                .frame(width: 13 * unit, height: 10 * unit)
                .overlay { Circle().fill(.white).frame(width: 2.8 * unit, height: 2.8 * unit).offset(y: -0.4 * unit) }
                .offset(x: 5.5 * unit, y: 11 * unit)
        }
        .frame(width: 96, height: 96, alignment: .topLeading)
    }
}

/// Arco del candado: dos lados rectos y medio círculo arriba.
nonisolated private struct LockShackle: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.minY + radius), radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

// MARK: - ¿Ya usas Chirogra en otro aparato?

/// Lo que antes era el recuadro del paso 1 del alta: quien ya lleva sus libros en otro aparato no tiene que crear la
/// empresa otra vez. Si llegó aquí es que iCloud no trajo libros (el otro aparato no los ha subido, p. ej. con iCloud
/// apagado desde la 1.0): al encenderlo allí, llegan solos y la raíz deja la bienvenida (`companies` deja de estar vacío).
struct OtherDeviceSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Palette.blue)
                        .accessibilityHidden(true)
                    Text("¿Ya usas Chirogra en otro aparato?")
                        .font(.title2.bold())
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("No crees la empresa otra vez: en ese aparato, enciende «Sincronizar con iCloud» en Ajustes (en el iPhone, en Más) y tus libros llegarán aquí solos.")
                        .font(.body)
                        .foregroundStyle(Palette.ink2)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(24)
                .padding(.top, 8)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.background)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(width: 440, height: 300)
        #endif
    }
}

#Preview {
    WelcomeView(onCreate: {}, onSample: {}).modelContainer(try! ChirograStore.makeContainer(inMemory: true))
}
