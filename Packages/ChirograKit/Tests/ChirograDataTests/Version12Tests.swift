import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// 1.2: asientos de ajuste del contador, bitácora de cambios (aparato y antes/después) y banca (dividir y motivo al
/// excluir). docs/DATOS-V5.md.
@MainActor
@Suite("1.2: ajustes del contador, bitácora y banca", .serialized)
struct Version12Tests {
    let container: ModelContainer
    let books: Bookkeeper
    let today = Calendar.current.startOfDay(for: Date())

    init() throws {
        Bookkeeper.deviceNameOverride = "iPhone de prueba"
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext)
        _ = try books.setUpCompany(legalName: "Doce LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
    }

    var context: ModelContext { container.mainContext }

    func account(_ code: String) throws -> Account {
        try #require(try books.accounts().first { $0.code == code })
    }

    func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: today)! }

    func transaction(_ amount: Int64, _ details: String, into bank: Account) throws -> BankTransaction {
        let result = try books.importStatementLines([BankStatementLine(date: day(-2), amount: amount, details: details, externalID: details)],
                                                    source: .ofx, into: bank)
        return try #require(result.imported.first)
    }

    func balance(_ account: Account) throws -> Int64 {
        try books.ledgerLines().filter { $0.accountID == account.id }.reduce(0) { $0 + $1.debit - $1.credit }
    }

    // MARK: Ajustes del contador

    @Test("Un ajuste del contador es un asiento manual con su propio origen y lo dice la bitácora")
    func accountantAdjustment() throws {
        let rent = try account("6400")
        let prepaid = try account("1300")
        let entry = try books.post(JournalEntryDraft(date: day(-1), memo: "Renta pagada por adelantado", source: .accountantAdjustment,
                                                     lines: [.debit(prepaid.id, 120_000), .credit(rent.id, 120_000)]))
        #expect(entry.source == .accountantAdjustment)
        #expect(entry.source.isManual && EntrySource.manual.isManual && !EntrySource.invoice.isManual)
        let event = try #require(try books.auditLog(entityID: entry.id).first)
        #expect(event.summary.hasPrefix("Ajuste del contador \(entry.number)"))
        #expect(event.device == "iPhone de prueba")
        // Una versión anterior que no conoce el origen lo lee como manual.
        #expect(EntrySource(rawValue: "algoNuevo") == nil)
        #expect(entry.sourceRaw == "accountantAdjustment")
        // Se revierte como cualquier asiento manual.
        let reversal = try books.reverse(entry)
        #expect(reversal.reversesEntryID == entry.id)
        #expect(try balance(rent) == 0)
    }

    // MARK: Bitácora

    @Test("Cada cambio lleva el aparato; la bitácora va de la más reciente a la más vieja y se filtra por cosa")
    func auditLogOrderAndDevice() throws {
        let log = try books.auditLog()
        #expect(!log.isEmpty)
        #expect(log.allSatisfy { $0.device == "iPhone de prueba" })
        #expect(zip(log, log.dropFirst()).allSatisfy { $0.date >= $1.date })
        let company = try #require(try books.company())
        #expect(try books.auditLog(entityID: company.id).allSatisfy { $0.entityID == company.id })
        #expect(try books.auditLog(limit: 1).map(\.id) == [log[0].id])
    }

    @Test("La bitácora de una empresa no enseña la de otra")
    func auditLogIsPerCompany() throws {
        let saved = Bookkeeper.companyLimit
        Bookkeeper.companyLimit = CompanyLimits.accountant
        defer { Bookkeeper.companyLimit = saved }
        let firstID = try #require(try books.company()?.id)
        let other = try books.forNewCompany()
        let secondID = try other.setUpCompany(legalName: "Otra LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US")).id
        let mine = try books.forCompany(firstID).auditLog().map(\.id)
        let theirs = try books.forCompany(secondID).auditLog().map(\.id)
        #expect(!mine.isEmpty && !theirs.isEmpty)
        #expect(Set(mine).isDisjoint(with: theirs))
    }

    @Test("Editar un gasto anota el antes y el después de cada campo que cambió")
    func expenseEditDetails() throws {
        let checking = try account("1010")
        let supplies = try account("6500")
        let office = try account("6350")
        let expense = try books.createExpense(ExpenseInput(date: day(-3), payee: "Home Depot", paymentAccountID: checking.id, method: .card,
                                                           lines: [.init(details: "Tornillos", amount: 4_500, accountID: supplies.id)]))
        var input = ExpenseInput(expense)
        input.payee = "The Home Depot"
        input.lines = [.init(details: "Tornillos", amount: 5_000, accountID: office.id)]
        try books.updateExpense(expense, with: input)
        let event = try #require(try books.auditLog(entityID: expense.id).first { $0.action == "edit" })
        #expect(event.detailLines.contains("Beneficiario: Home Depot → The Home Depot"))
        #expect(event.detailLines.contains { $0.hasPrefix("Total: $45.00 → $50.00") })
        #expect(event.detailLines.contains { $0.hasPrefix("Línea 1: 6500 · Suministros · $45.00") && $0.contains("6350 · Gastos de oficina · $50.00") })
        #expect(!event.detailLines.contains { $0.hasPrefix("Fecha") })
        // Sin cambios no hay detalle (y en uno sin asiento, ni evento).
        let before = try books.auditLog(entityID: expense.id).count
        try books.updateExpense(expense, with: ExpenseInput(expense))
        #expect(try books.auditLog(entityID: expense.id).first { $0.action == "edit" }?.changeDetails.isEmpty == true
                || books.auditLog(entityID: expense.id).count == before)
    }

    @Test("Las pantallas anotan altas y ediciones de clientes; una edición sin cambios no se anota")
    func logSaveCustomer() throws {
        let customer = Customer(name: "Ana Ríos")
        books.insert(customer)
        books.logSave(.customer, id: customer.id, name: customer.name, before: nil, after: AuditSnapshot(customer))
        try context.save()
        let before = AuditSnapshot(customer)
        customer.email = "ana@rios.com"
        customer.paymentTermsDays = 15
        books.logSave(.customer, id: customer.id, name: customer.name, before: before, after: AuditSnapshot(customer))
        books.logSave(.customer, id: customer.id, name: customer.name, before: AuditSnapshot(customer), after: AuditSnapshot(customer))
        try context.save()
        let events = try books.auditLog(entityID: customer.id)
        #expect(events.map(\.action).sorted() == ["create", "update"])
        let created = try #require(events.first { $0.action == "create" })
        #expect(created.summary == "Cliente nuevo: Ana Ríos")
        #expect(created.detailLines.contains("Nombre: Ana Ríos"))
        let edited = try #require(events.first { $0.action == "update" })
        #expect(edited.detailLines == ["Correo: — → ana@rios.com", "Plazo de pago: 30 días → 15 días"])
        #expect(edited.subject == .customer)
    }

    @Test("Borrar un borrador de factura o un estimado deja lo que tenían en la bitácora")
    func deletionsAreLogged() throws {
        let customer = Customer(name: "Café Aurora")
        books.insert(customer)
        let income = try account("4000")
        let invoice = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: day(0), dueDate: day(15),
                                                            lines: [.init(details: "Diseño", unitPrice: 50_000, isTaxable: false, incomeAccountID: income.id)]))
        let invoiceID = invoice.id
        try books.deleteDraft(invoice)
        #expect(try context.fetch(FetchDescriptor<Invoice>()).isEmpty)
        let event = try #require(try books.auditLog(entityID: invoiceID).first { $0.isDeletion })
        #expect(event.detailLines.contains("Cliente: Café Aurora"))
        #expect(event.detailLines.contains("Total: $500.00"))

        let issued = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: day(0), dueDate: day(15),
                                                           lines: [.init(details: "Logo", unitPrice: 20_000, isTaxable: false, incomeAccountID: income.id)]))
        _ = try books.issue(issued)
        #expect(throws: BookkeepingError.self) { try books.deleteDraft(issued) }
        try books.void(issued)
        #expect(try books.auditLog(entityID: issued.id).contains { $0.action == "void" })

        let estimate = try books.saveEstimate(EstimateInput(customer: customer, issueDate: day(0), expirationDate: day(30),
                                                            lines: [.init(details: "Mural", unitPrice: 90_000, isTaxable: false, incomeAccountID: income.id)]))
        let estimateID = estimate.id
        try books.deleteEstimate(estimate)
        #expect(try books.auditLog(entityID: estimateID).contains { $0.isDeletion && $0.detailLines.contains("Total: $900.00") })
    }

    // MARK: Banca

    @Test("Excluir guarda el motivo en el movimiento y en la bitácora; devolverlo a la bandeja lo quita")
    func ignoreWithReason() throws {
        let checking = try account("1010")
        let movement = try transaction(-1_840, "UBER *TRIP", into: checking)
        try books.ignore(movement, reason: "  Duplicado  ")
        #expect(movement.status == .ignored)
        #expect(movement.ignoreReason == "Duplicado")
        let event = try #require(try books.auditLog(entityID: movement.id).first { $0.action == "ignore" })
        #expect(event.detailLines.contains("Motivo: Duplicado"))
        #expect(event.detailLines.contains("Importe: -$18.40") || event.detailLines.contains("Importe: −$18.40"))
        try books.returnToInbox(movement)
        #expect(movement.status == .toReview && movement.ignoreReason.isEmpty)
        let back = try #require(try books.auditLog(entityID: movement.id).first { $0.action == "returnToInbox" })
        #expect(back.detailLines.contains("Motivo de exclusión: Duplicado"))
        // Sin motivo también se puede.
        try books.ignore(movement)
        #expect(movement.ignoreReason.isEmpty && movement.status == .ignored)
    }

    @Test("Una salida dividida crea un gasto con una línea por parte y cuadra")
    func splitOutflow() throws {
        let card = try account("2100")
        let supplies = try account("6500")
        let meals = try account("6650")
        let movement = try transaction(-12_000, "COSTCO WHOLESALE", into: card)
        let result = try books.categorize(movement, splitInto: [BankSplitPart(accountID: supplies.id, amount: 9_000, memo: "Papel"),
                                                                BankSplitPart(accountID: meals.id, amount: 3_000)])
        guard case .expense(let expense) = result else { Issue.record("no es un gasto"); return }
        #expect(expense.sortedLines.map(\.amount) == [9_000, 3_000])
        #expect(expense.sortedLines.map(\.details) == ["Papel", "COSTCO WHOLESALE"])
        #expect(expense.total == 12_000)
        #expect(movement.status == .categorized)
        #expect(movement.categoryAccountID == supplies.id)
        #expect(try balance(supplies) == 9_000 && balance(meals) == 3_000 && balance(card) == -12_000)
        #expect(try books.splitParts(of: movement).map(\.amount) == [9_000, 3_000])
        let event = try #require(try books.auditLog(entityID: movement.id).first { $0.action == "categorize" })
        #expect(event.summary.hasPrefix("Movimiento dividido en 2 cuentas"))
        #expect(event.detailLines.contains("6500 · Suministros: $90.00 · Papel"))
    }

    @Test("Una entrada dividida crea un depósito con una línea al haber por parte")
    func splitInflow() throws {
        let checking = try account("1010")
        let income = try account("4000")
        let owner = try account("3000")
        let movement = try transaction(150_000, "DEPOSIT", into: checking)
        let result = try books.categorize(movement, splitInto: [BankSplitPart(accountID: income.id, amount: 100_000),
                                                                BankSplitPart(accountID: owner.id, amount: 50_000, memo: "Aportación")])
        guard case .deposit(let entry) = result else { Issue.record("no es un depósito"); return }
        #expect(entry.source == .bankDeposit)
        #expect(entry.totalDebits == 150_000 && entry.totalCredits == 150_000)
        #expect(try balance(income) == -100_000 && balance(owner) == -50_000 && balance(checking) == 150_000)
        #expect(try books.splitParts(of: movement).map(\.accountID) == [income.id, owner.id])
        #expect(movement.matchedLineID != nil)
    }

    @Test("Dividir exige dos partes que sumen el movimiento y ninguna a una cuenta de dinero")
    func splitValidation() throws {
        let checking = try account("1010")
        let savings = try account("1020")
        let supplies = try account("6500")
        let meals = try account("6650")
        let movement = try transaction(-10_000, "AMAZON", into: checking)
        #expect(throws: BookkeepingError.self) {
            try books.categorize(movement, splitInto: [BankSplitPart(accountID: supplies.id, amount: 10_000)])
        }
        #expect(throws: BookkeepingError.self) {
            try books.categorize(movement, splitInto: [BankSplitPart(accountID: supplies.id, amount: 6_000), BankSplitPart(accountID: meals.id, amount: 3_000)])
        }
        #expect(throws: BookkeepingError.self) {
            try books.categorize(movement, splitInto: [BankSplitPart(accountID: supplies.id, amount: 6_000), BankSplitPart(accountID: savings.id, amount: 4_000)])
        }
        #expect(throws: BookkeepingError.self) {
            try books.categorize(movement, splitInto: [BankSplitPart(accountID: supplies.id, amount: 10_500), BankSplitPart(accountID: meals.id, amount: -500)])
        }
        #expect(movement.status == .toReview)
        #expect(try context.fetch(FetchDescriptor<Expense>()).isEmpty)
        // Uno sin dividir no tiene partes.
        try books.categorize(movement, as: supplies)
        #expect(try books.splitParts(of: movement).isEmpty)
    }

    @Test("La copia de seguridad conserva el aparato, el detalle y el motivo de exclusión")
    func backupKeepsNewFields() throws {
        let checking = try account("1010")
        let movement = try transaction(-500, "CAFE", into: checking)
        try books.ignore(movement, reason: "Personal")
        let data = try BackupArchive.make(from: context, appVersion: "1.2")
        let restoredContainer = try ChirograStore.makeContainer(inMemory: true)
        _ = try BackupArchive.restore(data, into: restoredContainer.mainContext, actor: "Pruebas")
        let restored = try #require(try restoredContainer.mainContext.fetch(FetchDescriptor<BankTransaction>()).first)
        #expect(restored.ignoreReason == "Personal")
        let event = try #require(try restoredContainer.mainContext.fetch(FetchDescriptor<AuditEvent>()).first { $0.action == "ignore" })
        #expect(event.device == "iPhone de prueba")
        #expect(event.detailLines.contains("Motivo: Personal"))
    }
}
