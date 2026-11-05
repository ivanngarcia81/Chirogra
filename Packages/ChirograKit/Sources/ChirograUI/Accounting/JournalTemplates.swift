import ChirograCore
import ChirograData
import Foundation

/// Plantillas del editor de asientos (build 4): lo que un pequeño negocio necesita registrar a mano, dicho en llano.
/// El usuario elige la plantilla, la(s) cuenta(s) de dinero, el importe y la fecha; las líneas salen solas.
/// «Asiento a mano» (débitos y créditos) sigue en el editor, para el contador.
enum JournalTemplate: String, CaseIterable, Identifiable {
    /// Débito banco / crédito 3000 Capital del dueño.
    case ownerContribution
    /// Débito 3100 Retiros del dueño / crédito banco.
    case ownerDraw
    /// Débito cuenta destino / crédito cuenta origen.
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ownerContribution: String(localized: "Puse dinero de mi bolsillo en el negocio")
        case .ownerDraw: String(localized: "Saqué dinero del negocio para mí")
        case .transfer: String(localized: "Pasé dinero entre mis cuentas")
        }
    }

    var systemImage: String {
        switch self {
        case .ownerContribution: "arrow.down.circle"
        case .ownerDraw: "arrow.up.circle"
        case .transfer: "arrow.left.arrow.right.circle"
        }
    }

    /// Concepto que se propone (se puede cambiar).
    var defaultMemo: String {
        switch self {
        case .ownerContribution: String(localized: "Aportación del dueño")
        case .ownerDraw: String(localized: "Retiro del dueño")
        case .transfer: String(localized: "Traspaso entre cuentas")
        }
    }

    /// Etiqueta de la primera cuenta de dinero (la segunda solo la pide el traspaso).
    var moneyAccountLabel: String {
        switch self {
        case .ownerContribution: String(localized: "¿A qué cuenta entró?")
        case .ownerDraw: String(localized: "¿De qué cuenta salió?")
        case .transfer: String(localized: "¿De qué cuenta salió?")
        }
    }

    var needsDestination: Bool { self == .transfer }

    /// Cuentas en las que puede estar el dinero: caja, bancos y tarjetas (`AccountSubtype.isMoneyAccount`), sin las
    /// de sistema ni las archivadas. Primero los bancos, como en Banca.
    static func moneyAccounts(in accounts: [Account]) -> [Account] {
        accounts.filter { $0.isPostable && $0.subtype.isMoneyAccount && $0.subtype != .undepositedFunds }
            .sorted { lhs, rhs in
                let rank: (Account) -> Int = { $0.subtype == .bank ? 0 : $0.subtype == .cash ? 1 : 2 }
                return (rank(lhs), lhs.code) < (rank(rhs), rhs.code)
            }
    }

    /// Cuenta del patrimonio que usa la plantilla: 3000 Capital del dueño o 3100 Retiros del dueño (por subtipo; si
    /// hay varias, la del código de la plantilla). El traspaso no usa ninguna.
    func equityAccount(in accounts: [Account]) -> Account? {
        let (subtype, code): (AccountSubtype, String)
        switch self {
        case .ownerContribution: (subtype, code) = (.ownersEquity, "3000")
        case .ownerDraw: (subtype, code) = (.ownersDraw, "3100")
        case .transfer: return nil
        }
        let candidates = accounts.filter { $0.subtype == subtype && $0.isPostable }
        return candidates.first { $0.code == code } ?? candidates.min { $0.code < $1.code }
    }

    /// El asiento que sale de la plantilla, o `nil` si falta algo (importe, cuentas, o el traspaso a la misma cuenta).
    /// `money` es la cuenta de dinero de `moneyAccountLabel`; `destination`, la de destino del traspaso.
    func draft(date: Date, memo: String, amount: Int64, money: UUID?, destination: UUID?, accounts: [Account]) -> JournalEntryDraft? {
        guard amount > 0, let money else { return nil }
        let memo = memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultMemo : memo
        let lines: [JournalLineDraft]
        switch self {
        case .ownerContribution:
            guard let equity = equityAccount(in: accounts) else { return nil }
            lines = [JournalLineDraft(accountID: money, debit: amount), JournalLineDraft(accountID: equity.id, credit: amount)]
        case .ownerDraw:
            guard let draw = equityAccount(in: accounts) else { return nil }
            lines = [JournalLineDraft(accountID: draw.id, debit: amount), JournalLineDraft(accountID: money, credit: amount)]
        case .transfer:
            guard let destination, destination != money else { return nil }
            lines = [JournalLineDraft(accountID: destination, debit: amount), JournalLineDraft(accountID: money, credit: amount)]
        }
        return JournalEntryDraft(date: date, memo: memo, source: .manual, lines: lines)
    }
}
