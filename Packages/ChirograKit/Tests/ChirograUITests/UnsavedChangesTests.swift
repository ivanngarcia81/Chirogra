import Testing
@testable import ChirograUI

/// La barra lateral solo pregunta si hay un editor que sigue existiendo con cambios.
@Suite("Cambios sin guardar")
@MainActor
struct UnsavedChangesTests {
    @Test("Un editor con cambios cuenta; sin cambios o retirado, no")
    func reportAndRemove() {
        let changes = UnsavedChanges()
        let editor = EditorToken()
        changes.report(editor, hasChanges: true)
        #expect(changes.hasChanges)
        changes.report(editor, hasChanges: false)
        #expect(!changes.hasChanges)
        changes.report(editor, hasChanges: true)
        changes.remove(editor)
        #expect(!changes.hasChanges)
    }

    @Test("Un editor que ya no existe no deja aviso, aunque no se haya retirado")
    func releasedEditorDoesNotCount() {
        let changes = UnsavedChanges()
        var editor: EditorToken? = EditorToken()
        changes.report(editor!, hasChanges: true)
        #expect(changes.hasChanges)
        editor = nil
        #expect(!changes.hasChanges)
    }

    @Test("Una hoja encima no borra los cambios del editor de debajo")
    func sheetOverEditor() {
        let changes = UnsavedChanges()
        let invoice = EditorToken()
        let customer = EditorToken()
        changes.report(invoice, hasChanges: true)
        changes.report(customer, hasChanges: false)
        changes.remove(customer)
        #expect(changes.hasChanges)
    }

    @Test("Descartar ejecuta lo de cada editor vivo y vacía el registro")
    func discardAll() {
        let changes = UnsavedChanges()
        let editor = EditorToken()
        var discarded = 0
        changes.report(editor, hasChanges: true) { discarded += 1 }
        changes.discardAll()
        #expect(discarded == 1)
        #expect(!changes.hasChanges)
    }
}
