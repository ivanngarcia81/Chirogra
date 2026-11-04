# Chirogra: contexto para retomar en otro chat

Resumen del chat de coordinación de Chirogra al **3 de noviembre de 2026**. Léelo entero antes de seguir. El diseño técnico está en [DISEÑO.md](DISEÑO.md), el sistema visual en [REDISEÑO-NATIVO.md](REDISEÑO-NATIVO.md) y la API del esquema 2 en [DATOS-V2.md](DATOS-V2.md); aquí van el estado, las decisiones del usuario, lo pendiente y cómo se trabaja. Al usuario se le habla siempre en español.

## Dónde nos quedamos (empieza aquí)

1. **Anillo de foco del iPad: arreglado y confirmado por el usuario (3-nov).** En Gastos ya no sale el marco cuadrado al hacer clic con el trackpad. Lo arregló `830ed69` (acento de las listas maestro en `Color.clear`, `MasterListStyle`); `e8c43d2` (`.focusEffectDisabled()` en la fila) no bastaba.
2. `main` = `e9db54e` en GitHub (pendientes menores y piezas en `DesignSystem`). Después `de6ef43` (copia de seguridad, cierra el MVP; sin empujar) y encima, **sin commitear**, la suscripción (abajo). No hay ramas ni worktrees abiertos.
3. Instalado en los tres aparatos (iPhone, iPad y Mac) con `82348a9` el 3-nov por la tarde.
4. **Siguiente: fase 2.** Antes, que el usuario decida si se publica la 1.0 (desplegar el esquema de CloudKit) y la lista y el orden de la fase 2: DISEÑO §3.2 y este documento no coinciden (Plaid, usuarios y permisos son fase 3 en DISEÑO). Lo primero técnico sería el esquema 3 con los datos de la conciliación (DISEÑO §4.6).

## Estado actual

- **App aprobada y en `main`:** rediseño nativo (2-nov) + Mac con tabla e inspector (2-nov) + esquema 2 con lo que dibujaba el canvas (3-nov) + ícono nuevo (`541169a`, `App/AppIcon.icon` = `chirogra.icon` de Icon Composer).
- **Datos:** los tres aparatos ya migraron a `SchemaV2` (migración ligera, solo aditiva, desde V1). **Una versión anterior de la app ya no abre esos datos.** La empresa del usuario es «Ríos Diseño & Obra», «Solo en este dispositivo» (sin iCloud), con datos de ejemplo.
- **iCloud:** contenedor `iCloud.com.chirogra.app` y esquema 2 desplegado a producción (4-nov). Hasta la 1.0 la sincronización nunca funcionó (la app no tenía el permiso).

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
- **Ícono de la app** = `chirogra.icon`. El **logo de la empresa** queda para después.
- **Modo oscuro del Mac:** el Mac del usuario está en oscuro; las hojas siguen al sistema.

## Pendiente

**Probado por el usuario y funciona (2-nov):** Escape y Return en los editores del Mac, ⌥⌘I, doble clic, ordenar columnas, soltar un recibo, «Registrar pago» en la hoja.

**Copia de seguridad (3-nov, cierra el MVP):** Ajustes › iCloud, copias y seguridad: «Crear copia ahora» (archivo `.chirogra`, tipo `com.chirogra.backup` declarado en `Info.plist` y `project.yml`), «Restaurar desde una copia…» (confirmación con empresa, fecha y registros; guarda antes una copia de lo actual en Application Support/«Copias antes de restaurar», las 3 últimas) y «Deshacer la última restauración». Tras restaurar se rehace la navegación (`BooksReplacement`, `.id` del `AppShell`) y sale «Copia restaurada». Código: `ChirograData/Backup.swift` + `Backup+Generated.swift` (lo escribe `scripts/gen-backup.py`; **volver a ejecutarlo al cambiar el esquema**, `BackupTests` lo exige). Probado: 5 pruebas (cubre todo el esquema, ida y vuelta idéntica, valores por defecto de una copia vieja, archivos malos sin tocar nada) y en la copia de prueba del Mac de punta a punta (crear, restaurar, deshacer, con la base comprobada por SQLite). Argumentos de QA (Debug): `-qa.ajustes data`, `-qa.copia <ruta>`, `-qa.restaurar <ruta>` (rutas dentro del contenedor de la copia de prueba).

**Suscripción (3-nov, sin commitear):** `Shell/Subscription.swift`: `SubscriptionStore` (StoreKit 2, producto `com.chirogra.app.mensual`; `notConfigured` mientras el producto no exista en App Store Connect → no bloquea nada, así que las versiones instaladas hoy siguen abiertas), `PaywallView` (`SubscriptionStoreView`, sale sola una vez al crear la empresa o al abrir con la suscripción vencida), aviso de solo lectura (arriba en iPhone/iPad; al pie de la barra lateral en el Mac), «Suscripción» en Ajustes › iCloud, copias y seguridad. Los «+» (`AddButton`, `masterAddButton`, `MacTablePage`, `QuickAction`) abren la suscripción en solo lectura; `Bookkeeper.isReadOnly` bloquea todo guardado de `Bookkeeper` (`BookkeepingError.readOnly`, `ReadOnlyTests`) y `AppAutomations` no corre. `App/Chirogra.storekit` + esquema de Xcode (`project.yml` `run.storeKitConfiguration`): **al ejecutar desde Xcode** se puede comprar de prueba. QA: `-qa.suscripcion prueba|activa|vencida`. Fuera de Xcode y sin el producto en App Store Connect la pantalla dice «Subscription Unavailable» (normal). **Falta:** crear la suscripción en App Store Connect (grupo «Chirogra», mensual, prueba de 2 semanas, $24.99), la URL de la política de privacidad (`ChirograLinks.privacyPolicy`, hoy `nil`; condiciones = EULA de Apple) y probar la compra desde Xcode.

**Capturas de la App Store (3-nov):** en el escritorio del usuario, «Chirogra – capturas App Store» (`es`/`en` × iPhone 6.9″ 1320×2868, iPad 13″ 2064×2752, Mac 2880×1800 con la ventana sobre un fondo). Argumentos de QA para repetirlas (Debug): `-qa.mes anterior` (Inicio y Gastos en el mes anterior), `-qa.periodo trimestre|año` (Reportes), `-qa.pestana sales|expenses|banking|reports` (iPhone), `-qa.fila N` también en Ventas y Gastos del iPad. En el Mac la ventana no cabe en 16:10 con el inspector (pantalla de 1050 pt de alto): se captura a 1624×986 y se compone en 2880×1800.

**Probado por el usuario en su iPad (3-nov) y funciona:** hoja de nueva factura con el diseño ancho (vertical y horizontal), borrador con impuesto en la lista ($108.25), plan de cuentas con ••4821 completo y subcuentas sangradas, «Crear copia ahora» con el panel de guardar.

**Versión 1.0 (4-nov, sin commitear):** `MARKETING_VERSION` 1.0.0 y build 1 (el `Info.plist` ya los toma de `project.yml`), `ITSAppUsesNonExemptEncryption = NO`, `UIBackgroundModes` `remote-notification`. **iCloud nunca estuvo activado** (la app no tenía el permiso: el interruptor «Sincronizar con iCloud» abría el almacén local): ahora `App/Chirogra.entitlements` (iOS: CloudKit con `iCloud.com.chirogra.app` y `aps-environment`) y `App/Chirogra-macOS.entitlements` (`CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`, con `com.apple.developer.aps-environment`). El 4-nov el usuario creó el contenedor `iCloud.com.chirogra.app` y lo asignó al App ID `com.chirogra.app` (iCloud + Push); las compilaciones firmadas de iOS y Mac ya llevan los permisos. **Esquema creado en Desarrollo el 4-nov** desde el Mac (los primeros intentos daban «Invalid bundle ID for container» hasta que Apple propagó la asignación, ~6 min). Cómo se hizo: `-qa.esquemaCloudKit 1` (Debug, aparato con iCloud) llama a `ChirograStore.initializeCloudKitSchema` (Core Data + `initializeCloudKitSchema`, almacén temporal) y el resultado queda en `qa.esquemaCloudKit.resultado` (ajustes de la app; `log show` no lo muestra desde aquí); **desplegado a producción el 4-nov** por el usuario en la consola de CloudKit («Changes Deployed»). Si el esquema cambia (V3), repetir: `-qa.esquemaCloudKit 1` y «Deploy Schema Changes…». `CloudKitSchemaTests` comprueba las reglas de CloudKit del modelo. Textos de la App Store: docs/APP-STORE.md.

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

**Cobro en línea (decidido el 3-nov para la fase 2):**
1. **Sin servidor:** enlace de pago propio del usuario en Ajustes (Stripe Payment Link, Square, PayPal.me, datos de Zelle o transferencia) → botón «Pagar ahora» y QR en el PDF y el correo de la factura. El cobro se registra a mano.
2. **Con servidor, junto con Plaid:** Stripe Connect (la cuenta de Stripe de cada usuario; el dinero no pasa por Chirogra), un enlace por factura con su importe, aviso de Stripe al servidor y la app registra el cobro al abrir (el servidor no escribe en el iCloud del usuario). Comisión de Stripe como gasto, cuenta puente «Fondos no depositados» hasta el depósito, que se concilia con la importación del banco. Posible comisión de Chirogra por pago (p. ej. 0.5 %). Entraría en el plan «Chirogra + Banco» ($39.99/mes; el plan sin banco sigue a $29.99), en el mismo grupo de suscripción.

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
