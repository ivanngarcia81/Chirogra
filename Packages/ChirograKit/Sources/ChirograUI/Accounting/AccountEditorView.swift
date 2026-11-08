import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Alta y edición de una cuenta del plan (canvas `MacPlanCuentas`, «Editar…»): número, nombre, tipo y tipo de detalle,
/// cuenta principal, descripción y, en bancos y tarjetas, los últimos 4 dígitos («Corriente ••4821»). Al editar pasa
/// por `Bookkeeper.updateAccount`, que valida todo: el tipo solo cambia si la cuenta no tiene movimientos ni
/// subcuentas, y las cuentas de sistema no cambian de tipo de detalle; el formulario lo dice antes de intentarlo.
struct AccountEditorView: View {
    /// Cuenta que se edita; `nil` para una cuenta nueva.
    let account: Account?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @State private var code: String
    @State private var name: String
    @State private var type: AccountType
    @State private var subtype: AccountSubtype
    @State private var parentID: UUID?
    @State private var details: String
    @State private var last4: String
    @State private var errorMessage: String?

    /// `newSubtype`: el tipo de una cuenta nueva (Banca la abre como cuenta de banco).
    init(account: Account? = nil, newSubtype: AccountSubtype = .operatingExpense) {
        self.account = account
        let input = account.map(AccountInput.init) ?? AccountInput(code: "", name: "", subtype: newSubtype)
        _code = State(initialValue: input.code)
        _name = State(initialValue: input.name)
        _type = State(initialValue: input.subtype.accountType)
        _subtype = State(initialValue: input.subtype)
        _parentID = State(initialValue: input.parentID)
        _details = State(initialValue: input.details)
        _last4 = State(initialValue: input.last4)
    }

    private var trimmedCode: String { code.trimmingCharacters(in: .whitespaces) }

    private var codeTaken: Bool {
        !trimmedCode.isEmpty && accounts.contains { $0.id != account?.id && !$0.isArchived && $0.code == trimmedCode }
    }

    /// Movimientos o subcuentas: la cuenta ya no cambia de tipo (activo, pasivo…).
    private var typeLocked: Bool {
        guard let account else { return false }
        return account.isSystem || !(account.lines ?? []).isEmpty || !(account.children ?? []).isEmpty
    }

    /// Las cuentas de sistema (CxC, Sales tax por pagar…) tampoco cambian de tipo de detalle.
    private var subtypeLocked: Bool { account?.isSystem ?? false }

    private var showsLast4: Bool { subtype == .bank || subtype == .creditCard || !last4.isEmpty }

    private var last4Valid: Bool { last4.isEmpty || (last4.count == 4 && last4.allSatisfy { $0.isASCII && $0.isNumber }) }

    /// Cuentas que pueden ser la principal: activas, del mismo tipo, sin movimientos propios y sin crear ciclos.
    private var parentCandidates: [Account] {
        accounts.filter { candidate in
            guard candidate.id != account?.id, candidate.type == type else { return false }
            if candidate.id == account?.parent?.id { return true }
            guard !candidate.isArchived, (candidate.lines ?? []).isEmpty else { return false }
            var node = candidate.parent
            while let current = node {
                if current.id == account?.id { return false }
                node = current.parent
            }
            return true
        }
    }

    private var tracking: String {
        "\(code)|\(name)|\(subtype.rawValue)|\(parentID?.uuidString ?? "")|\(details)|\(last4)"
    }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                labeled("Número") {
                    TextField("Número", text: $code)
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                }
                labeled("Nombre") { TextField("Nombre", text: $name) }
            } header: {
                SectionLabel(text: String(localized: "Cuenta"))
            } footer: {
                if codeTaken { Text("Ya existe una cuenta con ese número.").foregroundStyle(Palette.negative) }
            }
            Section {
                if typeLocked {
                    LabeledContent("Tipo", value: type.title)
                } else {
                    Picker("Tipo", selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .onChange(of: type) { _, newType in
                        if subtype.accountType != newType {
                            subtype = AccountSubtype.allCases.first { $0.accountType == newType } ?? subtype
                        }
                        if let parentID, !parentCandidates.contains(where: { $0.id == parentID }) { self.parentID = nil }
                    }
                }
                if subtypeLocked {
                    LabeledContent("Tipo de detalle", value: subtype.title)
                } else {
                    Picker("Tipo de detalle", selection: $subtype) {
                        ForEach(AccountSubtype.allCases.filter { $0.accountType == type }, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Picker("Cuenta principal", selection: $parentID) {
                    Text("Ninguna").tag(UUID?.none)
                    ForEach(parentCandidates) { Text($0.displayName).tag(Optional($0.id)) }
                }
            } header: {
                SectionLabel(text: String(localized: "Tipo"))
            } footer: {
                Text(typeFooter)
            }
            if showsLast4 {
                Section {
                    labeled("Últimos 4 dígitos") {
                        TextField("Últimos 4 dígitos", text: $last4, prompt: Text(verbatim: "0000"))
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .onChange(of: last4) { _, value in
                                let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(4))
                                if digits != value { last4 = digits }
                            }
                    }
                } header: {
                    SectionLabel(text: subtype == .creditCard ? String(localized: "Tarjeta") : String(localized: "Cuenta bancaria"))
                } footer: {
                    Text(last4Valid ? String(localized: "Se muestran así: \(previewName).")
                                    : String(localized: "Escribe los 4 dígitos o deja el campo vacío."))
                }
            }
            Section {
                TextField("Descripción (opcional)", text: $details, axis: .vertical)
                    .lineLimit(1...4)
            } header: {
                SectionLabel(text: String(localized: "Descripción"))
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle(account == nil ? "Nueva cuenta" : "Editar cuenta")
        .inlineTitle()
        .discardableEditor(tracking: tracking, token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || codeTaken || !last4Valid)
                    .headerButton()
            }
        }
    }

    /// En el iPhone y el iPad el campo de un formulario no muestra su nombre una vez escrito: va con su etiqueta a la
    /// izquierda y el valor a la derecha. En el Mac el formulario ya la pone.
    @ViewBuilder
    private func labeled(_ title: LocalizedStringKey, @ViewBuilder field: () -> some View) -> some View {
        #if os(iOS)
        LabeledContent(title) { field().multilineTextAlignment(.trailing) }
        #else
        field()
        #endif
    }

    /// «Corriente ••4821».
    private var previewName: String {
        let base = name.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Cuenta") : name
        return last4.isEmpty ? base : "\(base) ••\(last4)"
    }

    private var typeFooter: String {
        if account?.isSystem == true {
            return String(localized: "Cuenta del sistema: Chirogra la usa al contabilizar los documentos, así que su tipo no cambia.")
        }
        if let account, !(account.lines ?? []).isEmpty {
            return String(localized: "La cuenta ya tiene movimientos: su tipo no cambia. Si hace falta, crea otra cuenta y reclasifica con un asiento.")
        }
        if let account, !(account.children ?? []).isEmpty {
            return String(localized: "La cuenta tiene subcuentas: su tipo no cambia.")
        }
        return String(localized: "El tipo decide dónde aparece la cuenta en los reportes. Una subcuenta suma en su cuenta principal.")
    }

    private func save() {
        let input = AccountInput(code: trimmedCode, name: name, subtype: subtype, details: details, parentID: parentID, last4: last4)
        let books = Bookkeeper(context: context)
        do {
            if let account {
                try books.updateAccount(account, with: input)
            } else {
                let created = Account(code: "", name: name, subtype: subtype)
                Bookkeeper(context: context).insert(created)
                do {
                    try books.updateAccount(created, with: input)
                } catch {
                    context.delete(created)
                    throw error
                }
            }
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
