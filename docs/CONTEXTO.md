# Chirogra: contexto para retomar en otro chat

Estado de Chirogra al **9 de noviembre de 2026**. Léelo entero antes de seguir. El diseño técnico está en
[DISEÑO.md](DISEÑO.md), el sistema visual y los argumentos de QA en [REDISEÑO-NATIVO.md](REDISEÑO-NATIVO.md) (§5), los
datos en [DATOS-V4.md](DATOS-V4.md) (y [DATOS-V2.md](DATOS-V2.md)), la fase 2 en [PLAN-FASE2.md](PLAN-FASE2.md) y la
ficha de la App Store en [APP-STORE.md](APP-STORE.md). Aquí van el estado, lo pendiente, las decisiones del usuario, lo
aprendido y cómo se trabaja. **Al usuario se le habla siempre en español.**

El historial día a día (builds 2 a 21, pruebas, guiones) se quitó el 9-nov para que este archivo no crezca: está en git
(`git show 0f7bb1e:docs/CONTEXTO.md`) y en los mensajes de los commits.

## Dónde nos quedamos (empieza aquí)

- **`main` lleva todo** (fase 2 sin servidor unida el 9-nov, merge `6f745a4`) y está empujado. El 9-nov se borraron
  las worktrees y ramas locales de los agentes y `fase2-integracion` (todo estaba ya en `main`); en GitHub sigue
  `origin/fase2-integracion`, igual que lo unido.
- **Versiones en App Store Connect:**
  - **1.0 (build 11):** el 7-nov se envió a revisión con la suscripción «Chirogra monthly» y su grupo. Apple la
    **rechazó** porque la descripción no tenía el enlace a las condiciones de uso (EULA). El 9-nov el usuario la
    **reenvió** con el **build 11** (en revisión esa noche): descripción completa con «Privacy Policy: …» y «Terms of Use: …» al final (en/es,
    iOS y macOS; texto en APP-STORE.md) y «Chirogra monthly» en el envío; **el plan de contadores NO va en la 1.0**.
    El aviso «Newer Build Available» es normal: se pulsa Submit.
  - **1.0.1 (build 15): enviarla en cuanto Apple apruebe la 1.0.** El build 11 tiene el fallo de iCloud en Producción
    (no sincroniza nada; ver «Lo aprendido») y el 15 lo arregla. Crear la versión 1.0.1 (iOS y macOS), elegir el build
    15, notas: «La app del Mac recibe al momento los cambios de tus otros aparatos; un aparato nuevo trae tus libros de
    iCloud sin pedir el alta».
  - **1.1.0 (builds 16 a 21, TestFlight):** la fase 2 entera. El **21** (`467cdcf`) lo prueba el usuario; el **22** (`3662619`, subido
    el 10-nov para iOS y macOS) lleva además la bienvenida en carrusel (abajo). **Toda la fase 2 va en la 1.1** (decisión del
    9-nov: no se esconde nada para 1.2/1.3), con el plan de contadores en el envío.
- **Bienvenida en carrusel (aprobada por el usuario el 10-nov en su iPhone; build 22):** opción B del canvas «Chirogra — Bienvenida»
  (https://claude.ai/artifact/PB4NmST2UPeAA3wTZFjres) en `Onboarding/WelcomeView.swift`. Sale sin empresas antes del
  alta (ajuste `welcome.seen`); «Crear mi empresa» → paso 1, que ya no lleva los datos de ejemplo ni el aviso de iCloud
  (pasaron a la última página; «Atrás» del paso 1 vuelve a ella). Botones en vidrio, no morados como el canvas.
  `-qa.bienvenida N` la abre en la página N; `-qa.muestra` y `-qa.alta` la saltan.
- **Esquema 4 desplegado a Producción** (8-nov). El build 20 se probó en Producción en el iPhone y el Mac del usuario
  (8-nov): sincronizan libros, clientes, empresas, banca y recibos. `/Applications/Chirogra.app` y la app del iPhone
  tienen esa compilación de prueba (Debug, entorno Production); instalar encima desde TestFlight conserva los datos.

**Siguiente (orden acordado el 10-nov):**

*A. Ahora, mientras Apple revisa la 1.0 (todo entra en la 1.1, sin tocar el esquema de iCloud):*
1. Usuario: probar los builds 21 y 22 de TestFlight.
2. Usuario: terminar el plan de contadores en App Store Connect (en borrador desde el 10-nov, con su captura). Falta:
   textos (en `Chirogra for Accountants` / `Unlimited businesses, each with its own books.`; es `Chirogra para
   contadores` / `Empresas sin límite, cada una con sus libros.`), disponibilidad, comprobar $99.99 y 2 semanas gratis,
   **nivel 1** del grupo (salió en el 2). No pulsar «Add for Review»: va **con la 1.1**. Mientras no esté completo, la
   sandbox no lo devuelve («Subscription Unavailable»): para capturarlo, `SKTestSession` o ejecutar desde Xcode.
3. **Panel de clientes: HECHO el 10-nov, en el build 23** (`5473946`, subido el 10-nov para iOS y macOS). Canvas «Chirogra — Panel de
   clientes» (https://claude.ai/artifact/46eihuFoKbh8RrMEvHHNxA), encargo en `docs/PANEL-CLIENTES.md`. Datos:
   `Bookkeeper.clientSummaries` (`ChirograData/Bookkeeper+Clients.swift`, pruebas en `ClientSummaryTests`): estado
   (urgente: sales tax vencido o a ≤ 7 días, o banco sin conciliar > 60 días; pendiente: banco por revisar, facturas
   vencidas, conciliación > 30 días o avisos), sales tax del último periodo sin pagar (o el del periodo en curso),
   la cuenta más atrasada en conciliar, cierre y último asiento. Pantalla: `ChirograUI/Clients/ClientsView.swift`
   (iPhone: tarjetas; iPad y Mac: `Table`; Mac: inspector y menú contextual). Navegación: `ClientsRouter` —
   `AppSection.clients` arriba en la barra lateral (se abre al arrancar), en el iPhone el panel tapa las pestañas
   al abrir e Inicio lleva «‹ Clientes»; «Todos los clientes» en el selector de empresa; cada pendiente cambia de
   empresa y abre su pantalla (`ClientRoute`, la recoge cada pantalla con `onClientRoute`). Existe con el plan para
   contadores o con más de una empresa. «Clientes» del panel es la clave `clients.title` («Clients»; el de Ventas
   es «Customers»). Decisiones del usuario: Clientes como pantalla principal del iPhone y filtros en cápsulas.
   Probado en simulador (iPhone: todas las rutas con una prueba de UI; iPad claro y oscuro) y copia del Mac.
4. **Reclasificar en lote: HECHO el 10-nov, en el build 24.** «Reclasificar gastos…» (`Expenses/ReclassifyExpensesView.swift`;
   menú «···» de Gastos en iPhone e iPad, «Reclasificar…» en la barra del Mac): categoría actual + periodo, gastos
   marcados, categoría nueva. `Bookkeeper.reclassifyExpenses` cambia solo las líneas de la categoría actual con
   `updateExpense` (reversión + asiento nuevo); los de periodo cerrado se cuentan aparte (`ReclassifyTests`). Los
   movimientos del banco ya categorizados no entran (crean gastos, que sí entran; los depósitos no).
5. **Arreglos menores: HECHOS el 10-nov, en el build 24.** Puerto Rico 10.5 % estatal comprobado (IVU 11.5 % = 10.5 +
   1 municipal, guías de 2026 de terceros); al cambiar el estado en Ajustes se crea su tasa
   (`Bookkeeper.stateChanged`, y pasa a predeterminada si la anterior era la estatal sola; `StateChangeTests`); los
   fallos de la tasa o del saldo de apertura tras crear la empresa salen en un aviso de la raíz (`SetupIssue`); el
   aviso 1099 del Mac solo cuenta a los que llegan al mínimo. Ya estaban: la nota «Todo se lee en este aparato» y el
   aviso de la primera lectura del recibo (también en el Mac). **No hecho:** el permiso de red del Mac solo hace falta
   para bajar la tabla de sales tax por código postal (`PostalTaxTableLoader.remoteURL`), y su fuente está sin decidir.
6. Build 24 con 4 y 5, subido el 10-nov.

*B. Cuando Apple apruebe la 1.0:*
7. Usuario: enviar la 1.0.1 (build 15).
8. Enviar la 1.1.0 (último build): capturas nuevas (carrusel y panel), notas «What's New» en/es, notas para el revisor
   y el plan de contadores en el mismo envío.

*C. 1.2, sin servidor pero con cambio de esquema (desplegar a Producción y probar, ver «Lo aprendido»):*
9. Asientos de ajuste marcados como del contador.
10. Bitácora de cambios (quién cambió qué y cuándo, también lo borrado).
11. Banca: dividir un movimiento en varias cuentas y motivo al excluir.

*D. 2.0, con servidor (Supabase, proyecto aparte; PLAN-FASE2.md «Después: con servidor»):*
12. Plaid (plan «Chirogra + Banco»; entra a la bandeja «Por revisar» como otra `BankTransactionSource`). Cambia la
    promesa de privacidad: texto de la bienvenida, política y etiqueta de la tienda.
13. El contador dentro de los libros del cliente: usuarios y permisos, preguntas al cliente sobre movimientos.
14. Stripe Connect (cobro por enlace en la factura), sales tax exacto por dirección.
15. Nómina con un proveedor embebido (Gusto Embedded o Check), plan más alto.

*Fijo cada año:* actualizar el mínimo del 1099-NEC (`Form1099.swift`, `inflationAdjusted`).

## Pendiente menor y sin comprobar

- Sin decidir: quien tenga libros en la 1.0 con iCloud apagado y estrene otro aparato con la 1.0.1 ve el alta; el aviso
  `OtherDeviceSection` del alta le dice que encienda iCloud en el primero.
- **1099-NEC:** la tabla `inflationAdjusted` de `ChirograData/Form1099.swift` ($600 hasta 2025, $2,000 desde 2026) hay
  que **actualizarla cada año** cuando el IRS publique la cifra.
- Sin comprobar: VoiceOver de verdad y letra grande; correo real (`MFMailComposeViewController`, `NSSharingService`);
  logo desde Fotos; un cargo automático que se cobre solo al vencer; registrar y revertir un asiento en pantalla en el
  Mac; si el botón de idioma del alta abre la página de Chirogra en Ajustes o la raíz.
- **No construido a propósito (espera al servidor):** Plaid, Stripe Connect, sales tax exacto por dirección, usuarios y
  permisos, «Vista por el cliente», nómina (PLAN-FASE2.md, «Después: con servidor»).

## Estado de las cuentas y servicios

- **App Store Connect:** app «Chirogra» (iOS + macOS, English (U.S.), bundle `com.chirogra.app`, Apple ID 6830687358,
  SKU CHIROGRA-001). Suscripción `com.chirogra.app.mensual` («Chirogra monthly», grupo «Chirogra», 1 mes, 2 semanas
  gratis). Categoría, «Data Not Collected», 4+ y notas de revisión en APP-STORE.md. Capturas en el escritorio del
  usuario («Chirogra – capturas App Store»; en el Mac se captura a 1624×986 y se compone en 2880×1800).
- **iCloud:** contenedor `iCloud.com.chirogra.app` (App ID `com.chirogra.app` con iCloud + Push). Esquema 4 en Producción.
  En Producción quedan datos de ejemplo de las pruebas: se borran con «Empezar con mi empresa».
- **Web:** https://chirogra.com, GitHub Pages desde `sitio/` de `main` (workflow «Sitio», se publica al empujar).
  Dominio del usuario en Cloudflare, DNS «DNS only» (4 A y 4 AAAA de GitHub Pages, `www` CNAME →
  `ivanngarcia81.github.io`). Privacidad `/privacidad/` · `/privacy/`, soporte `/soporte/` · `/support/`, guía
  `/guia/` · `/guide/` (con glosario: al cambiar un menú de la app, ponerlo al día en los dos idiomas; al cambiar una
  pantalla, rehacer su captura).
- **Correo:** `soporte@chirogra.com` se reenvía al Gmail del usuario con Cloudflare Email Routing (activado el 9-nov;
  MX `route1-3.mx.cloudflare.net`, SPF y DKIM `cf2024-1` puestos por Cloudflare). Solo recibe: para enviar desde esa
  dirección haría falta otro servicio.

## Decisiones del usuario (no deshacer sin preguntar)

- **Precio:** plan normal mensual con 14 días gratis, $24.99 los 3 primeros meses de lanzamiento y luego $29.99 para los
  nuevos (los suscritos conservan su precio). **Plan para contadores: $99.99 al mes** (9-nov; QuickBooks Online
  Accountant es gratis para el contador y cobra $38–$340 al mes por empresa cliente). Con el banco, plan
  «Chirogra + Banco» a $39.99.
- **Suscripción vencida = solo lectura** (se ven los libros, copias, CSV y PDF; no se registra nada). «Canjear código»
  en Ajustes › Suscripción y en la pantalla de planes.
- **Empresas:** plan normal, 1; **plan para contadores, sin límite** (`CompanyLimits.accountant`). Las archivadas y la de
  ejemplo **cuentan**. Sin el producto de contador a la venta, el límite es 1. Al bajar de plan se conservan y usan
  todas. En TestFlight (sandbox) no hay límite, para probar. Una empresa pasa de un plan a otro con la copia
  `.chirogra`. El contador dentro de la app del cliente (caso B) espera al servidor.
- **Banca:** las reglas creadas desde la bandeja solo proponen; número de pendientes en la barra lateral; «Por revisar»
  arriba en el iPhone si hay pendientes. **Recibos:** tabla de sales tax de fuentes oficiales (SST, 24 estados); el
  lector se prepara al abrir la app. **Reportes:** presupuestos dentro de Reportes; el flujo de efectivo sigue la base.
- **Diseño:** rediseño nativo según el canvas (manda el canvas salvo lo de esta lista). Botón principal en vidrio sin
  relleno (`.glass`), nada de botones morados. Pestañas del iPhone: Inicio · Ventas · Gastos · Banca · Más (Reportes e
  Impuestos en «Más», Impuestos antes que Contabilidad). Fila elegida de la columna maestro rellena de Tinta. iPad:
  maestro-detalle; Mac: tabla a todo el ancho + inspector de ~300 pt (⌥⌘I), densidad de Mac (28 pt; barra lateral 220 pt
  en Mac, 280 en iPad). **Elevación «como Tamio»** (8-nov): en el Mac, suelo gris `Palette.background`, tarjetas y
  tablas blancas `Palette.surface` con filo y sombra corta (`macElevation`), inspector sin fondo propio; en el iPad
  `padElevation` y las listas maestro en `Palette.masterColumn`. Ajustes del Mac con tarjetas propias
  (`Settings/SettingsCards.swift`).
- **Ícono:** la χ (build 20, `App/AppIcon.icon`); `LogoMark` dibuja la misma χ dentro de la app. El de la web
  (`sitio/img/icono.png`, 256 px) sale del `AppIcon.icns` de la compilación del Mac (`iconutil -c iconset`).
- Gastos y Banca arrancan en el último mes con movimientos; la tarjeta de Gastos suma solo gastos. Método de pago según
  la cuenta (banco → débito/transferencia/cheque; tarjeta → tarjeta; caja → efectivo).
- **Editar algo contabilizado = reversión + asiento nuevo** (DISEÑO §6.5). Una factura emitida sin cobros se edita así
  (mismo número, «Editada» en Actividad).
- **Alta:** idioma, estado → «Tasa de Texas» fija → ciudad → tasa de la ciudad → total sumado (máx. 20 %), tipo de
  empresa, saldo inicial opcional. «Sales tax por pagar · Vence el …» en Inicio.
- **Nómina:** sí, pero junto con el servidor, integrando Gusto Embedded o Check (no desde cero).
- **Cobro en línea:** hoy, enlace de pago propio («Pagar ahora» y QR). Con servidor: Stripe Connect (el dinero no pasa
  por Chirogra), cuenta puente «Fondos no depositados», en el plan «Chirogra + Banco».
- El guion de prueba del usuario (artículo 32kiNBUgqBpqTrZ4MTfgc7) está **terminado**: no pedir otra ronda salvo que él
  lo pida.

## Lo aprendido (no repetir errores)

- **CloudKit en Producción es para siempre:** solo añadir (opcionales o con valor por defecto), **nunca renombrar** (con
  CloudKit Core Data se niega y la app se cierra al abrir; `originalName` no sirve), nunca reutilizar un nombre, ningún
  nombre reservado (`entityName` choca con `CD_entityName`: en Desarrollo llega vacío y en Producción rechaza el lote
  entero; ese fue el fallo de la 1.0). Migraciones que mueven datos, a medida (`willMigrate`/`didMigrate`, como
  `migrateV2toV3`). Lo vigilan `CloudKitSchemaTests` y `MigrationTests`. Reglas completas en PLAN-FASE2.md.
- **Cambio de esquema:** `-qa.esquemaCloudKit 1` (Debug, Mac con iCloud; resultado en el ajuste
  `qa.esquemaCloudKit.resultado`) → el usuario despliega en la consola de CloudKit («Deploy Schema Changes…») →
  **probar en Producción** con una compilación firmada por el equipo con
  `com.apple.developer.icloud-container-environment = Production` (así se usan los `-qa.*`). El registro de CloudKit se
  ve con `devicectl … --console`, `DEVICECTL_CHILD_OS_ACTIVITY_DT_MODE=enable` y `-com.apple.CoreData.CloudKitDebug 3`
  (con la app de TestFlight no sale). Al cambiar el esquema, volver a ejecutar `scripts/gen-backup.py` (`BackupTests`
  lo exige).
- **Un almacén por empresa en el mismo contenedor NO sirve** (comparten la zona de CloudKit y se mezclan): por eso un solo
  almacén con `companyID` en cada registro.
- **iCloud:** el Mac tiene que registrarse para los avisos push (`ChirograAppDelegate`) o no importa hasta reabrir.
  `ChirograStore.resolveSyncPreference()` enciende iCloud la primera vez si no hay libros locales (`hasLocalBooks(at:)`
  abre la base y busca una empresa) y lo deja apagado si los hay.
- **Cuelgue al 100 % de CPU** con `navigationDestination(isPresented:)` + `@CompanyQuery`: usar
  `StablePage`/`stableDestination` (`Shell/CompanyScope.swift`).
- **macOS 27:** `controlBackgroundColor` y `windowBackgroundColor` son blancos los dos (por eso colores fijos). Un
  `ScrollView`/`Form` estrecho hace que la barra pinte su franja blanca solo encima de él: el contenedor de desplazamiento
  a todo el ancho y la columna dentro (`SettingsForm`, alta con `contentMargins`). Las secciones del `Form` `.grouped`
  del Mac no admiten `listRowBackground` ni `backgroundStyle`.
- `Shape` con aislamiento MainActor por defecto: declararlo `nonisolated`.
- Con la hoja de suscripción abierta, `quit` por AppleScript falla («User canceled (-128)»): usar `kill`.
- La prueba de humo de `BankingView` con `ImageRenderer` se cae en ese renderizador (en pantalla funciona).
- **StoreKit en el simulador:** con `xcodebuild test` no se usa `App/Chirogra.storekit` (ni poniéndolo en la acción de
  pruebas del esquema): el simulador pregunta a la sandbox de verdad, que solo devuelve productos completos en App Store
  Connect. Para capturar la pantalla de compra: en la prueba de `UITestsQA`, `SKTestSession(configurationFileNamed:)`
  con el `.storekit` como recurso del target de pruebas. Muestra el nombre interno del producto y lo guarda en caché.
- En el simulador, `simctl uninstall` con el simulador apagado no hace nada: arrancarlo antes (`simctl boot` y
  `bootstatus`), o los datos de la prueba anterior siguen ahí.
- Animaciones de entrada: un cambio de estado en `onChange(initial: true)` u `onAppear` cae en la misma pasada en que
  aparece la vista y SwiftUI lo pinta ya terminado. Usar `.task(id:)` con una espera corta (la bienvenida usa 150 ms).
  Las capturas finales no lo delatan: comprobarlo con varias capturas seguidas (`simctl io … screenshot` en bucle).
- Para ver la bienvenida en el iPhone del usuario sin tocar su app: copia «Chirogra Prueba»
  (`com.chirogra.qa.bienvenida`, entitlements vacíos y, solo en la copia, `resolveSyncPreference` con iCloud apagado).

## Reglas de trabajo

- **Commit y push solo cuando el usuario lo pida** (suele decir «commitea y empújalo»). Instalar en los aparatos cuando
  lo pida.
- **Verificar uno mismo antes de pedirle que pruebe:** simulador, copia de prueba del Mac y aparatos (abajo).
- Accesibilidad: 44 pt en iOS, Dynamic Type, VoiceOver, contraste AA. Bilingüe: textos nuevos en
  `App/Localizable.xcstrings` con su inglés y los mismos marcadores (`%@`, no `%1$@`; lo exige `StringCatalogTests`).
- Hojas de editor con `.editorSheetSizing()`; formularios con `.formStyle(.grouped)` (o `SettingsForm` en Ajustes).
- Avisar antes de borrar nada del ordenador del usuario. No cambiar ajustes del sistema ni de Xcode. **No buscar claves
  ni credenciales en el ordenador del usuario.** No mover el ratón del Mac: el usuario lo usa.
- El canvas de Claude Design es de solo lectura: https://claude.ai/artifact/Ai344mUq54BECC4Pw4quV9 (herramienta
  Artifact, `path: project/<tablero>.dc.html`).
- **No tocar el simulador de iPad `BEB1EA39`:** es de otro proyecto (Tamio).

### Equipo de agentes
Para bloques grandes, el coordinador lanza agentes en worktrees (`isolation: worktree`; la sesión tiene que estar con el
directorio actual dentro del repo), **cada uno con archivos distintos y su propio simulador y copia del Mac**. Si hay que
cambiar el modelo, primero un agente de datos y después los de pantallas. Los agentes hacen commit en su rama; el
coordinador los junta en una rama de integración, compila, pasa `swift test`, revisa en pantalla y, cuando el usuario lo
aprueba, pasa a `main`. Después se borran las worktrees y ramas.

### Fusionar el catálogo de textos
Si dos ramas añaden textos, git choca en `App/Localizable.xcstrings`. Usar `scripts/merge-xcstrings.py` (las tres
versiones salen de `git show ":1:App/Localizable.xcstrings"`, `":2:…"`, `":3:…"`; en zsh, con comillas). Revisar a mano
las claves que lista como cambiadas en las dos ramas.

## Proyecto, subidas y aparatos

- **Proyecto:** `project.yml` es la fuente; se regenera con `xcodegen` **en una copia** (scratchpad) y se copian al repo
  `project.pbxproj`, el esquema, `Info.plist` y los `.entitlements`, comparando antes con `diff`.
- **Subir un build:** `CURRENT_PROJECT_VERSION` en `project.yml` **y** en el pbxproj (comprobar con xcodegen en una copia
  que coinciden); `MARKETING_VERSION` si cambia la versión. Desde un clon limpio del commit: `xcodebuild archive`
  (Release, `-destination 'generic/platform=iOS'` y luego `'generic/platform=macOS'`,
  `DEVELOPMENT_TEAM=4N9XEU7F4P -allowProvisioningUpdates`) y `xcodebuild -exportArchive -exportOptionsPlist <plist>
  -allowProvisioningUpdates` con `method` `app-store-connect`, `destination` `upload`, `teamID` 4N9XEU7F4P,
  `signingStyle` `automatic`. Usa la cuenta del usuario en Xcode. El usuario prefiere que se suba directamente.
- **StoreKit:** `App/Chirogra.storekit` en el esquema de Xcode: al ejecutar desde Xcode se compra de prueba. Fuera de
  Xcode, o con otro bundle id, la pantalla dice «Subscription Unavailable» (normal).
- Equipo de firma `4N9XEU7F4P`, bundle id `com.chirogra.app`. iPhone 17 Pro Max `00008150-0005793E3EC0401C`; iPad Pro
  12,9″ (5.ª gen.) `00008103-001439A91E6B001E`.

### Comprobar en pantalla
- **Simulador** (iPhone/iPad): pruebas de interfaz temporales con un target `UITestsQA` añadido a `project.yml` +
  `xcodegen`, en una copia del repo en el scratchpad (**nunca commitear** `UITestsQA`, el cambio de `project.yml` ni el
  `.xcodeproj` regenerado). Las capturas horizontales salen giradas.
- **Mac sin tocar los datos del usuario:** copia de prueba con otro identificador (`PRODUCT_BUNDLE_IDENTIFIER=com.chirogra.qa.<nombre>
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS=<un .entitlements con <dict/>>`),
  arrancada con `open -g -j -n <app> --args -iCloudSyncEnabled NO -qa.…` (REDISEÑO-NATIVO §5: `-qa.muestra 1`,
  `-qa.seccion`, `-qa.ajustes`, `-qa.suscripcion activa|vencida|contador|nueva`, `-qa.apariencia claro`…). Captura con
  `screencapture -l <windowID> -o -x` (id por PID con `CGWindowListCopyWindowInfo` con `optionAll`; las hojas son
  ventanas aparte). Al terminar, `kill` del PID y `rm -rf ~/Library/Containers/com.chirogra.qa.<nombre>`. System Events
  busca procesos por nombre: si hace falta accesibilidad, renombrar la copia («ChirograQA»).
- **Aparato físico:** `xcodebuild test … -destination 'id=<UDID>' -resultBundlePath r.xcresult DEVELOPMENT_TEAM=4N9XEU7F4P
  -allowProvisioningUpdates` con capturas como `XCTAttachment` (`xcrun xcresulttool export attachments`); al terminar,
  `xcrun devicectl device uninstall app --device <UDID> com.chirogra.uitestsqa.xctrunner`. Cambia los datos del usuario.

### Instalar en los aparatos
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

Problemas conocidos: si el aparato sale «desconectado», reintentar. «The developer disk image could not be mounted» o
«device was still locked» = desbloquearlo y reintentar. Al empujar en zsh, el hash entre comillas
(`"<hash>:refs/heads/main"`).
