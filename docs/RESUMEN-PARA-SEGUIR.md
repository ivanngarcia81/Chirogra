# Chirogra: resumen para empezar el siguiente chat (15-nov-2026)

Lee esto primero y después [CONTEXTO.md](CONTEXTO.md), que tiene el detalle («Dónde nos quedamos» y «Siguiente»).
**Al usuario se le habla siempre en español.**

## Estado

- **Ramas:** `main` = `version-1.3` (merge `d083f0c` del 15-nov, más `1eb280f` y `db519c1`), todo empujado y la carpeta
  limpia. La web (`sitio/`) se publica desde `main` y ya enseña la 1.3 y el icono χρ (comprobado en chirogra.com).
- **Último build: 46 (1.3.0)**, subido a TestFlight para iOS y macOS el 15-nov. El 45 (icono χρ) se subió el 14-nov.
- **En App Store Connect:** la **1.0 (build 11)** espera la revisión. **Decidido el 13-nov:** cuando la aprueben se envía
  **directo la 1.3** con su último build, sin la 1.0.1, la 1.1 ni la 1.2, con un «What's New» que junte las tres. El plan
  «Chirogra para contadores» está completo en App Store Connect y va en ese envío (no pulsar «Add for Review» suelto).
- **Aparatos del usuario:** iPhone y Mac con el código del 45 (icono χρ, instalado el 14-nov desde Xcode con iCloud de
  Producción). El 46 no está instalado en ninguno. El iPad sigue sin instalar desde el 41 (lo hace él; no insistir).
- **Plan de la 2.0:** escrito en [PLAN-2.0.md](PLAN-2.0.md) (commit `0f16d46`); el código empieza cuando la 1.3 esté en la
  tienda.

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
| 37 | `e002ed1` | 1.2.0: filas con campo que toman el toque en toda la fila (`.fieldRow()`: descuento, Enviar, presupuesto, plantillas, monto parcial); títulos en los importes de reembolso, nota de crédito y pago de sales tax; «Base: …» en menú con letra de accesibilidad. |
| 38 | `6616919` | 1.2.0: **arreglos de la QA de Hudson** (prueba completa como empresario, contador y auditor; informe en el worktree `Chirogra-QA-Hudson`, carpeta `QA/` sin seguimiento): cierre con motivo obligatorio sin contraseña, «Registrar con fecha» del primer día abierto, «Fijar contraseña y cerrar», «Libros cerrados hasta…» en Inicio, aviso bajo las fechas cerradas y «Cambios después del cierre» (pantalla y paquete del contador); reclasificar lo conciliado sin romper la conciliación; impuesto incluido en $0; fecha al convertir estimado; vencimiento de proveedor; «Saldada: cobrado + crédito»; Total y Saldo en el Mac; alta sin tipo de negocio elegido; guía al día. 330 pruebas; 22/22 controles de Hudson. |
| 39 | `afeb040` | 1.2.0: **pestañas y favoritos a elección en el iPhone** (decisión del usuario del 12-nov): «Más › Personalizar» › Pestañas (entre Inicio y Más, fijos, caben 3 herramientas a elección y en orden) y Favoritos (arriba de Más, sin límite); mantener pulsada una herramienta de Más la añade. Por aparato (`phone.tabs`, `more.favorites`). `Shell/PhoneShortcuts.swift`, guía es/en, `PhoneShortcutsTests` (335 pruebas). |
| 40 | `a2fe01e` | 1.2.0: **Seguridad aparte de iCloud y copias** (pedido del usuario: las dos filas de Más abrían la misma pantalla) y el resto de la QA de Hudson: «Mover dinero» (traspaso, pagar la tarjeta, retiro y aportación) en el «+» de Inicio y en cada cuenta de Banca; ficha de la cuenta con «Entró / Salió»; «Máximo $X (saldo pendiente)» al cobrar; «N ya importados · M nuevos» al reimportar; el ZIP del alta propone el estado; bitácora «Categoría: A → B»; factura con cobros con «Editar» y «Anular» desactivados y el motivo. 338 pruebas. |
| 41 | `ae9ced3` | 1.2.0: **icono nuevo, la χ cursiva** (archivo del usuario «chirogra greek inicials.icon»), también en `LogoMark` (`ChiGlyph`, sacado del SVG), en la animación de la bienvenida (contorno y luego relleno) y en la web. |
| 42 | `36c85ad` | 1.2.0: **lo borrado no vuelve de iCloud**: cada empresa borrada se apunta en el almacén de clave-valor de iCloud (`DeletedCompanies`, permiso `ubiquity-kvstore-identifier` nuevo) y todos los aparatos la vuelven a borrar si alguien la sube otra vez; las automatizaciones esperan a la importación al abrir; **«Borrar todo y empezar de cero…»** en Ajustes › iCloud y copias (escribir BORRAR; espera a que el borrado suba). 343 pruebas. |
| 43 | `809bb88` | 1.2.0: **iconos de color en las subsecciones de la barra lateral** (Mac e iPad; decisión del usuario del 13-nov) y **hoja de planes del Mac** sin los botones de StoreKit encima del segundo plan («Restaurar compras» y «Canjear código» como enlaces, 760 de alto). |
| 44 | `7825510`…`79e8272` | **1.3.0** (rama `version-1.3`): H04 (flechas de periodo en los reportes del iPhone), H19 (antigüedad y conciliaciones en el paquete del contador) y H22 (etiquetas de VoiceOver). |
| 45 | `55add7e` | 1.3.0: icono χρ (χ blanca, ρ azafrán) en la app, la bienvenida y la web. |
| 46 | `786f6fa` | 1.3.0: la tabla de Clientes del iPad ya no pinta su fondo blanco (`.scrollContentBackground(.hidden)`): va sobre el gris de la pantalla y se distingue de la barra lateral (pedido del 15-nov). |

## Último chat (14 y 15-nov)

- **Icono χρ (build 45, `55add7e`, 14-nov):** el `AppIcon.icon` del usuario (χ blanca y ρ azafrán `#F2B33D` sobre el
  degradado índigo) copiado tal cual a `App/AppIcon.icon`. Dentro de la app, `LogoMark` dibuja lo mismo con `ChiGlyph`
  y `RhoGlyph` (`DesignSystem/ChiGlyph.swift`, generados de los dos `<path>` del SVG: si cambia el icono, regenerarlos)
  y `Palette.logoRho`. La bienvenida dibuja el contorno de la χ, luego el de la ρ, y las rellena. También el icono de la
  web y las capturas `bienvenida-es/en.jpg` de la guía. Detalle en CONTEXTO, «Ícono».
- **Build 46 (`786f6fa`, 15-nov):** la tabla de Clientes del iPad ya no pinta su fondo blanco y va sobre el gris de la
  pantalla, distinta de la barra lateral (el usuario las veía del mismo color). Visto en el simulador del iPad, claro y
  oscuro.
- **Ojo para el siguiente chat:** el 14 y el 15-nov trabajaron dos chats a la vez en `version-1.3`. Antes de tocar nada,
  `git fetch` y `git log origin/version-1.3 origin/main` para ver qué hizo el otro.
- **Truco de capturas de la guía en el Mac:** `defaultSize` no bastó para la ventana de 900×1040. Fijarla con
  `defaults write com.chirogra.qa.<nombre> "NSWindow Frame SwiftUI.WindowGroup<ChirograUI.ChirograRootView>-1-AppWindow-1"
  "300 0 900 1040 0 0 1920 1050 "` y arrancar con `-qa.alta 1 -qa.altaEstado TX -qa.altaCiudad Austin
  -qa.altaCiudadTasa 2 -qa.altaZip 78702`; recorte de 600 px de ancho desde (150, 48), 936 de alto en español y 918 en
  inglés.

## Lo que le toca al usuario

1. **Probar el build 46 en TestFlight** (iPhone, iPad y Mac): el icono χρ, el logo y la animación de la bienvenida, y la
   tabla de Clientes del iPad. De paso, lo de las versiones anteriores que no haya probado: código postal en el alta
   (Austin 78702 → 8.25 %), pestañas y favoritos del iPhone (Más › Personalizar), «Seguridad» aparte de «iCloud y
   copias», «Mover dinero», «Borrar todo y empezar de cero». **Ojo:** la 1.2 y la 1.3 pasan los libros del aparato al
   esquema 5 y la 1.1 ya no los abre.
2. **Instalar en el iPad** cuando quiera (desde TestFlight o pidiéndolo).
3. **Avisar cuando Apple apruebe la 1.0**, para preparar el envío de la 1.3.

## Lo siguiente

1. **Cuando aprueben la 1.0: enviar directo la 1.3** (decisión del 13-nov), con su último build. Preparar entonces un
   «What's New» que junte 1.1, 1.2 y 1.3 (las tres partes están en [APP-STORE.md](APP-STORE.md)), las notas para el
   revisor juntas, el plan para contadores en el envío y las capturas (`00-bienvenida` y `06-panel-clientes` en el
   escritorio, y las que falten). **Revisar que las capturas enseñen el logo χρ:** las hechas antes del 14-nov
   llevan la χ sola.
2. **Probar en TestFlight el último build de la 1.3** antes de enviarla.
3. **Tasas por código postal: cada trimestre** (1 ene, 1 abr, 1 jul, 1 oct) correr `scripts/tasas/descargar.sh` y
   `generar.py` y subir un build (DATOS-V5.md). Faltan AL AK AZ CO HI ID LA MO MS NM PA SC VA.
4. **2.0 con servidor:** plan en [PLAN-2.0.md](PLAN-2.0.md). Ya se pueden hacer los trámites (equipo «Chirogra» en
   Plaid con producción y Statements, cotizaciones de Gusto Embedded y Check, perfil en Stripe Connect); el código
   empieza cuando la 1.3 esté en la tienda.

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
