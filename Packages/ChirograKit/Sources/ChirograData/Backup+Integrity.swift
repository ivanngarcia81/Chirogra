import CryptoKit
import Foundation

// MARK: - Suma de comprobación de la copia (auditoría del 23-nov)
//
// El formato 1 era la firma y el JSON con zlib, sin nada que compruebe el contenido: el zlib de Apple es DEFLATE sin
// suma propia, y en una prueba con 300 copias sin contraseña con un solo bit cambiado, 80 se restauraban sin aviso con
// datos distintos. Desde el 23-nov el JSON lleva delante la suma SHA-256 del resto:
//
//     {"integrity":"sha256:<64 hex>","info":{…},"payload":{…}}
//
// - Sigue siendo el formato 1 (misma firma, mismo JSON): una versión anterior de Chirogra ignora la clave
//   `integrity` y la restaura igual.
// - Las copias de antes empiezan por `{"info":` (siempre se escribieron con las claves ordenadas): se abren como
//   siempre, sin suma que comprobar.
// - Cualquier otra cosa —la suma no coincide o el principio no es ninguno de los dos— es una copia dañada, y se dice
//   antes de enseñar sus datos o de tocar los libros.
// La suma protege de archivos dañados, no de alguien que edite la copia a propósito (podría rehacer la suma): para eso
// está la contraseña (AES-GCM, `Backup+Encryption.swift`), que autentica el archivo entero.

extension BackupArchive {
    static let integrityPrefix = Data(#"{"integrity":"sha256:"#.utf8)
    static let legacyPrefix = Data(#"{"info":"#.utf8)
    private static let digestLength = 64

    /// El JSON de la copia con su suma delante (ver arriba). `info` y `payload` ya codificados.
    static func sealedJSON(info: Data, payload: Data) -> Data {
        let body = Data(#""info":"#.utf8) + info + Data(#","payload":"#.utf8) + payload + Data("}".utf8)
        return integrityPrefix + Data(hex(SHA256.hash(data: body)).utf8) + Data(#"","#.utf8) + body
    }

    /// `true` si el JSON lleva la suma y coincide, o si es una copia de antes (sin suma); `false` si está dañado.
    static func hasValidIntegrity(_ json: Data) -> Bool {
        if json.starts(with: legacyPrefix) { return true }
        guard json.starts(with: integrityPrefix) else { return false }
        let digestStart = json.startIndex + integrityPrefix.count
        let bodyStart = digestStart + digestLength + 2
        guard json.endIndex > bodyStart, json[(digestStart + digestLength)..<bodyStart].elementsEqual(Data(#"","#.utf8)) else { return false }
        let stored = String(decoding: json[digestStart..<(digestStart + digestLength)], as: UTF8.self)
        return stored == hex(SHA256.hash(data: json[bodyStart...]))
    }

    /// `true` si la copia trae la suma (las de antes del 23-nov no).
    public static func hasChecksum(_ data: Data) -> Bool {
        (try? decompressed(data))?.starts(with: integrityPrefix) ?? false
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
