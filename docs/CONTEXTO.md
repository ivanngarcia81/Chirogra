# Chirogra: contexto para retomar en otro chat

Resumen del chat de coordinación de Chirogra al **7 de noviembre de 2026**. Léelo entero antes de seguir. El diseño técnico está en [DISEÑO.md](DISEÑO.md), el sistema visual en [REDISEÑO-NATIVO.md](REDISEÑO-NATIVO.md) y la API del esquema 2 en [DATOS-V2.md](DATOS-V2.md); aquí van el estado, las decisiones del usuario, lo pendiente y cómo se trabaja. Al usuario se le habla siempre en español.

## Dónde nos quedamos (empieza aquí)

**7-nov (tarde): BUILD 9 SUBIDO** (iOS y macOS) desde `40bb205` de la rama `build7`. **Todo (builds 6, 7, 8 y 9 y el ícono nuevo, también el de la web `sitio/img/icono.png`) fusionado en `main` y empujado el 7-nov**; la web se publica con ese empuje. **Para revisión, elegir el build 9.** Solo cambia la línea de la factura en el formulario estrecho (iPhone), como la dibujó el usuario: descripción (varias líneas) con precio · «Gravable»; debajo «1 × − +» y la cuenta de ingreso; al final «Total de la línea» (antes el total iba junto a la descripción y se confundía con el precio). El guion v5 solo cambia el encabezado; las notas siguen en `notas8`.

**7-nov (tarde): BUILD 8 SUBIDO** (iOS y macOS, «Upload succeeded») desde `0291565` de la rama local **`build7`** (lleva el build 7 y el ícono nuevo `d5ca398`), **sin fusionar ni empujar**. **Para revisión, elegir el build 8.** Viene de las notas del guion del build 7 (colección `notas7`: todo fácil menos alta y correcciones, regulares). Lleva:
- **Ícono nuevo** (`App/AppIcon.icon`, del `Chirogra 1.icon` del usuario: carpeta con la «C», sin el sello). El ícono de la web (`sitio/img/icono.png`) sigue siendo el viejo.
- **Apertura:** tras «Ciudad o condado», la fila de solo lectura «Tasa de Austin 2%» (total − estado): el usuario pidió el orden total → ciudad → % de la ciudad.
- **Gasto:** «Impuesto incluido» se calcula solo con la tasa predeterminada de la empresa (`SalesTaxCalculator.taxesIncluded`) **al salir del campo del monto** (`MoneyRow(onEndEditing:)`): calcularlo en cada tecla reformateaba el monto a medias («$3.0046.88»). Escrito a mano deja de seguir al monto; al editar, sigue si lo guardado era lo calculado. 346.88 → $26.44; 364.88 → $27.81.
- Guion v4 en el mismo artículo; notas nuevas en **`notas8`**.

**7-nov: BUILD 7** desde `266ba42` de la rama local **`build7`** (sale de `build6`), **sin fusionar ni empujar**. Viene de la prueba del usuario con el guion del build 6 (notas en la colección `notas` del artículo: alta fácil, factura fácil, impuestos **difícil** —tuvo que ir a Más para la tasa de Austin—, gasto y correcciones regulares; pidió el resumen del sales tax en Inicio). Lleva:
- **Tasa total en la página de apertura:** bajo «Estado», «Tasa total que cobras» (vacía = la del estado) y, si es mayor, «Ciudad o condado». `Bookkeeper.setUpSalesTax(totalMillionths:localName:)` crea la estatal y suma la diferencia como tasa local en la agencia del estado (Texas 6.25 % + Austin 2 % = grupo «Austin, TX» 8.25 % predeterminado). Total menor que el estatal o > 20 %: no deja continuar. En AL, AZ, CO y LA la nota avisa que algunas ciudades cobran aparte.
- **Sales tax en Inicio:** fila «Sales tax por pagar · Vence el 20 ene» (o «al día» con el impuesto de las facturas) que abre Impuestos; en el iPhone bajo las acciones rápidas, en el iPad en la columna bajo las cuatro secciones, en el Mac bajo las cifras.
- La nota del cobro («primero se envía el invoice…») era del **guion**, no de la app: el guion v3 envía la factura antes de cobrarla (correo del cliente = el del usuario).
- 189 pruebas. Visto en el simulador: alta con 8.25 + Austin → factura de $1,800 con $148.50 → fila en Inicio → resumen Texas $112.50 + Austin $36.00; iPad con datos de ejemplo.
- **Guion v3** en el mismo artículo; las notas nuevas van a la colección **`notas7`** (las del build 6 quedan en `notas`).
- Al aprobarlo: fusionar `build7` (que incluye `build6`) en `main` y empujar. **Para revisión, elegir el build 7.**

**6-nov (tarde): BUILD 6 SUBIDO** (iOS y macOS) desde `c377af5` de la rama local **`build6`** (sale de `main` `ba4b716`), **sin fusionar ni empujar**. Lleva los tres puntos que eligió el usuario tras el recorrido del build 5: baldosa **«Editar»** a la vista en la factura emitida sin cobros (en el iPad, botón «Editar factura» en la barra; «Duplicar» pasa al «⋯»); **Impuestos antes que Contabilidad** en «Más» del iPhone (la barra lateral no cambia); **método de pago que concuerda con la cuenta** (`PaymentMethodPicker` en `Expenses/ExpenseFormParts.swift`: banco → tarjeta de débito, transferencia o cheque; tarjeta de crédito → solo tarjeta de crédito; caja → efectivo), también en recurrentes y en el detalle del gasto. Visto en el simulador con datos de ejemplo. El guion del artículo ya habla del build 6. **Para enviar a revisión hay que elegir el build 6.** Al aprobarlo: fusionar `build6` en `main` y empujar. Próxima subida: build 7.

**6-nov: BUILD 5 SUBIDO** (iOS y macOS, «Upload succeeded») desde `18aea38` y **fusionado en `main`** (`5c2e9d3`, con el build 4) y **empujado**; worktrees y ramas de los builds 4 y 5 borradas. **Para enviar a revisión hay que elegir el build 5.** Nació de un recorrido «cliente nuevo» en el simulador (empresa Pintura Martínez LLC en Austin, TX; factura, gasto, cobro parcial, correcciones). Lleva, en tres agentes:
- **Ventas** (`c4f8dd2`, `eb1ef84`): `keyboardDoneButton()` (pieza común `4dc1784`) en el cobro y editores; precio de la línea en caja «Precio»; **editar una factura emitida sin cobros** (`Bookkeeper.updateIssuedInvoice`: reversión + asiento nuevo, mismo número, «Editada» en Actividad); estado «Emitida» hasta que se envía («Enviada» después); aviso «Factura F-… emitida» que ofrece enviarla. QA: `-qa.editar 1`, `-qa.emitir 1`.
- **Gastos** (`96e1dea`): «Listo» en todos los teclados de importe; `MoneyRow` (tocar la fila enfoca el campo); `VendorPicker` con «Nuevo proveedor…» («Pagado a» se esconde con proveedor elegido); `ExpenseCategories` (primero «Gastos y costos», aparte equipo/prepagos; sin cuentas por cobrar, contra-cuentas ni gasto de depreciación).
- **Alta, Impuestos, Inicio** (`4e7a4ce`): «Nueva tasa» con «Sumar a Texas (6.25%)…» que crea el grupo y lo deja predeterminado (`Bookkeeper.addTaxRate`), agencia ya elegida, porcentaje vacío; panel del alta oculto con el teclado; aviso de la tasa bajo «Estado»; **«Tipo de empresa»** en el alta (LLC por el nombre); Inicio dice qué cuenta forma el efectivo. QA: `-qa.tasa nueva|grupo`.
- **Glosario** de menús y palabras de contabilidad en la guía web (`sitio/guia#glosario`, `sitio/guide#glossary`, `997894d`), publicado con el empuje de `main`. Al cambiar un menú de la app, ponerlo al día en los dos idiomas.
- 188 pruebas. Recorrido completo repetido sobre el build 5: mismos totales ($317.63 de sales tax sobre $3,850).
- **Guion para el usuario:** https://claude.ai/artifact/32kiNBUgqBpqTrZ4MTfgc7 (35 pasos con capturas; sus calificaciones y notas por parte quedan en la base del artículo, colección `notas`; leerlas con ArtifactData cuando diga «ya terminé»).
- **Pendiente:** que el usuario lo pruebe con el guion y lea Claude sus notas; lo que salga va a un **build 6** (`CURRENT_PROJECT_VERSION` a 6). La guía web aún tiene las capturas del build 3 en las secciones de alta, tasas y factura: rehacerlas cuando el usuario apruebe el build 5.
- **Sin aclarar:** en el primer recorrido, XCTest no vio la app «quieta» (esperaba 60 s por acción) desde el editor de la primera factura, sin uso de CPU; tras relanzar no se repitió. No afecta al usuario, pero si vuelve a pasar, buscar una animación que no termina.

**Al 5-nov (antes del build 5): la 1.0 estaba lista salvo la revisión del usuario y sus tareas en App Store Connect.** Subidas a App Store Connect (iOS y macOS): 1.0.0 (1) a **(5)**. El usuario **aún no ha enviado nada a revisión**.

**Qué lleva el build 4 («la app se explica sola»; agentes C y D, 175 pruebas):**
- **Agente C (`04b5e3d`): alta y primeros pasos.**
  - Fila «Idioma de la app»: en iOS abre los Ajustes de la app; en el Mac, «Idioma y región».
  - Tasa estatal base creada al elegir el estado (tabla `ChirograData/StateSalesTax.swift`, Tax Foundation a mediados de 2026), predeterminada si no había otra. DE, MT, NH y OR no tienen sales tax estatal; AK solo local.
  - Paso 3 del alta «saldo inicial» del banco y, opcional, la tarjeta: un asiento de apertura contra 3900 (`Bookkeeper+Onboarding.swift`). Se puede saltar.
  - «Primeros pasos» de Inicio con 7 pasos, cada uno con su «para qué» y su atajo.
  - QA: `-qa.alta N`, `-qa.altaEstado TX`, `-qa.altaBanco`, `-qa.altaTarjeta`, `-qa.altaCrear 1`, `-qa.altaGasto 1`, `-qa.saldo 1`.
- **Agente D (`bde01b5`): cada pantalla se explica sola.**
  - Estados vacíos que explican qué es la sección y ofrecen empezar (`EmptyGuide`).
  - Pistas TipKit (`DesignSystem/Pistas.swift`; en el Mac no hay): «¿Ya te pagaron?», «¿Pagas algo cada mes?», «¿Cobras sales tax?» en Más, y el «+» del iPad.
  - Asientos con plantilla (`Accounting/JournalTemplates.swift`): aportación (banco / 3000), retiro (3100 / banco), traspaso entre cuentas y «Asiento a mano, para tu contador».
  - Ayuda ⓘ (`TermHelp`) en débito, crédito, gravable, capital, tasa combinada y saldo en libros.
  - «Añadir tasa…» en la factura si no hay tasas, y la nota «Esta factura no lleva impuesto».
  - Pie explicativo de Impuestos en «Más» del iPhone.
  - QA: `-qa.pistas reset|todas|ocultas`, `-qa.vacia 1`, `-qa.asiento aportacion|retiro|traspaso|manual`, `-qa.ayuda <palabra>` (documentados en REDISEÑO-NATIVO §5 de la rama).
- **Integración (coordinador):** `App/Localizable.xcstrings` fusionado con `scripts/merge-xcstrings.py`, sin claves en conflicto. Visto en el simulador del iPhone (alta → Inicio → Ventas vacía → Más con la pista) y en la copia del Mac (Inicio con los pasos, plantilla de asiento).

**Lo siguiente, en orden (marcado quién):**
1. **Usuario · probar el build 5 en TestFlight desde cero** con el guion del artículo (arriba). Para verlo en TestFlight hace falta un grupo de **Internal Testing** con su cuenta y el build añadido (si el grupo no tiene distribución automática).
2. **Claude · después:** leer sus notas, arreglar en un build 6 si hace falta y actualizar la **guía web** (`sitio/guia`, `sitio/guide`) con el alta nueva (idioma, saldo inicial, tasa estatal y local, tipo de empresa), editar factura, plantillas de asiento y pistas, rehaciendo las capturas afectadas (cómo, en «Guía de uso» abajo).
3. **Usuario · suscripción en App Store Connect:** grupo «Chirogra», `com.chirogra.app.mensual`, 1 mes, **$24.99**, oferta de introducción **gratis 2 semanas**, sin Family Sharing (textos en [APP-STORE.md](APP-STORE.md)). Sin el producto, la pantalla de suscripción dice «Subscription Unavailable» y la app no bloquea nada (`notConfigured`).
4. **Claude · captura de la pantalla de suscripción** para la revisión de la compra, cuando exista el producto.
5. **Usuario · ficha y envío a revisión** con el último build: textos, categoría, URLs, «Data Not Collected», edad 4+ y notas para la revisión en [APP-STORE.md](APP-STORE.md); capturas en su escritorio («Chirogra – capturas App Store»).
   - **Rehacer las capturas de la App Store** si el usuario quiere mostrar el ícono nuevo o las pantallas nuevas; con datos de ejemplo no cambian.
6. **Usuario · correo `soporte@chirogra.com`** (reenvío en Cloudflare): lo citan la web y la app; sigue sin confirmar.
7. **Probar iCloud de verdad:** activar «Sincronizar con iCloud» **primero en un aparato**, esperar a que suba y luego en los demás. Nunca se ha probado la sincronización real.
8. **Después de publicar:** la 1.1 (plan para contadores) y la fase 2 (ver abajo).

**Hallazgos de la prueba del usuario (5-nov), ya atendidos en el build 4:** no encontró dónde poner el sales tax (empresa nueva sin tasas; Impuestos al fondo de «Más»); su iPhone está en inglés y la app salió en inglés (se cambia en Ajustes › Apps › Chirogra › Idioma); «la app no explica a simple vista qué hacer».

**Pendientes y dudas del build 4 (sin hacer):**
- **Propuesta de D, sin decidir:** subir el grupo Impuestos por encima de Contabilidad en «Más» del iPhone. No se cambió porque el orden lo fija el canvas: preguntar al usuario.
- **Tasa de Puerto Rico** en la tabla: 10.5 % de memoria, sin comprobar.
- Si el usuario cambia el estado después en Ajustes, no se crea la tasa nueva.
- Un error al crear la tasa o el asiento de apertura después de crear la empresa no se le muestra.
- **Sin probar en un aparato real:**
  - si el botón de idioma abre la página de Chirogra en Ajustes o la raíz;
  - guardar una tasa desde la factura;
  - «Añadir tasa…» en el iPad y el Mac;
  - el globo ⓘ en el Mac;
  - VoiceOver y letra grande.
- La prueba de humo de `BankingView` con `ImageRenderer` se quitó porque se cae en ese renderizador (en pantalla funciona).
- Del build 2: el aviso de la tabla de proveedores del Mac cuenta los marcados como 1099 aunque no lleguen al mínimo.

**Próxima subida:** `CURRENT_PROJECT_VERSION` a **5** en `project.yml` y en el `project.pbxproj` (comprobar con xcodegen en una copia que coinciden). Se archiva desde un clon limpio del commit y se sube con `xcodebuild -exportArchive` (ver «TestFlight»). El usuario prefiere que se suba directamente. Si quisiera Transporter: `destination` `export`.

**Pendiente menor sin hacer:** en el Mac no se probó en pantalla registrar y revertir un asiento ni el estado vacío (D vio estados vacíos y el editor en el Mac con QA).

## Estado actual

- **App en `main`:** rediseño nativo (2-nov) + Mac con tabla e inspector (2-nov) + esquema 2 con lo que dibujaba el canvas (3-nov) + ícono (`541169a`) + pendientes menores y `DesignSystem` (`e9db54e`) + copia de seguridad (`de6ef43`) + suscripción y solo lectura (`d4de7a9`) + QA de capturas (`82348a9`) + web (`36f3276`, `30ee87d`, `623c564`) + versión 1.0.0 con iCloud (`0f554ff`) + guía de uso web y arreglo de Impuestos (`8278ac5`, `b6dab31`) + build 2 («Empezar con mi empresa», 1099, «Guía de uso»; `d2eb0b0`) + ícono nuevo y build 3 (`330a0fd`) + builds 4 y 5 con el glosario web (`5c2e9d3`).
- **Datos:** los tres aparatos ya migraron a `SchemaV2`. **Una versión anterior de la app ya no abre esos datos.** Instalado el build 3 en iPhone, iPad y Mac (con datos de ejemplo «Ríos Diseño & Obra», salvo que el usuario haya usado «Empezar con mi empresa» en su prueba del iPhone), «Solo en este dispositivo».
- **iCloud:** contenedor `iCloud.com.chirogra.app` asignado al App ID `com.chirogra.app` (iCloud + Push) y esquema 2 desplegado a producción (4-nov).
- **App Store Connect:** app «Chirogra» creada (iOS + macOS, English (U.S.), bundle `com.chirogra.app`, Apple ID 6830687358, SKU CHIROGRA-001). Subidas 1.0.0 (1) a (5) para las dos plataformas; sin enviar a revisión.
- **Web:** https://chirogra.com (GitHub Pages desde `sitio/`, dominio del usuario en Cloudflare). Privacidad `/privacidad/` · `/privacy/`, soporte `/soporte/` · `/support/`.
- **Precio decidido:** mensual con 14 días gratis; $24.99 los 3 primeros meses de lanzamiento y luego $29.99 para los nuevos (los suscritos conservan su precio); con la conexión al banco, plan «Chirogra + Banco» a $39.99.

### Proyecto de Xcode
`project.yml` es la fuente: se regenera con `xcodegen` **en una copia** (scratchpad) y se copian al repo `project.pbxproj`, el esquema, `Info.plist` y los `.entitlements` generados, comparando antes con `diff` (así se hizo el 3 y el 4-nov; el diff debe tener solo lo esperado).

### TestFlight
Desde un clon limpio del commit: `xcodebuild archive` (Release, `-destination 'generic/platform=iOS'` y luego `'generic/platform=macOS'`, `DEVELOPMENT_TEAM=4N9XEU7F4P -allowProvisioningUpdates`) y `xcodebuild -exportArchive -exportOptionsPlist <plist> -allowProvisioningUpdates` con `method` `app-store-connect`, `destination` `upload`, `teamID` 4N9XEU7F4P, `signingStyle` `automatic`. Usa la cuenta del usuario en Xcode (no hace falta clave de API). **No buscar claves ni credenciales en el ordenador del usuario.**

## Qué se hizo en este chat

### Antes del 2-nov (versión `038b168`)
Barra lateral, estados de iCloud, aviso «¿Descartar los cambios?» en los editores, ícono de Icon Composer, Liquid Glass, columna maestro-detalle en iPad y Mac, densidad de Mac.

### 2-nov: hallazgos del iPad en vertical y rediseño nativo (equipo de agentes)
- iPad vertical: barra lateral que se cierra sola en las páginas de lista y de ancho fijo (`d343fa1`); hojas de editor grandes (`de93afd`); título en línea en los detalles (`9476336`); VoiceOver en «Registrar pago» (`2742f53`).
- Rediseño nativo según el canvas: base (`62f5b58`), botón principal en vidrio sin relleno (`4db4ec2`), áreas A–D (`96c44e1`, `7fdc121`, `6975c8f`, `5229973`), QA del coordinador (`106c441`).

### 2-nov: Mac con tabla + inspector (equipo de agentes)
- Estructura y pieza común `Shell/MacTablePage.swift`, Facturas (`6d5a395`); Clientes (`f4f48cc`); Gastos (`67556f1`); Banca, Asientos y Plan (`ff7d81b`); Proveedores y Por pagar (`db976e7`); inspector de Inicio, Reportes e Impuestos (`ed07f05`).
- Arreglos del coordinador: «Estado» en inglés = «Status» y los selectores de estado de EE. UU. = clave «Estado de EE. UU.» (`af3c994`); Gastos y Banca arrancan en el último mes con movimientos y la tarjeta de Gastos suma solo la tabla (`8a82ec1`); hojas menos apretadas: iPad horizontal hasta 980 pt, «Nueva factura» del Mac 860–920 pt, `.formStyle(.grouped)` en 7 formularios (`8952b61`); tarjeta de Gastos de iPhone/iPad igual que la del Mac, VoiceOver sin títulos dobles, hojas de Impuestos (`4f4e68e`).

### 3-nov: lo que dibujaba el canvas (esquema 2, equipo de agentes)
- Datos: `SchemaV2` + migración + servicios en `Bookkeeper` + pruebas (`463355f`, `97b15d4`, ver [DATOS-V2.md](DATOS-V2.md)).
- Gastos/Proveedores/Por pagar/Banca (`0b9db97`): programar pago, pago en lote, recurrentes (cargo automático o «por confirmar»), editar gasto contabilizado (reversión + asiento nuevo, con historial), impuesto incluido y cliente en gastos, W-9 y pago preferido, «Corriente ••4821».
- Contabilidad/Impuestos/Inicio (`67aecf8`, `4af935d`, `04e62a6`): editar cuenta (y últimos 4 dígitos), plan de cuentas agrupado y plegable en el Mac (`MacTablePage` admite `children:`), cierre con historial y contraseña (hash con sal), editar tasa, impuesto predeterminado, precios con impuesto incluido, origen de ventas, campana de avisos, automatizaciones al abrir (`runAutomations()` en `monitorsCloudSync()`).
- Ventas/Clientes (`f503010`): estimados (lista, editor, detalle, convertir en factura completa/anticipo/por líneas), enviar con Para/Asunto/copia, recordatorios, contacto y notas fechadas del cliente, plantilla de factura (logo, color, estilo; también en el PDF), facturas con impuesto incluido.
- Arreglo: el campo de importe va vacío con cero; escribir «500» guardaba $0.01 (`84bf407`).
- Probado en el iPad físico: migración, campana, Por pagar programado, ficha de proveedor, Estimados, Recurrentes, plantilla, Impuestos y Cierre.

### 3 y 4-nov: cierre del MVP y preparación de la 1.0 (este chat)
- Pendientes menores (`e9db54e`): borradores con impuesto en las listas, editor ancho en la hoja del iPad, ••4821 y subcuentas en la columna maestro, Por pagar del Mac; piezas repetidas a `DesignSystem` (`RowGroup`, `Monogram`, `.zebra`, `MasterRows.swift`) con capturas antes/después idénticas.
- Copia de seguridad `.chirogra` (`de6ef43`): crear, restaurar (con prueba en memoria y copia previa) y deshacer; código por modelo generado por `scripts/gen-backup.py`.
- Suscripción StoreKit y solo lectura (`d4de7a9`); precio decidido con el usuario (arriba).
- Capturas de la App Store y argumentos de QA (`82348a9`); Banca del iPhone sin nombres cortados.
- Web chirogra.com con portada, privacidad y soporte (`36f3276`, `30ee87d`, `623c564`).
- Versión 1.0.0, iCloud activado de verdad, esquema de CloudKit en producción y textos de la App Store (`0f554ff`); subida a App Store Connect (iOS y macOS).
- Revisado por el usuario y bien: marco de foco de Gastos en el iPad (arreglado), hoja de factura ancha, borradores con impuesto, plan de cuentas y «Crear copia ahora» en el iPad.

### 4 y 5-nov: build 2, 3 y 4 (este chat)
- Arreglo de la caja «Facturas nuevas» de Impuestos (`8278ac5`); guía de uso web es/en con 18 capturas del Mac (`b6dab31`).
- Prueba técnica de iCloud: dos almacenes en el mismo contenedor se mezclan (más abajo, «Plan para contadores»).
- Build 2 (`d2eb0b0`, agentes A y B): «Empezar con mi empresa», 1099 por año, «Guía de uso» en la app.
- Build 3 (`330a0fd`): ícono nuevo del usuario en la app y en la web.
- Build 4 (rama `integracion-build4`, agentes C y D): la app se explica sola (arriba).
- Investigado y decidido para la fase 2: escaneo de recibos y sales tax automático (más abajo).

## Decisiones del usuario (no deshacer sin preguntar)

- **Precio (3-nov):** un solo plan **mensual** con **14 días de prueba gratis**. Lanzamiento a **$24.99/mes durante los 3 primeros meses**; después **$29.99/mes** para los nuevos, **conservando el precio** a los ya suscritos (en App Store Connect). El usuario pensó en $69.99 y lo bajó al ver el mercado (QuickBooks Simple Start $38, Xero Early $27). Subir más solo cuando llegue la conexión con el banco.
- **Suscripción vencida = solo lectura** (se ven los libros y se sacan copias, CSV y PDF; no se registra nada).

- **Rediseño nativo según el canvas actual** (2-nov), que deja sin efecto el descarte de `7a8b97f`. Manda el canvas salvo lo de esta lista.
- **Botón principal en vidrio sin relleno** (`.glass`), aunque el canvas lo rellene de Tinta. Nada de botones morados.
- **Pestañas del iPhone:** Inicio · Ventas · Gastos · Banca · Más (Reportes en «Más»).
- **Fila elegida de la columna maestro rellena de Tinta** con texto blanco; **barra lateral** con grupos «Negocio» y «Libros».
- **iPad: maestro-detalle. Mac: tabla a todo el ancho + inspector de ~300 pt** (⌥⌘I), como el canvas.
- **Mac con densidad de Mac** (`Metrics.target` 28 pt en Mac, 44 pt en iOS; barra lateral de 220 pt en el Mac, 280 pt en el iPad).
- **Gastos y Banca** arrancan en el último mes con movimientos si el actual está vacío; la tarjeta de Gastos suma solo los gastos (sin facturas por pagar), en los tres aparatos.
- **Editar algo contabilizado** = reversión + asiento nuevo (los asientos contabilizados son inmutables, DISEÑO §6.5).
- **Ícono de la app** = el que hizo el usuario en Icon Composer el 4-nov (carpeta con hojas y el sello de Chirogra; original en su escritorio, «Chirogra 1.icon»), copiado tal cual en `App/AppIcon.icon` desde el build 3. Sustituye a `chirogra.icon`. El de la web (`sitio/img/icono.png`, 256 px) sale del `AppIcon.icns` de la compilación del Mac (`iconutil -c iconset`). El **logo de la empresa** queda para después.
- **Modo oscuro del Mac:** el Mac del usuario está en oscuro; las hojas siguen al sistema.

## Detalle de lo hecho y lo pendiente

**Probado por el usuario y funciona (2-nov):** Escape y Return en los editores del Mac, ⌥⌘I, doble clic, ordenar columnas, soltar un recibo, «Registrar pago» en la hoja.

**Copia de seguridad (3-nov, `de6ef43`, cierra el MVP):** Ajustes › iCloud, copias y seguridad: «Crear copia ahora» (archivo `.chirogra`, tipo `com.chirogra.backup` declarado en `Info.plist` y `project.yml`), «Restaurar desde una copia…» (confirmación con empresa, fecha y registros; guarda antes una copia de lo actual en Application Support/«Copias antes de restaurar», las 3 últimas) y «Deshacer la última restauración». Tras restaurar se rehace la navegación (`BooksReplacement`, `.id` del `AppShell`) y sale «Copia restaurada». Código: `ChirograData/Backup.swift` + `Backup+Generated.swift` (lo escribe `scripts/gen-backup.py`; **volver a ejecutarlo al cambiar el esquema**, `BackupTests` lo exige). Probado: 5 pruebas (cubre todo el esquema, ida y vuelta idéntica, valores por defecto de una copia vieja, archivos malos sin tocar nada) y en la copia de prueba del Mac de punta a punta (crear, restaurar, deshacer, con la base comprobada por SQLite). Argumentos de QA (Debug): `-qa.ajustes data`, `-qa.copia <ruta>`, `-qa.restaurar <ruta>` (rutas dentro del contenedor de la copia de prueba).

**Suscripción (3-nov, `d4de7a9`):** `Shell/Subscription.swift`: `SubscriptionStore` (StoreKit 2, producto `com.chirogra.app.mensual`; `notConfigured` mientras el producto no exista en App Store Connect → no bloquea nada, así que las versiones instaladas hoy siguen abiertas), `PaywallView` (`SubscriptionStoreView`, sale sola una vez al crear la empresa o al abrir con la suscripción vencida), aviso de solo lectura (arriba en iPhone/iPad; al pie de la barra lateral en el Mac), «Suscripción» en Ajustes › iCloud, copias y seguridad. Los «+» (`AddButton`, `masterAddButton`, `MacTablePage`, `QuickAction`) abren la suscripción en solo lectura; `Bookkeeper.isReadOnly` bloquea todo guardado de `Bookkeeper` (`BookkeepingError.readOnly`, `ReadOnlyTests`) y `AppAutomations` no corre. `App/Chirogra.storekit` + esquema de Xcode (`project.yml` `run.storeKitConfiguration`): **al ejecutar desde Xcode** se puede comprar de prueba. QA: `-qa.suscripcion prueba|activa|vencida`. Fuera de Xcode y sin el producto en App Store Connect la pantalla dice «Subscription Unavailable» (normal). **Falta:** crear la suscripción en App Store Connect (grupo «Chirogra», mensual, prueba de 2 semanas, $24.99), la URL de la política de privacidad (`ChirograLinks.privacyPolicy`, hoy `nil`; condiciones = EULA de Apple) y probar la compra desde Xcode.

**Capturas de la App Store (3-nov):** en el escritorio del usuario, «Chirogra – capturas App Store» (`es`/`en` × iPhone 6.9″ 1320×2868, iPad 13″ 2064×2752, Mac 2880×1800 con la ventana sobre un fondo). Argumentos de QA para repetirlas (Debug): `-qa.mes anterior` (Inicio y Gastos en el mes anterior), `-qa.periodo trimestre|año` (Reportes), `-qa.pestana sales|expenses|banking|reports` (iPhone), `-qa.fila N` también en Ventas y Gastos del iPad. En el Mac la ventana no cabe en 16:10 con el inspector (pantalla de 1050 pt de alto): se captura a 1624×986 y se compone en 2880×1800.

**Probado por el usuario en su iPad (3-nov) y funciona:** hoja de nueva factura con el diseño ancho (vertical y horizontal), borrador con impuesto en la lista ($108.25), plan de cuentas con ••4821 completo y subcuentas sangradas, «Crear copia ahora» con el panel de guardar.

**Versión 1.0 (4-nov, `0f554ff`):** `MARKETING_VERSION` 1.0.0 y build 1 (el `Info.plist` ya los toma de `project.yml`), `ITSAppUsesNonExemptEncryption = NO`, `UIBackgroundModes` `remote-notification`. **iCloud nunca estuvo activado** (la app no tenía el permiso: el interruptor «Sincronizar con iCloud» abría el almacén local): ahora `App/Chirogra.entitlements` (iOS: CloudKit con `iCloud.com.chirogra.app` y `aps-environment`) y `App/Chirogra-macOS.entitlements` (`CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`, con `com.apple.developer.aps-environment`). El 4-nov el usuario creó el contenedor `iCloud.com.chirogra.app` y lo asignó al App ID `com.chirogra.app` (iCloud + Push); las compilaciones firmadas de iOS y Mac ya llevan los permisos. **Esquema creado en Desarrollo el 4-nov** desde el Mac (los primeros intentos daban «Invalid bundle ID for container» hasta que Apple propagó la asignación, ~6 min). Cómo se hizo: `-qa.esquemaCloudKit 1` (Debug, aparato con iCloud) llama a `ChirograStore.initializeCloudKitSchema` (Core Data + `initializeCloudKitSchema`, almacén temporal) y el resultado queda en `qa.esquemaCloudKit.resultado` (ajustes de la app; `log show` no lo muestra desde aquí); **desplegado a producción el 4-nov** por el usuario en la consola de CloudKit («Changes Deployed»). Si el esquema cambia (V3), repetir: `-qa.esquemaCloudKit 1` y «Deploy Schema Changes…». `CloudKitSchemaTests` comprueba las reglas de CloudKit del modelo. Textos de la App Store: docs/APP-STORE.md.

**TestFlight (4-nov):** 1.0.0 (build 1) de `0f554ff` subida a App Store Connect para iOS y para macOS con la cuenta del usuario en Xcode: `xcodebuild archive` (Release, `generic/platform=iOS` y `generic/platform=macOS`, `-allowProvisioningUpdates`) y `xcodebuild -exportArchive` con un ExportOptions de `method` `app-store-connect`, `destination` `upload`, `teamID` 4N9XEU7F4P, firma automática. **Cada subida nueva necesita otro número de build** (`CURRENT_PROJECT_VERSION` en `project.yml`: el siguiente es 2).

**Sitio web (4-nov):** `sitio/` (portada con ícono, capturas, seis funciones con íconos SVG y «Tus libros son tuyos»; `/privacidad`, `/privacy`, `/soporte`, `/support`, rutas relativas) publicado con GitHub Pages por `.github/workflows/sitio.yml` en **https://chirogra.com** (dominio comprado por el usuario en Cloudflare; DNS en Cloudflare «DNS only»: 4 A y 4 AAAA de GitHub Pages y `www` CNAME → `ivanngarcia81.github.io`; certificado aprobado y HTTPS obligatorio; `www` y `http` redirigen). La app enlaza `https://chirogra.com/privacidad/` o `/privacy/` según el idioma (`ChirograLinks.privacyPolicy`). En App Store Connect: privacidad `https://chirogra.com/privacidad/` (o `/privacy/` en inglés) y soporte `https://chirogra.com/soporte/` (`/support/`). Correo de soporte en las páginas: `soporte@chirogra.com` (reenvío de correo de Cloudflare, lo crea el usuario).

**Comprobado el 3-nov:** archivar una cuenta en el Mac (inspector del plan de cuentas; se guarda con el autoguardado). Los cargos automáticos, las reversiones y los asientos manuales tienen pruebas de datos.

**Sin comprobar**
- VoiceOver de verdad (iPhone, iPad y Mac) e iPad con letra grande.
- Correo real (`MFMailComposeViewController`, `NSSharingService`), logo desde Fotos, que un cargo automático se cobre solo al vencer en un aparato.
- En pantalla: registrar un asiento de punta a punta y revertirlo en el Mac; estado vacío del Mac; el panel de guardar la copia en el Mac (en el iPad funciona).

**Para la copia de prueba del Mac con accesibilidad:** System Events busca los procesos **por nombre**, y la copia también se llama «Chirogra»: renombrarla (ejecutable y `CFBundleName` «ChirograQA», volver a firmar con `--entitlements` de la original para conservar el sandbox). Sin el sandbox usa `~/Library/Application Support/Chirogra.store` (ahí hay uno sobrante del 31-oct, no es del usuario).

**Pendiente menor hecho el 3-nov (`e9db54e`; verificado en el simulador del iPad y la copia de prueba del Mac):**
- Borradores con impuesto en las listas: `saveDraft` y `convertToInvoice` guardan `subtotal/taxTotal/total` del borrador (como los estimados) y `runAutomations()` los pone al día al abrir (`refreshDraftTotals()`, borradores de antes o tasas cambiadas). `draftAmount` usa `total`; `balanceDue` de un borrador es 0.
- Editor de factura en la hoja del iPad: en el iPad elige el diseño ancho por el ancho medido (≥ 640 pt), porque dentro de la hoja la clase de tamaño es compacta. El iPhone sigue igual.
- Plan de cuentas en la columna maestro del iPad: ••4821 (`maskedName`, hasta 3 líneas) y subcuentas sangradas (`ChartOfAccountsView.outline`).
- Por pagar del Mac: anchos ideales de las columnas que caben con el inspector abierto en una ventana de 1280 pt; antes la tabla se desplazaba de lado y «Registrar pago» quedaba cortado.

- Piezas repetidas subidas a `DesignSystem`: `RowGroup` (antes `HomeRowGroup`, `PhoneGroup`, `TaxGroupCard`; `macBorder` = el filete de Reportes en el Mac), `Monogram` (antes `CustomerMonogram`, `VendorMonogram` y el de la ficha de proveedor; `InitialsTile` y `CompanyMonogram` lo usan por dentro), `.zebra(_:onIOS:)` (antes una en la ficha de proveedor, copias en Ventas, Clientes, Impuestos y Reportes, y a mano en Inicio, que la lleva también en el iPad) y las filas maestro en `DesignSystem/MasterRows.swift` (`MasterRow`, `.masterRow`…), que ahora usa también Estimados. Comprobado con capturas antes/después idénticas píxel a píxel en 18 pantallas (Mac, iPad, iPhone).
- No se movieron `ComparisonBars`, `ActivityMark` ni `LineEditRow`: solo los usa una pantalla. Subirlos cuando otra los necesite.

**No construido a propósito:** «Vista por el cliente» (necesita servidor). **Fase 2:** OCR, bandeja del banco e importar/conciliar (Plaid solo en un backend), usuarios y permisos, varias empresas, deducibles y «Exportar para mi contador».

**Guía de uso (4-nov, sin commitear):** `sitio/guia/` (es) y `sitio/guide/` (en), 13 secciones con 18 capturas del Mac por idioma en `sitio/img/guia/` (copia de prueba del Mac con los argumentos `-qa.*` y datos de ejemplo; las hojas se capturan como ventana aparte y se recorta su franja vacía de 33 px). Enlazada desde el menú de todas las páginas y desde Soporte. Revisada con Chrome sin ventana a 1280 y 390 px y en oscuro. Falta: el enlace «Ayuda» dentro de la app (build 2 o 1.1). Al cambiar una pantalla, rehacer su captura.

**Build 2 de la 1.0 (4-nov, `d2eb0b0`; agentes A y B en worktrees + coordinador):**
- **«Empezar con mi empresa»** (agente A, `f51ef91`): aviso en Inicio (con «×» por aparato) y sección en Ajustes › iCloud, copias y seguridad mientras los libros sean de ejemplo; confirmación; borra todo con `Backup.eraseAll` (uno a uno, pasa por iCloud) y vuelve al alta. Detección sin esquema nuevo: el alta de la empresa de ejemplo deja un `AuditEvent` con actor «Ejemplo» (viaja por iCloud y en las copias); libros de ejemplo = todas las empresas lo son; `SampleData.discard` no borra libros reales (`notSample`). `paywallShownOnce` vuelve a `false` al borrar, así la suscripción sale al crear la empresa real; se permite también en solo lectura. QA: `-qa.empezar 1` (confirmación) y `-qa.empezar confirmar` (borra). 9 pruebas en `SampleDataTests`.
- **1099-NEC** (agente B, `87529f6`): `ChirograData/Form1099.swift`, mínimo por año fiscal ($600 hasta 2025, $2,000 desde 2026; tabla `inflationAdjusted` que hay que **actualizar cada año** cuando el IRS publique la cifra de 2027 en adelante); textos con el importe sin centavos. Pendiente menor: el aviso de la tabla del Mac («N proveedores requieren 1099-NEC») cuenta los marcados como 1099 aunque no lleguen al mínimo.
- **«Guía de uso»** (coordinador): `Settings/HelpLinks.swift` (`ChirograLinks.guide`, `GuideLinkRow`, `ChirograHelpCommands` con ⌘?) en Ajustes del iPad/Mac, al final de «Más» del iPhone y en el menú Ayuda; la guía web explica «Empezar con mi empresa».
- Verificado: 152 pruebas, capturas en simuladores de iPhone/iPad y en la copia del Mac (claro, oscuro, inglés). Sin comprobar: el borrado sincronizado por iCloud entre aparatos y la sección «Ayuda» de «Más» en pantalla (queda abajo).

**Decidido el 4-nov para la fase 2 (el usuario; orden sin fijar):**
- **Escanear el recibo y rellenar el gasto:** cámara de documentos de VisionKit (iPhone/iPad; hoy la app no abre la cámara), lectura con Vision (`RecognizeDocumentsRequest`) y extracción con Foundation Models en el aparato (comercio, fecha, total, impuesto incluido, categoría sugerida) + revisión del usuario antes de guardar. Sin servidor ni costo; sin Apple Intelligence, total y fecha con reglas simples. No cambia el esquema. Lo hacen QuickBooks, FreshBooks, Wave y Xero.
- **Sales tax automático, en dos pasos:** (1) sugerir la tasa por código postal con una tabla mensual publicada en chirogra.com (sin servidor; aproximada, el usuario confirma); (2) tasa exacta por dirección como el Automated Sales Tax de QuickBooks, con un proveedor de pago (Avalara, TaxJar, Stripe Tax, Zip-Tax) a través del servidor de la fase 2 (el de Plaid y el cobro en línea), dentro del plan «Chirogra + Banco». Texas cobra por origen en las ventas dentro del estado: ahí basta el impuesto predeterminado.

**Plan para contadores (decidido el 4-nov; el usuario lo quiere para la siguiente versión después de la 1.0, «el build 2»: entendido como la 1.1, no como el build 2 de la 1.0):** caso A: el contador independiente lleva los libros de **hasta 5 empresas** desde su propia app y su iCloud; el cliente no usa Chirogra. **Conviven los dos planes:** el individual de siempre (el dueño lleva sus propios libros, 1 empresa) y el de contador; una empresa puede pasar de uno a otro en cualquier sentido con la copia `.chirogra` (el contador se la entrega al dueño, o el dueño se la da a su contador) (el caso B, el contador dentro de la app del cliente con permisos, queda para después: SwiftData no comparte datos de iCloud entre cuentas). Segundo nivel de suscripción en el grupo «Chirogra», plan alto; precio sin fijar (propuesta: $89.99–$99.99/mes; QuickBooks Online Accountant es gratis para el contador y cobra a cada cliente). Piezas: selector de empresa, lista de empresas con lo pendiente de cada una, alta de otra empresa, límite de 5 en la app; la copia `.chirogra` por empresa sirve para entregarle los libros al cliente. **Prueba del 4-nov (Mac, iCloud de desarrollo): un almacén por empresa en el mismo contenedor NO sirve.** Dos almacenes SwiftData con `.private("iCloud.com.chirogra.app")` comparten la misma zona de CloudKit: se guardó «SPIKE-A» en A y B, recién creado, la recibió al importar (10 s). Registros de prueba borrados de iCloud y de la Mac. Caminos: (1) **recomendado:** un solo almacén con la empresa en cada registro (esquema 3, migración que asigna la empresa actual; añadir campos es compatible con el esquema de producción); (2) un contenedor de iCloud por empresa (5 contenedores más creados en el portal, cada cambio de esquema desplegado 6 veces).

**Cobro en línea (decidido el 3-nov para la fase 2):**
1. **Sin servidor:** enlace de pago propio del usuario en Ajustes (Stripe Payment Link, Square, PayPal.me, datos de Zelle o transferencia) → botón «Pagar ahora» y QR en el PDF y el correo de la factura. El cobro se registra a mano.
2. **Con servidor, junto con Plaid:** Stripe Connect (la cuenta de Stripe de cada usuario; el dinero no pasa por Chirogra), un enlace por factura con su importe, aviso de Stripe al servidor y la app registra el cobro al abrir (el servidor no escribe en el iCloud del usuario). Comisión de Stripe como gasto, cuenta puente «Fondos no depositados» hasta el depósito, que se concilia con la importación del banco. Posible comisión de Chirogra por pago (p. ej. 0.5 %). Entraría en el plan «Chirogra + Banco» ($39.99/mes; el plan sin banco sigue a $29.99), en el mismo grupo de suscripción.

**Nómina (payroll): idea pendiente, sin decidir (6-nov).** El usuario preguntó si la app tendrá nómina. Hoy no: DISEÑO.md la deja para «más adelante». Lo que sí se puede: registrar la nómina pagada con otro servicio (Gusto, ADP, QuickBooks Payroll) como gasto o asiento; el plan de cuentas ya trae «6850 · Sueldos y salarios» y «2300 · Nómina por pagar». Si se hace, la recomendación es **no construirla desde cero** (retenciones federales y estatales, depósitos, 941/940, W-2/W-4, cambian cada año) sino integrar un proveedor de nómina embebida (Gusto Embedded, Check) a través del servidor de la fase 2 (el de Plaid), como plan más alto. Falta que el usuario decida si la quiere y cuándo.

## Reglas de trabajo

- **Commit y push solo cuando el usuario lo pida** (suele decir «commitea y empújalo»). Instalar en los aparatos cuando lo pida.
- **Verificar uno mismo antes de pedirle que pruebe:** simulador, copia de prueba del Mac y el iPad físico (abajo).
- Accesibilidad: 44 pt en iOS, Dynamic Type, VoiceOver, contraste AA. Bilingüe español/inglés: textos nuevos en `App/Localizable.xcstrings` con su inglés y los mismos marcadores (`%@`, no `%1$@`; lo exige `StringCatalogTests`).
- Hojas de editor con `.editorSheetSizing()` y formularios con `.formStyle(.grouped)` (sin él, en el Mac se desbordan).
- Avisar antes de borrar nada del ordenador del usuario. No cambiar ajustes del sistema ni de Xcode.
- El canvas de Claude Design es de solo lectura: https://claude.ai/artifact/Ai344mUq54BECC4Pw4quV9 (se lee con la herramienta Artifact, `path: project/<tablero>.dc.html`).
- **No tocar el simulador de iPad `BEB1EA39`:** es de otro proyecto (Tamio).

### Cómo se trabajó: equipo de agentes
Para bloques grandes, el coordinador lanza agentes en worktrees (`isolation: worktree`; la sesión tiene que estar con el directorio actual dentro del repo o falla), **cada uno con archivos distintos y su propio simulador y copia del Mac**. Si varias funciones necesitan cambiar el modelo, primero un agente de datos y después los de pantallas. Los agentes hacen commit en su rama; el coordinador los junta en una rama de integración, compila, pasa `swift test`, revisa en pantalla y, cuando el usuario lo aprueba, pasa a `main`. Después se borran las worktrees y ramas.

### Fusionar el catálogo de textos
Si dos ramas añaden textos, git choca en `App/Localizable.xcstrings`. Usar `scripts/merge-xcstrings.py` (las tres versiones salen de `git show ":1:App/Localizable.xcstrings"`, `":2:…"`, `":3:…"`; en zsh, con comillas o `${n}`, porque `$n:` lo interpreta zsh). Revisar a mano las claves que lista como cambiadas en las dos ramas.

## Comprobar en pantalla

- **Simulador** (iPhone/iPad): pruebas de interfaz temporales con un target `UITestsQA` añadido a `project.yml` + `xcodegen`, en una copia del repo en el scratchpad (**nunca commitear** `UITestsQA`, el cambio de `project.yml` ni el `.xcodeproj` regenerado). Datos: «Try with sample data». Las capturas horizontales salen giradas.
- **Mac sin tocar los datos del usuario:** copia de prueba con otro identificador (`PRODUCT_BUNDLE_IDENTIFIER=com.chirogra.qa.<nombre> CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS=<un .entitlements con `<dict/>`>`: desde el 4-nov la app lleva iCloud y, firmada ad hoc con esos permisos, no arranca), argumentos de prueba `-qa.*` (solo Debug, ver REDISEÑO-NATIVO §5: `-qa.muestra 1 -qa.seccion <página> -qa.fila N -qa.inspector 1 -qa.nuevo 1 -qa.apariencia claro`…), `open -g -j -n <app> --args …`, captura de su ventana con `screencapture -l <windowID> -o -x` (id por PID con `CGWindowListCopyWindowInfo`, ventana de capa 0 y más de 300 pt de alto), `kill` de su PID y `rm -rf ~/Library/Containers/com.chirogra.qa.<nombre>` al terminar. Sin mover el ratón: el usuario usa el Mac.
- **iPad físico:** `xcodebuild test … -destination 'id=00008103-001439A91E6B001E' -resultBundlePath r.xcresult DEVELOPMENT_TEAM=4N9XEU7F4P -allowProvisioningUpdates` con capturas como `XCTAttachment`; sacarlas con `xcrun xcresulttool export attachments --path r.xcresult --output-path <dir>`. Al terminar, `xcrun devicectl device uninstall app --device <UDID> com.chirogra.uitestsqa.xctrunner`. Lo que se pruebe ahí cambia los datos del iPad del usuario.

## Compilar e instalar en los aparatos

- Equipo de firma: `4N9XEU7F4P`. Bundle id: `com.chirogra.app`.
- iPhone 17 Pro Max: `00008150-0005793E3EC0401C`. iPad Pro 12,9″ (5.ª gen.): `00008103-001439A91E6B001E`.

Desde un clon limpio del commit aprobado, en una carpeta temporal (`$T`):

```bash
git clone -q ~/Documents/GitHub/Chirogra $T/src && git -C $T/src checkout -q <hash>
cd $T/src && xcodebuild -project Chirogra.xcodeproj -scheme Chirogra -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath $T/dd DEVELOPMENT_TEAM=4N9XEU7F4P -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> $T/dd/Build/Products/Debug-iphoneos/Chirogra.app
```

Para el Mac, compilar con `-configuration Release -destination 'platform=macOS'` y luego:

```bash
osascript -e 'tell application id "com.chirogra.app" to quit'; rm -rf /Applications/Chirogra.app && ditto $T/dd/Build/Products/Release/Chirogra.app /Applications/Chirogra.app && codesign -v /Applications/Chirogra.app && open /Applications/Chirogra.app
```

Problemas conocidos: si el aparato sale «desconectado», reintentar. «The developer disk image could not be mounted» o «device was still locked» = el aparato está bloqueado; desbloquearlo y reintentar. Al empujar en zsh, escribir el hash entre comillas (`"<hash>:refs/heads/main"`): `$H:r` es un modificador de zsh.
