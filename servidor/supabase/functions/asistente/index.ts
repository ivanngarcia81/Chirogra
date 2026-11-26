// Función `asistente` (docs/PLAN-1.4.md §2): pasa la conversación de la app a Claude y le devuelve la respuesta.
//
// - No guarda la conversación ni nada de los libros: solo cuenta preguntas, vueltas y tokens (`asistente.uso`).
// - Las herramientas las ejecuta la app: cuando Claude pide una, la respuesta vuelve a la app con `parada: "tool_use"`
//   y la app manda la siguiente petición con los resultados. Cada petición es una vuelta.
// - Quién puede preguntar: la compra firmada por la App Store (`compra`, 100 preguntas al mes por suscripción) o, en
//   el uso libre, el `AppTransaction` firmado (`app`, 20 preguntas en total). Las pruebas de la app Debug mandan la
//   cabecera `x-chirogra-prueba` con el secreto `ASISTENTE_PRUEBA`.
//
// Petición (POST, JSON): { idioma, hoy, aparato, empresa, base, compra?, app?, mensajes, capacidades? }
// `capacidades`: lo que sabe enseñar la app (build 69): «borradores» (tarjetas de registrar con una frase) y
// «pantallas» (botón «Ir a…», más sales_tax y buscar_movimientos).
// Respuesta: { contenido, parada, preguntas: { usadas, limite } } o { error } con el código HTTP del caso.

import Anthropic from "npm:@anthropic-ai/sdk@1.14.0";
import postgres from "npm:postgres@3.4.9";
import { permiso, type Permiso } from "./apple.ts";
import { BORRADORES, HERRAMIENTAS, PANTALLAS } from "./herramientas.ts";
import { contexto, guia, instrucciones } from "./prompt.ts";

const MODELO = "claude-opus-5-5";
const LIMITES = {
  suscripcion: { preguntas: 100, vueltas: 600 },
  libre: { preguntas: 20, vueltas: 120 },
  prueba: { preguntas: 1000, vueltas: 6000 },
} as const;
const MAX_MENSAJES = 60;
const MAX_BYTES = 200_000;

const anthropic = new Anthropic(); // ANTHROPIC_API_KEY, de los secretos del proyecto.
const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 3, prepare: false });

type Cuerpo = {
  idioma?: unknown;
  hoy?: unknown;
  aparato?: unknown;
  empresa?: unknown;
  base?: unknown;
  compra?: unknown;
  app?: unknown;
  mensajes?: unknown;
  capacidades?: unknown;
};

const json = (cuerpo: unknown, estado = 200) =>
  new Response(JSON.stringify(cuerpo), { status: estado, headers: { "Content-Type": "application/json" } });

/// Comparación en tiempo constante para el secreto de las pruebas.
function iguales(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  let d = 0;
  for (let i = 0; i < x.length; i++) d |= x[i] ^ y[i];
  return d === 0;
}

/// La conversación tiene la forma que espera la API: empieza y acaba en el usuario y alterna.
function mensajesValidos(m: unknown): m is Anthropic.Beta.BetaMessageParam[] {
  if (!Array.isArray(m) || m.length === 0 || m.length > MAX_MENSAJES || m.length % 2 === 0) return false;
  return m.every((x, i) =>
    x && typeof x === "object" && (x as { role?: unknown }).role === (i % 2 === 0 ? "user" : "assistant") &&
    (typeof (x as { content?: unknown }).content === "string" || Array.isArray((x as { content?: unknown }).content))
  );
}

/// Una pregunta nueva: el último mensaje del usuario es texto, no los resultados de una herramienta.
function esPreguntaNueva(m: Anthropic.Beta.BetaMessageParam[]): boolean {
  const ultimo = m.at(-1)?.content;
  if (ultimo === undefined || typeof ultimo === "string") return true;
  return !ultimo.some((b) => b.type === "tool_result");
}

const texto = (v: unknown, max: number, porOmision = "") =>
  typeof v === "string" ? v.slice(0, max) : porOmision;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "metodo" }, 405);
  const crudo = await req.text();
  if (crudo.length > MAX_BYTES) return json({ error: "demasiado_largo" }, 413);
  let cuerpo: Cuerpo;
  try {
    cuerpo = JSON.parse(crudo);
  } catch (_) {
    return json({ error: "peticion" }, 400);
  }
  if (!mensajesValidos(cuerpo.mensajes)) return json({ error: "peticion" }, 400);
  const mensajes = cuerpo.mensajes;

  // Quién pregunta.
  let quien: Permiso | { clase: "prueba"; clave: string } | null = null;
  const prueba = req.headers.get("x-chirogra-prueba");
  const secreto = Deno.env.get("ASISTENTE_PRUEBA");
  if (prueba && secreto && iguales(prueba, secreto)) {
    quien = { clase: "prueba", clave: "prueba" };
  } else {
    quien = await permiso(cuerpo.compra, cuerpo.app);
  }
  if (!quien) return json({ error: "suscripcion" }, 403);

  // Cuenta la vuelta, si cabe en el límite.
  const limite = LIMITES[quien.clase];
  const periodo = quien.clase === "libre" ? "total" : new Date().toISOString().slice(0, 7);
  const pregunta = esPreguntaNueva(mensajes);
  const [uso] = await sql`
    select * from asistente.contar(${quien.clave}, ${periodo}, ${pregunta}, ${limite.preguntas}, ${limite.vueltas})`;
  const preguntas = { usadas: uso.usadas as number, limite: limite.preguntas };
  if (!uso.permitido) return json({ error: "limite", clase: quien.clase, preguntas }, 429);

  const idioma = cuerpo.idioma === "en" ? "en" : "es";
  const capacidades = Array.isArray(cuerpo.capacidades) ? cuerpo.capacidades : [];
  const borradores = capacidades.includes("borradores");
  const pantallas = capacidades.includes("pantallas");
  const textoGuia = await guia(idioma);
  try {
    const respuesta = await anthropic.beta.messages.create({
      model: MODELO,
      max_tokens: 8000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: { effort: "low" },
      tools: [...HERRAMIENTAS, ...(pantallas ? PANTALLAS : []), ...(borradores ? BORRADORES : [])],
      system: [
        { type: "text", text: instrucciones(borradores, pantallas) },
        { type: "text", text: textoGuia, cache_control: { type: "ephemeral" } },
        {
          type: "text",
          text: contexto({
            hoy: texto(cuerpo.hoy, 10, new Date().toISOString().slice(0, 10)),
            idioma,
            aparato: texto(cuerpo.aparato, 20, "iPhone"),
            empresa: texto(cuerpo.empresa, 120),
            base: cuerpo.base === "cash" ? "cash" : "accrual",
          }),
        },
      ],
      // La conversación también, para las vueltas siguientes de la misma pregunta.
      cache_control: { type: "ephemeral" },
      messages: mensajes,
    });

    const u = respuesta.usage;
    await sql`select asistente.sumar_tokens(${quien.clave}, ${periodo}, ${u.input_tokens}, ${
      u.cache_creation_input_tokens ?? 0
    }, ${u.cache_read_input_tokens ?? 0}, ${u.output_tokens})`;

    return json({ contenido: respuesta.content, parada: respuesta.stop_reason, preguntas });
  } catch (error) {
    if (error instanceof Anthropic.RateLimitError) return json({ error: "ocupado" }, 503);
    if (error instanceof Anthropic.BadRequestError) {
      console.error("peticion rechazada", error.message);
      return json({ error: "peticion" }, 400);
    }
    console.error("fallo del modelo", error instanceof Anthropic.APIError ? error.status : "", String(error));
    return json({ error: "servidor" }, 502);
  }
});
