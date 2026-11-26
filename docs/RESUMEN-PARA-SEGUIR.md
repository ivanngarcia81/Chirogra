# Chirogra: resumen para empezar el siguiente chat (25-nov-2026, rama `version-1.4` EMPEZADA; 1.3.0 EN LA TIENDA con el 64)

Lee esto primero y después [CONTEXTO.md](CONTEXTO.md), que tiene el detalle («Dónde nos quedamos» y «Lo aprendido»).
**Al usuario se le habla siempre en español.**

## Estado

- **Último build: 67 (1.4.0)**, subido a TestFlight iOS y macOS el 26-nov: el asistente con los lápices del icono en vez
  de la chispa, y en el iPad y el Mac su panel con cabecera propia (la «X» dentro del panel), línea divisoria y fondo
  gris más claro (`Palette.assistantPanel`). Antes: 66 (1.4.0), subido el 25-nov (`c0c2e33`): agenda (avisos y Calendario),
  impuestos estimados y asistente sin servidor. **Esquema 6 de CloudKit creado en Desarrollo el 25-nov
  (`-qa.esquemaCloudKit 1` → «listo») y DESPLEGADO A PRODUCCIÓN por el usuario el 25-nov** («Deploy Schema Changes…»):
  el 66 ya se puede usar con libros reales.
  Antes: 65 (1.3.0, 23-nov, `00ace74`): auditoría técnica y pruebas de interfaz. Antes: 64 (21-nov noche, icono «chirogra pencils»); del 22 al 63, en la tabla.
- **En App Store Connect:** la **1.0 quedó aprobada el 22-nov con el build 15**, y **la 1.3.0 (iOS y macOS, build 64,
  con la suscripción «Chirogra para contadores») está APROBADA y EN LA TIENDA** (lo dijo el usuario el 25-nov; textos en
  APP-STORE.md, «Envío de la 1.3.0 tras aprobarse la 1.0»). El 65 (auditoría técnica) solo está en TestFlight: sus
  arreglos y los de los testers salen con la siguiente versión (1.4, o una 1.3.1 si algo es grave). Se saltaron la 1.0.1, la 1.1 y la 1.2 (decidido el 13-nov): el «What's
  New» junta las tres. iOS y Mac llevan textos distintos (el Mac sin recorrido ni líneas del iPhone/iPad, y «adjunta» en
  vez de «escanea» recibos). Si Apple rechaza algo, el usuario trae el mensaje del Resolution Center. Si la web de App
  Store Connect falla (sin apps, lo saca al entrar), suele ser la sesión de Safari (pestaña privada / borrar datos).
- **Rama de trabajo: `version-1.4`** (1.4.0, creada el 25-nov desde `version-1.3` en `81f8708`; build 66; empujada el
  25-nov junto con `version-1.3`). La 1.4
  tiene su canvas: https://claude.ai/artifact/GDQsZiSZRruwx3PhhLytyt (encargo en [DISEÑO-1.4.md](DISEÑO-1.4.md)).
- **Ramas:** `version-1.3` con el 65, sus docs y `81f8708` (arreglos de Yurii S.), **empujada el 25-nov** (GitHub Actions en verde: pruebas, compilación y
  las 4 de interfaz). `main` en `83b1db4` (build 50 y la web con «Kairogra»), empujada el 17-nov; los builds de después
  no tocan la web (`sitio/`, se publica desde `main`), así que no hace falta moverla.
- **Testers externos** (Userbrain, Beta Family, UXtweak) entran con el enlace público
  https://testflight.apple.com/join/RGwqqUyw; el usuario asigna cada build a ese grupo (el 22-nov seguían con el 61).
- **Aparatos del usuario:** iPhone con TestFlight (build 59 el 21-nov). **iPad Pro 12,9″ con el Debug del código del
  61** (Producción), instalado a petición suya el 21-nov: ahí la hoja de planes sale al abrir porque el Debug usa otra
  tienda de prueba sin su suscripción (no es un fallo; CONTEXTO, «Dónde nos quedamos»). Mac: TestFlight.
- **Capturas de la tienda:** las seis `00-bienvenida.png` de `~/Desktop/Chirogra – capturas App Store` (en y es; iPhone
  6.9, iPad 13, Mac) **rehechas el 23-nov** con el icono «chirogra pencils»; las viejas, en «Anteriores bienvenida (logo
  χ)» de la misma carpeta. El logo de `~/Desktop/Chirogra-logo` (cuadrado a sangre y redondeado, 1024 px, sRGB)
  **rehecho el 23-nov** con el icono nuevo (los viejos, en «Anteriores (logo χρ)»); el cuadrado es el del App profile de
  Plaid.
- **Plaid para la 1.5 (antes 2.0):** equipo nuevo **«Chirogra»** (`6b04d81ce1b977000ef535cc`; el de Tamio es otro),
  solicitud enviada el 23-nov y **PRODUCCIÓN APROBADA el 24-nov** (Pay As You Go; Transactions, Balance y Statements; uso
  «SMB bookkeeping»). Quedan las tareas del Home del panel: **Add use case descriptions** (Link › Data Transparency
  Messaging: casos de contabilidad/finanzas del negocio, nada de pagos ni préstamos; **Publish**), Compliance Center (registro OAuth de los bancos) y la
  redirect URI `https://chirogra.com/plaid-oauth`. Política de seguridad para el cuestionario en
  [SECURITY-POLICY.md](SECURITY-POLICY.md) y en PDF en `~/Desktop/Chirogra-Information-Security-Policy.pdf` (si se
  cambia, regenerarlo: Markdown → HTML → Chrome sin cabecera). Dependabot (alertas y actualizaciones de seguridad), escaneo
  de secretos y protección al empujar **activados el 23-nov** en el repo (público; 0 alertas). Compromete además a borrar del buzón lo no recogido en 30 días y a borrar la cuenta desde
  la app.
- **Orden de versiones (decidido el 25-nov):** **1.4** agenda + asistente con Claude + **apartado para impuestos
  estimados** (pedido de un cliente, confirmado el 25-nov) → **1.5** banco con Plaid y plan «Chirogra + Bank» (reutiliza
  el servidor de la 1.4) → **2.0** contador dentro, Stripe y nómina. Planes en [PLAN-1.4.md](PLAN-1.4.md) y
  [PLAN-2.0.md](PLAN-2.0.md) (§1 Plaid es ahora la 1.5).

El detalle de cada build del 49 al 64 (los antiguos puntos «0.» de «Lo siguiente») se quitó el 23-nov para que no se
acumule: está en `git show 1fe35ff:docs/RESUMEN-PARA-SEGUIR.md` y en los mensajes de los commits.

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
| 50 | `9f32335` | 1.3.0: aviso de iCloud en una línea con «×» (sin cuenta, nota azul que no vuelve; «Detalles» con el código), «Marcar como pagada · $X», botón «Precio» en la barra del teclado, «Registrar gasto» en la ficha de la cuenta, «Por cobrar» en grande. 346 pruebas. |
| 51 | `4d84399` | 1.3.0: recorrido de la primera vez en cada pestaña del iPhone (estilo A «Foco» de Claude Design), «Ver el recorrido otra vez» en Más › Ayuda; fuera la pista de personalizar la barra. 346 pruebas. |
| 52 | `5643a27` | 1.3.0: tras un tester de Beta Family: al borrar los datos de ejemplo el recorrido vuelve a salir con la empresa propia; «Sin cuenta ni contraseña: tus libros se quedan en tus aparatos y en tu iCloud.» en la última página de la bienvenida. 346 pruebas. |
| 53 | `a5f6468` | 1.3.0: tras Yurii S. (tester de pago de Beta Family; iPhone 16e, iOS 26.7.1, letra XL, región de Ucrania, oscuro): en Ventas, si «1 570,00 US$ of 2 570 US$» no cabe junto al cliente, «of …» baja a su línea (salía «M…»); «Ver el recorrido otra vez» lleva a Inicio; defensa del hueco del teclado sin teclado (`ignoringStaleKeyboardSpace`; lista cortada y barra de Total a media pantalla, no reproducido). 346 pruebas. |
| 54 | `801e8c3` | 1.3.0: **«Tutorial completo»** en Más › Ayuda (cada pantalla del iPhone explica todos sus botones la primera vez; el corto no cambia); **iOS 27**: los pasos que iluminan botones de la barra de arriba ya no se saltan (`marcoEnVentana` mira `accessibilityElements`); en Inicio el recorrido ilumina el título del grupo con su tarjeta (iPhone 13 mini, Jiga T. de Beta Family). 177 + 75 pruebas. |
| 55 | `216d429` | 1.3.0: tras Yurii S. (Beta Family, build 54; iPhone 16e, formato de Ucrania, oscuro): **campos de dinero** que se editan sin la moneda (`MoneyField`: «10,99» al escribir, «10,99 US$» al salir; antes lo tecleado se pegaba tras «US$» y el importe no cambiaba: «10,99 US$80», «1,00 US$896253»; en EE. UU. «$510.99»); lee coma o punto decimal; **difuminado** (`.ultraThinMaterial`) en la primera tarjeta de cada recorrido, la que no ilumina nada. 177 + 75 + 87 pruebas (`ScreenSmokeTests` ya se caía en el 54: `ImageRenderer`, «no current update to enqueue action to»). |
| 56 | `130588b` | 1.3.0: tras Eric (Beta Family, build 55; iPhone 13, iOS 27.2.1; app 3/5, recomendación 2/5) y un **repaso visual** de toda la app. 350 pruebas (94 + 181 + 75). |
| 57 | `c13f955` | 1.3.0: en «Nuevo gasto › Recibo» los tres botones (escanear, foto, archivo) vuelven a ir **uno por fila**; salían amontonados en una sola (captura del usuario con el 56; venía del 54). 350 pruebas. |
| 58 | `944e0ad` | 1.3.0: **Clientes** sin avisos encimados (con un filtro vacío, «Nothing to handle» se montaba sobre «¿Llevas los libros de otro negocio?»; captura del usuario) y **«Idioma»** en Más › Moneda y formatos lleva a Ajustes › Apps › Chirogra. 350 pruebas. |
| 59 | `34f6cc0` | 1.3.0: **anular un cobro** (pendiente del informe de Eric): cada cobro en su fila de «Actividad» de la factura; tocarlo o «⋯ › Anular cobro…» lo revierte en su fecha, la factura vuelve a quedar pendiente y el movimiento del banco enlazado vuelve a «Por revisar». 355 pruebas. |
| 60 | `229695f` | 1.3.0: **iPad**: Conciliación y Reglas con lista y detalle; repaso de diseño de las 27 secciones (títulos de columna enteros, «Facturas», icono de color en Banca, Libro mayor con título grande, lápiz de Editar); detalles a 720 pt y reportes a 820 pt **centrados**; tabla de líneas de la factura alineada; **recorrido de la primera vez en el iPad**. 355 pruebas. |
| 61 | `8dbdd3b` | 1.3.0: `fieldBox` con 8 pt arriba y abajo («Notas y términos» de la factura ya no pega el texto arriba); en los detalles del iPad el dato gris va **en la misma línea** que el título (`TituloConDetalle`: líneas de factura, estimado, factura por pagar y asiento; historial del gasto). Capturas del usuario. 355 pruebas. |
| 62 | `b0a1777` | 1.3.0: revisión externa del 21-nov: copias `.chirogra` **con contraseña** (AES-GCM, PBKDF2; se pide al restaurar), números de documento repetidos tras sincronizar se renumeran (`resolveNumberCollisions`, bitácora y aviso), **sin `fatalError`** si la base no abre (`StoreRecoveryView`); iPad: todas las listas como Inicio. `scripts/verificar.sh` y GitHub Actions (`pruebas.yml`, runner `xcode-27`). |
| 63 | `864153d` | 1.3.0: iPad: Libro mayor, Cierre, Bitácora e Impuestos a 820 pt centrados; Ajustes en la tarjeta gris; Bitácora con lista y detalle; más aire en deducibles y estados. Capturas del usuario. |
| 64 | `b2c8e43` | 1.3.0: **icono «chirogra pencils»** (lapicero y lápiz cruzados en χ, ρ azafrán con brillo de lupa; archivo del usuario), también `LogoMark` y la bienvenida (`LogoGlyph`), el icono de la web y las capturas de la guía. **Enviado a revisión** (1.3.0 iOS y macOS) el 22-nov. |
| 65 | `00ace74` | 1.3.0: **auditoría técnica** (base caja con notas de crédito y saldo a favor, suma SHA-256 en las copias, aviso de iCloud en local, saldos rehechos tras sincronizar, importes en 128 bits, sales tax de las notas, aviso de tabla por ZIP vieja, no anular facturas con nota) y **pruebas de interfaz** en el repo (`PruebasInterfaz`, `scripts/interfaz.sh`). 403 pruebas + 4 de interfaz. |
| 66 | `c0c2e33` | 1.4.0: agenda (avisos, Calendario), impuestos estimados, asistente sin servidor (esquema 6). |
| 67 | — | 1.4.0: asistente con los lápices de Chirogra; panel del iPad y Mac con cabecera, «X», línea y fondo más claro. |

## Último chat (25-nov, tarde): informe de Yurii S. en el iPad y comienzo de la 1.4

- **Informe de Yurii S.** (Beta Family, iPad Pro 11″, iPadOS 26.7.1, formato de Ucrania; 4/5 general, **2/5
  facilidad**, 3/5 recomendar). Tres arreglos en `81f8708` (`version-1.3`), comprobados con una prueba de interfaz
  temporal en el simulador «iPad Pro 11-inch (M5)» `BEC858CE` que falla con el código de antes y pasa con este:
  importes en una línea en todas las tablas (`amountColumn(_:)`; «2 400,00 / US$» bajaba a dos líneas), la barra lateral
  guarda su desplazamiento (`Sidebar.scrollOffset`; se rehacía con cada página y volvía arriba) y la presentación de
  cada recorrido no se salta con un toque en su primer segundo (`Recorrido.tocarVelo`).
- **Pendiente de su informe:** pide un tutorial más simple que explique anular cobros y las líneas de la factura,
  «sobre todo en el iPad». Sin hacer; idea: «Void Payment…» también en la lista de cobros de la factura.
- **1.4 empezada** a petición del usuario: rama `version-1.4` (1.4.0) y encargo del canvas en
  [DISEÑO-1.4.md](DISEÑO-1.4.md) (agenda, asistente con opción A botón / B burbuja, permiso, apartado para impuestos).

## Chat anterior (23 al 25-nov): Plaid aprobado, 1.3 en la tienda, orden de versiones y testers

Sin código: todo fue trámites, decisiones y testers. Commits del chat: `cec3bf1` (resumen limpio), `ad732e0` (política
de seguridad), `d7a4663`, `a2d9a31`, `63c6ed4` (empujados); lo del 24–25-nov (este resumen y los planes), sin commitear hasta que el usuario lo diga.

- **La 1.3.0 está en la tienda** (iOS y macOS, build 64; el usuario lo dijo el 25-nov). Lo siguiente sale como 1.4.0 (o
  1.3.1 si un tester encuentra algo grave).
- **Plaid, equipo «Chirogra»:** pasos del panel hechos con el usuario por capturas (equipo nuevo, Pay As You Go,
  verificación del negocio, casos de uso, cuestionario de seguridad con [SECURITY-POLICY.md](SECURITY-POLICY.md) y su
  PDF, PDF de MFA del consumidor en `~/Desktop/Chirogra-Consumer-MFA.pdf`, logo cuadrado de `~/Desktop/Chirogra-logo`).
  **Producción aprobada el 24-nov.** Quedan las tareas del Home: **Add use case descriptions** (Link › Data
  Transparency Messaging; contabilidad/finanzas del negocio, nada de pagos ni préstamos; **Publish**; el usuario iba a
  mandar captura de la lista), Compliance Center (OAuth) y la redirect URI. Dependabot y escaneo de secretos activados.
- **Orden de versiones (25-nov):** 1.4 = agenda + asistente con Claude + **apartado para impuestos estimados** (un
  cliente preguntó por «R&B» y confirmó que quería apartar lo de cada trimestre: 1040-ES, 4 pagos al año; PLAN-1.4 §3);
  1.5 = banco con Plaid y plan «Chirogra + Bank», reutilizando el servidor de la 1.4; 2.0 = contador, Stripe y nómina.
  Recomendación mía (B) aceptada al decir «comenzar con la 1.4 y así subir la secuencia».
- **Asistente con IA:** se le explicó cómo funcionaría (botón arriba en Inicio / barra del iPad y Mac, ⌘K; guiar,
  registrar con borrador que él confirma, preguntas sobre los números, avisos; permiso la primera vez; 100 al mes). En el
  canvas de diseño de la 1.4 decide **botón o burbuja flotante**.
- **Apple Pay:** Chirogra no tiene código de Apple Pay (PassKit). A un cliente le salió «Set up Apple Pay»: es la hoja de
  compra de iOS al tocar un plan sin forma de pago en su cuenta de Apple; él dijo que fue por error. Cobro de facturas
  con Apple Pay: solo a través del enlace de Stripe/Square en «Pagar ahora» (y Stripe Connect en la 2.0).
- **Beta Family:** Jiga T. («iPad», en realidad iPhone 13 mini; recorridos ocultos por las marcas de iCloud de otra
  prueba, sin cambios de código). **Yurii S. (iPad, 25-nov)** se atascó con la tarea «factura de dos líneas → cobro →
  anular el cobro»: (1) la hoja de planes tras los 7 días (TestFlight no cobra, pero pide la contraseña de la cuenta de
  Apple, que no recordaba); (2) buscaba «Save»: en el iPad el botón es **«Issue Invoice»**, arriba a la derecha; (3) al
  emitir pregunta si enviarla («Not Now»); (4) **«Void Payment…» solo sale en «⋯» cuando ya hay un cobro**, y en el menú
  estaba «Void Invoice», que podía tocar por error. Se le guió paso a paso por el chat de Beta Family. Esperando su
  informe.
- **BetaTesting.com:** prueba «Single Session» para dueños de negocio (iPhone/iPad), 5 testers × 2 créditos, sin
  Expedite. Al lanzar salía «There are no published tasks/surveys…»: hay que publicar las tareas antes; no se sabe si
  ya lo arregló.

**Para los textos de los tests:** decir «Issue Invoice» y no «Save»; avisar «If a subscription screen appears, tap
"Try Free" (TestFlight never charges); have your Apple Account password handy»; separar crear factura, cobrar y anular
en pasos numerados. **Idea si más testers tropiezan:** «Void Payment…» también en la lista de cobros de la factura.

## Chat anterior (23-nov): auditoría técnica, pruebas de interfaz y build 65

Pedido del usuario: revisar a fondo un informe externo («Auditoría técnica y correcciones de Chirogra — Build 64») y
corregir desde la causa lo que fuera real. Commiteado en `205400a`; luego, a petición suya, pruebas de interfaz
(`0e9d365`) y **build 65 subido iOS y macOS** (`00ace74`). Empujado, Actions en verde. `scripts/verificar.sh` y `scripts/interfaz.sh`
en verde.

- **Base caja con notas de crédito (error real):** `cashBasisLedgerLines()` repartía cada cobro sobre la factura menos
  sus notas, calculado con los datos de hoy: una nota posterior reescribía periodos pasados (el día del cobro salía
  $125 haber / $25 debe), y el saldo a favor aplicado a **otra** factura no movía nada, así que cuentas y sales tax en
  caja salían mal (escenario $100 + nota $20 aplicada a otra de $50: 4000 = $100 en vez de $80, 4100 = $28.35 en vez
  de $50, sales tax $8.25 en vez de $6.60). Ahora cada documento lleva lo que le falta por reconocer
  (`CashBasisPending`) y los hechos se recorren por fecha (detalle en el comentario de la función y DATOS-V4 §4).
  Los reembolsos ya no se reparten entre todas las notas del cliente. `CashBasisCreditTests` (15 pruebas, una con
  historias al azar que comprueba que nada reescribe un día pasado y que, liquidado todo, caja = devengo por cuenta).
  Las pantallas con base caja (Reportes, Impuestos, Deducibles, Presupuestos) recalculan al aplicar saldo a favor
  (`CreditApplication` en la clave de su caché).
- **Copias (error real):** sin contraseña no tenían suma de comprobación (el zlib de Apple es DEFLATE sin suma): de 300
  copias con un bit cambiado, 80 se restauraban sin aviso con otros datos. Ahora el JSON lleva delante
  `"integrity":"sha256:…"` (`Backup+Integrity.swift`), mismo formato 1: las versiones anteriores la leen igual y las
  copias de antes se abren igual. `BackupIntegrityTests`. El cifrado (AES-GCM + PBKDF2) y la copia automática antes de
  restaurar ya estaban del build 62.
- **iCloud:** si el contenedor con CloudKit falla, la app abría el mismo almacén en local **sin decirlo**; ahora la
  franja de iCloud lo avisa (`ChirograStore.cloudKitOpenFailure`). Comprobado que en local se sigue guardando el
  historial que CloudKit sube después. Nuevo `reconcileDocumentBalances()` (`Bookkeeper+Consistency.swift`) tras cada
  sincronización: rehace lo cobrado, acreditado y reembolsado de facturas, facturas de proveedor y notas a partir de
  sus registros (dos cobros a la vez en dos aparatos dejaban la suma de uno solo); solo corrige lo que vio igual dos
  pasadas seguidas, con línea en la bitácora. `DocumentBalanceTests`, `StoreRecoveryTests`.
- **Importes extremos (error real):** `(a * b).dividedRoundingHalfAwayFromZero(by:)` en 64 bits cerraba la app: una
  factura de $100 millones con $10 millones de descuento. Ahora `Int64.multiplied(by:dividedRoundingHalfAwayFromZeroBy:)`
  en 128 bits en los 9 sitios. `LargeAmountTests`.
- **Sales tax:** el reporte restaba de cada nota de crédito el importe entero como gravable; con líneas no gravables no
  cuadraba con el diario. Ahora usa la base y el impuesto contabilizados (`issuedTaxableBase`). Aviso en la sugerencia
  por ZIP cuando la tabla tiene más de 100 días (`PostalTaxTable.isStale`; la incluida es del 11-nov-2026, así que el
  aviso sale desde el 20-feb-2027 si no se regenera). La descarga de chirogra.com (apagada) ya no puede poner una tabla
  más vieja. `SalesTaxCreditNoteTests`, `PostalTaxTableAgeTests`.
- **Migración real:** almacén escrito por el código de la 1.0 publicada (build 15, `c214680`, esquema 3) migrado con
  `CHIROGRA_STORE=… swift test --filter MigrationTests`: cuadra, sin huérfanos, nada que corregir en saldos. El almacén
  quedó en el scratchpad de este chat (se pierde); se regenera con un worktree de `c214680` y `SampleData.populate`.
- **Revisión independiente (agente) de la base caja y los saldos:** 4 hallazgos arreglados con su prueba (comprobado
  que fallan sin el arreglo): cada reembolso consume las notas que ya existían cuando se hizo (`refundAllocations`; una
  nota antedatada emitida después reescribía un mes pasado), signo al deshacer una toma fallida, confirmación de saldos
  por tiempo (10 min, no dos pasadas: una importación llega en varias tandas) y diccionarios sin cierre con ids
  repetidos. Además, ya no se puede **anular una factura con nota de crédito** aunque su cobro se haya anulado.
  403 pruebas (94 + 229 + 80).
- **Pruebas de interfaz (pedido del usuario):** objetivo `PruebasInterfaz` (`UITests/FlujosTests.swift`) con 4 flujos
  del iPhone que comprueban resultados, no solo que se dibuje: cobrar la F-1003 desde Inicio (Por cobrar baja $1,100.02),
  anular ese cobro (vuelve), emitir una factura nueva (Por cobrar sube su total) y Reportes en base caja (el cobro suma
  $1,092.40 a Total ingresos; en devengado nada). `-qa.reiniciar 1` (solo Debug) borra los libros al abrir.
  `scripts/interfaz.sh` y un trabajo `interfaz` en `pruebas.yml`, en verde en GitHub tras tres arreglos: el script
  propaga el fallo (con `pipefail`, `|| true` lo tapaba), arranca el simulador antes (en frío caducaba la primera
  prueba) y la prueba cierra el teclado con insistencia; si falla, Actions adjunta el `.xcresult` con capturas. En
  GitHub tardan unos 10 minutos (cada prueba 1–4 min). Truco:
  el precio de una línea se escribe con el botón «Precio» de la barra del teclado (tocar el campo a veces no da foco) y
  se confirma con «Listo»; las pruebas van con `@MainActor`.
- **Docs:** README al día (estado real, 1.4/2.0 como previstas, iCloud, `verificar.sh`); DATOS-V4 §4.
- **Pendiente:** `ScreenSmokeTests` sigue cayéndose (SwiftUI, «no current update to enqueue action to», también en
  serie); solo hay pruebas de interfaz del iPhone (ni iPad ni Mac); la tabla por ZIP no marca los ZIP que cruzan
  jurisdicciones (habría que regenerarla con los archivos oficiales); `Money(decimal:)` da un valor sin sentido por
  encima de ~$92 mil billones.

## Chat anterior (21-nov noche y 22-nov): build 64, aprobación de la 1.0 y envío de la 1.3.0

- **Tarea de Beta Family para revisar el iPad** (en inglés y español: About, What to test, 4 tareas y 5 preguntas
  aparte), dada en el chat.
- **Build 64 (`b2c8e43`):** el usuario pidió cambiar el icono por `~/Desktop/chirogra pencils.icon`. Copiado tal cual a
  `App/AppIcon.icon`; dentro de la app `LogoGlyph` (`DesignSystem/LogoGlyph.swift`, sustituye a `ChiGlyph`/`RhoGlyph`)
  dibuja las 7 piezas sacadas de los SVG de las capas, con `Palette.logoFill` (degradado P3 del icono), `logoTip` y
  `logoBall`; la bienvenida dibuja el contorno de cada pieza (lapicero, lápiz, ρ) y luego la rellena. Icono de la web
  con `ictool`; `bienvenida-es/en.jpg` de la guía rehechas con la copia QA del Mac (la clave del marco de la ventana
  cambió: CONTEXTO, «Ícono»). Visto en el simulador y el Mac; `verificar.sh --rapido` en verde. Subido iOS y macOS.
- **Apple aprobó la 1.0 el 22-nov con el build 15** (no el 11). El mismo día el usuario **envió la 1.3.0 (iOS y macOS)
  con el build 64** y la suscripción «Chirogra para contadores». Textos usados (What's New iOS, What's New Mac, notas
  de revisión iOS y Mac) en APP-STORE.md, «Envío de la 1.3.0 tras aprobarse la 1.0». Al crear la versión se puso
  `1.3.0` porque el build lleva ese número; la suscripción se añade en «In-App Purchases and Subscriptions» de la
  versión (no en «In-App Purchases › Create», que es para consumibles).
- **Capturas de la tienda:** las `00-bienvenida.png` llevaban el logo viejo (χρ); se rehicieron el 23-nov (ver «Estado»).

## Chat anterior (21-nov, mediodía y tarde): builds 59, 60 y 61

- **Build 59 (`34f6cc0`):** el usuario eligió hacer **«Anular cobro»**, el pendiente que quedaba del informe de Eric.
  Visto en el simulador y subido a petición suya.
- **Build 60 (`229695f`):** se puso a revisar la app **en su iPad** (Debug instalado desde el Mac) y mandó capturas con
  lo que veía mal rodeado: Conciliación y Reglas estiradas (pidió lista y detalle), «Sales sourcing» apretado, títulos de
  la tabla de la factura descolocados y la fila más baja que el campo, «Payables (0)» en dos líneas. Pidió además un
  **repaso de diseño de toda la app**: se capturaron las 27 secciones del iPad (con detalle) y del Mac, se arreglaron las
  diferencias y se le mandaron hojas antes/después. Decisiones suyas: reportes a 820 pt **centrados** (todos, también
  Presupuesto), detalles a 720 pt **centrados**, icono de color en las cuentas, y el **recorrido de la primera vez en el
  iPad** en el mismo build. Preguntó por qué en el iPad la hoja de planes salía enseguida.
- **Build 61 (`8dbdd3b`):** dos capturas más del iPad: «Notas y términos» con el texto pegado arriba, y el dato gris
  («1 × $50.00 · taxable», «Nov 21, 2026 · Current») que quería en la misma línea.
- **Cómo se trabajó:** él prueba en su iPad y manda capturas; se arregla, se ve en el simulador del iPad
  (`ADB9E3BB`, en horizontal y vertical) con hojas antes/después, se le reinstala el Debug y él dice «súbelo». Pruebas de
  interfaz en una copia del repo en el scratchpad (sin commitear): `IPadTodo` (cada sección por `-qa.seccion`, con
  `QA_LISTA` y `QA_SOLO_MAESTRO`; toca la primera fila de la columna maestro por su posición: con la barra lateral
  cerrada la columna empieza en x = 0), `IPadRecorrido` (`-qa.recorrido reset`, paso a paso), `IPadRepaso`, `AnularCobro`.
  El Mac, con una copia ad hoc sin iCloud (`com.chirogra.qa.repaso`) abierta en segundo plano por sección y
  `screencapture -l` de su ventana. Las capturas del iPad en horizontal se guardan con la orientación en el PNG: `NSImage`
  las dibuja derechas, `sips -r` no gira los píxeles.

## Chat anterior (21-nov, mañana): builds 56, 57 y 58

- **Build 56 (`130588b`):** informe de Beta Family de **Eric** con el 55 (recomendación 2/5: «no security assurances»,
  «parece hecho con IA») y un **repaso visual** de toda la app. Hecho con **un agente por arreglo** en worktrees.
  El usuario vio capturas antes/después de cada cambio de diseño y eligió **mantener el círculo de iniciales** en las
  fichas de cliente y proveedor.
- **Build 57 (`c13f955`):** captura del usuario con el 56: los botones del recibo de «Nuevo gasto» salían amontonados
  en una fila. Venía del 54 (`.id` del tutorial sobre el grupo de botones).
- **Build 58 (`944e0ad`):** otra captura suya: en Clientes, con un filtro vacío, dos avisos se pisaban. Y preguntó
  **dónde se cambia el idioma**: no se encontraba. Ahora la fila «Idioma» de Más › Moneda y formatos lleva a Ajustes.
  Antes de subirlo pidió **instalar el Debug en su iPhone** para verlo (iPhone 17 Pro Max, `00008150-0005793E3EC0401C`,
  con `devicectl` e iCloud de Producción, ver CONTEXTO «Instalar en los aparatos»).
- **Cómo se trabajó:** capturas en el simulador «Chirogra QA 16e» (`44631678`) con pruebas de interfaz `UITestsQA` en
  una copia aparte (no se commitean: `Build56QA`, `Build56Repaso`, `Build56Cabeceras`, `Build56Circulo`,
  `Build56Menores`, `Build56Recibo`, `Build57Clientes`, `Build58Idioma`). Hojas de capturas antes/después mandadas al
  usuario. El usuario manda capturas de su iPhone con lo que ve mal rodeado: arreglar, enseñar antes/después y
  esperar su «sí» para el build.
- **Worktrees de agentes:** nacen de `main` (`83b1db4`), no de `version-1.3`. Al agente: `git merge --ff-only <HEAD>` y
  `git apply --index <parche de lo sin commitear>`; recoger con `git add -N . && git diff --binary` y aplicar con
  `git apply --3way` (antes `git add -u` si hay cambios sin preparar). Sus DerivedData (~1,5 GB cada uno) llenaron el
  disco: borrarlos al terminar. Los 12 worktrees y sus ramas `worktree-agent-*` ya se borraron.
- **Pruebas:** `swift test --skip ScreenSmokeTests` (94 + 181 + 75 = 350). `ScreenSmokeTests` se cae desde el 54.
  `ReceiptReaderTests` (Vision) falla a veces con el Mac cargado (simuladores, compilaciones); sola pasa.

## Chat anterior (17 y 18-nov): builds 50, 51 y 52, recorrido y testers

- **Builds subidos (iOS y macOS):** 50 (`9f32335`, aviso de iCloud, cobro, precio), 51 (`4d84399`, recorrido de la
  primera vez en cada pestaña del iPhone, estilo A «Foco» de Claude Design) y 52 (`5643a27`, tras un tester de Beta
  Family). 346 pruebas en todos.
- **Build 52:** al borrar los datos de ejemplo se olvidan los recorridos vistos (el tester vio el recorrido con la
  empresa inventada y pedía «el tutorial para mi propio negocio»); y en la última página de la bienvenida, «Sin cuenta
  ni contraseña: tus libros se quedan en tus aparatos y en tu iCloud.» (pedía «entrar con Apple o Google o como
  invitado»: no sabía que no hay cuenta; «como invitado» ya es «Probar con datos de ejemplo»).
- **Testers:** Userbrain (graban la pantalla y hablan), **Beta Family** (formulario con «About the app» y «What to
  test»; tarea del 52 en inglés y español con 3 tareas y 5 preguntas) y **UXtweak** (solo imágenes: se recomendó
  *First Click Test*, sin moderar, con 6 tareas sobre las capturas `01-inicio`, `02-ventas`, `03-gastos` de la tienda,
  copiadas a `~/Desktop/Chirogra-UXtweak`). Los comentarios de errores llegan por «Compartir comentarios beta» de
  TestFlight (captura → miniatura) y se leen en App Store Connect › TestFlight › Comentarios.
- **Redes:** se le dieron textos para invitar a probar con el enlace de TestFlight (Instagram/Facebook, X/Threads e
  inglés) y el logo a 1024 px en `~/Desktop/Chirogra-logo` (redondeado con fondo transparente y cuadrado para perfil,
  sacados de `App/AppIcon.icon/Assets/chirogra-N-icono.svg`).
- **Balance de los testers (pregunta del usuario):** del 47 al 52 casi todo salió de ellos: el alta que se vaciaba
  (fallo real), el error de iCloud sin cuenta, la suscripción que asustaba (3 de 3), el precio de la factura, la factura
  de $0, la pronunciación y el recorrido en la empresa propia. Límites: pocos (unos 6 + 1), casi todo primera impresión
  y no siempre dueños de negocio. Recomendado: esperar lo que digan del 52 antes de más cambios y buscar 2 o 3 negocios
  reales que la usen unas semanas.
- **Ojo al subir:** `xcodegen` quita `com.apple.developer.ubiquity-kvstore-identifier` de `App/Chirogra.entitlements`
  (no está en `project.yml`). En el clon de subida, después de `xcodegen`, `git checkout App/Chirogra.entitlements`, o
  los recorridos vistos no se guardan en iCloud.

## Chats anteriores (16-nov, tarde): testers de Userbrain y builds 47 y 48

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

0. **Esperar a que los testers terminen con el 65** (Yurii S. en Beta Family; BetaTesting.com) y traer sus informes:
   con eso se arregla y se empieza la 1.4.
0b. **Plaid:** «Add use case descriptions» (Publish), luego las demás tareas del Home (Compliance Center, redirect URI).
1. **Asignar el 64 o el 65** al grupo de testers externos del enlace público y mandar más testers (Beta Family,
   Userbrain, UXtweak). Traer aquí sus informes.
2. **Seguir revisando el iPad** (con el Debug o desde TestFlight, que no enseña la hoja de planes al abrir) y mandar
   capturas de lo que vea mal; el recorrido del iPad se repite en Ajustes › «Ver el recorrido otra vez».
3. **Probar en un aparato** lo que solo se ha visto en el simulador: el recorrido con Reducir movimiento y VoiceOver, y
   el aviso de iCloud en el iPad (si sale, captura de «Detalles»).
4. **Para la 1.4:** la clave de Anthropic y el proyecto de Supabase «chirogra» los pone él en los secretos (no crearlos
   ni buscarlos). Pregunta abierta: si la suscripción cuesta más con el asistente.

## Lo siguiente

0. **1.4 en `version-1.4`:** canvas hecho (asistente con **burbuja flotante**, elegida el 25-nov). **Datos de la agenda
   y de los impuestos estimados hechos** (esquema 6: `Appointment`, `EstimatedTaxSetting`, `EstimatedTaxPayment`;
   [DATOS-V6.md](DATOS-V6.md); commit `cd974ed`, sin empujar). **Pantallas
   de la agenda, primera tanda** (25-nov, commit `3d0fb18`): `Agenda/` con Día (franjas), Semana (tira de días) y Lista
   («Por facturar»), ficha de la cita, editor (pregunta centrada «Solo esta / Esta y las siguientes»), «Crear factura»
   y «Crear estimado» desde la cita (`InvoiceEditorView(appointment:)`), Agenda en la barra lateral (después de
   Ventas) y en Más del iPhone, y citas en los datos de ejemplo. QA: `-qa.seccion agenda`, `-agenda.mode day|week|list`,
   en el iPhone `-phone.tabs sales,agenda,expenses -qa.pestana agenda`. Después (commit `6d966ed`): «Hoy» en Inicio
   (tarjeta del iPhone y sección de la columna del iPad, solo si la agenda se usa) y «Citas» en la ficha del cliente
   (`Agenda/AgendaCards.swift`). **Avisos** (commiteados): notificaciones
   locales de los próximos 14 días (máx. 50) que se rehacen al cambiar una cita (`AppointmentReminderScheduler` en
   `AppShell`); el permiso se pide al guardar la primera cita con aviso, no al abrir; se apagan por aparato en el «⋯» de
   la Agenda. **Calendario** (opción A del usuario, 25-nov:
   acceso completo; commiteado): «Añadir las citas a Calendario» en el «⋯» de la Agenda, por aparato; las citas van a
   un calendario propio «Chirogra» y cada evento lleva `chirogra://cita/<empresa>/<cita>` en su URL, así que se ponen al
   día (y se quitan al cancelar o borrar) sin duplicarse entre aparatos ni al reinstalar (`AppointmentCalendar`
   en `Agenda/AppointmentCalendar.swift`; `NSCalendarsFullAccessUsageDescription` y `ENABLE_RESOURCE_ACCESS_CALENDARS` en
   project.yml). **iPad y Mac** (commiteado): Día y Lista en
   una tarjeta con la ficha de la cita al lado (`AppointmentDetailView(embedded:)`) y la Semana en 7 columnas con
   franjas (`WeekGrid`); visto en el iPad de 11″, el Mac solo compilado. La agenda queda completa. **Pantallas de impuestos estimados** (commiteadas):
   `Taxes/EstimatedTaxViews.swift` con la tarjeta «Apartado para impuestos» (Inicio del iPhone entre «Ingresos y gastos»
   y «Por cobrar», y arriba de Reportes; oculta por defecto en S/C-corp), la pantalla (pago que toca, «Registrar pago
   al IRS», las cuatro fechas, pagos anotados con «Quitar», porcentaje y tarjeta) y la hoja «Pago al IRS». Impuestos
   tiene subsecciones en la barra (`SidebarItem.taxes`: «Impuesto sobre ventas» e «Impuestos estimados») y Más del
   iPhone la herramienta nueva. QA: `-qa.seccion estimatedTax`. La sección del iPad en Inicio
   («Apartado para impuestos» en la columna) hecha después (commiteada); falta el inspector del Mac. **Asistente sin servidor** (commiteado): burbuja flotante (`Assistant/`, encima de la barra de pestañas
   en el iPhone, abajo a la derecha del detalle en iPad y Mac), hoja en el iPhone y panel (inspector) en iPad y Mac,
   permiso la primera vez (`assistant.consent`, por aparato), sin conexión y solo lectura. Las sugerencias de cifras
   (ganancia del mes, quién me debe, cuánto apartar) se contestan ya en el aparato (`AssistantTools`, lo que el servidor
   usará como herramientas) con tarjetas e «Ir a…»; «Anota un gasto» abre el editor; una pregunta escrita dice que falta
   el servidor. Siguiente del asistente: servidor (función `asistente` en Supabase «chirogra») cuando el usuario ponga
   la clave de Anthropic y cree el proyecto; después, las pantallas de impuestos estimados. Los trámites del usuario (clave de Anthropic y
   Supabase «chirogra») hacen falta para el asistente (§4.4).
1. **Informes de testers:** leerlos, arreglar desde la causa, enseñarle capturas antes/después y esperar su «súbelo».
   Los xlsx de Beta Family se leen descomprimiéndolos (no hay openpyxl); las fotos son enlaces firmados en
   `xl/worksheets/_rels/sheet3.xml.rels` que caducan a los 7 días (bajarlas con curl).
2. **Pendientes técnicos (del 65):** `ScreenSmokeTests` se cae (SwiftUI con `ImageRenderer`, «no current update to
   enqueue action to»; correr el resto con `--skip ScreenSmokeTests`); solo hay pruebas de interfaz del iPhone (ni iPad
   ni Mac); la tabla por ZIP no marca los ZIP que cruzan jurisdicciones (regenerarla con los archivos oficiales);
   `Money(decimal:)` da un valor sin sentido por encima de ~$92 mil billones.
3. **Pendientes menores sin cerrar:** la confirmación de «Anular cobro»
   sale como globo con flecha (el usuario puede pedir un aviso centrado); el hueco del teclado del informe de Yurii S.
   (build 53) no se reprodujo: si vuelve, preguntar si usa teclado de otra app, Bluetooth o dictado.
4. **Tasas por código postal: cada trimestre** (1 ene, 1 abr, 1 jul, 1 oct; la próxima, el 1-ene-2027) correr
   `scripts/tasas/descargar.sh` y `generar.py` y subir un build (DATOS-V5.md). Faltan AL AK AZ CO HI ID LA MO MS NM PA
   SC VA. Sin regenerar, el aviso de tabla vieja sale desde el 20-feb-2027.
5. **1.4 con agenda, asistente con IA e impuestos estimados:** plan en [PLAN-1.4.md](PLAN-1.4.md) (rama
   `version-1.4` aparte; Claude a través de Supabase «chirogra» en región de EE. UU.; 100 preguntas al mes, citas que se
   repiten, modelo tras medir; §3 apartado para impuestos). Lo primero: los
   trámites del usuario y el canvas de diseño.
6. **1.5 con el banco (Plaid)** y **2.0** (contador, Stripe, nómina): plan en [PLAN-2.0.md](PLAN-2.0.md). Plaid ya
   tiene producción (24-nov); faltan sus tareas del panel. Antes de abrir Link a clientes reales: política de privacidad
   con el banco, buzón que se borra a los 30 días y borrar la cuenta en la app. Trámites de la 2.0 (cotizaciones de
   Gusto Embedded y Check, Stripe Connect) cuando toque.

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
- **Revisión en sus aparatos (21-nov):** cuando pide ver algo antes del build, se le instala el Debug (iPhone
  `00008150-0005793E3EC0401C`, iPad `00008103-001439A91E6B001E`) desde una copia del árbol de trabajo con
  `icloud-container-environment = Production`. Al ser de desarrollo se pueden leer sus ajustes con `devicectl device copy
  from --domain-type appDataContainer` (así se vio el `freeUse.start` del 10-nov). Él decide «súbelo» o «publícalo».
- Decisiones de diseño del iPad (21-nov): detalles de una columna a 720 pt y reportes a 820 pt, **centrados**; títulos de
  columna maestro siempre enteros («+» solo si hay otro botón o la etiqueta es larga); lápiz para Editar; el dato gris
  en la misma línea si cabe.
