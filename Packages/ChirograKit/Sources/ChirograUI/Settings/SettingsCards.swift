import SwiftUI

// MARK: - Formulario de Ajustes con tarjetas (build 20)
//
// En iPhone y iPad, `SettingsForm` y `SettingsSection` son el `Form` agrupado y la `Section` del sistema, como antes.
// En el Mac, tarjetas blancas con filo y sombra corta sobre el suelo gris, como Tamio (`Grupo` + `tarjetaMac`): el
// `Form` agrupado del Mac pinta sus secciones en un gris que no se deja cambiar (probados `listRowBackground` en el
// formulario y en la sección, y `backgroundStyle`), y Ajustes se veía plano al lado del resto de la app.
//
// En el Mac las filas no las coloca el formulario, así que aquí se ponen como él: el nombre a la izquierda y el
// control a la derecha (`LabeledContent`, interruptores, `SettingsPicker`, `SettingsField`, `SettingsTextArea`).

/// El formulario de una página de Ajustes. La página pone su fondo (`screenBackground()`) como siempre.
struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        // El `ScrollView` a todo el ancho y el límite de 640 pt dentro: con el `ScrollView` de 640 pt, el Mac pintaba
        // la franja blanca de la barra solo encima del formulario, cortada sobre el suelo gris (prueba del build 20).
        .labeledContentStyle(SettingsRowLabeledContentStyle())
        .toggleStyle(SettingsRowToggleStyle())
        #else
        Form { content }
            .formStyle(.grouped)
        #endif
    }
}

/// Una sección: en el Mac, su rótulo, la tarjeta con una fila por vista (separadas por una línea) y su nota debajo.
/// `plain`: sin tarjeta (avisos de error, la vista previa de la plantilla, el botón «Guardar»).
struct SettingsSection<Content: View, Header: View, Footer: View>: View {
    private let plain: Bool
    private let content: Content
    private let header: Header
    private let footer: Footer

    init(plain: Bool = false, @ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header,
         @ViewBuilder footer: () -> Footer) {
        self.plain = plain
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 7) {
            header.padding(.horizontal, 6)
            if plain {
                content
            } else {
                Group(subviews: content) { rows in
                    if !rows.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                row
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                                if index < rows.count - 1 { Divider().padding(.leading, 14) }
                            }
                        }
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                        .macElevation(cornerRadius: Metrics.cardRadius)
                    }
                }
            }
            footer
                .font(.footnote)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
        }
        #else
        Section { content } header: { header } footer: { footer }
        #endif
    }
}

extension SettingsSection where Header == EmptyView, Footer == EmptyView {
    init(plain: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(plain: plain, content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

extension SettingsSection where Footer == EmptyView {
    init(plain: Bool = false, @ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.init(plain: plain, content: content, header: header, footer: { EmptyView() })
    }
}

extension SettingsSection where Header == EmptyView {
    init(plain: Bool = false, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(plain: plain, content: content, header: { EmptyView() }, footer: footer)
    }
}

/// Un menú de opciones con su nombre: en el Mac, el nombre a la izquierda y el menú a la derecha (fuera del `Form`
/// del sistema el `Picker` los ponía pegados); en iOS, el `Picker` del formulario.
struct SettingsPicker<Selection: Hashable, Options: View>: View {
    let title: LocalizedStringKey
    @Binding var selection: Selection
    @ViewBuilder var options: Options

    init(_ title: LocalizedStringKey, selection: Binding<Selection>, @ViewBuilder options: () -> Options) {
        self.title = title
        _selection = selection
        self.options = options()
    }

    var body: some View {
        #if os(macOS)
        LabeledContent(title) {
            Picker(title, selection: $selection) { options }
                .labelsHidden()
                .fixedSize()
        }
        #else
        Picker(title, selection: $selection) { options }
        #endif
    }
}

/// Un texto de varias líneas (dirección, mensaje, nota al pie, instrucciones). En el Mac, el nombre encima y el campo
/// a todo lo ancho; en iOS, el `TextField` vertical del formulario, como antes.
struct SettingsTextArea: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let prompt: Text
    var lines: ClosedRange<Int> = 2...5

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(Palette.ink)
                .accessibilityHidden(true)
            TextField(title, text: $text, prompt: prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .labelsHidden()
                .lineLimit(lines)
                .accessibilityLabel(Text(title))
        }
        #else
        TextField(title, text: $text, prompt: prompt, axis: .vertical)
            .lineLimit(lines)
            .accessibilityLabel(Text(title))
        #endif
    }
}

#if os(macOS)
/// Fila de nombre y valor: el nombre a la izquierda en Tinta y el valor (o el control) a la derecha, en gris.
struct SettingsRowLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.label
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 12)
            configuration.content
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Interruptor de una fila: lo que dice a la izquierda y el interruptor pegado a la derecha, como en el `Form`.
struct SettingsRowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}
#endif
