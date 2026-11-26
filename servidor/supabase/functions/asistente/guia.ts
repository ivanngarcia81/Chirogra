// La guía de uso de la web (chirogra.com/guia y /guide) en texto plano, para que el asistente conteste «¿cómo hago…?».
//
// Se lee de la web la primera vez que hace falta y se queda en memoria mientras la función siga viva: así la guía del
// asistente es siempre la publicada, sin volver a desplegar. El texto sale igual cada vez (la caché del prompt depende
// de eso). Si la web no responde, el asistente contesta sin guía y se vuelve a intentar en la petición siguiente.

const DIRECCIONES = { es: "https://chirogra.com/guia/", en: "https://chirogra.com/guide/" } as const;
const guardadas = new Map<string, Promise<string>>();

export function leerGuia(idioma: "es" | "en"): Promise<string> {
  let guia = guardadas.get(idioma);
  if (!guia) {
    guia = descargar(DIRECCIONES[idioma]).catch((error) => {
      console.error("guia", String(error));
      guardadas.delete(idioma);
      return "";
    });
    guardadas.set(idioma, guia);
  }
  return guia;
}

async function descargar(direccion: string): Promise<string> {
  const respuesta = await fetch(direccion, { signal: AbortSignal.timeout(5000) });
  if (!respuesta.ok) throw new Error(`HTTP ${respuesta.status}`);
  return textoPlano(await respuesta.text());
}

const ENTIDADES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };

/// La página en texto: títulos con «#», listas con «-», sin menús, estilos ni imágenes.
export function textoPlano(html: string): string {
  let t = html.replace(/<(script|style|header|footer|nav)[^>]*>[\s\S]*?<\/\1>/gi, "");
  t = t.replace(/<img[^>]*>/gi, "");
  t = t.replace(/<h([1-3])[^>]*>/gi, (_, n) => "\n" + "#".repeat(Number(n) + 1) + " ");
  t = t.replace(/<li[^>]*>/gi, "\n- ");
  t = t.replace(/<(p|tr|div|figcaption)[^>]*>/gi, "\n");
  t = t.replace(/<[^>]+>/g, "");
  t = t.replace(/&(#\d+|#x[0-9a-f]+|[a-z]+);/gi, (entidad, nombre: string) => {
    if (nombre.startsWith("#x") || nombre.startsWith("#X")) return String.fromCodePoint(parseInt(nombre.slice(2), 16));
    if (nombre.startsWith("#")) return String.fromCodePoint(parseInt(nombre.slice(1), 10));
    return ENTIDADES[nombre.toLowerCase()] ?? entidad;
  });
  return t.split("\n").map((l) => l.replace(/\s+/g, " ").trim()).filter((l) => l && l !== "-").join("\n");
}
