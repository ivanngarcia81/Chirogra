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
