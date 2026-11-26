import XCTest

/// Pruebas de interfaz de los flujos principales del iPhone (auditoría del 23-nov): no solo que la pantalla se dibuje,
/// sino que tocar lo que toca el usuario cambie los libros y lo que se ve. Cada prueba arranca con los datos de ejemplo
/// recién cargados (`-qa.reiniciar 1 -qa.muestra 1`, solo en Debug) y la app en español de EE. UU., sin iCloud.
/// Correr con `scripts/interfaz.sh`.
@MainActor
final class FlujosTests: XCTestCase {
    let app = XCUIApplication()
    /// Las máquinas de GitHub Actions son mucho más lentas que un Mac: esperas largas (solo se esperan, no se gastan).
    let patience: TimeInterval = 30

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-iCloudSyncEnabled", "NO", "-AppleLanguages", "(es)", "-AppleLocale", "es_US",
                               "-qa.reiniciar", "1", "-qa.muestra", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Total pendiente"].waitForExistence(timeout: patience * 2), "Inicio con los datos de ejemplo")
    }

    // MARK: Ayudantes

    /// «$7,170.02» o «−$293.14» → centavos.
    func cents(_ text: String) -> Int64? {
        let negative = text.contains("−") || text.contains("-")
        let digits = text.filter { $0.isNumber }
        guard text.contains("$"), let value = Int64(digits) else { return nil }
        return negative ? -value : value
    }

    /// Lo que dice «Total pendiente» en Inicio (Por cobrar), en centavos. La etiqueta es «Total pendiente, $7,170.02,
    /// Vencido …» (la coma de miles no lleva espacio detrás).
    func pendingOnHome() throws -> Int64 {
        let label = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Total pendiente, '")).firstMatch.label
        let parts = label.components(separatedBy: ", ")
        XCTAssertGreaterThan(parts.count, 1, label)
        return try XCTUnwrap(cents(parts[1]), label)
    }

    func button(startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let timeout = timeout ?? patience
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "No aparece: \(element)", file: file, line: line)
        // Las hojas y los diálogos se animan: el toque antes de que se asienten se pierde.
        let deadline = Date().addingTimeInterval(timeout)
        while !element.isHittable, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        element.tap()
    }

    /// Cierra el teclado con «Listo» de su barra; si sigue abierto (en las máquinas lentas de GitHub un toque a veces no
    /// basta), lo intenta otra vez y luego deslizando el formulario hacia abajo.
    func dismissKeyboard() {
        for attempt in 0..<4 where app.keyboards.count > 0 {
            let done = app.toolbars.buttons["Listo"]
            if attempt < 2, done.waitForExistence(timeout: 5) { done.tap() } else { app.collectionViews.firstMatch.swipeDown() }
            let closed = expectation(for: NSPredicate(format: "count == 0"), evaluatedWith: app.keyboards)
            _ = XCTWaiter.wait(for: [closed], timeout: 5)
        }
        XCTAssertEqual(app.keyboards.count, 0, "el teclado sigue abierto")
    }

    /// Cobra la F-1003 de Clínica Del Valle ($1,100.02) desde Inicio y deja abierta su ficha.
    func payClinicInvoice() {
        tapWhenReady(button(startingWith: "Clínica Del Valle, F-1003"))
        tapWhenReady(app.buttons["Marcar como pagada · $1,100.02"])
        tapWhenReady(app.sheets.buttons["Marcar como pagada"])
        XCTAssertTrue(app.staticTexts["Clínica Del Valle, $1,100.02, Pagada, Total cobrado $1,100.02"].waitForExistence(timeout: patience))
    }

    // MARK: Pruebas

    func testCobrarUnaFacturaLaSacaDePorCobrar() throws {
        let before = try pendingOnHome()
        payClinicInvoice()
        XCTAssertTrue(button(startingWith: "Cobro, ").exists, "el cobro aparece en la actividad")
        tapWhenReady(app.navigationBars.buttons["Inicio"])
        XCTAssertTrue(app.staticTexts["Total pendiente"].waitForExistence(timeout: patience))
        XCTAssertEqual(try pendingOnHome(), before - 110_002)
        XCTAssertFalse(button(startingWith: "Clínica Del Valle, F-1003").exists, "ya no está en Por cobrar")
    }

    func testAnularElCobroDevuelveLaFacturaAPendiente() throws {
        let before = try pendingOnHome()
        payClinicInvoice()
        tapWhenReady(app.navigationBars.buttons["Más acciones"])
        tapWhenReady(app.buttons["Anular cobro…"])
        tapWhenReady(app.sheets.buttons["Anular cobro"])
        XCTAssertTrue(app.buttons["Marcar como pagada · $1,100.02"].waitForExistence(timeout: patience), "vuelve a poder cobrarse")
        tapWhenReady(app.navigationBars.buttons["Inicio"])
        XCTAssertTrue(app.staticTexts["Total pendiente"].waitForExistence(timeout: patience))
        XCTAssertEqual(try pendingOnHome(), before)
        XCTAssertTrue(button(startingWith: "Clínica Del Valle, F-1003").exists)
    }

    func testEmitirUnaFacturaNuevaLaSumaAPorCobrar() throws {
        let before = try pendingOnHome()
        tapWhenReady(app.buttons["Factura"].firstMatch)
        XCTAssertTrue(app.navigationBars["Nueva factura"].waitForExistence(timeout: patience))
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label == 'Cliente' AND value == 'Sin elegir'")).firstMatch)
        tapWhenReady(app.buttons["Clínica Del Valle"].firstMatch)
        let description = app.textFields["Descripción"]
        tapWhenReady(description)
        description.typeText("Prueba de interfaz")
        // «Precio» de la barra del teclado lleva el foco al precio de la línea (como haría el usuario).
        tapWhenReady(app.buttons["Precio"].firstMatch)
        app.typeText("250")
        // Cerrar el teclado: el importe se confirma al salir del campo y vuelve la barra con el total y «Emitir».
        dismissKeyboard()
        // El total (con el impuesto que toque) es lo que tiene que sumarse a Por cobrar.
        let totalLabel = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Total, $'")).firstMatch
        XCTAssertTrue(totalLabel.waitForExistence(timeout: patience))
        let total = try XCTUnwrap(cents(totalLabel.label))
        XCTAssertGreaterThanOrEqual(total, 25_000)
        tapWhenReady(app.buttons["Emitir factura"])
        // Tras emitir, la app ofrece enviarla: «Ahora no».
        let later = app.buttons["Ahora no"]
        if later.waitForExistence(timeout: 8) { later.tap() }
        let back = app.navigationBars.buttons["Inicio"]
        if back.waitForExistence(timeout: 3) { back.tap() }  // si tras emitir quedó abierta la ficha, se vuelve a Inicio
        XCTAssertTrue(app.staticTexts["Total pendiente"].waitForExistence(timeout: patience))
        XCTAssertEqual(try pendingOnHome(), before + total)
    }

    /// «Total ingresos» del estado de resultados a la vista, en centavos («Total ingresos, $6,062.40, Oct …»).
    func totalIncome() throws -> Int64 {
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Total ingresos, '")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: patience))
        return try XCTUnwrap(cents(row.label.components(separatedBy: ", ")[1]), row.label)
    }

    func testEnBaseCajaElCobroSumaLosIngresosYEnDevengadoNo() throws {
        tapWhenReady(app.tabBars.buttons["Más"])
        tapWhenReady(app.buttons["Estado de resultados"])
        let accrual = try totalIncome()
        tapWhenReady(app.buttons["Caja"])
        XCTAssertTrue(app.staticTexts["Ríos Diseño & Obra · base caja"].waitForExistence(timeout: patience))
        let cash = try totalIncome()

        // Cobrar la F-1003 ($1,000 de servicios + $92.40 de materiales + $7.62 de sales tax) desde Inicio.
        tapWhenReady(app.tabBars.buttons["Inicio"])
        payClinicInvoice()
        tapWhenReady(app.tabBars.buttons["Más"])
        XCTAssertTrue(app.staticTexts["Ríos Diseño & Obra · base caja"].waitForExistence(timeout: patience))
        // En caja entra el ingreso cobrado sin el impuesto, que es un pasivo.
        XCTAssertEqual(try totalIncome(), cash + 109_240)
        tapWhenReady(app.buttons["Devengado"])
        XCTAssertTrue(app.staticTexts["Ríos Diseño & Obra · base devengado"].waitForExistence(timeout: patience))
        XCTAssertEqual(try totalIncome(), accrual, "en devengado la factura ya contaba al emitirse")
    }
}

/// El tutorial de seguir (1.4): con la empresa recién creada, la persona crea de verdad su primer cliente, su primera
/// factura y un gasto tocando lo que se ilumina, y termina en el apartado para impuestos. Con `TEST_RUNNER_CAPTURAS=<carpeta>`
/// guarda una captura de cada paso.
@MainActor
final class TutorialGuiadoTests: XCTestCase {
    let app = XCUIApplication()
    let patience: TimeInterval = 30

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-iCloudSyncEnabled", "NO", "-AppleLanguages", "(es)", "-AppleLocale", "es_US",
                               "-qa.reiniciar", "1", "-qa.alta", "1", "-qa.altaCrear", "1", "-qa.altaEstado", "TX",
                               "-qa.recorrido", "guiado"]
        app.launch()
    }

    private var paso = 0

    /// Espera la tarjeta del paso y, si se pidieron, guarda su captura.
    func tarjeta(_ titulo: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts[titulo].waitForExistence(timeout: patience), "No sale la tarjeta «\(titulo)»", file: file, line: line)
        // La tarjeta entra animada y el foco se desliza: la captura, cuando se asienta.
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        foto(titulo)
    }

    func foto(_ nombre: String) {
        paso += 1
        let captura = XCUIScreen.main.screenshot()
        let adjunto = XCTAttachment(screenshot: captura)
        adjunto.name = nombre
        adjunto.lifetime = .keepAlways
        add(adjunto)
        if let carpeta = ProcessInfo.processInfo.environment["CAPTURAS"] {
            let archivo = String(format: "%02d ", paso) + nombre.replacingOccurrences(of: "/", with: "-") + ".png"
            try? captura.pngRepresentation.write(to: URL(fileURLWithPath: carpeta).appendingPathComponent(archivo))
        }
    }

    func tocar(_ elemento: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(elemento.waitForExistence(timeout: patience), "No aparece: \(elemento)", file: file, line: line)
        let limite = Date().addingTimeInterval(patience)
        while !elemento.isHittable, Date() < limite { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        elemento.tap()
    }

    func boton(_ prefijo: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefijo)).firstMatch
    }

    /// En el iPad los editores son anchos: la tabla de líneas y «Guardar gasto».
    var esIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    func testElTutorialDeSeguirCreaClienteFacturaYGasto() throws {
        tarjeta("Aprende haciendo")
        tocar(app.buttons["Empezar"])

        // Cliente: tocar la fila, escribir el nombre, «Siguiente», «Guardar».
        tarjeta("Tu primer cliente")
        tocar(boton("Añade tu primer cliente"))
        tarjeta("Escribe su nombre")
        XCTAssertFalse(app.buttons["Siguiente"].isEnabled, "«Siguiente» espera al nombre")
        let nombre = app.textFields["Nombre o empresa"]
        tocar(nombre)
        nombre.typeText("Rosa Martínez")
        foto("Nombre escrito")
        tocar(app.buttons["Siguiente"])
        tarjeta("Guárdalo")
        tocar(app.navigationBars.buttons["Guardar"])

        // Factura: la fila, el cliente, la línea con su precio, el impuesto y «Emitir».
        tarjeta("Tu primera factura")
        tocar(boton("Crea tu primera factura"))
        tarjeta("Elige el cliente")
        tocar(app.buttons.matching(NSPredicate(format: "label == 'Cliente' AND value == 'Sin elegir'")).firstMatch)
        tocar(app.buttons["Rosa Martínez"].firstMatch)
        tarjeta("Qué vendiste y a cuánto")
        let descripcion = app.textFields[esIPad ? "Producto o servicio, línea 1" : "Descripción"]
        tocar(descripcion)
        descripcion.typeText("Diseño de logotipo")
        if esIPad { tocar(app.textFields["Precio, línea 1"]) } else { tocar(app.buttons["Precio"].firstMatch) }
        app.typeText("250")
        foto("Línea escrita")
        tocar(app.buttons["Siguiente"])
        tarjeta("El sales tax, solo")
        tocar(app.buttons["Siguiente"])
        tarjeta("Emítela")
        if app.keyboards.count > 0, app.toolbars.buttons["Listo"].exists { tocar(app.toolbars.buttons["Listo"]) }
        foto("Emítela sin teclado")
        tocar(app.buttons["Emitir factura"])
        // «Enviar a …» en vez de «Ahora no»: la hoja de enviar no puede quedar tapada por el velo (26-nov, Mac).
        tocar(boton("Enviar a Rosa Martínez"))
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: patience))
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        foto("Hoja de enviar")
        XCTAssertFalse(app.staticTexts["Anota un gasto"].isHittable, "el tutorial no se dibuja encima de la hoja de enviar")
        tocar(app.navigationBars.buttons["Cancelar"].firstMatch)
        let descartar = app.buttons["Descartar"]
        if descartar.waitForExistence(timeout: 3) { descartar.tap() }
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        foto("Tras emitir")

        // Gasto: la fila, el monto, la categoría y «Guardar».
        tarjeta("Anota un gasto")
        tocar(boton("Registra un gasto"))
        tarjeta("¿Cuánto pagaste?")
        let monto = app.textFields["Monto"]
        tocar(monto)
        monto.typeText("45")
        foto("Monto escrito")
        tocar(app.buttons["Siguiente"])
        tarjeta("¿A quién le pagaste?")
        let pagadoA = app.textFields["Pagado a (comercio o persona)"]
        tocar(pagadoA)
        pagadoA.typeText("Office Depot")
        tocar(app.buttons["Siguiente"])
        tarjeta("¿En qué se fue?")
        XCTAssertFalse(app.buttons["Siguiente"].isEnabled, "«Siguiente» espera a la categoría")
        tocar(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Categoría'")).firstMatch)
        foto("Menú de categorías")
        let suministros = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'suministros'")).firstMatch
        XCTAssertTrue(suministros.waitForExistence(timeout: 10), app.debugDescription)
        suministros.tap()
        foto("Categoría elegida")
        tocar(app.buttons["Siguiente"])
        tarjeta("Guárdalo")
        tocar(app.navigationBars.buttons[esIPad ? "Guardar gasto" : "Guardar"])

        // Impuestos: el apartado para el IRS si Inicio lo enseña; si no (el iPad lo tiene en su columna), el sales tax.
        let apartado = app.staticTexts["Tu apartado para impuestos"]
        let ventas = app.staticTexts["Tu sales tax"]
        let limite = Date().addingTimeInterval(patience)
        while !apartado.exists, !ventas.exists, Date() < limite { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }
        if apartado.exists {
            tarjeta("Tu apartado para impuestos")
            if esIPad { tocar(boton("Apartado para impuestos")) } else { tocar(app.buttons["tarjeta.apartado"]) }
            tarjeta("Lo que toca apartar")
        } else {
            tarjeta("Tu sales tax")
            tocar(boton("Configura tu sales tax"))
            tarjeta("Lo que le debes al estado")
        }
        tocar(app.buttons["Siguiente"])
        tarjeta("¡Ya sabes lo principal!")
        tocar(app.buttons["Terminar"])
        XCTAssertFalse(app.staticTexts["¡Ya sabes lo principal!"].waitForExistence(timeout: 2))
    }
}
