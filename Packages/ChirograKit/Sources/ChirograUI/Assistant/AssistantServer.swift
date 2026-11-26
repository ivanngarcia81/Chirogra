import ChirograCore
import ChirograData
import Foundation
import StoreKit
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - El servidor del asistente (1.4, docs/PLAN-1.4.md §2; `servidor/supabase/functions/asistente`)
//
// La app manda la conversación en el formato de la API de Claude; el servidor la pasa a Claude y devuelve su
// respuesta. Cuando Claude pide una herramienta, la app la ejecuta aquí con los libros del aparato y manda el
// resultado en la petición siguiente: el servidor nunca ve los libros, solo esas cifras ya sumadas.

/// Un valor JSON cualquiera: los bloques de la respuesta se guardan tal cual para devolverlos en la vuelta siguiente
/// (el pensamiento del modelo y los bloques de herramienta tienen que volver sin cambios).
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { o[key] } else { nil }
    }

    var string: String? {
        if case .string(let s) = self { s } else { nil }
    }
}

/// Lo que contesta el servidor.
struct AssistantReply: Decodable {
    let contenido: [JSONValue]?
    let parada: String?
    let error: String?
    let clase: String?
}

enum AssistantServerError: Error, Equatable {
    case notConfigured
    case offline
    case noSubscription
    /// `freeUse`: se acabaron las 20 preguntas del uso libre; si no, las 100 del mes.
    case limit(freeUse: Bool)
    case busy
    case server
}

enum AssistantServer {
    /// La función `asistente` del proyecto de Supabase «chirogra».
    static let endpoint = URL(string: "https://nybetiuxfzkbfoijssfo.supabase.co/functions/v1/asistente")

    static var isConfigured: Bool { endpoint != nil }

    struct Request: Encodable {
        let idioma: String
        let hoy: String
        let aparato: String
        let empresa: String
        let base: String
        let compra: String?
        let app: String?
        let mensajes: [JSONValue]
    }

    static func send(_ request: Request) async throws -> AssistantReply {
        guard let endpoint, isConfigured else { throw AssistantServerError.notConfigured }
        var urlRequest = URLRequest(url: endpoint, timeoutInterval: 90)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        #if DEBUG
        // `-qa.asistentePrueba <secreto>`: las pruebas sin compra de verdad (simulador, copia del Mac). Solo Debug.
        if let secret = UserDefaults.standard.string(forKey: "qa.asistentePrueba"), !secret.isEmpty {
            urlRequest.setValue(secret, forHTTPHeaderField: "x-chirogra-prueba")
        }
        #endif
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw AssistantServerError.offline
        }
        let reply = try? JSONDecoder().decode(AssistantReply.self, from: data)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200 where reply?.contenido != nil: return reply!
        case 403: throw AssistantServerError.noSubscription
        case 429: throw AssistantServerError.limit(freeUse: reply?.clase == "libre")
        case 503: throw AssistantServerError.busy
        default: throw AssistantServerError.server
        }
    }

    /// La compra firmada de la suscripción vigente, si la hay.
    static func purchaseProof() async -> String? {
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result, SubscriptionStore.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                return result.jwsRepresentation
            }
        }
        return nil
    }

    /// La prueba firmada de que la app es la de la App Store (para el uso libre, sin suscripción).
    static func appProof() async -> String? {
        (try? await AppTransaction.shared)?.jwsRepresentation
    }

    static var deviceName: String {
        #if os(macOS)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    static var languageCode: String {
        Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true ? "en" : "es"
    }
}
