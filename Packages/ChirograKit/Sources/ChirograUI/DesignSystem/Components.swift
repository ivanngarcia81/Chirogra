import ChirograCore
import ChirograData
import SwiftUI

// MARK: - Formato

extension Int64 {
    /// Centavos → "$1,250.00".
    var money: String { Money(minorUnits: self).formatted() }
}

extension Date {
    var shortDate: String { formatted(.dateTime.day().month(.abbreviated).year()) }
    var dayMonth: String { formatted(.dateTime.day().month(.abbreviated)) }
}

// MARK: - Tipografía

extension Font {
    /// Cifras destacadas (tarjeta de efectivo, totales). El tamaño del canvas se traduce al estilo de texto
    /// más cercano para que escale con Dynamic Type.
    static func amount(_ size: CGFloat) -> Font {
        let style: Font.TextStyle = switch size {
        case 34...: .largeTitle
        case 26..<34: .title
        case 21..<26: .title2
        case 18..<21: .title3
        default: .headline
        }
        return .system(style, weight: .bold).monospacedDigit()
    }
    static let cardTitle = Font.headline
    static let label = Font.caption.weight(.semibold)
}

// MARK: - Superficies

struct CardModifier: ViewModifier {
    var padding: CGFloat = Metrics.cardPadding
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = Metrics.cardPadding) -> some View { modifier(CardModifier(padding: padding)) }

    /// Fondo de pantalla del canvas, en listas y en vistas con scroll.
    func screenBackground() -> some View {
        scrollContentBackground(.hidden).background(Palette.background)
    }

    @ViewBuilder
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

// MARK: - Botones

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
            .padding(.horizontal, 22)
            .foregroundStyle(isEnabled ? Palette.onBrand : Palette.ink3)
            .background(isEnabled ? Palette.brand : Palette.surface2, in: RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
            .padding(.horizontal, 22)
            .foregroundStyle(destructive ? Palette.negative : Palette.brand)
            .background(destructive ? Palette.negativeWash : Palette.brandWash,
                        in: RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static var destructive: SecondaryButtonStyle { SecondaryButtonStyle(destructive: true) }
}

// MARK: - Chips de estado

struct StatusChip: View {
    let text: String
    let foreground: Color
    let background: Color
    var compact = false

    var body: some View {
        Text(text)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .padding(.horizontal, compact ? 8 : 11)
            .padding(.vertical, compact ? 2 : 5)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }
}

extension StatusChip {
    /// Estados de factura del canvas: Borrador, Enviada, Pago parcial, Vencida · N días, Pagada (+ Anulada).
    init(invoice: Invoice, compact: Bool = true) {
        if let days = invoice.daysOverdue() {
            self.init(text: "Vencida · \(days) \(days == 1 ? "día" : "días")", foreground: Palette.negative, background: Palette.negativeWash, compact: compact)
            return
        }
        switch invoice.status {
        case .draft: self.init(text: "Borrador", foreground: Palette.ink2, background: Palette.surface2, compact: compact)
        case .sent: self.init(text: "Enviada", foreground: Palette.brand, background: Palette.brandWash, compact: compact)
        case .partiallyPaid: self.init(text: "Pago parcial", foreground: Palette.warning, background: Palette.warningWash, compact: compact)
        case .paid: self.init(text: "Pagada", foreground: Palette.positive, background: Palette.positiveWash, compact: compact)
        case .void: self.init(text: "Anulada", foreground: Palette.ink3, background: Palette.surface2, compact: compact)
        }
    }

    init(bill: Bill, compact: Bool = true) {
        switch bill.status {
        case .open: self.init(text: "Por pagar", foreground: Palette.brand, background: Palette.brandWash, compact: compact)
        case .partiallyPaid: self.init(text: "Pago parcial", foreground: Palette.warning, background: Palette.warningWash, compact: compact)
        case .paid: self.init(text: "Pagada", foreground: Palette.positive, background: Palette.positiveWash, compact: compact)
        case .void: self.init(text: "Anulada", foreground: Palette.ink3, background: Palette.surface2, compact: compact)
        }
    }
}

// MARK: - Piezas de lista

struct InitialsTile: View {
    let text: String
    var foreground: Color = Palette.brand
    var background: Color = Palette.brandWash
    @ScaledMetric(relativeTo: .subheadline) private var side = Metrics.iconTile

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .frame(width: side, height: side)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct IconTile: View {
    let systemImage: String
    var foreground: Color = Palette.brand
    var background: Color = Palette.brandWash
    @ScaledMetric(relativeTo: .body) private var side = Metrics.iconTile

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.medium))
            .frame(width: side, height: side)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Fila del canvas: icono o iniciales, título, subtítulo e importe con chip opcional.
struct LedgerRow<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text(subtitle).font(.subheadline).foregroundStyle(Palette.ink3).lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.label)
            .tracking(0.6)
            .foregroundStyle(Palette.ink3)
    }
}

struct KPITile: View {
    let title: String
    let value: String
    var note: String? = nil
    var noteColor: Color = Palette.ink3

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3)
            Text(value).font(.amount(17)).foregroundStyle(Palette.ink).minimumScaleFactor(0.7).lineLimit(2)
            if let note { Text(note).font(.caption.weight(.semibold)).foregroundStyle(noteColor) }
        }
        .card(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

/// Tarjeta destacada en color de marca (efectivo disponible, ganancia neta).
struct HeroCard: View {
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.5).opacity(0.85)
            Text(value).font(.amount(38)).tracking(-0.5).minimumScaleFactor(0.6).lineLimit(2)
            if let detail {
                HStack(spacing: 8) {
                    Circle().fill(Palette.accent).frame(width: 8, height: 8)
                    Text(detail).font(.subheadline)
                }
                .opacity(0.9)
            }
        }
        .foregroundStyle(Palette.onBrand)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.brand, in: RoundedRectangle(cornerRadius: Metrics.heroRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Estado vacío / primera vez del canvas.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(Palette.ink3)
            Text(title).font(.headline).foregroundStyle(Palette.ink)
            Text(message).font(.subheadline).foregroundStyle(Palette.ink3).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.secondary).fixedSize()
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// Logotipo de Chirogra: cuadrado en tinta, "C" abierta y punto de azafrán.
struct LogoMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 11 / 40, style: .continuous).fill(Palette.brand)
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(Palette.onBrand, style: StrokeStyle(lineWidth: size * 3.4 / 40, lineCap: .round))
                .frame(width: size * 18 / 40, height: size * 18 / 40)
            Circle().fill(Palette.accent)
                .frame(width: size * 5.4 / 40, height: size * 5.4 / 40)
                .offset(x: size * 8.6 / 40)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Chirogra")
    }
}

// MARK: - Campos

/// Campo de importe en dólares enlazado a centavos.
struct MoneyField: View {
    let title: String
    @Binding var minorUnits: Int64

    var body: some View {
        TextField(title, value: decimal, format: .currency(code: "USD"))
            .monospacedDigit()
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
    }

    private var decimal: Binding<Decimal> {
        Binding(
            get: { Money(minorUnits: minorUnits).decimalValue },
            set: { minorUnits = Money(decimal: $0).minorUnits }
        )
    }
}

/// Selector de cuenta filtrado (p. ej. solo cuentas de dinero o de gasto).
struct AccountPicker: View {
    let title: String
    let accounts: [Account]
    @Binding var selection: UUID?

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Elegir…").tag(UUID?.none)
            ForEach(accounts) { account in
                Text(account.displayName).tag(Optional(account.id))
            }
        }
    }
}

/// Mensaje de error recuperable con texto claro.
struct ErrorBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.negative)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.negativeWash, in: RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous))
    }
}
