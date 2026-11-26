// Comprueba las pruebas de compra que manda la app (JWS firmados por la App Store).
//
// StoreKit 2 firma cada transacción y el `AppTransaction` con ES256 y pone en la cabecera `x5c` la cadena de
// certificados: hoja → intermedio de Apple → «Apple Root CA - G3». Aquí se comprueba que la raíz es la de Apple (por su
// huella SHA-256, fija), que cada certificado firma al siguiente y estaba vigente al firmar, y luego la firma del JWS
// con la clave de la hoja. Lo que firma Xcode en las pruebas locales («Xcode») no pasa: su raíz no es la de Apple.

// @peculiar/x509 usa tsyringe, que necesita `Reflect.metadata` cargado antes.
import "npm:reflect-metadata@0.2.2";
import * as x509 from "npm:@peculiar/x509@3.1.0";
import { compactVerify, decodeProtectedHeader, importX509 } from "npm:jose@6.2.18";

/// Huella SHA-256 de «Apple Root CA - G3» (https://www.apple.com/certificateauthority/, válido hasta 2039).
const APPLE_ROOT_G3_SHA256 = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";
/// Extensiones que Apple pone en sus certificados: la hoja que firma lo de la App Store y el intermedio WWDR.
const OID_HOJA = "1.2.840.113635.100.6.11.1";
const OID_INTERMEDIO = "1.2.840.113635.100.6.2.1";

export const BUNDLE_ID = "com.chirogra.app";

const hex = (buffer: ArrayBuffer) => [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, "0")).join("");

/// Verifica el JWS y devuelve su contenido. Lanza un error si algo no cuadra.
/// `huellaRaiz` solo cambia en las pruebas, con una cadena hecha a mano.
export async function verificarJWS(jws: string, huellaRaiz = APPLE_ROOT_G3_SHA256): Promise<Record<string, unknown>> {
  const cabecera = decodeProtectedHeader(jws);
  if (cabecera.alg !== "ES256" || !Array.isArray(cabecera.x5c) || cabecera.x5c.length !== 3) {
    throw new Error("cabecera");
  }
  const [hoja, intermedio, raiz] = cabecera.x5c.map((der) => new x509.X509Certificate(der));

  const huella = hex(await crypto.subtle.digest("SHA-256", raiz.rawData));
  if (huella !== huellaRaiz) throw new Error("raiz");
  if (!hoja.getExtension(OID_HOJA) || !intermedio.getExtension(OID_INTERMEDIO)) throw new Error("extensiones");

  // Cada certificado firmado por el siguiente, y vigentes en la fecha de firma (o ahora, si el JWS no la trae).
  const payload = JSON.parse(new TextDecoder().decode(base64url(jws.split(".")[1])));
  const firmadoEl = new Date(typeof payload.signedDate === "number" ? payload.signedDate : Date.now());
  for (const [cert, emisor] of [[hoja, intermedio], [intermedio, raiz], [raiz, raiz]] as const) {
    const valido = await cert.verify({ publicKey: emisor.publicKey, date: firmadoEl });
    if (!valido) throw new Error("cadena");
  }

  const clave = await importX509(hoja.toString("pem"), "ES256");
  const { payload: bytes } = await compactVerify(jws, clave);
  return JSON.parse(new TextDecoder().decode(bytes));
}

function base64url(texto: string): Uint8Array {
  const base64 = texto.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(texto.length / 4) * 4, "=");
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
}

/// Quién pregunta y cuánto puede preguntar.
export type Permiso =
  | { clase: "suscripcion"; clave: string }
  | { clase: "libre"; clave: string };

const PRODUCTOS = new Set(["com.chirogra.app.mensual", "com.chirogra.app.contador.mensual"]);

/// Con la suscripción vigente: 100 preguntas al mes por suscripción (`originalTransactionId`). Sin ella, con el
/// `AppTransaction` de una app auténtica: las 20 preguntas del uso libre, una sola vez por instalación de la cuenta.
export async function permiso(compra: unknown, app: unknown): Promise<Permiso | null> {
  if (typeof compra === "string" && compra.length > 0) {
    try {
      const t = await verificarJWS(compra);
      const vence = typeof t.expiresDate === "number" ? t.expiresDate : 0;
      if (t.bundleId === BUNDLE_ID && PRODUCTOS.has(String(t.productId)) && !t.revocationDate && vence > Date.now()) {
        return { clase: "suscripcion", clave: `sub:${t.originalTransactionId}` };
      }
    } catch (_) {
      // Una compra que no se puede comprobar no da permiso; se mira el uso libre.
    }
  }
  if (typeof app === "string" && app.length > 0) {
    try {
      const a = await verificarJWS(app);
      const id = a.appTransactionId ?? a.deviceVerification;
      if (a.bundleId === BUNDLE_ID && typeof id === "string" && id.length > 0) {
        return { clase: "libre", clave: `libre:${id}` };
      }
    } catch (_) {
      return null;
    }
  }
  return null;
}
