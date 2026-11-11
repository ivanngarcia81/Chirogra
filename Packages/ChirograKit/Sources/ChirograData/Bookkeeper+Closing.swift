import CommonCrypto
import Foundation
import SwiftData

/// Hash de la contraseña de cierre: PBKDF2-HMAC-SHA256 con sal aleatoria de 16 bytes. Se guarda como
/// `pbkdf2-sha256$<iteraciones>$<sal base64>$<hash base64>`; la contraseña nunca se guarda.
public enum ClosingPassword {
    public static let iterations = 120_000
    static let saltLength = 16
    static let keyLength = 32

    public static func hash(_ password: String) -> String {
        var generator = SystemRandomNumberGenerator()
        let salt = Data((0..<saltLength).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        let key = derive(password, salt: salt, iterations: iterations)
        return "pbkdf2-sha256$\(iterations)$\(salt.base64EncodedString())$\(key.base64EncodedString())"
    }

    public static func verify(_ password: String, against stored: String) -> Bool {
        let parts = stored.split(separator: "$").map(String.init)
        guard parts.count == 4, parts[0] == "pbkdf2-sha256", let rounds = Int(parts[1]), rounds > 0,
              let salt = Data(base64Encoded: parts[2]), let expected = Data(base64Encoded: parts[3]) else { return false }
        let key = derive(password, salt: salt, iterations: rounds)
        // Comparación en tiempo constante.
        guard key.count == expected.count else { return false }
        return zip(key, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    static func derive(_ password: String, salt: Data, iterations: Int) -> Data {
        let passwordData = Data(password.utf8)
        var derived = Data(count: keyLength)
        _ = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self), passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), keyLength
                    )
                }
            }
        }
        return derived
    }
}

// MARK: - Cierre de periodo (canvas `MacCierre`)

extension Bookkeeper {

    /// Historial de cierres y reaperturas, del más reciente al más antiguo.
    public func closingHistory() throws -> [PeriodClose] {
        try fetch(PeriodClose.self, sortBy: [SortDescriptor(\.date, order: .reverse)])
    }

    /// Cierra los libros hasta `date` (incluido): desde entonces no se registra nada con esa fecha o anterior.
    /// Solo avanza la fecha de cierre; para retrocederla está `reopenBooks`.
    @discardableResult
    public func closeBooks(through date: Date, note: String = "", device: String = "", calendar: Calendar = .current) throws -> PeriodClose {
        guard let company = try company() else { throw BookkeepingError.noCompany }
        let target = calendar.startOfDay(for: date)
        if let current = company.lockDate, target <= calendar.startOfDay(for: current) {
            throw BookkeepingError.invalidState(String(localized: "Los libros ya están cerrados hasta esa fecha."))
        }
        let record = PeriodClose(isReopen: false, lockDate: target, previousLockDate: company.lockDate, actor: actor, device: device, note: note)
        insert(record)
        company.lockDate = target
        audit("Company", company.id, "closeBooks", String(localized: "Libros cerrados hasta el \(AuditFormat.day(target))"))
        try saveOrRollback()
        return record
    }

    /// Reabre los libros: deja la fecha de cierre en `date` (anterior a la actual) o sin cierre (`nil`).
    /// Si hay contraseña de cierre, hay que darla.
    @discardableResult
    public func reopenBooks(to date: Date?, password: String? = nil, note: String = "", device: String = "",
                            calendar: Calendar = .current) throws -> PeriodClose {
        guard let company = try company() else { throw BookkeepingError.noCompany }
        guard let current = company.lockDate else { throw BookkeepingError.invalidState(String(localized: "Los libros no están cerrados.")) }
        let target = date.map { calendar.startOfDay(for: $0) }
        if let target, target >= calendar.startOfDay(for: current) {
            throw BookkeepingError.invalidState(String(localized: "Para reabrir, la nueva fecha de cierre debe ser anterior a la actual."))
        }
        if company.hasClosingPassword {
            guard let password, ClosingPassword.verify(password, against: company.closingPasswordHash) else {
                throw BookkeepingError.wrongClosingPassword
            }
        }
        let record = PeriodClose(isReopen: true, lockDate: target, previousLockDate: current, actor: actor, device: device, note: note)
        insert(record)
        company.lockDate = target
        audit("Company", company.id, "reopenBooks", String(localized: "Libros reabiertos"))
        try saveOrRollback()
        return record
    }

    /// Fija o cambia la contraseña de cierre. Si ya hay una, hay que dar la actual.
    public func setClosingPassword(_ newPassword: String, current: String? = nil) throws {
        guard let company = try company() else { throw BookkeepingError.noCompany }
        if company.hasClosingPassword {
            guard let current, ClosingPassword.verify(current, against: company.closingPasswordHash) else {
                throw BookkeepingError.wrongClosingPassword
            }
        }
        guard newPassword.count >= 4 else {
            throw BookkeepingError.invalidState(String(localized: "La contraseña de cierre necesita al menos 4 caracteres."))
        }
        company.closingPasswordHash = ClosingPassword.hash(newPassword)
        audit("Company", company.id, "closingPassword", String(localized: "Contraseña de cierre cambiada"))
        try saveOrRollback()
    }

    /// Quita la contraseña de cierre (hay que dar la actual).
    public func removeClosingPassword(current: String) throws {
        guard let company = try company() else { throw BookkeepingError.noCompany }
        guard company.hasClosingPassword else { return }
        guard ClosingPassword.verify(current, against: company.closingPasswordHash) else { throw BookkeepingError.wrongClosingPassword }
        company.closingPasswordHash = ""
        audit("Company", company.id, "closingPassword", String(localized: "Contraseña de cierre quitada"))
        try saveOrRollback()
    }

    /// `true` si la contraseña es la de cierre (o si no hay contraseña).
    public func verifyClosingPassword(_ password: String) throws -> Bool {
        guard let company = try company(), company.hasClosingPassword else { return true }
        return ClosingPassword.verify(password, against: company.closingPasswordHash)
    }
}
