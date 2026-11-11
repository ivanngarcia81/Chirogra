import ChirograCore
import ChirograData
import SwiftUI

// 1.2 (canvas `BancaRevisar`): «Dividir» un movimiento en varias cuentas y el motivo al excluirlo.

/// Motivos de exclusión del canvas. El `rawValue` es la etiqueta en español (se traduce con `localizedTitle`); se
/// guarda en el movimiento el texto en el idioma de la app (`BankTransaction.ignoreReason`).
enum BankExclusionReason: String, CaseIterable, Identifiable {
    case personal = "Gasto personal"
    case duplicate = "Duplicada"
    case ownTransfer = "Transferencia entre mis cuentas"

    var id: String { rawValue }
}

/// Una línea de la división mientras se edita.
struct BankSplitLine: Identifiable, Equatable {
    var id = UUID()
    var accountID: UUID?
    var amount: Int64 = 0
}

/// Las líneas de la división: cuenta e importe, «Añadir línea» y «Por asignar» (lo que falta para llegar al importe
/// del movimiento; en verde con ✓ solo cuando ya se puede registrar).
struct BankSplitSections: View {
    let total: Int64
    let accounts: [Account]
    @Binding var lines: [BankSplitLine]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static func remaining(_ lines: [BankSplitLine], total: Int64) -> Int64 { total - lines.reduce(0) { $0 + $1.amount } }

    /// Se puede registrar: dos líneas o más, todas con cuenta e importe, y nada por asignar.
    static func isComplete(_ lines: [BankSplitLine], total: Int64) -> Bool {
        lines.count >= 2 && lines.allSatisfy { $0.accountID != nil && $0.amount > 0 } && remaining(lines, total: total) == 0
    }

    var body: some View {
        let remaining = Self.remaining(lines, total: total)
        let complete = Self.isComplete(lines, total: total)
        // Una sección por línea, con la cuenta y el importe en filas separadas: en una sola fila, tocar el importe
        // abría el menú de la cuenta (QA del iPad, 11-nov).
        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
            Section {
                AccountPicker(title: String(localized: "Cuenta"), accounts: accounts, selection: binding(line, \.accountID))
                    .lineSplitActions(canRemove: lines.count > 2) { remove(line.id) }
                LabeledContent("Importe") {
                    MoneyField(title: String(localized: "Importe"), minorUnits: binding(line, \.amount))
                        .labelsHidden().multilineTextAlignment(.trailing)
                }
                #if os(iOS)
                // El estilo del sistema: con el de la app el campo medía lo que «$0.00» y no tomaba el toque de la fila.
                .labeledContentStyle(.automatic)
                #endif
                .lineSplitActions(canRemove: lines.count > 2) { remove(line.id) }
            } header: {
                if index == 0 { SectionLabel(text: String(localized: "Líneas")) }
            }
        }
        Section {
            Button("Añadir línea", systemImage: "plus.circle") {
                lines.append(BankSplitLine(amount: max(0, remaining)))
            }
            .frame(minHeight: Metrics.target)
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Text("Por asignar").foregroundStyle(Palette.ink)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                HStack(spacing: 6) {
                    Text(remaining.money).monospacedDigit().fontWeight(.semibold).lineLimit(1)
                        .foregroundStyle(complete ? Palette.positive : remaining == 0 ? Palette.ink2 : Palette.warning)
                    if complete {
                        Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Palette.positive)
                            .accessibilityLabel(Text("Cuadra"))
                    }
                }
            }
            .frame(minHeight: Metrics.target)
            .accessibilityElement(children: .combine)
        } footer: {
            Text(complete || remaining != 0 ? String(localized: "La suma de las líneas debe ser igual a \(total.money).")
                 : String(localized: "Elige la cuenta y el importe de cada línea."))
        }
    }

    /// El campo de una línea por su id (una línea quitada devuelve lo último que tenía, sin fallar).
    private func binding<Value>(_ line: BankSplitLine, _ key: WritableKeyPath<BankSplitLine, Value>) -> Binding<Value> {
        Binding(get: { lines.first { $0.id == line.id }?[keyPath: key] ?? line[keyPath: key] },
                set: { value in if let index = lines.firstIndex(where: { $0.id == line.id }) { lines[index][keyPath: key] = value } })
    }

    private func remove(_ id: UUID) { lines.removeAll { $0.id == id } }
}

private extension View {
    /// Quitar una línea de la división: deslizar en iPhone y iPad, menú contextual en los tres.
    @ViewBuilder
    func lineSplitActions(canRemove: Bool, remove: @escaping () -> Void) -> some View {
        if canRemove {
            #if os(iOS)
            swipeActions { Button("Quitar línea", systemImage: "trash", role: .destructive, action: remove) }
                .contextMenu { Button("Quitar línea", systemImage: "trash", role: .destructive, action: remove) }
            #else
            contextMenu { Button("Quitar línea", systemImage: "trash", role: .destructive, action: remove) }
            #endif
        } else {
            self
        }
    }
}

/// «Motivo de exclusión» (canvas): los tres motivos y «Otro motivo» con su texto.
struct BankExclusionSection: View {
    @Binding var reason: BankExclusionReason?
    @Binding var otherReason: String

    var body: some View {
        Section {
            ForEach(BankExclusionReason.allCases) { option in
                row(option.localizedTitle, isOn: reason == option) { reason = option }
            }
            row(String(localized: "Otro motivo"), isOn: reason == nil) { reason = nil }
            if reason == nil {
                TextField("Motivo", text: $otherReason)
                    .labeledField(String(localized: "Motivo"))
            }
        } header: {
            SectionLabel(text: String(localized: "Motivo de exclusión"))
        } footer: {
            Text("No se incluirá en tus libros. Puedes devolverlo a la bandeja desde el filtro «Excluidos».")
        }
    }

    /// El texto que se guarda.
    static func text(_ reason: BankExclusionReason?, other: String) -> String {
        reason?.localizedTitle ?? other.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func row(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Image(systemName: "checkmark").fontWeight(.semibold)
                    .foregroundStyle(isOn ? Palette.brand : .clear).accessibilityHidden(true)
            }
            .frame(minHeight: Metrics.target)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

extension View {
    /// Excluir desde un atajo (deslizar, menú contextual, el botón del Mac): pregunta el motivo con los del canvas
    /// o sin motivo, y llama a `perform` con el texto.
    func bankExclusionDialog(_ transaction: Binding<BankTransaction?>, perform: @escaping (BankTransaction, String) -> Void) -> some View {
        confirmationDialog("¿Por qué excluyes este movimiento?", isPresented: Binding(get: { transaction.wrappedValue != nil },
                                                                                      set: { if !$0 { transaction.wrappedValue = nil } }),
                           titleVisibility: .visible, presenting: transaction.wrappedValue) { target in
            ForEach(BankExclusionReason.allCases) { reason in
                Button(reason.localizedTitle, role: .destructive) { perform(target, reason.localizedTitle) }
            }
            Button("Excluir sin motivo", role: .destructive) { perform(target, "") }
        } message: { _ in
            Text("No se incluirá en tus libros. Puedes devolverlo a la bandeja desde el filtro «Excluidos».")
        }
    }
}

extension BankTransaction {
    /// «Excluido · Duplicada» o el estado solo.
    var statusWithReason: String {
        status == .ignored && !ignoreReason.isEmpty ? "\(statusTitle) · \(ignoreReason)" : statusTitle
    }
}
