import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// MARK: - Cierre de periodo (`MacCierre`)

/// Caja «Libros cerrados hasta» con su candado y su aviso, la lista de revisión del mes que se va a cerrar y «Cerrar
/// periodo» con la nueva fecha. La contraseña de cierre y el historial de cierres del canvas no se guardan en el
/// modelo: quedan fuera.
struct PeriodCloseWideView: View {
    @Environment(\.modelContext) private var context
    @Query private var companies: [Company]
    @Query private var invoices: [Invoice]
    @Query private var expenses: [Expense]
    @Query private var bills: [Bill]
    @State private var newDate: Date?

    private let calendar = Calendar.current

    /// Último día del mes de `date`.
    private func endOfMonth(_ date: Date) -> Date {
        let month = DateInterval.month(containing: date)
        return calendar.startOfDay(for: month.end.addingTimeInterval(-1))
    }

    /// Propuesta: el mes siguiente al cierre actual o, sin cierre, el mes pasado.
    private func proposedDate(_ company: Company) -> Date {
        if let lock = company.lockDate { return endOfMonth(calendar.date(byAdding: .day, value: 1, to: lock) ?? lock) }
        return endOfMonth(calendar.date(byAdding: .month, value: -1, to: .now) ?? .now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let company = companies.first {
                    let target = newDate ?? proposedDate(company)
                    let checks = checklist(for: target)
                    statusBox(company, checks: checks, target: target)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            checklistBox(checks, target: target).frame(minWidth: 320, maxWidth: .infinity)
                            closeBox(company, target: target).frame(minWidth: 300, maxWidth: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 16) { checklistBox(checks, target: target); closeBox(company, target: target) }
                    }
                }
            }
            .padding(Metrics.gutter)
        }
        .background(Palette.background)
        .navigationTitle("Cierre de periodo")
        .navigationSubtitle(String(localized: "Bloquea los meses ya revisados para que nadie los cambie por error"))
        .headerTitle()
        .onDisappear { try? context.save() }
    }

    // MARK: Estado

    /// Candado en índigo, «Libros cerrados hasta» con la fecha en grande, el estado del mes a cerrar y el aviso.
    private func statusBox(_ company: Company, checks: [Check], target: Date) -> some View {
        let pending = checks.filter { !$0.ok }.count
        let month = target.formatted(.appDateTime.month(.wide)).sentenceCased
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                LargeIconTile(systemImage: company.lockDate == nil ? "lock.open" : "lock", color: Palette.indigo)
                VStack(alignment: .leading, spacing: 1) {
                    Text(company.lockDate == nil ? String(localized: "Libros abiertos") : String(localized: "Libros cerrados hasta"))
                        .font(.label).foregroundStyle(Palette.ink2)
                    Text(company.lockDate?.shortDate ?? String(localized: "Sin cierre")).font(.amount(24)).foregroundStyle(Palette.ink)
                }
                Spacer(minLength: 8)
                StatusChip(text: pending == 0 ? String(localized: "\(month) listo para cerrar") : String(localized: "\(month) tiene pendientes"),
                           foreground: pending == 0 ? Palette.positive : Palette.warning, background: .clear, compact: true,
                           dot: pending == 0 ? Palette.green : Palette.orange)
            }
            .accessibilityElement(children: .combine)
            if let lock = company.lockDate {
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(Palette.ink2).accessibilityHidden(true)
                    Text("Las transacciones con fecha hasta el \(lock.shortDate) están bloqueadas. Para corregirlas, reabre el periodo.")
                        .font(.footnote).foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 0)
    }

    // MARK: Lista de revisión

    fileprivate struct Check: Identifiable {
        let id: String
        let ok: Bool
        let title: String
        var note: String? = nil
        let item: SidebarItem
    }

    /// Lo que conviene revisar del mes que se va a cerrar, sacado de los datos (no se marca a mano).
    private func checklist(for target: Date) -> [Check] {
        let month = DateInterval.month(containing: target)
        let name = target.formatted(.appDateTime.month(.wide))
        let issued = invoices.filter { $0.status != .draft && $0.status != .void && month.contains($0.issueDate) }.count
        let drafts = invoices.filter { $0.status == .draft && month.contains($0.issueDate) }.count
        let monthExpenses = expenses.filter { month.contains($0.date) }
        let noReceipt = monthExpenses.filter { ($0.attachments ?? []).isEmpty }.count
        let monthBills = bills.filter { $0.status != .void && month.contains($0.billDate) }.count
        var checks = [Check(id: "invoices", ok: true, title: String(localized: "Facturas de \(name) emitidas (\(issued))"), item: .sales(.invoices))]
        if drafts > 0 {
            checks.append(Check(id: "drafts", ok: false, title: String(localized: "\(drafts) borradores de factura sin emitir"),
                                note: String(localized: "Emítelos o bórralos antes de cerrar"), item: .sales(.invoices)))
        }
        checks += [
            Check(id: "expenses", ok: true, title: String(localized: "Gastos de \(name) registrados (\(monthExpenses.count))"), item: .expenses(.expenses)),
            Check(id: "receipts", ok: noReceipt == 0,
                  title: noReceipt == 0 ? String(localized: "Todos los gastos tienen recibo") : String(localized: "\(noReceipt) gastos sin recibo adjunto"),
                  note: noReceipt == 0 ? nil : String(localized: "Adjunta los recibos que te falten"), item: .expenses(.expenses)),
            Check(id: "bills", ok: true, title: String(localized: "Facturas de proveedor de \(name) (\(monthBills))"), item: .expenses(.bills)),
            Check(id: "tax", ok: true, title: String(localized: "Revisa el impuesto sobre ventas"), item: .report(.salesTax)),
        ]
        return checks
    }

    private func checklistBox(_ checks: [Check], target: Date) -> some View {
        let ready = checks.filter(\.ok).count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Antes de cerrar \(target.formatted(.appDateTime.month(.wide)))").font(.cardTitle).foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("\(ready) de \(checks.count) listos").font(.footnote).foregroundStyle(Palette.ink2)
            }
            VStack(spacing: 0) {
                ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                    if index > 0 { Divider() }
                    checkRow(check)
                }
            }
            .padding(.horizontal, 12)
            .card(padding: 0)
        }
    }

    private func checkRow(_ check: Check) -> some View {
        SectionLink(item: check.item) {
            check.item.destination
        } label: {
            HStack(spacing: 10) {
                Image(systemName: check.ok ? "checkmark" : "exclamationmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(check.ok ? Palette.green : Palette.orange, in: Circle())
                    .accessibilityLabel(check.ok ? String(localized: "Listo") : String(localized: "Revisar"))
                VStack(alignment: .leading, spacing: 1) {
                    Text(check.title).foregroundStyle(Palette.ink)
                    if let note = check.note { Text(note).font(.footnote).foregroundStyle(Palette.warning) }
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.chevron).accessibilityHidden(true)
            }
            .frame(minHeight: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    #if os(macOS)
    private static let rowHeight: CGFloat = 38
    #else
    private static let rowHeight: CGFloat = 52
    #endif

    // MARK: Cerrar periodo

    private func closeBox(_ company: Company, target: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cerrar periodo").font(.cardTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            HStack(spacing: 12) {
                Text("Nueva fecha de cierre").foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                DatePicker("Nueva fecha de cierre", selection: Binding(get: { target }, set: { newDate = $0 }), in: ...Date.now,
                           displayedComponents: .date)
                    .labelsHidden()
                    .fixedSize()
                    // En cifras sigue la región (1e6efbf): «10/31/26» en EE. UU.
                    .environment(\.locale, .app)
            }
            .frame(minHeight: Self.rowHeight)
            .padding(.horizontal, 12)
            .card(padding: 0)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { Spacer(minLength: 0); closeButtons(company, target: target) }
                VStack(alignment: .trailing, spacing: 8) { closeButtons(company, target: target) }
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func closeButtons(_ company: Company, target: Date) -> some View {
        if let lock = company.lockDate {
            Button("Quitar cierre", role: .destructive) {
                company.lockDate = nil
                newDate = nil
                try? context.save()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Palette.negative)
            Button(String(localized: "Reabrir \(lock.formatted(.appDateTime.month(.wide).year()))")) {
                let previous = calendar.date(byAdding: .day, value: -1, to: DateInterval.month(containing: lock).start)
                // Si el cierre no estaba a fin de mes, reabrir quita sólo ese tramo del mes.
                company.lockDate = previous.map { calendar.startOfDay(for: $0) }
                newDate = nil
                try? context.save()
            }
            .buttonStyle(.secondary)
            .fixedSize()
        }
        Button(String(localized: "Cerrar hasta el \(target.shortDate)")) {
            company.lockDate = calendar.startOfDay(for: target)
            newDate = nil
            try? context.save()
        }
        .buttonStyle(.primaryCompact)
        .disabled(company.lockDate.map { calendar.startOfDay(for: target) <= $0 } ?? false)
    }
}
