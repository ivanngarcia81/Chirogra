# Servidor de Chirogra

Proyecto de Supabase **«chirogra»** (organización Chirogra, aparte del de Tamio). Por ahora solo tiene el asistente de
la 1.4 (`docs/PLAN-1.4.md` §2).

- `supabase/functions/asistente/`: la función. Pasa la conversación de la app a Claude (`claude-opus-5-5`, esfuerzo
  `low`, con los `fallbacks` del servidor) y devuelve la respuesta. No guarda conversaciones ni nada de los libros.
  - `apple.ts`: comprueba la compra firmada por la App Store (100 preguntas al mes por suscripción) o, en el uso libre,
    el `AppTransaction` (20 preguntas en total).
  - `herramientas.ts`: las herramientas que pide Claude. Las ejecuta la app (`AssistantTools.run`), no el servidor.
  - `prompt.ts`: las instrucciones; `guia.ts` lee la guía de uso de chirogra.com (/guia y /guide) y la guarda en memoria.
- `supabase/migrations/`: el esquema `asistente` (fuera de la API de datos) con el uso por mes.

Secretos del proyecto (Edge Functions › Secrets), nunca en el repo:

- `ANTHROPIC_API_KEY`: la clave de Anthropic «chirogra-asistente» (la puso el usuario el 26-nov).
- `ASISTENTE_PRUEBA`: contraseña de las pruebas de la app Debug (`-qa.asistentePrueba <secreto>`). Se puede borrar.

Comprobar los tipos sin instalar nada en el sistema: `npm i deno` en una carpeta aparte y
`deno check supabase/functions/asistente/index.ts`.
