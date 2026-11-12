# Chirogra: resumen para empezar el siguiente chat (11-nov-2026)

Lee esto primero y después [CONTEXTO.md](CONTEXTO.md), que tiene el detalle («Dónde nos quedamos» y «Siguiente»).
**Al usuario se le habla siempre en español.**

## Estado

- **Dos ramas, las dos empujadas:**
  - `main` llega hasta la **1.1** (build 30, `e56f45c`) y la web (`sitio/`).
  - `version-1.2` llega hasta el **build 36** (`08a6367`) y estos documentos al día. Hasta que se una a `main` (cuando
    salga la 1.1), **los documentos al día están en `version-1.2`**; los de `main` se quedaron en el 10-nov.
- **Último build subido: 36 (1.2.0)**, para iOS y macOS (11-nov). La 1.1 sigue en el **30**.
- **1.0 (build 11):** en revisión de Apple. Cuando la aprueben, el usuario envía la **1.0.1 (build 15)**, que arregla
  iCloud en Producción.
- **1.1.0:** lista en el **build 30**. Lleva toda la fase 2 (decisión del 9-nov) y lo hecho el 10-nov.
- **1.2.0:** lista en el **build 36** (rama `version-1.2`, [DATOS-V5.md](DATOS-V5.md)). Esquema 5 desplegado y probado
  en Producción. Textos para la tienda en [APP-STORE.md](APP-STORE.md), «Versión 1.2.0».

| Build | Commit | Qué trae |
|---|---|---|
| 22 | `3662619` | Bienvenida en carrusel animado (opción B del canvas «Chirogra — Bienvenida»). |
| 23 | `5473946` | Panel de clientes del plan para contadores (canvas del usuario «Chirogra — Panel de clientes», encargo en [PANEL-CLIENTES.md](PANEL-CLIENTES.md)). |
| 24 | `d7c2e0a` | «Reclasificar gastos…» en lote; tasa al cambiar de estado en Ajustes; errores del alta visibles; aviso 1099 del Mac; Puerto Rico 10.5 % comprobado. |
| 25 | `f23f5a7` | Arreglos de la QA con tres agentes (iPhone, iPad y copia del Mac): «+» de Inicio en solo lectura, gráfica de Inicio, «Por cobrar» filtrado, ventana del Mac, panel, textos y plurales. |
| 26 | `eccaaa9` | Tarjeta del mes de Gastos con la base de Inicio (decisión del 10-nov, cambia la del 2-nov), letra grande, tasas en orden estable, signo «−», «Seguridad» en Más. |
| 27 | `7095e90` | «With receipt» en el filtro de Gastos en inglés (faltaba en el catálogo) y prueba que exige en el catálogo las etiquetas de los enums. |
| 28 | `b379921` | Panel de clientes: fila elegida legible (blanco sobre Tinta) y columnas Sales tax, Avisos y Última actividad sin cortar. |
| 29 | `713ecd2` | Con la app en inglés, la empresa de ejemplo sale en inglés («Rios Design & Build»), también con la región en español. |
| 30 | `e56f45c` | Tarjeta de deducibles de Impuestos: «Export for My Accountant…» ya no se parte en tres líneas (iPad) ni se corta (Mac); si no caben, los botones van uno debajo del otro. **Último de la 1.1.** |
| 31 | `b4d04c5` | **Versión 1.2.0** (rama `version-1.2`): ajustes del contador, bitácora de cambios, Dividir y motivo al excluir. Esquema 5 desplegado y probado en Producción. |
| 32 | `0b4137d` | 1.2.0: la última página de la bienvenida pregunta «¿Para quién llevas los libros?»; camino del contador (canvas «Chirogra — Contadores», opción A). |
| 33 | `87e7a39` | 1.2.0: arreglos de la QA con tres agentes (11-nov): campos de Banca que no tomaban el toque (`labeledField` con el estilo del sistema), Dividir con cuenta e importe en filas separadas, filtro «Del contador» en el diario del iPhone y el iPad, bitácora con fechas «5 nov 2026», «−$» y estados de estimado en palabras, textos de Excluir y del alta del contador, letra grande en la bienvenida. |
| 34 | `e802c4b` | 1.2.0: «Saltar» de la bienvenida del iPhone y el iPad en cápsula de vidrio (el usuario no lo veía como texto suelto). |
| 35 | `a89b78f` | 1.2.0: «Ocultar» / «Mostrar» en los «Primeros pasos» de Inicio también sin movimientos (`homeSetupStepsHidden`, por aparato). |
| 36 | `3e50675` | 1.2.0: **sales tax por código postal dentro de la app**: 27,583 ZIP en 34 estados (24 con tasa de condado y ciudad, 10 solo con la del estado). Se sugiere en el alta, en Ajustes y en el cliente. `scripts/tasas/`, DATOS-V5.md. |

## Lo que le toca al usuario

1. Esperar la aprobación de la 1.0 y enviar la 1.0.1 (build 15). **Sin decidir (10-nov):** saltarse la 1.0.1 y enviar
   directo la 1.1 (el build 30 ya trae el arreglo de iCloud del 15): ahorra una revisión, pero la 1.1 es más grande y
   puede tardar más. Preguntarle al usuario cuando aprueben la 1.0.
2. Plan **«Chirogra para contadores»**: **completo en App Store Connect** (10-nov), sin enviar. No pulsar «Add for
   Review» suelto: se añade al envío de la 1.1.
3. Probar el **build 30**: con el iPhone en inglés, «Try with sample data» debe dar «Rios Design & Build».
4. Probar el **build 36** en TestFlight: código postal en el alta (Austin 78702 → 8.25 %, Lodi 07644 → 6.625 %),
   «Saltar», «Ocultar» en Inicio, bitácora, Dividir y el camino del contador. **Ojo:** instalar la 1.2 pasa los libros
   de ese aparato al esquema 5 y la 1.1 ya no los abre.

## Lo siguiente

1. **Envío de la 1.1.0** (cuando la 1.0 y la 1.0.1 estén aprobadas): **todo preparado el 10-nov** en
   [APP-STORE.md](APP-STORE.md) (descripción, texto promocional, «What's New» en/es, notas para el revisor) y capturas
   `00-bienvenida` y `06-panel-clientes` en el escritorio. Elegir el **build 30** y añadir el plan para contadores al envío.
2. **Envío de la 1.2.0** (cuando la 1.1 esté aprobada): elegir el **build 36**; «What's New» y notas para el revisor
   preparados el 11-nov en APP-STORE.md. Antes, unir `version-1.2` a `main` (la web se publica desde `main`) y decidir
   si hacen falta capturas nuevas (bitácora, Dividir).
3. **Tasas por código postal: cada trimestre** (1 ene, 1 abr, 1 jul, 1 oct) correr `scripts/tasas/descargar.sh` y
   `generar.py` y subir un build (DATOS-V5.md). Faltan AL AK AZ CO HI ID LA MO MS NM PA SC VA.
4. **2.0 con servidor:** Plaid (plan «Chirogra + Banco»), el contador dentro de los libros del cliente, Stripe (con Apple
   Pay y Google Pay dentro), nómina. Esperar a que la 1.1 esté en la tienda; mientras, se puede escribir el plan.
5. **Menores sin hacer** (CONTEXTO, punto 6b y «C»): selector Devengado/Caja con letra grande, textos cortados en el
   Mac, y los `MoneyField` dentro de `LabeledContent` (descuento de la factura, «Para» de Enviar, presupuesto) que
   solo toman el toque sobre la cifra. La campana de Avisos y la barra del alta del iPad son del sistema.

## Cómo se trabaja con este usuario

- Commit, push y subir builds **solo cuando lo pida**.
- Probar en copias, nunca en sus datos: simuladores `B8931A17` (iPhone) y `ADB9E3BB` (iPad); en el Mac, una copia con
  otro bundle id, firmada ad hoc y sin iCloud. **No tocar el simulador `BEB1EA39`** (es de Tamio).
- No mover el ratón del Mac, no cambiar ajustes del sistema ni de Xcode, no buscar claves, avisar antes de borrar.
- En su iPhone, para enseñarle algo sin tocar su app: la copia «Chirogra Prueba» (`com.chirogra.qa.bienvenida`).
- Para decisiones de diseño, mostrarle muestras reales (capturas de la app) antes de cambiar algo que él ya decidió.
- Subir un build: `CURRENT_PROJECT_VERSION` en `project.yml` y en el pbxproj, clon limpio del commit (`git clone
  --no-local`), `xcodebuild archive` (iOS y macOS, `DEVELOPMENT_TEAM=4N9XEU7F4P -allowProvisioningUpdates`) y
  `-exportArchive` con `method app-store-connect`, `destination upload` (CONTEXTO, «Subir un build»).
- En un simulador nuevo: `-iCloudSyncEnabled NO` (sin cuenta de iCloud, CloudKit cierra la app) y `-qa.suscripcion
  activa` (si no, la pantalla de planes tapa Inicio).
