# Chirogra: resumen para empezar el siguiente chat (16-nov-2026)

Lee esto primero y después [CONTEXTO.md](CONTEXTO.md), que tiene el detalle («Dónde nos quedamos» y «Siguiente»).
**Al usuario se le habla siempre en español.**

## Estado

- **Ramas:** `version-1.3` en `f99bd71` (builds 47 y 48) y `main` en `c5f687d` (limpieza del 16-nov; sin los dos
  commits de los builds, que no tocan la web). Las dos empujadas el 16-nov y la carpeta limpia. La web (`sitio/`) se
  publica desde `main`.
- **Último build: 49 (1.3.0)**, subido a TestFlight para iOS y macOS el 16-nov (noche). Antes, el 48, subido el 16-nov. **El usuario lo está probando** y lo usa
  para los testers de Userbrain. El 47 también se subió el 16-nov.
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
| 47 | `1f96a17` | 1.3.0: **el alta ya no se vacía al salir y volver a la app** (test de Userbrain): `RootView` solo enseña la pantalla de espera de iCloud en la primera importación (`sync.isFirstImport`, antes `isSyncing`, que volvía a ser cierto cada vez que la app volvía al primer plano). |
| 48 | `f99bd71` | 1.3.0: tras el 2.º test de Userbrain: en la factura del iPhone el **precio en su propia fila** (campo con borde) y tocar «Total de la línea» lleva al precio; **«Guardar borrador» con texto** en vez del ✓; **Inicio con cifras en color** (ingresos verde, gastos rojo, ganancia color de marca o rojo si es negativa; también la gráfica y el Mac), «Ganancia del mes» / «Profit this month» y «Sales tax you owe». 346 pruebas. |
| 49 | `292f269` | 1.3.0: arreglos de los testers de Userbrain: 7 días de uso libre, confirmación de factura de $0, «Para guardar, falta: …», franja de iCloud con 20 s de gracia, pista para personalizar la barra, «Se pronuncia «Kairogra»». 346 pruebas. |

## Último chat (16-nov, tarde): testers de Userbrain y builds 47 y 48

- **Testers externos:** el usuario usa **Userbrain** (testers pagados que graban la pantalla y hablan) y TestFlight
  externo con enlace público (lo crea él en App Store Connect). Se le dieron el texto de «What to Test», una tarea
  única para Userbrain y la frase del paso 1 («A simple bookkeeping app for US small businesses to track sales,
  expenses, invoices, and sales tax on iPhone, iPad, and Mac.»).
- **Dos tests vistos (los dos con el build 34).** En el resumen de Userbrain son CS (1.º) y TH (2.º):
  - El alta se vaciaba al salir de la app → **arreglado en el 47** (solo se ve con iCloud real: comprobarlo en TestFlight).
  - La hoja de suscripción asustó al 1.º («It's trying to charge me»), que abandonó. El 2.º siguió tras leer «You will
    not be charged» porque la tarea de Userbrain ya lo explicaba.
  - No encontraba dónde poner el precio de la factura; creía que no se podía guardar sin enviar; calculaba la ganancia
    restando en Banca → **arreglado en el 48** (opción C elegida por el usuario tras ver capturas; la variante de
    recuadros grandes descartada).
  - Pidió asteriscos en los campos obligatorios → **decidido no ponerlos por ahora**: la app ya marca «Opcional». Si
    más testers se pierden, una línea «Falta: …» bajo Continuar.
  - Otros del resumen de Userbrain sin cambio: tipos de negocio que no encajan con algunos sectores (un solo
    comentario) y datos inventados en el alta (normal en un test).
- **Pendientes de decisión del usuario:** si la suscripción deja usar la app un tiempo antes de pedirla (hoy sale al
  crear la empresa, con prueba de 14 días).

## Chat anterior (16-nov, mañana): auditoría y limpieza con 5 agentes

- Pedido del usuario: quitar código muerto, duplicados, archivos y recursos sin uso **sin cambiar nada de lo que hace
  la app**. Cinco agentes en worktrees (Core+Data; tres de ChirograUI por carpetas; recursos/docs/scripts), un revisor
  independiente del diff y unificaciones entre carpetas del coordinador. Rama `limpieza-auditoria`, unida a
  `version-1.3` y `main` (sin build nuevo: lo de la 1.3 ya subido es el 46).
- Quitado: 170 textos del catálogo sin uso (las otras 271 «stale» son textos solo del Mac, **no borrarlas**:
  `sync-strings.sh` solo compila iOS), `scripts/sales-tax-zip.py` (lo sustituyó `scripts/tasas/`), componentes y
  colores sin uso (`FilterChip`, `UnderlineTabs`, `MiniStat`, `HeroCard`, `FlowLayout`, `onBrand`, `outflow`…),
  `Company.shownName` (= `Company.name`), `StatusChip.background` (no se dibujaba). Unificados: `failureAlert`,
  `receiptFileImporter`, `receiptRemovalDialog`, `BillSummarySection`, `BillFilter.matches`, ayudantes de Reportes,
  reparto prorrateado y desglose de sales tax en Core. −268 líneas Swift, catálogo 762 → 709 KB, app iOS −88 KB.
- Comprobado: 346 pruebas, iOS y macOS compilan, 25 pantallas del Mac iguales píxel a píxel antes y después.
- **Arreglo de paso (aprobado por el usuario):** Reportes › Sales tax sacaba las tasas en otro orden en cada arranque
  (líneas de impuesto = relación sin orden); ahora `ReportBuilder.salesTaxSummary` las ordena como `stableOrder`.
- Docs que se ven desactualizados (sin tocar): `README.md` (conciliación y recibos como pendientes, iCloud),
  `DISEÑO.md` («nada implementado»), y `REDISEÑO-NATIVO.md`/`DISEÑO.md` nombran tokens ya borrados.

## Chat de antes (14 y 15-nov)

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

1. **Probar el build 48 en TestFlight** (lo está haciendo): el alta al salir y volver (47), la factura del iPhone,
   «Save draft» e Inicio en color (48); y más testers de Userbrain con el 48. Además: el icono χρ, la animación de la
   bienvenida y la tabla de Clientes del iPad (45 y 46). De paso, lo de las versiones anteriores que no haya probado: código postal en el alta
   (Austin 78702 → 8.25 %), pestañas y favoritos del iPhone (Más › Personalizar), «Seguridad» aparte de «iCloud y
   copias», «Mover dinero», «Borrar todo y empezar de cero». **Ojo:** la 1.2 y la 1.3 pasan los libros del aparato al
   esquema 5 y la 1.1 ya no los abre.
2. **Instalar en el iPad** cuando quiera (desde TestFlight o pidiéndolo).
3. **Avisar cuando Apple apruebe la 1.0**, para preparar el envío de la 1.3.

## Lo siguiente

0. **Build 50: HECHO en `version-1.3` (16-nov, madrugada), SIN COMMITEAR NI SUBIR.** Tras el 5.º tester de Userbrain
   (el primero con el 49; le dio 6–7 sobre 10) y las capturas del usuario del aviso de iCloud, que les salía a todos:
   - **Aviso de iCloud:** franja de una línea con «×» que se cierra en todas las pestañas (`SyncMonitor.dismissBanner`);
     antes de enseñar un fallo se pregunta a CloudKit por la cuenta (`accountStatus`): sin cuenta (o iCloud apagado para
     Chirogra) sale como nota azul «Tus libros se guardan en este aparato», que se cierra para siempre; textos propios
     para iCloud lleno y cuenta por revisar; «Detalles» con dominio y número del error (`failureCode`). Sospecha: los
     testers no tienen iCloud para la app (sin cuenta llega `NSCocoaErrorDomain 134400`, que el 49 no reconocía). Sin
     comprobar en un aparato real: pendiente que el usuario instale el 49/50 en su iPad. QA: `-ChirograForceSync
     sinCuenta|fallo`.
   - **Cobro:** «Marcar como pagada · $X» (parcial: «Registrar cobro de $X»); tocar «Pago · Pendiente» o «Pagada» en
     Actividad lleva al botón (el tester tocaba esos círculos). El cobro funcionaba: reproducido en el simulador.
   - **Precio de la factura:** la barra del teclado (la de «Listo») tapaba la fila del precio y los toques se perdían
     (visto en el simulador); escribiendo la descripción, la barra lleva «Precio», que pasa el foco al precio.
   - «Registrar gasto» en la ficha de una cuenta de Banca (`RecordExpenseButton`), con esa cuenta de pago.
   - «Por cobrar $X» en grande en Ventas; texto de borrar los datos de ejemplo: «No se borra nada tuyo».
   - Comprobado: 346 pruebas, iOS y macOS compilan, catálogo traducido, capturas en ~/Desktop/Chirogra-capturas-50.
0. **Build 49: SUBIDO a TestFlight iOS y macOS (16-nov noche), commit `292f269` en `version-1.3`, sin empujar.** Decisiones del usuario: 7 días de uso
   libre, consejo para personalizar la barra (no cambiar las pestañas de entrada), pronunciación en bienvenida, tienda,
   web y tarea de Userbrain. Lo hecho:
   - **Uso libre de 7 días** (`SubscriptionStore.freeUseDays`): quien nunca se ha suscrito registra sin hoja de planes
     desde su primera empresa (fecha más antigua de los libros, guardada también en el almacén de clave-valor de
     iCloud, `freeUse.start`); después, solo lectura y la hoja dice «Tus 7 días de uso libre terminaron…». Ajustes
     enseña «Uso libre: quedan N días». QA: `-qa.suscripcion libre|nueva`.
   - Los «Primeros pasos» de Inicio pasan por `whenWritable` (por ahí le salió el error al 3.er tester); el error de
     solo lectura ya no dice «terminó» a quien nunca se suscribió (`Bookkeeper.readOnlyCanStartTrial`).
   - **Factura de $0:** «El total de la factura es $0.00» con «Emitir de todos modos» en el editor, el detalle y la
     tabla del Mac (`confirmsZeroTotalIssue`).
   - **Lo que falta:** gasto y factura con el botón siempre activo y aviso «Para guardar, falta: …»
     (`MissingFields`); en el alta, la línea «Para continuar, falta: …» bajo el botón.
   - **iCloud:** la franja de error solo sale si el fallo dura 20 s sin un evento bueno (`SyncMonitor.failureGrace`);
     sin cuenta de iCloud, enseguida y con texto propio («iCloud no está activado»).
   - **Barra del iPhone:** pista `CustomizeTabsTip` arriba de Más (en `TipGroup` con la de Impuestos, de una en una);
     en Personalizar › Pestañas, al añadir, la lista sube a «Así se verá» y vibra.
   - **«Se pronuncia «Kairogra»»** bajo el nombre en la bienvenida (en inglés «Pronounced “KY-roh-grah”»), en la web
     (`sitio/`, se publica al empujar `main`) y en la descripción de la tienda (APP-STORE.md, para el envío de la 1.3).
   - Comprobado: 346 pruebas, catálogo sin textos por traducir, capturas del simulador del iPhone (bienvenida, alta,
     uso libre, pista de Más, gasto incompleto, fin del uso libre); macOS compila. Lo siguiente: que el usuario lo pruebe y más testers de Userbrain con el 49.
   Lo que dijeron los testers (para el registro):
   - **Avisar antes de emitir una factura de $0** («This invoice total is $0.00. Issue anyway?»): el 2.º tester emitió
     una de $0 sin darse cuenta y tuvo que duplicarla.
   - **Avisar antes de emitir una factura de $0** («This invoice total is $0.00. Issue anyway?»): el 2.º tester emitió
     una de $0 sin darse cuenta y tuvo que duplicarla.
   - Lo que salga de los nuevos tests de Userbrain con el 48. **El usuario quiere esperar a más testers y arreglarlo
     todo de una vez** (16-nov). Lo del **3.er tester** (con el 48; factura, gasto y pestañas le resultaron fáciles):
     - **Suscripción (3 de 3 testers tropiezan):** cerró la hoja de planes, al poner el saldo del banco en el alta le
       salió el error «Your books are read-only because your subscription ended» (sin haberse suscrito nunca: el texto
       de `BookkeepingError.readOnly` en `Bookkeeper.swift` no mira `canStartTrial`, y sale como alerta de error en vez
       de abrir la hoja de planes) y tuvo que suscribirse para seguir. Le confundió «Restore» y buscó un código.
       Propuesto: que guardar sin suscripción abra la hoja con «Empieza tu prueba gratis» (eso va seguro), y decidir
       si se deja registrar unos días antes de pedirla. Sin build: decir en la tarea de Userbrain que TestFlight no cobra.
     - **Reportes lejos** (tuvo que ir a Más y bajar): propuesto Ventas, Gastos y Reportes como pestañas de entrada
       (hoy Ventas, Gastos y Banca, `PhoneShortcuts.defaultTabs`), o Reportes como favorito arriba de Más.
     - Comentarios sueltos: el aspecto «más vibrante» y le costó pronunciar «Chirogra». El asistente con IA quedó
       en PLAN-2.0.md, «Ideas por estudiar».
     Lo del **4.º tester** (con el 48, datos de ejemplo; empezó la prueba gratis sin problema tras leer «You will not
     be charged»; Inicio en color le bastó para ver cómo iba el negocio; factura, gasto y pestañas fáciles):
     - **«We couldn't sync your data» nada más empezar.** `SyncMonitor.apply` (`SyncStatusViews.swift`) pone la franja
       con cualquier error de un evento de CloudKit, también los pasajeros que CloudKit reintenta solo. No se sabe el
       código. Propuesto: no enseñarla por errores que se reintentan solos salvo que duren, y un texto propio si no hay
       cuenta de iCloud.
     - **«It doesn't look like it changed it for me»** al cambiar Banca por Presupuesto contra real. **Comprobado en el
       simulador (16-nov): la barra sí cambia al momento** (sale «Budget»). Lo que confunde: la fila añadida desaparece
       de la vista (sube a «En la barra», fuera de pantalla) y en la barra el nombre es otro, más corto. Propuesto:
       al añadir, subir la lista hasta «En la barra» y una vibración.
     - **Campos obligatorios: segunda persona perdida** (en el gasto no sabía por qué no guardaba hasta poner el
       proveedor). Era la condición acordada para poner la línea «Falta: …» bajo el botón.
     - Le costó encontrar cómo registrar el cobro de la factura (al final lo vio en la factura: «user error»).
     - Segunda persona que querría más de 3 pestañas (sin darle importancia).
     - Idea: **citas o agenda con los clientes**, «todo en un solo sitio», como el programa que usa en su negocio.
     - Otra vez le costó pronunciar el nombre («KyraGra», «TriRobra»). **Se pronuncia «Kairogra»** (decisión del
       16-nov, en CONTEXTO); falta decidir dónde decirlo (tarea de Userbrain, bienvenida, tienda, web).
   - **1.4 con agenda y asistente con IA (decidido el 16-nov):** plan en [PLAN-1.4.md](PLAN-1.4.md). Rama
     `version-1.4` aparte; asistente con Claude a través de un servidor Supabase «chirogra» (base del de la 2.0);
     agenda con citas, cita → factura, recordatorios y Calendario. Lo primero: los trámites del usuario (clave de
     Anthropic, proyecto de Supabase) y el canvas de diseño. Decidido: 100 preguntas al mes, citas que se repiten
     desde el principio y el modelo (Opus 5.5 o Sonnet 5.5) tras medir en la QA.
   - Si el usuario lo decide: la suscripción después de un tiempo de uso, no al crear la empresa.
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
