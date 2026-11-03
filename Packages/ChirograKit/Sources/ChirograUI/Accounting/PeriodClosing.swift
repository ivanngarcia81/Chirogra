import ChirograCore
import ChirograData
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

// Piezas del cierre de periodo (canvas `MacCierre`) que usan la pantalla de cierre y los editores que registran:
// el nombre del aparato para el historial, la contraseña de cierre y «Desbloquear con contraseña» cuando algo cae en
// un periodo cerrado. Podrían subir a `DesignSystem` si otras áreas las usan (gastos, facturas).

enum PeriodClosing {
    /// Nombre del aparato para el historial de cierres («MacBook Pro de Ana», «iPad»).
    static var deviceName: String {
        #if os(macOS)
        Host.current().localizedName ?? ""
        #else
        UIDevice.current.name
        #endif
    }

    /// Fecha de cierre si el error es «periodo cerrado» (`BookkeepingError.invalidEntry(.periodLocked)`); si no, `nil`.
    static func lockDate(of error: Error) -> Date? {
        if case BookkeepingError.invalidEntry(.periodLocked(let date)) = error { return date }
        if case JournalValidationError.periodLocked(let date) = error { return date }
        return nil
    }

    /// Último día del mes de `date`.
    static func endOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        let month = DateInterval.month(containing: date, calendar: calendar)
        return calendar.startOfDay(for: month.end.addingTimeInterval(-1))
    }

    /// Fecha de cierre tras reabrir el último periodo: el fin del mes anterior al del cierre actual (canvas: «Solo se
    /// puede reabrir el último periodo cerrado»).
    static func reopenTarget(from lock: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: -1, to: DateInterval.month(containing: lock, calendar: calendar).start)
            .map { calendar.startOfDay(for: $0) }
    }

    /// «Octubre 2026».
    static func monthTitle(_ date: Date) -> String {
        date.formatted(.appDateTime.month(.wide).year()).sentenceCased
    }
}

// MARK: - Registrar en un periodo cerrado

/// Lo que hay que repetir con los libros desbloqueados cuando algo cae en un periodo cerrado.
struct ClosedPeriodRetry: Identifiable {
    let id = UUID()
    let lockDate: Date
    /// La acción, con un `Bookkeeper` que ya admite fechas del periodo cerrado.
    let perform: (Bookkeeper) throws -> Void
}

/// Pide la contraseña de cierre (o, sin contraseña, una confirmación) y repite la acción con
/// `Bookkeeper.unlockedForClosedPeriod(password:)`. Una contraseña equivocada lo dice y deja intentarlo otra vez.
private struct ClosedPeriodUnlock: ViewModifier {
    @Binding var retry: ClosedPeriodRetry?
    let onError: (String) -> Void
    @Environment(\.modelContext) private var context
    @Query private var companies: [Company]
    @State private var password = ""
    @State private var wrongPassword = false

    private var hasPassword: Bool { companies.first?.hasClosingPassword ?? false }

    func body(content: Content) -> some View {
        content
            .alert(hasPassword ? "Periodo cerrado" : "¿Registrar en un periodo cerrado?",
                   isPresented: Binding(get: { retry != nil }, set: { if !$0 { retry = nil; password = "" } }),
                   presenting: retry) { request in
                if hasPassword {
                    SecureField("Contraseña de cierre", text: $password)
                    Button("Desbloquear y registrar") { run(request) }
                } else {
                    Button("Registrar de todos modos") { run(request) }
                }
                Button("Cancelar", role: .cancel) { password = "" }
            } message: { request in
                Text(hasPassword
                     ? "Los libros están cerrados hasta el \(request.lockDate.shortDate). Escribe la contraseña de cierre para registrar con esa fecha."
                     : "Los libros están cerrados hasta el \(request.lockDate.shortDate). Si registras con esa fecha cambiarán reportes que ya pudiste entregar. Quedará anotado.")
            }
            .alert("La contraseña de cierre no es correcta.", isPresented: $wrongPassword) {
                Button("Aceptar", role: .cancel) {}
            }
    }

    private func run(_ request: ClosedPeriodRetry) {
        let typed = password
        password = ""
        do {
            let unlocked = try Bookkeeper(context: context).unlockedForClosedPeriod(password: hasPassword ? typed : nil)
            try request.perform(unlocked)
        } catch BookkeepingError.wrongClosingPassword {
            wrongPassword = true
        } catch {
            onError(error.localizedDescription)
        }
    }
}

extension View {
    /// Cuando `retry` tiene algo, pide la contraseña de cierre y lo repite (ver `ClosedPeriodUnlock`).
    func closedPeriodUnlock(_ retry: Binding<ClosedPeriodRetry?>, onError: @escaping (String) -> Void) -> some View {
        modifier(ClosedPeriodUnlock(retry: retry, onError: onError))
    }
}

// MARK: - Contraseña de cierre

/// Fijar o cambiar la contraseña de cierre (canvas `MacCierre`, «Contraseña de cierre»). Para cambiarla pide la actual.
/// Solo se guarda su huella (PBKDF2), nunca la contraseña.
struct ClosingPasswordEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    @State private var editorToken = EditorToken()
    @Query private var companies: [Company]
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var errorMessage: String?

    private var changing: Bool { companies.first?.hasClosingPassword ?? false }
    private var mismatch: Bool { !confirm.isEmpty && new != confirm }
    private var canSave: Bool { new.count >= 4 && new == confirm && (!changing || !current.isEmpty) }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            if changing {
                Section {
                    SecureField("Contraseña actual", text: $current)
                } header: {
                    SectionLabel(text: String(localized: "Actual"))
                }
            }
            Section {
                SecureField("Contraseña nueva", text: $new)
                SecureField("Repite la contraseña", text: $confirm)
            } header: {
                SectionLabel(text: String(localized: "Nueva"))
            } footer: {
                if mismatch {
                    Text("Las contraseñas no coinciden.").foregroundStyle(Palette.negative)
                } else {
                    Text("Al menos 4 caracteres. Se pedirá para reabrir un periodo y para registrar con una fecha cerrada. Si la olvidas, no se puede recuperar.")
                }
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle(changing ? "Cambiar contraseña de cierre" : "Contraseña de cierre")
        .inlineTitle()
        .discardableEditor(tracking: "\(current)|\(new)|\(confirm)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save).disabled(!canSave).headerButton()
            }
        }
    }

    private func save() {
        do {
            try Bookkeeper(context: context).setClosingPassword(new, current: changing ? current : nil)
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Fila del historial: qué se hizo («Cierre», «Reapertura»), hasta cuándo quedaron cerrados, cuándo y desde dónde.
extension PeriodClose {
    /// `true` en una reapertura (el modelo guarda `actionRaw`: `close` o `reopen`).
    var wasReopen: Bool { actionRaw == "reopen" }

    var actionTitle: String { wasReopen ? String(localized: "Reapertura") : String(localized: "Cierre") }

    /// «Septiembre 2026»: el mes que quedó cerrado o, en una reapertura, el que se reabrió.
    var periodTitle: String {
        if let month = wasReopen ? previousLockDate : lockDate { return PeriodClosing.monthTitle(month) }
        return String(localized: "Sin cierre")
    }

    var lockTitle: String { lockDate?.shortDate ?? "—" }

    /// «MacBook Pro de Ana» o quien lo hizo; vacío si no se sabe.
    var origin: String {
        [actor, device].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
