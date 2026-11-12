import ChirograCore
import ChirograData
import SwiftUI

// MARK: - Base caja / devengado (fase 2, docs/DATOS-V4.md §4)
//
// Los reportes que dependen de la base (estado de resultados, balance, balanza, flujo de efectivo, presupuestos y
// deducibles) llevan el mismo selector. La elección se recuerda **por empresa y en este aparato** (en `UserDefaults`,
// no en el esquema ni en iCloud): quien prepara los números para su contador en caja no cambia lo que ve otro aparato.

extension AccountingBasis {
    /// «Devengado» / «Caja», para el selector.
    var title: String {
        switch self {
        case .accrual: String(localized: "Devengado")
        case .cash: String(localized: "Caja")
        }
    }

    /// «base devengado» / «base caja», para los subtítulos de los reportes.
    var subtitle: String {
        switch self {
        case .accrual: String(localized: "base devengado")
        case .cash: String(localized: "base caja")
        }
    }
}

/// Lo que guarda la base de cada empresa: «<id>=cash;<id>=accrual» en una sola clave de `UserDefaults`.
enum ReportBasisStore {
    static let defaultsKey = "reportBasisByCompany"

    static func basis(in raw: String, company: UUID?) -> AccountingBasis? {
        guard let company else { return nil }
        for pair in raw.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == company.uuidString, let basis = AccountingBasis(rawValue: String(parts[1])) {
                return basis
            }
        }
        return nil
    }

    static func storing(_ basis: AccountingBasis, in raw: String, company: UUID?) -> String {
        guard let company else { return raw }
        var pairs = raw.split(separator: ";").map(String.init).filter { !$0.hasPrefix(company.uuidString + "=") }
        pairs.append("\(company.uuidString)=\(basis.rawValue)")
        return pairs.joined(separator: ";")
    }

    /// Sin nada guardado: devengado (lo de siempre). En Debug, `-qa.base caja|devengado` cambia ese valor inicial.
    static var initial: AccountingBasis {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "qa.base") {
        case "caja", "cash": return .cash
        default: break
        }
        #endif
        return .accrual
    }
}

/// La base elegida para la empresa activa (`CompanySession`), recordada en el aparato. Todas las pantallas que la usan
/// ven el mismo valor: al cambiarla en un reporte, cambia en los demás.
@propertyWrapper
struct ReportBasisSetting: DynamicProperty {
    @AppStorage(ReportBasisStore.defaultsKey) private var raw = ""

    var wrappedValue: AccountingBasis {
        get { ReportBasisStore.basis(in: raw, company: CompanySession.scope?.id) ?? ReportBasisStore.initial }
        nonmutating set { raw = ReportBasisStore.storing(newValue, in: raw, company: CompanySession.scope?.id) }
    }

    var projectedValue: Binding<AccountingBasis> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

/// Selector «Devengado | Caja» con su ⓘ. `compact`: un menú para la barra (iPad y Mac); si no, el segmentado del
/// sistema a todo el ancho con el ⓘ al lado (iPhone), o el mismo menú con letra de accesibilidad.
struct BasisPicker: View {
    @Binding var basis: AccountingBasis
    var compact = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if compact {
            menu
        } else if dynamicTypeSize.isAccessibilitySize {
            // Con letra de accesibilidad el segmentado no crece y cortaba «Devengado»: el menú de la barra, con su ⓘ.
            HStack(spacing: 4) {
                menu
                TermHelp(.accountingBasis)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 4) {
                Picker("Base contable", selection: $basis) {
                    ForEach(AccountingBasis.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                TermHelp(.accountingBasis)
            }
        }
    }

    private var menu: some View {
        Menu {
            Picker("Base contable", selection: $basis) {
                ForEach(AccountingBasis.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: basis == .cash ? "banknote" : "doc.text")
                Text(String(localized: "Base: \(basis.title)"))
                    .multilineTextAlignment(.leading)
            }
        }
        .menuIndicator(.hidden)
        .headerButton()
        .accessibilityLabel("Base contable")
        .accessibilityValue(basis.title)
    }
}

/// Memoria de un cálculo caro (las líneas en base caja, los deducibles) mientras no cambie su clave: el cuerpo de las
/// vistas se evalúa muchas veces y cada cálculo lee todo el diario. No es estado observable: no redibuja nada.
final class ReportMemo<Value> {
    private var key: String?
    private var value: Value?

    func value(for key: String, compute: () -> Value) -> Value {
        if key == self.key, let value { return value }
        let fresh = compute()
        self.key = key
        value = fresh
        return fresh
    }
}
