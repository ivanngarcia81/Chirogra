import ChirograData
import SwiftUI

// MARK: - Cómo protege Chirogra tus libros (tras el build 55)
//
// Eric (Beta Family, build 55): «no me dieron ninguna explicación de seguridad… si algo se filtra, la culpa es mía».
// Página de solo lectura que cuenta, en llano, dónde están los datos, quién puede abrirlos, qué queda registrado, las
// copias y qué sale del aparato. Cada frase sale de lo que hace el código (no promete nada más): ver el informe del
// cambio. Se abre desde Seguridad (arriba) y el recorrido de Más la señala una vez.

/// «Cómo protege Chirogra tus libros»: lo que hace la app para cuidar los datos y lo que queda en manos del usuario.
struct BooksProtectionView: View {
    @AppStorage(ChirograStore.syncEnabledKey) private var iCloudSyncEnabled = true
    @AppStorage("appLockEnabled") private var appLockEnabled = false

    var body: some View {
        SettingsForm {
            SettingsSection {
                row("iphone", Palette.blue,
                    title: String(localized: "En tus aparatos"),
                    detail: String(localized: "Tus libros se guardan en este aparato. Chirogra no tiene servidores propios, así que nosotros no podemos verlos."))
                row("icloud.fill", Palette.teal,
                    title: String(localized: "En tu iCloud, si lo activas"),
                    status: iCloudSyncEnabled ? String(localized: "Activado · iPhone, iPad y Mac") : String(localized: "Solo en este dispositivo"),
                    detail: String(localized: "Con «Sincronizar con iCloud», viajan cifrados a la base privada de tu cuenta de iCloud para llegar a tu iPhone, iPad y Mac. Sin ella, se quedan solo en este aparato."))
            } header: {
                SectionLabel(text: String(localized: "Dónde están"))
            }

            SettingsSection {
                row("faceid", Palette.green,
                    title: String(localized: "Bloqueo de la app"),
                    status: appLockEnabled ? String(localized: "Activado") : String(localized: "Desactivado"),
                    detail: String(localized: "Si lo activas en Seguridad, Chirogra pide Face ID, Touch ID o el código del aparato cada vez que vuelves a ella."))
            } header: {
                SectionLabel(text: String(localized: "Quién puede abrirlos"))
            } footer: {
                Text("Chirogra no pide cuenta ni contraseña para entrar: lo protegen el código de tu aparato y tu cuenta de Apple. No los compartas.")
            }

            SettingsSection {
                NavigationLink { AuditLogView() } label: {
                    HStack(spacing: 0) {
                        row("clock.arrow.circlepath", Palette.orange,
                            title: String(localized: "Bitácora de cambios"),
                            detail: String(localized: "Cada cambio queda anotado: qué cambió, cuándo y en qué aparato. Desde la app no se puede editar ni quitar una anotación."))
                        #if os(macOS)
                        // En el Mac la fila no la dibuja un `Form`: la flecha la pone la fila.
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.chevron)
                            .accessibilityHidden(true)
                        #endif
                    }
                    .contentShape(Rectangle())
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
                row("arrow.uturn.backward.circle", Palette.blue,
                    title: String(localized: "Lo contabilizado no se borra"),
                    detail: String(localized: "Si una corrección cambia la contabilidad de una factura emitida o de un gasto, Chirogra revierte su asiento y registra uno nuevo; el original sigue en el diario. Una factura emitida no se borra: se anula."))
                row("lock.fill", Palette.gray,
                    title: String(localized: "Meses cerrados"),
                    detail: String(localized: "Registrar en un mes cerrado pide la contraseña de cierre o, si no la fijaste, un motivo. Esa autorización también queda en la bitácora."))
            } header: {
                SectionLabel(text: String(localized: "Qué queda registrado"))
            }

            SettingsSection {
                row("externaldrive.fill.badge.plus", Palette.green,
                    title: String(localized: "Un archivo que guardas tú"),
                    detail: String(localized: "En iCloud y copias creas un archivo .chirogra con tus libros y recibos. No lleva contraseña: guárdalo en un sitio de confianza. Antes de restaurar una copia, Chirogra guarda lo que tenías para poder deshacerlo."))
            } header: {
                SectionLabel(text: String(localized: "Copias de seguridad"))
            }

            SettingsSection {
                row("paperplane.fill", Palette.indigo,
                    title: String(localized: "Solo lo que tú envías"),
                    detail: String(localized: "Chirogra no tiene analíticas ni publicidad y no manda tus libros a ningún servidor nuestro. Sale lo que tú compartes (facturas, reportes y copias) y, si la activas, la sincronización con iCloud."))
                row("doc.text.viewfinder", Palette.teal,
                    title: String(localized: "Recibos y extractos"),
                    detail: String(localized: "Los recibos se leen en el propio aparato. Chirogra no se conecta a tu banco: los extractos los importas tú desde un archivo."))
                if let url = ChirograLinks.privacyPolicy {
                    Link(destination: url) {
                        HStack(spacing: 12) {
                            IconTile(systemImage: "hand.raised.fill", foreground: Palette.blue)
                            Text("Política de privacidad").foregroundStyle(Palette.ink)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.ink2)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
                    .accessibilityHint(Text("Se abre en el navegador"))
                }
            } header: {
                SectionLabel(text: String(localized: "Qué sale del aparato"))
            } footer: {
                Text("La suscripción la cobra Apple: Chirogra nunca ve tu tarjeta.")
            }
        }
        .screenBackground()
        .navigationTitle("Cómo protege Chirogra tus libros")
        .inlineTitle()
    }

    /// Una fila de la página: icono de color, el título, un estado opcional (activado o no) y la explicación.
    private func row(_ symbol: String, _ color: Color, title: String, status: String? = nil, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemImage: symbol, foreground: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).foregroundStyle(Palette.ink)
                if let status {
                    Text(status).font(.footnote.weight(.medium)).foregroundStyle(Palette.ink2)
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Fila de arriba de Seguridad que abre `BooksProtectionView`.
struct BooksProtectionLink: View {
    var body: some View {
        NavigationLink { BooksProtectionView() } label: {
            HStack(spacing: 12) {
                IconTile(systemImage: "lock.shield.fill", foreground: Palette.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cómo protege Chirogra tus libros").foregroundStyle(Palette.ink)
                    Text("Dónde están tus datos, quién los ve y qué queda registrado.")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                #if os(macOS)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.chevron)
                    .accessibilityHidden(true)
                #endif
            }
            .contentShape(Rectangle())
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }
}
