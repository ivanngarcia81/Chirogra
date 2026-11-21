import CommonCrypto
import CryptoKit
import Foundation

// MARK: - Copia con contraseña (revisión externa del 21-nov; decisión del usuario: opcional)
//
// Una copia `.chirogra` lleva los libros enteros y sus adjuntos, también los W-9 de los proveedores (con el TIN o el SSN
// completo). Con contraseña, el archivo de siempre (firma `CHIROGRA-COPIA-1` + JSON con zlib) va cifrado entero:
//
//     «CHIROGRA-CIFRADA-1\n» · sal (16 bytes) · iteraciones (UInt32, big-endian) · AES-GCM combinado (nonce · cifrado · etiqueta)
//
// La clave (256 bits) sale de la contraseña con PBKDF2-HMAC-SHA256 y la sal; la cabecera entera va como dato asociado
// de AES-GCM, así que cambiar un solo byte del archivo hace que no se abra. Sin la contraseña no hay forma de abrirla
// (ni desde soporte). Al descifrar sale la copia de siempre, y el resto (`info`, `restoreCompany`) no cambia.

extension BackupArchive {
    static let encryptedSignature = Data("CHIROGRA-CIFRADA-1\n".utf8)
    /// Iteraciones de PBKDF2 (OWASP 2023 para HMAC-SHA256): unas décimas de segundo en un iPhone.
    public static let defaultKeyIterations: UInt32 = 600_000
    static let saltLength = 16

    /// La copia tiene contraseña (hay que pedirla y abrirla con `decrypt(_:password:)` antes de leerla).
    public static func isEncrypted(_ data: Data) -> Bool {
        data.starts(with: encryptedSignature)
    }

    /// Cifra una copia (lo que devuelve `make`) con la contraseña.
    public static func encrypt(_ backup: Data, password: String, iterations: UInt32 = defaultKeyIterations) throws -> Data {
        guard backup.starts(with: signature) else { throw BackupError.notABackup }
        var salt = Data(count: saltLength)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!) }
        guard status == errSecSuccess else { throw BackupError.damaged }
        let header = encryptedSignature + salt + withUnsafeBytes(of: iterations.bigEndian) { Data($0) }
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let sealed = try AES.GCM.seal(backup, using: key, authenticating: header)
        guard let combined = sealed.combined else { throw BackupError.damaged }
        return header + combined
    }

    /// Abre una copia con contraseña y devuelve la copia de siempre. Una copia sin contraseña se devuelve tal cual.
    public static func decrypt(_ data: Data, password: String) throws -> Data {
        guard isEncrypted(data) else { return data }
        let start = data.startIndex + encryptedSignature.count
        let headerEnd = start + saltLength + 4
        guard data.count > headerEnd - data.startIndex + 28 else { throw BackupError.damaged }
        let salt = data[start..<(start + saltLength)]
        let iterations = data[(start + saltLength)..<headerEnd].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard iterations > 0 else { throw BackupError.damaged }
        let key = try deriveKey(password: password, salt: Data(salt), iterations: iterations)
        do {
            let box = try AES.GCM.SealedBox(combined: data[headerEnd...])
            return try AES.GCM.open(box, using: key, authenticating: data[data.startIndex..<headerEnd])
        } catch {
            throw BackupError.wrongPassword
        }
    }

    static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let passwordData = Data(password.precomposedStringWithCanonicalMapping.utf8)
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self), passwordData.count,
                                         saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                                         derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == kCCSuccess else { throw BackupError.damaged }
        return SymmetricKey(data: derived)
    }
}
