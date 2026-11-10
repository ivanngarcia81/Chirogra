import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Banca del iPhone (canvas `Banca`): las cuentas de dinero con su saldo en libros y lo que les falta («N por
/// revisar», «Conciliada al…»); cada una abre su libro mayor. Debajo, Conciliar, Reglas, los movimientos ya revisados e
/// «Importar extracto», y la bandeja «Por revisar» con ✓ para aceptar lo que propone la app (banca 1.2).
struct BankingView: View {
    @Environment(\.modelContext) private var modelContext
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery private var journalLines: [JournalLine]
    @CompanyQuery(filter: #Predicate<BankTransaction> { $0.statusRaw == "toReview" },
                  sort: [SortDescriptor(\BankTransaction.date, order: .reverse), SortDescriptor(\BankTransaction.importedAt)])
    private var pending: [BankTransaction]
    @CompanyQuery(sort: \Reconciliation.statementDate, order: .reverse) private var reconciliations: [Reconciliation]
    @CompanyQuery(filter: #Predicate<BankRule> { $0.isActive }) private var rules: [BankRule]
    @CompanyQuery private var invoices: [Invoice]
    @CompanyQuery private var bills: [Bill]
    @State private var addingAccount = false
    @State private var importing: BankImportRequest?
    @State private var reviewing: BankTransaction?
    @State private var errorMessage: String?
    @State private var qaReconcile: Account?
    @State private var qaInbox = false
    @State private var qaRules = false

    var body: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let shown = ledger.moneyAccounts.filter { $0.subtype == .bank || $0.subtype == .creditCard || ledger.balance(of: $0) != 0 }
        let context = BankInboxContext(books: Bookkeeper(context: modelContext), accounts: accounts, invoices: invoices, bills: bills)
        // En la fila del iPhone, la cuenta corta («••4821»): el nombre completo no cabía junto a la propuesta.
        let names = Dictionary(accounts.map { ($0.id, $0.last4.isEmpty ? $0.name : "••\($0.last4)") }, uniquingKeysWith: { first, _ in first })
        List {
            // Con movimientos por revisar, la bandeja va arriba, antes que las cuentas (decisión del usuario, 8-nov).
            if !pending.isEmpty { inboxSection(context: context, names: names) }
            Section {
                if shown.isEmpty {
                    EmptyStateView(guide: .banking) { addingAccount = true }
                }
                ForEach(shown) { account in
                    NavigationLink { LedgerView(account: account) } label: {
                        accountRow(account, balance: ledger.cashBalance(of: account))
                    }
                }
            } header: {
                HStack(spacing: 0) {
                    SectionLabel(text: String(localized: "Cuentas · saldo en libros"))
                    TermHelp(.bookBalance)
                }
            } footer: {
                if !shown.isEmpty {
                    Text("Cuánto dinero tiene cada cuenta según lo que registras. Toca una para ver sus movimientos.")
                }
            }

            Section {
                NavigationLink { ReconciliationHubView() } label: {
                    shortcut("Conciliar", systemImage: "checklist", color: Palette.teal, value: nil)
                }
                NavigationLink { BankRulesView() } label: {
                    shortcut("Reglas", systemImage: "bolt", color: Palette.purple, value: String(localized: "\(rules.count) activas"))
                }
                NavigationLink { BankInboxScreen(initialFilter: .reviewed) } label: {
                    shortcut("Movimientos revisados", systemImage: "tray.full", color: Palette.gray, value: nil)
                }
                Button { importing = BankImportRequest(file: nil) } label: {
                    shortcut("Importar extracto", systemImage: "square.and.arrow.down", color: Palette.blue, value: nil)
                }
                .buttonStyle(.plain)
            }

            // Sin pendientes, la bandeja (vacía) va al final.
            if pending.isEmpty { inboxSection(context: context, names: names) }
        }
        .groupedList()
        .screenBackground()
        .navigationTitle("Banca")
        .navigationSubtitle(String(localized: "\(shown.count) cuentas · \(Date.now.monthYear)"))
        .headerTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { importing = BankImportRequest(file: nil) } label: { Image(systemName: "square.and.arrow.down") }
                    .accessibilityLabel("Importar CSV u OFX")
                    .headerButton()
            }
        }
        .sheet(isPresented: $addingAccount) { NavigationStack { AccountEditorView(newSubtype: .bank) }.editorSheetSizing() }
        .sheet(item: $importing) { request in NavigationStack { BankImportView(initialFile: request.file) }.editorSheetSizing() }
        .sheet(item: $reviewing) { BankReviewSheet(start: $0).editorSheetSizing() }
        .navigationDestination(item: $qaReconcile) { ReconciliationView(account: $0) }
        .stableDestination(isPresented: $qaInbox) { BankInboxScreen() }
        // Panel de clientes: «Banco» (bandeja) y «Conciliación» de una cuenta.
        .onClientRoute({ route in
            if route == .bankInbox { return true }
            if case .reconcile = route { return true }
            return false
        }) { route in
            if case .reconcile(let id) = route {
                qaReconcile = accounts.first { $0.id == id && ($0.subtype == .bank || $0.subtype == .creditCard) }
            } else {
                qaInbox = true
            }
        }
        .stableDestination(isPresented: $qaRules) { BankRulesView() }
        .alert("No se pudo completar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        #if DEBUG
        .task {
            try? await Task.sleep(for: .seconds(1))
            if let file = QABanking.importFile { importing = BankImportRequest(file: file); return }
            if let index = QABanking.reviewIndex, pending.indices.contains(index) { reviewing = pending[index] }
            let bankAccounts = shown.filter { $0.subtype == .bank || $0.subtype == .creditCard }
            if let index = QABanking.reconcileIndex, bankAccounts.indices.contains(index) { qaReconcile = bankAccounts[index] }
            if QABanking.opensInbox { qaInbox = true }
            if QABanking.opensRules { qaRules = true }
            if UserDefaults.standard.bool(forKey: "qa.aceptarSugeridas") {
                let context = BankInboxContext(books: Bookkeeper(context: modelContext), accounts: accounts, invoices: invoices, bills: bills)
                _ = BankReview.acceptAll(pending, context: context)
            }
        }
        #endif
    }

    private func inboxSection(context: BankInboxContext, names: [UUID: String]) -> some View {
        BankInboxSection(transactions: pending, context: context, accountNames: names,
                         review: { reviewing = $0 }, importStatement: { importing = BankImportRequest(file: nil) },
                         report: { errorMessage = $0 })
    }

    /// Fila de una cuenta (canvas `Banca`): icono de color, nombre y, debajo, «N por revisar» (naranja), «Conciliada al…»
    /// (verde) o el código; el saldo en libros a la derecha.
    private func accountRow(_ account: Account, balance: Int64) -> some View {
        let count = pending.filter { $0.accountID == account.id }.count
        let status = ReconciliationText.status(of: account, reconciliations: reconciliations)
        let subtitle: (String, Color) = count > 0 ? (String(localized: "\(count) por revisar"), Palette.warning)
            : reconciliations.contains(where: { $0.accountID == account.id }) ? (status.text, status.color)
            : (String(localized: "Saldo en libros · \(account.code)"), Palette.ink2)
        return HStack(spacing: 12) {
            IconTile(systemImage: account.bankSymbol, foreground: account.bankColor)
            VStack(alignment: .leading, spacing: 1) {
                // Hasta dos líneas: en el iPhone «Cuenta corriente ••4821» se cortaba en «••4…» (3-nov).
                Text(account.maskedName).foregroundStyle(Palette.ink).lineLimit(2)
                Text(subtitle.0).font(.footnote).foregroundStyle(subtitle.1).lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Text(balance.money).monospacedDigit().foregroundStyle(Palette.ink).fixedSize()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func shortcut(_ title: LocalizedStringKey, systemImage: String, color: Color, value: String?) -> some View {
        HStack(spacing: 12) {
            IconTile(systemImage: systemImage, foreground: color)
            Text(title).foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            if let value { Text(verbatim: value).foregroundStyle(Palette.ink2) }
        }
        .frame(minHeight: Metrics.target)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension Account {
    /// Icono de una cuenta de dinero (canvas: banco en azul, ahorro en verde, tarjeta en índigo, efectivo en verde).
    var bankSymbol: String {
        switch subtype {
        case .creditCard: "creditcard"
        case .cash: "banknote"
        default: "building.columns"
        }
    }

    var bankColor: Color {
        switch subtype {
        case .creditCard: Palette.creditCard
        case .cash: Palette.green
        default:
            ["ahorro", "saving"].contains { name.lowercased().contains($0) } ? Palette.green : Palette.bankAccount
        }
    }
}

/// Movimientos del mes de una cuenta de dinero (canvas `BancaCuentas`, Mac, y `iPadBancaCuentas`): la cuenta con su
/// saldo en grande y la tabla del mes (saldo inicial, retiro, depósito y saldo acumulado), con el mes anterior y el
/// siguiente. Es el detalle de la cuenta elegida en Banca cuando la columna es ancha.
struct AccountMovementsView: View {
    let account: Account
    @State private var monthOffset = 0
    @CompanyQuery private var journalLines: [JournalLine]
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @ScaledMetric(relativeTo: .subheadline) private var amountWidth: CGFloat = 104
    @ScaledMetric(relativeTo: .subheadline) private var dateWidth: CGFloat = 58

    /// Movimientos del mes: el saldo sigue lo que ve el usuario (una tarjeta de crédito en negativo, lo que se debe).
    var body: some View {
        let month = DateInterval.month(containing: .now, offset: monthOffset)
        let end = month.end.addingTimeInterval(-1)
        let ledger = LedgerView.ledger(for: account, from: month.start, to: end)
        let sign: Int64 = account.subtype == .creditCard ? -1 : 1
        let lines = Dictionary((account.lines ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let balance = Ledger(accounts: accounts, lines: journalLines).cashBalance(of: account)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.maskedName).font(.subheadline).foregroundStyle(Palette.ink2)
                Text(balance.money).font(.amount(40)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
                Text("Saldo en libros · \(account.code)").font(.subheadline).foregroundStyle(Palette.ink2)
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack { header; Spacer(minLength: 8); monthStepper(month) }
                    VStack(alignment: .leading, spacing: 4) { header; monthStepper(month) }
                }
                TableCard {
                    Text("Fecha").frame(width: dateWidth, alignment: .leading)
                    Text("Descripción").frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                    Text("Categoría o cuenta").frame(minWidth: 90, maxWidth: 190, alignment: .leading)
                    Text("Retiro").frame(width: amountWidth, alignment: .trailing)
                    Text("Depósito").frame(width: amountWidth, alignment: .trailing)
                    Text("Saldo").frame(width: amountWidth, alignment: .trailing)
                } rows: {
                    TableRow {
                        Text(month.start.dayMonth).foregroundStyle(Palette.ink2).frame(width: dateWidth, alignment: .leading)
                        Text("Saldo inicial").frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(minWidth: 90, maxWidth: 190, maxHeight: 1)
                        Color.clear.frame(width: amountWidth, height: 1)
                        Color.clear.frame(width: amountWidth, height: 1)
                        Text((sign * ledger.openingBalance).money).frame(width: amountWidth, alignment: .trailing)
                    }
                    .fontWeight(.semibold)
                    ForEach(Array(ledger.rows.enumerated()), id: \.element.id) { index, row in
                        TableRow {
                            Text(row.movement.date.dayMonth).foregroundStyle(Palette.ink2).frame(width: dateWidth, alignment: .leading)
                            Text(row.movement.memo.isEmpty ? String(localized: "Asiento") : row.movement.memo)
                                .lineLimit(1).frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                            Text(counterpart(of: lines[row.movement.id])).foregroundStyle(Palette.ink2).lineLimit(1)
                                .frame(minWidth: 90, maxWidth: 190, alignment: .leading)
                            Text(row.movement.credit > 0 ? row.movement.credit.money : "").frame(width: amountWidth, alignment: .trailing)
                            Text(row.movement.debit > 0 ? row.movement.debit.money : "").foregroundStyle(Palette.positive)
                                .frame(width: amountWidth, alignment: .trailing)
                            Text((sign * row.balance).money).frame(width: amountWidth, alignment: .trailing)
                        }
                        .zebra(index + 1)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(LedgerView.spokenMovement(row))
                    }
                    if ledger.rows.isEmpty {
                        Text("Sin movimientos este mes").font(.subheadline).foregroundStyle(Palette.ink2)
                            .frame(maxWidth: .infinity).padding(.vertical, 32)
                    }
                }
                Text("\(String(localized: "\(ledger.rows.count) movimientos")) · \(String(localized: "Saldo al \(end.dayMonth) \((sign * ledger.closingBalance).money)"))")
                    .font(.footnote).foregroundStyle(Palette.ink2)
                    .padding(.horizontal, 2)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Movimientos").font(.cardTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            NavigationLink("Libro mayor") { LedgerView(account: account) }.font(.subheadline).tint(Palette.brand)
        }
    }

    private func monthStepper(_ month: DateInterval) -> some View {
        HStack(spacing: 4) {
            Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: Metrics.target, height: Metrics.target) }
                .accessibilityLabel("Mes anterior")
            Text(month.start.monthYear)
                .font(.subheadline).foregroundStyle(Palette.ink2).monospacedDigit()
            Button { monthOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: Metrics.target, height: Metrics.target) }
                .disabled(monthOffset >= 0)
                .accessibilityLabel("Mes siguiente")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.brand)
    }

    /// La otra cuenta del asiento («Varias» si hay más de una).
    private func counterpart(of line: JournalLine?) -> String {
        guard let line, let entry = line.entry else { return "—" }
        let others = Set((entry.lines ?? []).compactMap(\.account).filter { $0.id != line.account?.id }.map(\.maskedName))
        return others.count == 1 ? others.first! : others.isEmpty ? "—" : String(localized: "Varias")
    }
}
