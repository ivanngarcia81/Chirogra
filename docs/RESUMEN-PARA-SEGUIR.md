# Chirogra: resumen para empezar el siguiente chat (13-nov-2026, tarde)

Lee esto primero y después [CONTEXTO.md](CONTEXTO.md), que tiene el detalle («Dónde nos quedamos» y «Siguiente»).
**Al usuario se le habla siempre en español.**

## Estado

- **`main` = `version-1.2`** (unidas el 12-nov, fast-forward pedido por el usuario), empujadas. La web (`sitio/`) se
  publica desde `main`, así que ya enseña la 1.2 (guía e icono nuevo).
- **Último build subido: 43 (1.2.0)**, para iOS y macOS (13-nov, noche): iconos de color en la barra lateral y hoja de planes del Mac (tabla).
  Antes, el **42** (13-nov, tarde): lo borrado ya no vuelve de iCloud y «Borrar todo y empezar de cero». La 1.1 sigue en
  el **30**.
  Para subirlo hubo que contestar en App Store Connect el aviso del DSA de la UE (sin él, «You do not have required
  contracts»); se recomendó «not a trader / no EU».
- **1.0 (build 11):** en revisión de Apple. Cuando la aprueben, el usuario envía la **1.0.1 (build 15)**, que arregla
  iCloud en Producción.
- **1.1.0:** lista en el **build 30**. Lleva toda la fase 2 (decisión del 9-nov) y lo hecho el 10-nov.
- **1.2.0:** lista en el **build 43** (rama `version-1.2`, [DATOS-V5.md](DATOS-V5.md)). Esquema 5 desplegado y probado
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
| 37 | `e002ed1` | 1.2.0: filas con campo que toman el toque en toda la fila (`.fieldRow()`: descuento, Enviar, presupuesto, plantillas, monto parcial); títulos en los importes de reembolso, nota de crédito y pago de sales tax; «Base: …» en menú con letra de accesibilidad. |
| 38 | `6616919` | 1.2.0: **arreglos de la QA de Hudson** (prueba completa como empresario, contador y auditor; informe en el worktree `Chirogra-QA-Hudson`, carpeta `QA/` sin seguimiento): cierre con motivo obligatorio sin contraseña, «Registrar con fecha» del primer día abierto, «Fijar contraseña y cerrar», «Libros cerrados hasta…» en Inicio, aviso bajo las fechas cerradas y «Cambios después del cierre» (pantalla y paquete del contador); reclasificar lo conciliado sin romper la conciliación; impuesto incluido en $0; fecha al convertir estimado; vencimiento de proveedor; «Saldada: cobrado + crédito»; Total y Saldo en el Mac; alta sin tipo de negocio elegido; guía al día. 330 pruebas; 22/22 controles de Hudson. |
| 39 | `afeb040` | 1.2.0: **pestañas y favoritos a elección en el iPhone** (decisión del usuario del 12-nov): «Más › Personalizar» › Pestañas (entre Inicio y Más, fijos, caben 3 herramientas a elección y en orden) y Favoritos (arriba de Más, sin límite); mantener pulsada una herramienta de Más la añade. Por aparato (`phone.tabs`, `more.favorites`). `Shell/PhoneShortcuts.swift`, guía es/en, `PhoneShortcutsTests` (335 pruebas). |
| 40 | `a2fe01e` | 1.2.0: **Seguridad aparte de iCloud y copias** (pedido del usuario: las dos filas de Más abrían la misma pantalla) y el resto de la QA de Hudson: «Mover dinero» (traspaso, pagar la tarjeta, retiro y aportación) en el «+» de Inicio y en cada cuenta de Banca; ficha de la cuenta con «Entró / Salió»; «Máximo $X (saldo pendiente)» al cobrar; «N ya importados · M nuevos» al reimportar; el ZIP del alta propone el estado; bitácora «Categoría: A → B»; factura con cobros con «Editar» y «Anular» desactivados y el motivo. 338 pruebas. |
| 41 | `ae9ced3` | 1.2.0: **icono nuevo, la χ cursiva** (archivo del usuario «chirogra greek inicials.icon»), también en `LogoMark` (`ChiGlyph`, sacado del SVG), en la animación de la bienvenida (contorno y luego relleno) y en la web. |
| 42 | `36c85ad` | 1.2.0: **lo borrado no vuelve de iCloud**: cada empresa borrada se apunta en el almacén de clave-valor de iCloud (`DeletedCompanies`, permiso `ubiquity-kvstore-identifier` nuevo) y todos los aparatos la vuelven a borrar si alguien la sube otra vez; las automatizaciones esperan a la importación al abrir; **«Borrar todo y empezar de cero…»** en Ajustes › iCloud y copias (escribir BORRAR; espera a que el borrado suba). 343 pruebas. |
| 43 | `809bb88` | 1.2.0: **iconos de color en las subsecciones de la barra lateral** (Mac e iPad; decisión del usuario del 13-nov) y **hoja de planes del Mac** sin los botones de StoreKit encima del segundo plan («Restaurar compras» y «Canjear código» como enlaces, 760 de alto). |
| 44 | `7825510`…`79e8272` | **1.3.0** (rama `version-1.3`): H04 (flechas de periodo en los reportes del iPhone), H19 (antigüedad y conciliaciones en el paquete del contador) y H22 (etiquetas de VoiceOver). |

## Último chat (13-nov)

- **1.3.0 (13-nov noche), rama `version-1.3` (empujada; `main` sigue en la 1.2):** H04, H19 y H22 hechos; H23 no se
  reproduce (sin cambios). **Build 44 (1.3.0) subido a TestFlight (iOS y macOS, 13-nov noche).** Detalle en CONTEXTO, «1.3.0». La 1.3 se envía después de la 1.2 (que
  sigue en el build 43). Falta el «What's New» de la 1.3 en APP-STORE.md.
- **Build 43 (13-nov noche, `809bb88`):** (1) **iconos de color en las subsecciones de la barra lateral**
  (decisión del usuario entre Tinta y colores, con muestra real): `SidebarItem.systemImage`/`color` en `Sidebar.swift`,
  los de Reportes y Contabilidad son los de «Más» del iPhone; también en el iPad (compilado, no visto: en vertical la
  barra se cierra). (2) **Hoja de planes del Mac:** StoreKit apilaba «Accept Offer», «Redeem Code» y «Restore» en la
  franja fija de abajo y tapaban el segundo plan; ahora «Restaurar compras» y «Canjear código» son enlaces bajo el texto
  (`macStoreLinks`), la hoja mide 760 (contadores 680) y el encabezado es más compacto. Visto con los planes reales en
  el Mac del usuario (instalado encima, Producción). Para ver la hoja sin empresa hizo falta una compilación de un solo
  uso con `-verPlanes` (no está en el repo): la hoja solo sale sola con una empresa en solo lectura.
- **Lo borrado volvía de iCloud (13-nov, tarde).** El usuario contó que al borrar una empresa o querer empezar de cero,
  la app lo restauraba. En la base del Mac (copia en el scratchpad) se vio que los borrados **sí llegan** por iCloud (el
  Mac recibió el de seis empresas desde el 10-nov); lo que pasa es que otro aparato que aún tiene esos libros los vuelve
  a subir (automatizaciones al abrir antes de recibir el borrado, encender iCloud con libros propios, o borrar los
  datos de iCloud desde los Ajustes del sistema). El usuario eligió hacerlo en la **1.2 (build 42)**. Detalle en
  CONTEXTO, «Build 42». No contestó qué hizo exactamente para «empezar de cero».
  - Comprobado: 343 pruebas (5 nuevas en `DeletedCompaniesTests`), app firmada de iOS y del Mac con el permiso nuevo, y
    en una copia del Mac (`com.chirogra.qa.borrar`, ejecutable renombrado a «ChirograQA» para System Events) la sección,
    la confirmación (BORRAR activa el botón, en minúsculas también), el borrado y las tres hojas (`-qa.empezarDeCero
    subiendo|listo|pendiente`). Subido a TestFlight (iOS y macOS). **Probado entre aparatos:** Saturn LLC borrada en el iPhone desapareció del Mac al abrirlo y no volvió. Para eso hubo que pasar el Mac a iCloud de **Producción** (las instalaciones desde Xcode iban a Development; CONTEXTO, «Instalar en los aparatos»); su base anterior está en `~/Documents/Chirogra-respaldo-Mac-desarrollo-13nov`.
- **Icono nuevo, la χ cursiva, y build 41 (12-nov noche):** `App/AppIcon.icon` = archivo del usuario; `LogoMark` con
  `ChiGlyph` (generado del SVG: si cambia el icono, regenerarlo). Subido iOS y macOS (`ad59089`), instalado en el
  iPhone y el Mac; **el iPad no** (lo hace el usuario).
- **Pendiente pequeño:** las capturas de la guía `copias-es/en.jpg` aún enseñan el bloqueo dentro de «iCloud y copias»
  (desde el build 40 está en Seguridad) y ahora tampoco tienen «Empezar de cero». Los worktrees `Chirogra-pestanas` y
  `Chirogra-QA-Hudson` se borraron el 13-nov (pedido del usuario); el detalle de H04/H19/H22/H23 para la 1.3 quedó en
  CONTEXTO.
- Truco de capturas de la guía: la copia del Mac con `defaultSize` de 900×1040 en `App/ChirograApp.swift` (solo en la
  copia) y `-qa.alta 1 -qa.altaEstado TX -qa.altaCiudad Austin -qa.altaCiudadTasa 2 -qa.altaZip 78702`; recorte de
  600 px de ancho desde (150, 48).
- **Ofrecido y sin empezar:** escribir el plan de la 2.0 con servidor (Plaid, contador dentro de los libros, Stripe,
  nómina). Esperar a que el usuario lo pida.

## Lo que le toca al usuario

1. Esperar la aprobación de la 1.0 y enviar la 1.0.1 (build 15). **Sin decidir (10-nov):** saltarse la 1.0.1 y enviar
   directo la 1.1 (el build 30 ya trae el arreglo de iCloud del 15): ahorra una revisión, pero la 1.1 es más grande y
   puede tardar más. Preguntarle al usuario cuando aprueben la 1.0.
2. Plan **«Chirogra para contadores»**: **completo en App Store Connect** (10-nov), sin enviar. No pulsar «Add for
   Review» suelto: se añade al envío de la 1.1.
3. Probar el **build 30**: con el iPhone en inglés, «Try with sample data» debe dar «Rios Design & Build».
4. Probar el **build 37** en TestFlight: código postal en el alta (Austin 78702 → 8.25 %, Lodi 07644 → 6.625 %),
   «Saltar», «Ocultar» en Inicio, tocar la fila (no la cifra) en el descuento de la factura y en Enviar, bitácora, Dividir y el camino del contador. **Ojo:** instalar la 1.2 pasa los libros
   de ese aparato al esquema 5 y la 1.1 ya no los abre.
5. Instalar el **build 41** en el iPad (él lo hace después) y probarlo en TestFlight (icono nuevo y logo de la bienvenida) y lo del **40**: Más › «iCloud y copias» y «Seguridad» (ya distintas), «+» de Inicio ›
   «Pagar la tarjeta», Banca › una cuenta › ⇆, y el alta con un ZIP sin elegir estado.
6. Probar el **build 39** en TestFlight (iPhone): «Más › Personalizar › Pestañas» (quitar Gastos, poner Asientos de
   diario o un reporte, ordenar, «Restablecer la barra»), «Favoritos», y mantener pulsada una herramienta de Más.

## Lo siguiente

1. **Envío de la 1.1.0** (cuando la 1.0 y la 1.0.1 estén aprobadas): **todo preparado el 10-nov** en
   [APP-STORE.md](APP-STORE.md) (descripción, texto promocional, «What's New» en/es, notas para el revisor) y capturas
   `00-bienvenida` y `06-panel-clientes` en el escritorio. Elegir el **build 30** y añadir el plan para contadores al envío.
2. **Envío de la 1.2.0** (cuando la 1.1 esté aprobada): elegir el **build 43**; «What's New» y notas para el revisor
   preparados el 11-nov en APP-STORE.md. Decidir si hacen falta capturas nuevas (bitácora, Dividir, icono nuevo).
3. **Tasas por código postal: cada trimestre** (1 ene, 1 abr, 1 jul, 1 oct) correr `scripts/tasas/descargar.sh` y
   `generar.py` y subir un build (DATOS-V5.md). Faltan AL AK AZ CO HI ID LA MO MS NM PA SC VA.
4. **2.0 con servidor:** Plaid (plan «Chirogra + Banco»), el contador dentro de los libros del cliente, Stripe (con Apple
   Pay y Google Pay dentro), nómina. Esperar a que la 1.1 esté en la tienda; mientras, se puede escribir el plan.
5. **Menores:** hechos (build 37, 12-nov; CONTEXTO, «C»): las filas con campo que solo tomaban el toque sobre
   la cifra y el selector Devengado/Caja con letra grande. Los textos cortados del Mac eran los datos de ejemplo en
   inglés (build 29). La campana de Avisos y la barra del alta del iPad son del sistema.

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
