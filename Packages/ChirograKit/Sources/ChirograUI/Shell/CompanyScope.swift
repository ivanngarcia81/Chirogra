import ChirograData
import Foundation
import SwiftData
import SwiftUI

// MARK: - Empresa activa en pantalla (varias empresas, docs/DATOS-V4.md §1)
//
// Todas las pantallas ven solo la empresa activa. La raíz (`ChirograRootView`) calcula el ámbito con
// `Bookkeeper.companyScope()` (la activa del aparato, `ActiveCompany`, o la primera del selector) y lo deja en
// `CompanySession.scope` **antes** de dibujar la app; cada `@CompanyQuery` lo lee al crearse y filtra con
// `CompanyScope.predicate(_:)` (que ya incluye los registros sin empresa cuando la activa es la principal).
//
// Al cambiar de empresa, `AppShell` rehace sus pestañas y columnas (`.id` con la empresa): todas las vistas se crean
// de nuevo con el ámbito nuevo, sin restos de la anterior. Las acciones pasan por `Bookkeeper(context:)`, que ya
// trabaja con la misma empresa activa.

/// Empresa con la que trabajan las pantallas. La pone la raíz; `nil` mientras no hay ninguna empresa.
enum CompanySession {
    static var scope: CompanyScope?

    /// Clave para la identidad de las vistas: cambia al cambiar de empresa (o si la principal pasa a ser otra).
    static func key(_ scope: CompanyScope?) -> String {
        scope.map { "\($0.id.uuidString)-\($0.includeOrphans)" } ?? "sin-empresa"
    }

    /// `filter` limitado a la empresa activa (`&&`). Sin empresa, `filter` tal cual.
    static func predicate<T: CompanyOwned>(_ filter: Predicate<T>?) -> Predicate<T>? {
        guard let scope else { return filter }
        let owned = scope.predicate(T.self)
        guard let filter else { return owned }
        return #Predicate<T> { owned.evaluate($0) && filter.evaluate($0) }
    }
}

/// `@Query` de la empresa activa: mismos argumentos que `@Query` (`filter`, `sort` con ruta y orden, o con
/// `SortDescriptor`), y el filtro de la empresa añadido. Se usa en todas las pantallas en vez de `@Query`.
@propertyWrapper
struct CompanyQuery<Element: CompanyOwned>: DynamicProperty {
    @Query private var results: [Element]

    var wrappedValue: [Element] { results }

    init(filter: Predicate<Element>? = nil, sort: [SortDescriptor<Element>] = []) {
        _results = Query(filter: CompanySession.predicate(filter), sort: sort)
    }

    init<Value: Comparable>(filter: Predicate<Element>? = nil, sort keyPath: KeyPath<Element, Value> & Sendable, order: SortOrder = .forward) {
        self.init(filter: filter, sort: [SortDescriptor(keyPath, order: order)])
    }

    init<Value: Comparable>(filter: Predicate<Element>? = nil, sort keyPath: KeyPath<Element, Value?> & Sendable, order: SortOrder = .forward) {
        self.init(filter: filter, sort: [SortDescriptor(keyPath, order: order)])
    }
}

/// La empresa activa como lista de un elemento (las pantallas usan `companies.first`). Sin empresa activa, todas.
@propertyWrapper
struct ActiveCompanyQuery: DynamicProperty {
    @Query private var results: [Company]

    var wrappedValue: [Company] { results }

    init() {
        if let id = CompanySession.scope?.id {
            _results = Query(filter: #Predicate<Company> { $0.id == id })
        } else {
            _results = Query()
        }
    }
}

extension Company {
    /// Nombre para el selector y las listas: el comercial o, si no hay, la razón social.
    var shownName: String { displayName.isEmpty ? legalName : displayName }
}

extension Array where Element == Company {
    /// En el orden del selector (`sortOrder` y después la más antigua), como `Bookkeeper.companies()`.
    var inSelectorOrder: [Company] {
        sorted { ($0.sortOrder, $0.createdAt, $0.id.uuidString) < ($1.sortOrder, $1.createdAt, $1.id.uuidString) }
    }
}

// MARK: - Red de seguridad al guardar

/// Lo que una pantalla inserta con `context.insert` y guarda con `context.save()` (sin pasar por `Bookkeeper`) quedaría
/// sin empresa, y un registro sin empresa cuenta como de la **principal**: con otra empresa activa, el cliente nuevo o
/// las líneas de una factura desaparecerían de la pantalla y `adoptOrphanRecords()` los daría a la empresa equivocada.
/// Antes de cada guardado en el hilo principal, lo insertado sin empresa toma la activa (como hace `Bookkeeper` en los
/// suyos). Lo que trae iCloud de un aparato con la 1.0.x no pasa por aquí (no es un guardado de la app).
enum CompanyStamp {
    private static var observer: (any NSObjectProtocol)?

    static func install() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: ModelContext.willSave, object: nil, queue: nil) { note in
            // Solo los contextos del hilo principal (los de las pantallas y las automatizaciones).
            guard Thread.isMainThread else { return }
            nonisolated(unsafe) let context = note.object as? ModelContext
            MainActor.assumeIsolated {
                if let context { stamp(context) }
            }
        }
    }

    /// Pone la empresa activa a lo insertado sin empresa. Devuelve cuántos cambió.
    @discardableResult
    static func stamp(_ context: ModelContext) -> Int {
        let pending = context.insertedModelsArray.compactMap { $0 as? any CompanyOwned }.filter { $0.companyID == nil }
        guard !pending.isEmpty, let id = CompanySession.scope?.id else { return 0 }
        for model in pending { set(model, id) }
        return pending.count
    }

    private static func set<T: CompanyOwned>(_ model: T, _ id: UUID) { model.companyID = id }
}

// MARK: - Páginas abiertas por código

/// Una página que se abre con `navigationDestination(isPresented:)` no debe crearse de nuevo cada vez que la pila se
/// actualiza. Cada vez que se crea, sus `@CompanyQuery` crean una consulta nueva (el filtro de la empresa es un
/// predicado nuevo), la consulta vuelve a leer, la página cambia, la pila se actualiza y vuelve a crearla: la app
/// quedaba colgada al 100 % de CPU (8-nov: «Abrir Impuestos» de la pista de Más, y `-qa.pestana reports`). Con
/// `StablePage` la página se crea una vez y la pila la reutiliza mientras `key` no cambie.
struct StablePage<Content: View>: View, Equatable {
    let key: AnyHashable
    let content: () -> Content

    init(key: AnyHashable = 0, @ViewBuilder content: @escaping () -> Content) {
        self.key = key
        self.content = content
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }

    var body: some View { content() }
}

extension View {
    /// `navigationDestination(isPresented:)` con la página creada una sola vez (`StablePage`).
    func stableDestination<Destination: View>(isPresented: Binding<Bool>,
                                              @ViewBuilder destination: @escaping () -> Destination) -> some View {
        navigationDestination(isPresented: isPresented) { StablePage(content: destination).equatable() }
    }
}
