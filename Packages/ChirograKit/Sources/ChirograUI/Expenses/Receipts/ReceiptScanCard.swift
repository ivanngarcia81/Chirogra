import ChirograCore
import ChirograData
import SwiftUI

/// Estado de la lectura del recibo en «Nuevo gasto».
enum ReceiptReadingState: Equatable {
    case idle
    case reading
    case done(ReceiptReading)
}

/// Marca de «Leído del recibo» junto a un campo que se rellenó solo (canvas `ReciboGasto`: chispa en Tinta).
struct ScannedMark: View {
    var body: some View {
        Image(systemName: "sparkle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.brand)
            .accessibilityLabel(Text("Leído del recibo"))
    }
}

/// Etiqueta de un campo con la marca si se leyó del recibo.
struct ScannedLabel: View {
    let title: String
    var subtitle: String? = nil
    var marked: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let subtitle {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(subtitle).font(.footnote).foregroundStyle(Palette.ink2)
                }
            } else {
                Text(title)
            }
            if marked { ScannedMark() }
        }
    }
}

/// Tarjeta «Leído del recibo» (canvas `ReciboGasto`): miniatura, comercio · fecha y cuántos campos se encontraron;
/// «Volver a escanear» (con cámara) y, si el comercio no es un proveedor, «Crear proveedor».
struct ReceiptScanCard: View {
    let state: ReceiptReadingState
    let receipt: ReceiptFile?
    /// El comercio leído no es ninguno de los proveedores: se ofrece crearlo.
    var unmatchedMerchant: String?
    var onRescan: ((ReceiptFile) -> Void)?
    var onCreateVendor: (() -> Void)?
    @State private var scanning = false
    @State private var readingStarted = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                if let receipt {
                    ReceiptThumbnail(data: receipt.data, contentType: receipt.type.identifier, side: 56)
                        .rotationEffect(.degrees(-2))
                }
                VStack(alignment: .leading, spacing: 2) { summary }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            if case .done = state {
                if let unmatchedMerchant, let onCreateVendor {
                    Divider().padding(.vertical, 4)
                    Button(action: onCreateVendor) {
                        Label("Crear proveedor «\(unmatchedMerchant)»", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
                if DocumentScanner.isAvailable, onRescan != nil {
                    Divider().padding(.vertical, 4)
                    Button { scanning = true } label: {
                        Label("Volver a escanear", systemImage: "doc.viewfinder")
                            .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .onChange(of: state == .reading) { _, reading in if reading { readingStarted = .now } }
        #if os(iOS)
        .fullScreenCover(isPresented: $scanning) {
            DocumentScannerView { file in
                scanning = false
                if let file { onRescan?(file) }
            }
            .ignoresSafeArea()
        }
        #endif
    }

    @ViewBuilder
    private var summary: some View {
        switch state {
        case .idle:
            EmptyView()
        case .reading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Leyendo el recibo…").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
            }
            TimelineView(.periodic(from: .now, by: 5)) { context in
                // La primera lectura tras instalar tarda más (el sistema prepara el modelo de texto).
                Text(context.date.timeIntervalSince(readingStarted) > 6
                     ? "La primera vez tarda un poco más: este aparato prepara la lectura. Puedes ir rellenando el resto."
                     : "Todo se lee en este aparato.")
                    .font(.footnote).foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .done(let reading):
            if reading.isEmpty {
                Label("No se pudo leer el recibo", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.warning)
                Text("Escribe los datos a mano; el recibo queda adjunto.").font(.footnote).foregroundStyle(Palette.ink2)
            } else {
                Label { Text("Leído del recibo") } icon: { Image(systemName: "sparkles") }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.brand)
                if let line = Self.headline(reading) {
                    Text(line).font(.subheadline).foregroundStyle(Palette.ink).lineLimit(2)
                }
                Text("\(reading.foundCount) de 4 campos encontrados").font(.footnote).foregroundStyle(Palette.ink2)
            }
        }
    }

    /// «The Home Depot · 29 oct».
    static func headline(_ reading: ReceiptReading) -> String? {
        let parts = [reading.merchant, reading.date?.dayMonth].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
