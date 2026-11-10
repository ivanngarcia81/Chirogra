# Chirogra: resumen para empezar el siguiente chat (10-nov-2026)

Lee esto primero y después [CONTEXTO.md](CONTEXTO.md), que tiene el detalle («Dónde nos quedamos» y «Siguiente»).
**Al usuario se le habla siempre en español.**

## Estado

- `main` está empujado hasta el commit de este resumen. Último build subido: **27** (`7095e90`), para iOS y macOS.
- **1.0 (build 11):** en revisión de Apple. Cuando la aprueben, el usuario envía la **1.0.1 (build 15)**, que arregla
  iCloud en Producción.
- **1.1.0:** lista en el **build 27**. Lleva toda la fase 2 (decisión del 9-nov) y lo hecho el 10-nov:

| Build | Commit | Qué trae |
|---|---|---|
| 22 | `3662619` | Bienvenida en carrusel animado (opción B del canvas «Chirogra — Bienvenida»). |
| 23 | `5473946` | Panel de clientes del plan para contadores (canvas del usuario «Chirogra — Panel de clientes», encargo en [PANEL-CLIENTES.md](PANEL-CLIENTES.md)). |
| 24 | `d7c2e0a` | «Reclasificar gastos…» en lote; tasa al cambiar de estado en Ajustes; errores del alta visibles; aviso 1099 del Mac; Puerto Rico 10.5 % comprobado. |
| 25 | `f23f5a7` | Arreglos de la QA con tres agentes (iPhone, iPad y copia del Mac): «+» de Inicio en solo lectura, gráfica de Inicio, «Por cobrar» filtrado, ventana del Mac, panel, textos y plurales. |
| 26 | `eccaaa9` | Tarjeta del mes de Gastos con la base de Inicio (decisión del 10-nov, cambia la del 2-nov), letra grande, tasas en orden estable, signo «−», «Seguridad» en Más. |
| 27 | `7095e90` | «With receipt» en el filtro de Gastos en inglés (faltaba en el catálogo) y prueba que exige en el catálogo las etiquetas de los enums. |

## Lo que le toca al usuario

1. Esperar la aprobación de la 1.0 y enviar la 1.0.1 (build 15).
2. Terminar el plan **«Chirogra para contadores»** en App Store Connect (en borrador, con su captura de revisión):
   textos en/es (`Chirogra for Accountants` / `Unlimited businesses, each with its own books.`; `Chirogra para
   contadores` / `Empresas sin límite, cada una con sus libros.`), disponibilidad, comprobar $99.99 y 2 semanas gratis,
   y pasarlo al **nivel 1** del grupo. No pulsar «Add for Review»: se envía con la 1.1.
3. Probar el build 27 en TestFlight. Si sale «solo lectura», suscribirse ahí es gratis (compra de prueba).

## Lo siguiente

1. **Envío de la 1.1.0** (cuando la 1.0 y la 1.0.1 estén aprobadas): capturas nuevas (carrusel y panel), notas
   «What's New» en/es, notas para el revisor y el plan para contadores en el mismo envío.
2. **1.2** (cambia el esquema de iCloud: desplegar a Producción y probar): asientos de ajuste del contador, bitácora
   de cambios, dividir movimientos del banco y motivo al excluir.
3. **2.0 con servidor:** Plaid (plan «Chirogra + Banco»), el contador dentro de los libros del cliente, Stripe, nómina.
4. **Menores sin hacer** (CONTEXTO, punto 6b): selector Devengado/Caja con letra grande, textos cortados en el Mac,
   datos de ejemplo en español con la app en inglés. La campana de Avisos y la barra del alta del iPad son del sistema.

## Cómo se trabaja con este usuario

- Commit, push y subir builds **solo cuando lo pida**.
- Probar en copias, nunca en sus datos: simuladores `B8931A17` (iPhone) y `ADB9E3BB` (iPad); en el Mac, una copia con
  otro bundle id, firmada ad hoc y sin iCloud. **No tocar el simulador `BEB1EA39`** (es de Tamio).
- No mover el ratón del Mac, no cambiar ajustes del sistema ni de Xcode, no buscar claves, avisar antes de borrar.
- En su iPhone, para enseñarle algo sin tocar su app: la copia «Chirogra Prueba» (`com.chirogra.qa.bienvenida`).
- Para decisiones de diseño, mostrarle muestras reales (capturas de la app) antes de cambiar algo que él ya decidió.
- Subir un build: `CURRENT_PROJECT_VERSION` en `project.yml` y en el pbxproj, clon limpio del commit, `xcodebuild
  archive` y `-exportArchive` (CONTEXTO, «Subir un build»).
