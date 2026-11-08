#if os(macOS)
import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Mac: Banca como tabla + inspector (canvas `BancaCuentas`). Arriba, las cuentas de dinero como tarjetas que se eligen
/// (icono de color, saldo en libros de 24 y código); debajo, los movimientos del mes de la cuenta elegida en la tabla
/// Fecha · Descripción · Categoría o cuenta · Retiro · Depósito · Saldo, con el mes anterior y el siguiente. El
/// inspector muestra el movimiento elegido (Detalles, Conciliación) con «Abrir asiento» y «Ver en libro mayor».
/// Importar movimientos, la bandeja «Por revisar» y la conciliación son de la fase 2: «Importar y conciliar ·
/// Próximamente» en la barra, desactivado.
struct BankingTablePage: View {
    static let isReady = true
    @Binding var selection: UUID?
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery private var journalLines: [JournalLine]
    /// Cuenta elegida en las tarjetas; sin elegir, la primera (o la de `-qa.cuenta N` en Debug).
    @State private var accountID: UUID?
    @State private var monthOffset = BankingTablePage.initialMonthOffset
    @State private var query = ""
    @State private var choosingMovement = false
    @State private var adding: NewMovement?
    @State private var openedEntry: JournalEntry?
    @State private var openedLedger: Account?

    var body: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let shown = ledger.moneyAccounts.filter { $0.subtype == .bank || $0.subtype == .creditCard || ledger.balance(of: $0) != 0 }
        let account = shown.first { $0.id == accountID } ?? shown[safe: Self.initialAccountIndex] ?? shown.first
        let month = DateInterval.month(containing: .now, offset: monthOffset)
        let statement = account.map { BankStatement(account: $0, month: month) }
        let rows = statement?.rows ?? []
        let filtered = filter(rows)
        MacTablePage(
            title: String(localized: "Banca"),
            subtitle: String(localized: "\(shown.count) cuentas · \(month.start.monthYear)"),
            rows: filtered, footer: footer(statement, filtered: filtered.count),
            query: $query, searchPrompt: Text("Descripción, cuenta o monto"),
            selection: $selection,
            sortOrder: [KeyPathComparator(\BankMovement.order)],
            addTitle: String(localized: "Nuevo movimiento"), onAdd: { choosingMovement = true },
            onOpen: { openedEntry = $0.entry },
            empty: empty(shown: shown, rows: rows, month: month),
            inspectorTitle: { _ in String(localized: "Movimiento") },
            inspectorPlaceholder: String(localized: "Selecciona un movimiento para ver sus detalles.")
        ) {
            TableColumn("Fecha", value: \.order) { movement in
                MacCellText(text: movement.date.dayMonth)
            }
            .width(min: 50, ideal: 58, max: 90)
            TableColumn("Descripción", value: \.memo) { movement in
                Text(movement.memo).lineLimit(1)
            }
            .width(min: 110, ideal: 160)
            TableColumn("Categoría o cuenta", value: \.counterpart) { movement in
                MacCellText(text: movement.counterpart)
            }
            .width(min: 90, ideal: 120, max: 220)
            TableColumn("Retiro", value: \.withdrawal) { movement in
                Text(movement.withdrawal > 0 ? movement.withdrawal.money : "").monospacedDigit()
            }
            .width(min: 70, ideal: 84, max: 130)
            .alignment(.trailing)
            TableColumn("Depósito", value: \.deposit) { movement in
                MacCellText(text: movement.deposit > 0 ? movement.deposit.money : "", color: Palette.positive).monospacedDigit()
            }
            .width(min: 70, ideal: 84, max: 130)
            .alignment(.trailing)
            TableColumn("Saldo", value: \.balance) { movement in
                Text(movement.balance.money).monospacedDigit().fontWeight(.semibold)
            }
            .width(min: 76, ideal: 92, max: 140)
            .alignment(.trailing)
        } filter: {
            if !shown.isEmpty {
                HStack(spacing: 4) {
                    Text("Saldo en libros de cada cuenta").font(.subheadline).foregroundStyle(Palette.ink2)
                    TermHelp(.bookBalance)
                }
                .padding(.horizontal, 2)
                .padding(.bottom, -4)
                BankAccountCards(accounts: shown, balance: { ledger.cashBalance(of: $0) }, selection: account?.id) { picked in
                    accountID = picked
                    selection = nil
                }
                if let account {
                    MovementsHeader(account: account, month: month, monthOffset: $monthOffset)
                }
            }
        } inspector: { movement in
            BankMovementInspector(movement: movement, account: account)
        } actions: { movement in
            if let entry = movement.entry {
                Button("Abrir asiento") { openedEntry = entry }.buttonStyle(.primary)
            }
            if let account {
                Button("Ver en libro mayor") { openedLedger = account }.buttonStyle(.secondary)
            }
        }
        .toolbar {
            // Fase 2 (DISEÑO §7.4): se anuncia, desactivado, como en el canvas.
            ToolbarItem(placement: .primaryAction) {
                Button {} label: {
                    Label("Importar y conciliar · Próximamente", systemImage: "square.and.arrow.down").labelStyle(.titleAndIcon)
                }
                .disabled(true)
                .help("Disponible en una próxima versión")
                .accessibilityLabel("Importar y conciliar, disponible en una próxima versión")
            }
        }
        .onChange(of: monthOffset) { selection = nil }
        .onAppear { showLatestMonthIfEmpty() }
        .onChange(of: accountID) { showLatestMonthIfEmpty() }
        .confirmationDialog("Nuevo movimiento", isPresented: $choosingMovement) {
            Button("Gasto") { adding = .expense }
            ForEach(JournalTemplate.allCases) { template in
                Button(template.title) { adding = .template(template) }
            }
            Button("Asiento a mano") { adding = .entry }
        } message: {
            Text("Los cobros de facturas se registran desde la factura.")
        }
        .sheet(item: $adding) { kind in
            NavigationStack {
                switch kind {
                case .expense: ExpenseEditorView()
                case .entry: JournalEntryEditorView()
                case .template(let template): JournalEntryEditorView(template: template)
                }
            }
            .editorSheetSizing()
        }
        .navigationDestination(item: $openedEntry) { JournalEntryDetailView(entry: $0) }
        .navigationDestination(item: $openedLedger) { LedgerView(account: $0, inDetailColumn: true) }
        #if DEBUG
        // `-qa.nuevo 1` pregunta «Nuevo movimiento»; `-qa.abrir 1` abre el asiento del movimiento elegido con `-qa.fila`.
        .task {
            try? await Task.sleep(for: .seconds(1))
            if UserDefaults.standard.bool(forKey: "qa.nuevo") { choosingMovement = true }
            guard UserDefaults.standard.bool(forKey: "qa.abrir"), let id = selection,
                  let line = journalLines.first(where: { $0.id == id }) else { return }
            openedEntry = line.entry
        }
        #endif
    }

    private func filter(_ rows: [BankMovement]) -> [BankMovement] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return rows }
        return rows.filter {
            $0.memo.localizedStandardContains(text) || $0.counterpart.localizedStandardContains(text)
                || $0.withdrawal.money.contains(text) || $0.deposit.money.contains(text)
        }
    }

    /// «11 movimientos · Saldo inicial $38,940.62 · Saldo al 31 oct $42,130.18» (canvas: la fila «Saldo inicial» y el pie).
    private func footer(_ statement: BankStatement?, filtered: Int) -> String {
        guard let statement else { return String(localized: "Sin cuentas de banco") }
        let total = statement.rows.count
        let count = filtered == total ? String(localized: "\(total) movimientos")
            : String(localized: "\(filtered) de \(total) movimientos")
        let end = statement.month.end.addingTimeInterval(-1)
        return [count, String(localized: "Saldo inicial \(statement.opening.money)"),
                String(localized: "Saldo al \(end.dayMonth) \(statement.closing.money)")].joined(separator: " · ")
    }

    private func empty(shown: [Account], rows: [BankMovement], month: DateInterval) -> MacTableEmpty {
        if shown.isEmpty {
            return MacTableEmpty(guide: .banking, action: nil)
        }
        if journalLines.isEmpty {
            // Libros nuevos: qué se verá aquí y, para empezar, el dinero que pone el dueño (plantilla de asiento).
            return MacTableEmpty(systemImage: "building.columns", title: String(localized: "Aún no hay movimientos"),
                                 message: String(localized: "Aquí verás cada cobro, gasto y pago de esta cuenta, con su saldo. Si pusiste dinero de tu bolsillo para empezar, regístralo aquí."),
                                 actionTitle: JournalTemplate.ownerContribution.title,
                                 action: { adding = .template(.ownerContribution) }, isGuide: true)
        }
        if rows.isEmpty {
            return MacTableEmpty(systemImage: "calendar", title: String(localized: "Sin movimientos en \(month.start.monthYear)"),
                                 message: String(localized: "Los cobros, gastos y asientos que usan esta cuenta aparecen aquí."),
                                 actionTitle: String(localized: "Mes anterior"), action: { monthOffset -= 1 })
        }
        return MacTableEmpty(title: String(localized: "Sin resultados"),
                             message: String(localized: "Ningún movimiento coincide con la búsqueda."),
                             actionTitle: String(localized: "Quitar búsqueda"), action: { query = "" })
    }

    /// `-qa.cuenta N` elige la cuenta N de las tarjetas y `-qa.mes N` el mes de hace N meses (solo Debug).
    private static var initialAccountIndex: Int {
        #if DEBUG
        UserDefaults.standard.integer(forKey: "qa.cuenta")
        #else
        0
        #endif
    }

    /// La cuenta de las tarjetas que se ve (la misma regla que `body`).
    private var visibleAccount: Account? {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let shown = ledger.moneyAccounts.filter { $0.subtype == .bank || $0.subtype == .creditCard || ledger.balance(of: $0) != 0 }
        return shown.first { $0.id == accountID } ?? shown[safe: Self.initialAccountIndex] ?? shown.first
    }

    /// Decisión del usuario (2-nov): si la cuenta no tiene movimientos en el mes que se ve (p. ej. a primeros de mes),
    /// se pasa al último mes en que sí los tiene, en lugar de una tabla vacía. Al abrir y al cambiar de cuenta.
    private func showLatestMonthIfEmpty() {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "qa.mes") != nil { return }
        #endif
        guard let account = visibleAccount else { return }
        let month = DateInterval.month(containing: .now, offset: monthOffset)
        let dates = (account.lines ?? []).compactMap { $0.entry?.date }
        guard !dates.contains(where: { month.contains($0) && $0 < month.end }), let latest = dates.max() else { return }
        let months = Calendar.current.dateComponents([.month], from: DateInterval.month(containing: latest).start,
                                                     to: DateInterval.month(containing: .now).start).month ?? 0
        monthOffset = -max(months, 0)
    }

    private static var initialMonthOffset: Int {
        #if DEBUG
        -abs(UserDefaults.standard.integer(forKey: "qa.mes"))
        #else
        0
        #endif
    }
}

// MARK: - Datos

/// Movimiento de una cuenta de dinero en el mes: una línea de asiento contabilizada, con el saldo acumulado como lo ve
/// el usuario (una tarjeta de crédito en negativo, lo que se debe). Claves de orden `nonisolated` para la tabla.
private nonisolated struct BankMovement: Identifiable {
    /// La línea del asiento.
    let id: UUID
    /// Posición en el mes (orden de fecha); ordena la columna «Fecha».
    let order: Int
    let date: Date
    let memo: String
    /// La otra cuenta del asiento («Varias» si hay más de una).
    let counterpart: String
    let withdrawal: Int64
    let deposit: Int64
    let balance: Int64
    let entry: JournalEntry?
}

/// Movimientos del mes de una cuenta (lo mismo que `AccountMovementsView`): saldo inicial, filas y saldo final.
private struct BankStatement {
    let month: DateInterval
    let opening: Int64
    let closing: Int64
    let rows: [BankMovement]

    init(account: Account, month: DateInterval) {
        let ledger = LedgerView.ledger(for: account, from: month.start, to: month.end.addingTimeInterval(-1))
        let sign: Int64 = account.subtype == .creditCard ? -1 : 1
        let lines = Dictionary((account.lines ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.month = month
        opening = sign * ledger.openingBalance
        closing = sign * ledger.closingBalance
        rows = ledger.rows.enumerated().map { index, row in
            let line = lines[row.movement.id]
            return BankMovement(id: row.movement.id, order: index, date: row.movement.date,
                                memo: row.movement.memo.isEmpty ? String(localized: "Asiento") : row.movement.memo,
                                counterpart: Self.counterpart(of: line),
                                withdrawal: row.movement.credit, deposit: row.movement.debit,
                                balance: sign * row.balance, entry: line?.entry)
        }
    }

    private static func counterpart(of line: JournalLine?) -> String {
        guard let line, let entry = line.entry else { return "—" }
        let others = Set((entry.lines ?? []).compactMap(\.account).filter { $0.id != line.account?.id }.map(\.maskedName))
        return others.count == 1 ? others.first! : others.isEmpty ? "—" : String(localized: "Varias")
    }
}

// MARK: - Piezas

/// Tarjetas de las cuentas (canvas `BancaCuentas`): icono de color de 22, nombre, saldo de 24 y «Saldo en libros ·
/// código»; la elegida con el borde de Tinta. Funcionan como un grupo de opciones (una sola elegida).
private struct BankAccountCards: View {
    let accounts: [Account]
    let balance: (Account) -> Int64
    let selection: UUID?
    let pick: (UUID) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            ForEach(accounts) { account in
                card(account, isSelected: account.id == selection)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cuentas")
    }

    private func card(_ account: Account, isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        let amount = balance(account).money
        return Button { pick(account.id) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: account.bankSymbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(account.bankColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(account.maskedName).font(.body.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                }
                Text(amount).font(.amount(24)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.top, 4)
                Text("Saldo en libros · \(account.code)").font(.subheadline).foregroundStyle(Palette.ink2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
            .background(Palette.surface, in: shape)
            .overlay(shape.strokeBorder(isSelected ? Palette.brandFill : Palette.separator, lineWidth: isSelected ? 2 : 0.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(account.maskedName), \(amount)"))
        .accessibilityHint(String(localized: "Muestra sus movimientos"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// «Movimientos · Corriente ••4821» con el mes y sus flechas (canvas: título de 13 bold y «Octubre 2026» a la derecha).
private struct MovementsHeader: View {
    let account: Account
    let month: DateInterval
    @Binding var monthOffset: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Movimientos · \(account.maskedName)").font(.headline).foregroundStyle(Palette.ink).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: Metrics.target, height: Metrics.target) }
                    .accessibilityLabel("Mes anterior")
                Text(month.start.monthYear).font(.subheadline).foregroundStyle(Palette.ink2).monospacedDigit()
                Button { monthOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: Metrics.target, height: Metrics.target) }
                    .disabled(monthOffset >= 0)
                    .accessibilityLabel("Mes siguiente")
            }
            .buttonStyle(.borderless)
            .tint(Palette.brand)
        }
        .padding(.top, 4)
        .padding(.horizontal, 2)
    }
}

/// Inspector del movimiento (canvas `BancaCuentas`): importe de 24 (verde si entra), descripción y «Depósito · fecha»;
/// Detalles (Fecha, Cuenta, Categoría o cuenta, importe, Saldo después, Origen) y Conciliación (todo se registra a
/// mano en el MVP; la importación bancaria es de la fase 2).
private struct BankMovementInspector: View {
    let movement: BankMovement
    let account: Account?

    var body: some View {
        let isDeposit = movement.deposit > 0
        let amount = max(movement.deposit, movement.withdrawal)
        let kind = isDeposit ? String(localized: "Depósito") : String(localized: "Retiro")
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: isDeposit ? "+\(amount.money)" : "−\(amount.money)")
                .font(.amount(24)).foregroundStyle(isDeposit ? Palette.positive : Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(movement.memo).font(.body).foregroundStyle(Palette.ink)
            Text(verbatim: "\(kind) · \(movement.date.shortDate)").font(.subheadline).foregroundStyle(Palette.ink2)
        }
        .accessibilityElement(children: .combine)
        MacInspectorSection(title: String(localized: "Detalles")) {
            MacInspectorRow(String(localized: "Fecha"), value: movement.date.shortDate)
            if let account { MacInspectorRow(String(localized: "Cuenta"), value: account.maskedName) }
            MacInspectorRow(String(localized: "Categoría o cuenta"), value: movement.counterpart)
            MacInspectorRow(kind, value: amount.money)
            MacInspectorRow(String(localized: "Saldo después"), value: movement.balance.money, bold: true)
            if let entry = movement.entry {
                MacInspectorRow(String(localized: "Origen"), value: "\(entry.source.title) · #\(entry.number)")
            }
        }
        MacInspectorSection(title: String(localized: "Conciliación")) {
            MacInspectorRow(label: String(localized: "Estado")) {
                StatusChip(text: String(localized: "Registrado a mano"), foreground: Palette.ink2, background: .clear,
                           compact: true, dot: Palette.gray)
            }
            MacInspectorRow(String(localized: "Importación bancaria"), value: String(localized: "Próximamente"), color: Palette.ink2)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
#endif
