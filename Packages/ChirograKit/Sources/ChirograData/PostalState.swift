import Foundation

// MARK: - Estado de un código postal (build 40, QA Hudson H13)
//
// En el alta, el código postal 07102 no proponía New Jersey: la tabla de tasas (`PostalTaxTable`) solo tiene 34 estados
// y la sugerencia solo aparecía con una tasa local. Los tres primeros dígitos de un ZIP dicen el estado (rangos del
// USPS), así que se deduce siempre; con la tabla cargada, manda la tabla.

public enum PostalState {

    /// Código de 2 letras del estado de un ZIP («07102» → «NJ»), o `nil` si no son 5 dígitos o el prefijo no es de
    /// ningún estado (territorios y correo militar).
    public static func state(for postalCode: String, table: PostalTaxTable? = nil) -> String? {
        guard let zip = PostalTaxTable.normalized(postalCode) else { return nil }
        if let rate = table?.rate(for: zip) { return rate.state }
        guard let prefix = Int(zip.prefix(3)) else { return nil }
        return ranges.first { $0.range.contains(prefix) }?.state
    }

    /// Prefijos de 3 dígitos por estado. Algunos estados tienen más de un rango (Texas también 885; Georgia 398-399;
    /// Virginia 201; Nueva York 005; Massachusetts 055).
    private static let ranges: [(range: ClosedRange<Int>, state: String)] = [
        (5...5, "NY"), (10...27, "MA"), (28...29, "RI"), (30...38, "NH"), (39...49, "ME"), (50...54, "VT"),
        (55...55, "MA"), (56...59, "VT"), (60...69, "CT"), (70...89, "NJ"), (100...149, "NY"), (150...196, "PA"),
        (197...199, "DE"), (200...200, "DC"), (201...201, "VA"), (202...205, "DC"), (206...219, "MD"),
        (220...246, "VA"), (247...268, "WV"), (270...289, "NC"), (290...299, "SC"), (300...319, "GA"),
        (320...339, "FL"), (341...349, "FL"), (350...369, "AL"), (370...385, "TN"), (386...397, "MS"),
        (398...399, "GA"), (400...427, "KY"), (430...459, "OH"), (460...479, "IN"), (480...499, "MI"),
        (500...528, "IA"), (530...549, "WI"), (550...567, "MN"), (569...569, "DC"), (570...577, "SD"),
        (580...588, "ND"), (590...599, "MT"), (600...629, "IL"), (630...658, "MO"), (660...679, "KS"),
        (680...693, "NE"), (700...715, "LA"), (716...729, "AR"), (730...732, "OK"), (733...733, "TX"),
        (734...749, "OK"), (750...799, "TX"), (800...816, "CO"), (820...831, "WY"), (832...838, "ID"),
        (840...847, "UT"), (850...865, "AZ"), (870...884, "NM"), (885...885, "TX"), (889...898, "NV"),
        (900...961, "CA"), (967...968, "HI"), (970...979, "OR"), (980...994, "WA"), (995...999, "AK"),
    ]
}
