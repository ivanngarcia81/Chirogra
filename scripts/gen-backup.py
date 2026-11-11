#!/usr/bin/env python3
"""Genera Packages/ChirograKit/Sources/ChirograData/Backup+Generated.swift a partir de los modelos del esquema actual
(los de SchemaV4: SchemaV4Models.swift, SchemaV4Models2.swift y SchemaV4Banking.swift, salvo los que SchemaV5.swift
sustituye: AuditEvent y BankTransaction).

La copia de seguridad (`BackupArchive`, DISEÑO §6.5) guarda cada modelo como un registro `Codable` con todas sus
propiedades guardadas y sus relaciones a uno (por `id`); las relaciones a muchos se rehacen solas por su inversa,
salvo las de muchos a muchos, que se guardan en el lado que declara la inversa. Desde el esquema 4 la copia es de una
empresa: se exportan la empresa y los registros con su `companyID` (`BackupScope`).

Uso: scripts/gen-backup.py   (después de cambiar un modelo; `BackupTests` falla si el archivo no está al día)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Packages/ChirograKit/Sources"
# En orden: un modelo definido en un archivo posterior sustituiría al del anterior.
MODEL_FILES = [SOURCES / "ChirograData/SchemaV4Models.swift", SOURCES / "ChirograData/SchemaV4Models2.swift",
               SOURCES / "ChirograData/SchemaV4Banking.swift", SOURCES / "ChirograData/SchemaV5.swift"]
# Clave en la copia de una propiedad que cambió de nombre en el esquema: así el formato de la copia no cambia y las
# copias de antes se siguen restaurando (y las nuevas, en una versión anterior de la app).
BACKUP_KEYS = {("AuditEvent", "subjectEntity"): "entityName"}
OUT = SOURCES / "ChirograData/Backup+Generated.swift"

ATTRIBUTE_TYPES = {"String", "Int", "Int64", "Bool", "Date", "UUID", "Decimal", "Data", "Double"}


def fail(message):
    sys.exit(f"gen-backup: {message}")


# --- Enumeraciones (para dar un valor cualquiera a los parámetros de los inicializadores) ---
first_case = {}
for path in SOURCES.rglob("*.swift"):
    text = path.read_text()
    for match in re.finditer(r"public enum (\w+)\b[^{]*\{(.*?)\n\}", text, re.S):
        case = re.search(r"^\s*case (\w+)", match.group(2), re.M)
        if case:
            first_case[match.group(1)] = case.group(1)


# --- Modelos ---
class Prop:
    def __init__(self, name, type_, default, inverse):
        self.name, self.default, self.inverse = name, default, inverse
        self.optional = type_.endswith("?")
        base = type_[:-1] if self.optional else type_
        self.many = base.startswith("[")
        self.base = base.strip("[]")
        self.type = type_


class Model:
    def __init__(self, name):
        self.name = name
        self.props = []
        self.init_params = []  # (label, type, has_default)


models = {}
order = []
for path in MODEL_FILES:
    lines = path.read_text().split("\n")
    i = 0
    while i < len(lines):
        if lines[i].strip() == "@Model":
            match = re.match(r"\s*public final class (\w+) \{", lines[i + 1])
            if not match:
                fail(f"no entiendo la clase tras @Model en {path.name}:{i + 2}")
            model = Model(match.group(1))
            if model.name not in models:
                order.append(model.name)
            models[model.name] = model
            depth = 1
            j = i + 2
            pending_inverse = None
            while depth > 0:
                line = lines[j]
                if depth == 1:
                    stripped = line.strip()
                    rel = re.match(r"@Relationship\((.*)\)\s*$", stripped)
                    if rel:
                        inverse = re.search(r"inverse: \\(\w+)\.(\w+)", rel.group(1))
                        pending_inverse = (inverse.group(1), inverse.group(2)) if inverse else None
                    prop = re.match(r"(?:@Relationship\((.*?)\)\s*)?(?:@Attribute\(.*?\)\s*)?public var (\w+): ([^={]+?)(?:\s*=\s*(.+))?$", stripped)
                    if prop and not stripped.endswith("{"):
                        inline = prop.group(1)
                        inverse = pending_inverse
                        if inline:
                            found = re.search(r"inverse: \\(\w+)\.(\w+)", inline)
                            inverse = (found.group(1), found.group(2)) if found else None
                        model.props.append(Prop(prop.group(2), prop.group(3).strip(), prop.group(4), inverse))
                        model.props[-1].key = BACKUP_KEYS.get((model.name, prop.group(2)), prop.group(2))
                        pending_inverse = None
                    elif not rel and stripped and not stripped.startswith("//"):
                        pending_inverse = None
                    init = re.match(r"public init\((.*)\) \{$", stripped)
                    if init and not model.init_params:
                        for param in re.split(r",\s*(?![^\[]*\])", init.group(1)):
                            found = re.match(r"(\w+): ([^=]+?)(\s*=.*)?$", param.strip())
                            model.init_params.append((found.group(1), found.group(2).strip(), bool(found.group(3))))
                depth += line.count("{") - line.count("}")
                j += 1
            i = j
        else:
            i += 1

if len(models) != 39:
    print(f"gen-backup: aviso, {len(models)} modelos (se esperaban 39)", file=sys.stderr)

# --- Clasificación de propiedades ---
for model in models.values():
    for prop in model.props:
        if prop.base in models:
            prop.kind = "toMany" if prop.many else "toOne"
        elif prop.base in ATTRIBUTE_TYPES and not prop.many:
            prop.kind = "attribute"
            if not prop.optional and prop.default is None:
                fail(f"{model.name}.{prop.name} no tiene valor por defecto")
        else:
            fail(f"tipo no admitido: {model.name}.{prop.name}: {prop.type}")


def find(model_name, prop_name):
    for prop in models[model_name].props:
        if prop.name == prop_name:
            return prop
    fail(f"no existe {model_name}.{prop_name}")


# Una relación a muchos se guarda solo si su inversa también es a muchos (muchos a muchos) y la inversa la
# declara este lado; si no, se rehace al poner la relación a uno del otro lado.
for model in models.values():
    for prop in model.props:
        if prop.kind != "toMany":
            continue
        if prop.inverse:
            other = find(*prop.inverse)
            prop.stored = other.kind == "toMany"
        else:
            declaring = [p for p in models[prop.base].props if p.inverse == (model.name, prop.name)]
            if len(declaring) != 1:
                fail(f"{model.name}.{prop.name}: no encuentro su inversa")
            prop.stored = False
            if declaring[0].kind != "toMany":
                pass  # se rehace con la relación a uno del otro lado

# --- Orden de creación: primero los modelos que otros piden en su inicializador ---
def required_parents(model):
    return [t for (_, t, has_default) in model.init_params if not has_default and t in models]


created, creation_order = set(), []
while len(creation_order) < len(order):
    progress = False
    for name in order:
        if name not in created and all(p in created for p in required_parents(models[name])):
            created.add(name)
            creation_order.append(name)
            progress = True
    if not progress:
        fail("dependencia circular entre inicializadores")


def lower_first(text):
    return text[0].lower() + text[1:]


def placeholder(model, label, type_):
    if type_ in models:
        prop = find(model.name, label)
        if prop.kind != "toOne":
            fail(f"{model.name}.init({label}:) no corresponde a una relación a uno")
        return f'try registry.require(registry.{lower_first(type_)}, record.{label}, "{model.name}.{label}")'
    if type_.endswith("?"):
        return "nil"
    if type_.startswith("["):
        return "[]"
    simple = {"String": '""', "Int": "0", "Int64": "0", "Bool": "false", "Date": "Date()", "Decimal": "0", "UUID": "UUID()",
              "Double": "0", "Data": "Data()"}
    if type_ in simple:
        return simple[type_]
    if type_ in first_case:
        return f".{first_case[type_]}"
    fail(f"no sé qué valor pasar a {model.name}.init({label}: {type_})")


def record_type(prop):
    if prop.kind == "attribute":
        return "String" if prop.base == "Decimal" else prop.base
    if prop.kind == "toOne":
        return "UUID"
    return "[UUID]"


out = []
w = out.append
w("// Generado por scripts/gen-backup.py a partir del esquema actual (SchemaV5). No editar a mano: cambia el modelo y vuelve a")
w("// ejecutar el script (BackupTests comprueba que cubre todas las propiedades del esquema).")
w("")
w("import ChirograCore")
w("import Foundation")
w("import SwiftData")
w("")
w("// MARK: - Registros")
w("")
w("extension BackupPayload {")
for name in order:
    model = models[name]
    w(f"    struct {name}Record: Codable {{")
    for prop in model.props:
        if prop.kind == "toMany" and not prop.stored:
            continue
        w(f"        var {prop.key}: {record_type(prop)}?")
    w("    }")
    w("")
out[-1:] = []
w("}")
w("")
w("struct BackupPayload: Codable {")
for name in order:
    w(f"    var {lower_first(name)}: [{name}Record]?")
w("}")
w("")
w("// MARK: - Propiedades cubiertas (para BackupTests)")
w("")
w("extension BackupArchive {")
w("    /// Por entidad, las propiedades del esquema que la copia guarda o rehace por su inversa.")
w("    static let coveredProperties: [String: Set<String>] = [")
for name in order:
    names = ", ".join(f'"{p.name}"' for p in models[name].props)
    w(f'        "{name}": [{names}],')
w("    ]")
w("")
w("    static let modelCount = " + str(len(order)))
w("}")
w("")
w("// MARK: - Exportar")
w("")
w("extension BackupPayload {")
w("    @MainActor")
w("    /// Los registros de la empresa de `scope` (o de todo, sin empresa).")
w("    init(context: ModelContext, scope: BackupScope) throws {")
for name in order:
    model = models[name]
    source = "scope.companies()" if name == "Company" else f"scope.descriptor({name}.self)"
    w(f"        {lower_first(name)} = try context.fetch({source}).map {{ model in")
    w(f"            {name}Record(")
    fields = []
    for prop in model.props:
        if prop.kind == "attribute":
            if prop.base == "Decimal":
                value = f"model.{prop.name}{'?' if prop.optional else ''}.backupString"
            else:
                value = f"model.{prop.name}"
        elif prop.kind == "toOne":
            value = f"model.{prop.name}?.id"
        elif prop.stored:
            value = f"model.{prop.name}?.map(\\.id).sorted {{ $0.uuidString < $1.uuidString }}"
        else:
            continue
        fields.append(f"                {prop.key}: {value}")
    w(",\n".join(fields))
    w("            )")
    w("        }.sorted { ($0.id?.uuidString ?? \"\") < ($1.id?.uuidString ?? \"\") }")
w("    }")
w("")
w("    /// Número de registros por entidad.")
w("    var counts: [String: Int] {")
w("        [")
for name in order:
    w(f'            "{name}": {lower_first(name)}?.count ?? 0,')
w("        ]")
w("    }")
w("}")
w("")
w("// MARK: - Restaurar")
w("")
w("@MainActor")
w("struct BackupRegistry {")
for name in order:
    w(f"    var {lower_first(name)}: [UUID: {name}] = [:]")
w("")
w("    func require<M>(_ table: [UUID: M], _ id: UUID?, _ field: String) throws -> M {")
w("        guard let id, let model = table[id] else { throw BackupError.brokenReference(field) }")
w("        return model")
w("    }")
w("")
w("    func optional<M>(_ table: [UUID: M], _ id: UUID?, _ field: String) throws -> M? {")
w("        guard let id else { return nil }")
w("        guard let model = table[id] else { throw BackupError.brokenReference(field) }")
w("        return model")
w("    }")
w("}")
w("")
w("extension BackupPayload {")
w("    /// Todos los modelos del esquema, para borrar los libros antes de restaurar.")
w("    static let modelTypes: [any PersistentModel.Type] = [")
for name in order:
    w(f"        {name}.self,")
w("    ]")
w("")
w("    /// Crea los modelos en `context` (primero los que otros piden en su inicializador) y después sus relaciones.")
w("    @MainActor")
w("    func insert(into context: ModelContext) throws {")
w("        var registry = BackupRegistry()")
for name in creation_order:
    model = models[name]
    var = lower_first(name)
    args = ", ".join(f"{label}: {placeholder(model, label, type_)}"
                     for (label, type_, has_default) in model.init_params if not has_default)
    w(f"        for record in {var} ?? [] {{")
    w(f"            let model = {name}({args})")
    for prop in model.props:
        if prop.kind != "attribute":
            continue
        if prop.base == "Decimal":
            source = f"record.{prop.key}.flatMap(Decimal.init(backupString:))"
        else:
            source = f"record.{prop.key}"
        if prop.optional:
            w(f"            model.{prop.name} = {source}")
        else:
            w(f"            model.{prop.name} = {source} ?? {prop.default}")
    w("            context.insert(model)")
    w(f"            registry.{var}[model.id] = model")
    w("        }")
for name in order:
    model = models[name]
    rels = [p for p in model.props if p.kind == "toOne" or (p.kind == "toMany" and p.stored)]
    if not rels:
        continue
    var = lower_first(name)
    w(f"        for record in {var} ?? [] {{")
    w(f"            guard let id = record.id, let model = registry.{var}[id] else {{ continue }}")
    for prop in rels:
        table = f"registry.{lower_first(prop.base)}"
        if prop.kind == "toOne":
            w(f'            model.{prop.name} = try registry.optional({table}, record.{prop.name}, "{name}.{prop.name}")')
        else:
            w(f'            model.{prop.name} = try record.{prop.name}.map {{ try $0.map {{ try registry.require({table}, $0, "{name}.{prop.name}") }} }} ?? []')
    w("        }")
w("    }")
w("}")
w("")

OUT.write_text("\n".join(out))
print(f"gen-backup: {OUT.relative_to(ROOT)} ({len(order)} modelos)")
