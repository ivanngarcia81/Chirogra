import Foundation
import Testing
@testable import ChirograCore

@Suite("Validación de asientos (doble partida)")
struct JournalValidatorTests {
    let cash = UUID()
    let income = UUID()
    let expense = UUID()
    let date = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("Un asiento con débitos = créditos es válido")
    func balancedEntryIsValid() throws {
        let entry = JournalEntryDraft(date: date, lines: [.debit(cash, 125_000), .credit(income, 125_000)])
        #expect(entry.totalDebits == entry.totalCredits)
        #expect(entry.isBalanced)
        try JournalValidator().validate(entry)
    }

    @Test("Un asiento multilínea cuadrado es válido")
    func multiLineBalanced() {
        let entry = JournalEntryDraft(date: date, lines: [
            .debit(cash, 10_000), .debit(expense, 2_550),
            .credit(income, 7_550), .credit(income, 5_000),
        ])
        #expect(JournalValidator().errors(for: entry).isEmpty)
    }

    @Test("Débitos ≠ créditos se rechaza con los dos totales")
    func unbalancedIsRejected() {
        let entry = JournalEntryDraft(date: date, lines: [.debit(cash, 10_000), .credit(income, 9_999)])
        #expect(!entry.isBalanced)
        #expect(entry.difference == 1)
        #expect(throws: JournalValidationError.unbalanced(debits: 10_000, credits: 9_999)) {
            try JournalValidator().validate(entry)
        }
    }

    @Test("Hacen falta al menos dos líneas")
    func needsTwoLines() {
        let entry = JournalEntryDraft(date: date, lines: [.debit(cash, 0)])
        #expect(JournalValidator().errors(for: entry).first == .tooFewLines(count: 1))
    }

    @Test("Una línea no puede tener importe al debe y al haber")
    func bothSidesRejected() {
        let entry = JournalEntryDraft(date: date, lines: [
            JournalLineDraft(accountID: cash, debit: 500, credit: 500),
            .credit(income, 0),
        ])
        #expect(JournalValidator().errors(for: entry).contains(.bothSides(index: 0)))
    }

    @Test("Importes negativos y líneas vacías se rechazan")
    func negativeAndEmpty() {
        let entry = JournalEntryDraft(date: date, lines: [.debit(cash, -100), .credit(income, 0)])
        let errors = JournalValidator().errors(for: entry)
        #expect(errors.contains(.negativeAmount(index: 0)))
        #expect(errors.contains(.emptyLine(index: 1)))
    }

    @Test("Todas las líneas en la misma cuenta no es un asiento")
    func singleAccountRejected() {
        let entry = JournalEntryDraft(date: date, lines: [.debit(cash, 100), .credit(cash, 100)])
        #expect(JournalValidator().errors(for: entry) == [.singleAccount])
    }

    @Test("Cuentas desconocidas o archivadas se rechazan")
    func accountChecks() {
        let archived = UUID()
        let known: [UUID: AccountInfo] = [
            cash: AccountInfo(id: cash, type: .asset),
            archived: AccountInfo(id: archived, type: .income, isPostable: false),
        ]
        let validator = JournalValidator(accountLookup: { known[$0] })
        let entry = JournalEntryDraft(date: date, lines: [.debit(cash, 100), .credit(archived, 60), .credit(income, 40)])
        let errors = validator.errors(for: entry)
        #expect(errors.contains(.accountNotPostable(index: 1)))
        #expect(errors.contains(.unknownAccount(index: 2)))
    }

    @Test("No se contabiliza en un periodo cerrado")
    func lockedPeriod() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let lock = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))!
        let validator = JournalValidator(lockDate: lock, calendar: calendar)
        let onLockDay = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 15))!
        let nextDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!

        #expect(validator.errors(for: JournalEntryDraft(date: onLockDay, lines: [.debit(cash, 1), .credit(income, 1)])) == [.periodLocked(lockDate: lock)])
        #expect(validator.isValid(JournalEntryDraft(date: nextDay, lines: [.debit(cash, 1), .credit(income, 1)])))
    }

    @Test("La reversión intercambia lados y sigue cuadrada; sumada al original deja saldos en cero")
    func reversal() {
        let entry = JournalEntryDraft(date: date, memo: "Venta", lines: [.debit(cash, 700), .debit(expense, 300), .credit(income, 1_000)])
        let reversal = entry.reversal(on: date)
        #expect(reversal.isBalanced)
        #expect(reversal.source == .reversal)

        var net: [UUID: Int64] = [:]
        for line in entry.lines + reversal.lines { net[line.accountID, default: 0] += line.debit - line.credit }
        #expect(net.values.allSatisfy { $0 == 0 })
    }
}
