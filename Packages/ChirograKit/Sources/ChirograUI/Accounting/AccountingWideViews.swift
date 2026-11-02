import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// MARK: - Cierre de periodo (`MacCierre`)

/// Fecha de cierre con su candado, aviso, nueva fecha y «Cerrar … / Reabrir …», y la lista de revisión del mes.
/// La contraseña de cierre y el historial de cierres del canvas no se guardan en el modelo: quedan fuera.
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
                MacPageTitle(String(localized: "Cierre de periodo"))
                Text("Bloquea los meses ya revisados para que nadie los cambie por error.")
                    .font(.subheadline).foregroundStyle(Palette.ink3)
                if let company = companies.first {
                    let target = newDate ?? proposedDate(company)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            lockCard(company, target: target).frame(maxWidth: .infinity)
                            checklist(for: target).frame(width: 340)
                        }
                        VStack(spacing: 16) { lockCard(company, target: target); checklist(for: target) }
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.background)
        .navigationTitle("Cierre de periodo")
        .headerTitle()
        .onDisappear { try? context.save() }
    }

    private func lockCard(_ company: Company, target: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                IconTile(systemImage: company.lockDate == nil ? "lock.open" : "lock")
                VStack(alignment: .leading, spacing: 2) {
                    Text(company.lockDate == nil ? String(localized: "Libros abiertos") : String(localized: "Libros cerrados hasta"))
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3)
                    Text(company.lockDate?.shortDate ?? String(localized: "Sin cierre")).font(.amount(28)).foregroundStyle(Palette.ink)
                }
            }
            .accessibilityElement(children: .combine)
            if let lock = company.lockDate {
                Label("Las transacciones con fecha hasta el \(lock.shortDate) están bloqueadas. Para corregirlas, reabre el periodo.",
                      systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.warning)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.warningWash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Nueva fecha de cierre").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink2)
                DatePicker("Nueva fecha de cierre", selection: Binding(get: { target }, set: { newDate = $0 }), in: ...Date.now,
                           displayedComponents: .date)
                    .labelsHidden()
                    .fixedSize()
                    // En cifras sigue la región (1e6efbf): «10/31/26» en EE. UU.
                    .environment(\.locale, .app)
            }
            HStack(spacing: 10) {
                Button(String(localized: "Cerrar hasta el \(target.shortDate)")) {
                    company.lockDate = calendar.startOfDay(for: target)
                    newDate = nil
                    try? context.save()
                }
                .glassActionButton()
                .disabled(company.lockDate.map { calendar.startOfDay(for: target) <= $0 } ?? false)
                if let lock = company.lockDate {
                    Button(String(localized: "Reabrir \(lock.formatted(.appDateTime.month(.wide).year()))")) {
                        let previous = calendar.date(byAdding: .day, value: -1, to: DateInterval.month(containing: lock).start)
                        // Si el cierre no estaba a fin de mes, reabrir quita sólo ese tramo del mes.
                        company.lockDate = previous.map { calendar.startOfDay(for: $0) }
                        newDate = nil
                        try? context.save()
                    }
                    .buttonStyle(.bordered)
                    Button("Quitar cierre", role: .destructive) {
                        company.lockDate = nil
                        newDate = nil
                        try? context.save()
                    }
                    .buttonStyle(.borderless)
                }
            }
            .controlSize(.large)
        }
        .card()
    }

    /// Lo que conviene revisar del mes que se va a cerrar, con enlace a cada pantalla.
    private func checklist(for target: Date) -> some View {
        let month = DateInterval.month(containing: target)
        let name = target.formatted(.appDateTime.month(.wide))
        let issued = invoices.filter { $0.status != .draft && $0.status != .void && month.contains($0.issueDate) }.count
        let drafts = invoices.filter { $0.status == .draft && month.contains($0.issueDate) }.count
        let monthExpenses = expenses.filter { month.contains($0.date) }
        let noReceipt = monthExpenses.filter { ($0.attachments ?? []).isEmpty }.count
        let monthBills = bills.filter { $0.status != .void && month.contains($0.billDate) }.count
        return VStack(alignment: .leading, spacing: 0) {
            Text("Antes de cerrar \(name)").font(.headline).foregroundStyle(Palette.ink).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
            checkRow(ok: true, String(localized: "Facturas de \(name) emitidas (\(issued))"), item: .sales(.invoices)) { SalesView(fixedSegment: .invoices) }
            if drafts > 0 {
                checkRow(ok: false, String(localized: "\(drafts) borradores de factura sin emitir"), item: .sales(.invoices)) { SalesView(fixedSegment: .invoices) }
            }
            checkRow(ok: true, String(localized: "Gastos de \(name) registrados (\(monthExpenses.count))"), item: .expenses(.expenses)) { ExpensesView(fixedSegment: .expenses) }
            checkRow(ok: noReceipt == 0, noReceipt == 0 ? String(localized: "Todos los gastos tienen recibo")
                                                        : String(localized: "\(noReceipt) gastos sin recibo adjunto"), item: .expenses(.expenses)) { ExpensesView(fixedSegment: .expenses) }
            checkRow(ok: true, String(localized: "Facturas de proveedor de \(name) (\(monthBills))"), item: .expenses(.bills)) { ExpensesView(fixedSegment: .bills) }
            checkRow(ok: true, String(localized: "Revisa el impuesto sobre ventas"), item: .report(.salesTax)) { ReportsView(fixedKind: .salesTax) }
        }
        .card()
    }

    private func checkRow<Destination: View>(ok: Bool, _ title: String, item: SidebarItem,
                                             @ViewBuilder destination: @escaping () -> Destination) -> some View {
        VStack(spacing: 0) {
            Divider()
            SectionLink(item: item, destination: destination) {
                HStack(spacing: 10) {
                    Image(systemName: ok ? "checkmark" : "exclamationmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 22, height: 22)
                        .foregroundStyle(ok ? Palette.positive : Palette.warning)
                        .background(ok ? Palette.positiveWash : Palette.warningWash, in: Circle())
                        .accessibilityLabel(ok ? String(localized: "Listo") : String(localized: "Revisar"))
                    Text(title).font(.subheadline).foregroundStyle(Palette.ink)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
