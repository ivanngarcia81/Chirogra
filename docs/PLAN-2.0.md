# Plan de la 2.0 con servidor (13-nov-2026)

Borrador escrito con las respuestas de Iván del 13-nov. No hay código todavía: se empieza a programar cuando la 1.3 esté
en la tienda. Sustituye a «Después: con servidor» de [PLAN-FASE2.md](PLAN-FASE2.md) y a la parte D de CONTEXTO.

## Decisiones del usuario (13-nov)

| Tema | Decisión |
|---|---|
| Dónde viven los libros | **Híbrido**: los libros siguen en el iCloud del usuario; el servidor solo guarda lo que necesita secretos (Plaid, Stripe, nómina) y las invitaciones. |
| Servidor | **Supabase**, proyecto aparte del de Tamio (recomendación aceptada). |
| El contador | Entra a los libros del cliente **desde la app de Chirogra** (iPhone, iPad, Mac) y puede exportar a programas de fuera. La **web para contadores queda para el futuro**. |
| Permisos del contador | **Los elige el cliente** al invitarlo: solo ver, ver y preguntar, o editar. Lo que haga el contador queda marcado y en la bitácora. |
| Pago del contador | **Gratis** para el contador invitado (el cliente ya paga). El plan de $99.99 sigue para quien lleva él mismo los libros de muchas empresas. |
| Otros usuarios | **Solo el dueño y su contador** (sin empleados ni socios en la 2.0). |
| Primera entrega | **Todo junto**: Plaid, el contador dentro, Stripe y nómina. |
| Plaid | **Solo lectura**: Transactions, Balance y **Statements desde el inicio**. No mueve dinero. |
| Stripe | Enlace de pago en cada factura. **Chirogra no cobra comisión**: solo la de Stripe. |
| Nómina | Con un proveedor embebido (Gusto Embedded o Check). Precio **base + por empleado**. |
| Precio | **Plan extra «Chirogra + Banco»**; el normal sigue igual. El precio se decide con los costos reales (abajo). |
| Países | **Solo EE. UU.** |

## Cómo queda armado

```
 iPhone / iPad / Mac (Chirogra)                       Supabase «chirogra»
 ┌───────────────────────────────┐                ┌──────────────────────────────────┐
 │ Libros en SwiftData + iCloud  │  Sign in with  │ Auth (Apple)                     │
 │ (como hoy, base privada)      │ ◄────Apple───► │ Postgres: conexiones, buzón,     │
 │                               │                │   invitaciones, cuentas Stripe,  │
 │ Recoge del buzón y lo         │ ◄──── buzón ── │   empresas de nómina             │
 │ escribe en los libros         │                │ Vault: tokens de Plaid           │
 └───────────────────────────────┘                │ Funciones: plaid-*, stripe-*,    │
                                                  │   nomina-*, apple-*, invitar     │
                                                  └───────▲──────────▲──────────▲────┘
                                                     Plaid │    Stripe │  Gusto/Check
```

- **El servidor no guarda los libros.** Guarda los tokens de acceso (Plaid en el Vault de Supabase, cifrados), el estado
  de cada conexión y un **buzón**: lo que llega de Plaid, Stripe o la nómina espera ahí hasta que la app lo recoge, lo
  escribe en los libros (iCloud) y confirma. Al confirmar se borra del buzón (o a los N días, a decidir).
- **Cuenta de Chirogra:** «Iniciar sesión con Apple», solo para quien encienda el banco, los cobros, la nómina o invite
  a un contador. Quien no use nada de eso sigue sin cuenta, como hoy.
- **El plan se comprueba en el servidor:** la app manda la transacción firmada de StoreKit y una función la verifica;
  las **App Store Server Notifications V2** avisan de altas, renovaciones y bajas. Sin plan «Banco» vigente, las
  funciones de Plaid no sincronizan.
- **En el repo:** carpeta `servidor/` en Chirogra (`supabase/migrations`, `supabase/functions`), en la rama `version-2.0`
  que saldrá de `version-1.3`. Mismas reglas que Tamio: claves solo en los secretos de Supabase, nunca en el repo.

## 1. Plaid (solo lectura)

- **Productos:** Transactions (movimientos), Balance (saldo y límite de la tarjeta) y Statements (extractos en PDF).
- **Conectar:** Link de Plaid. En iPhone y iPad con el SDK de iOS. En el Mac, ver cómo lo resolvió Tamio para Mac
  (Link alojado en una ventana web si el SDK no sirve en macOS).
- **Flujo:** `link/token/create` → la app abre Link → `item/public_token/exchange` → token guardado en el Vault →
  aviso `SYNC_UPDATES_AVAILABLE` → `/transactions/sync` desde el cursor (altas, cambios y bajas) → buzón → la app crea
  `BankTransaction` con `sourceRaw = plaid` y `externalID = transaction_id`, y entran a «Por revisar». Lo pendiente que
  pasa a contabilizado se actualiza, no se duplica. Todo lo de reglas, coincidencias y conciliación ya existe y no cambia
  (`BankTransactionSource`, PLAN-FASE2).
- **Saldos:** los que vienen con la sincronización (sin costo aparte). `/accounts/balance/get` solo al conciliar o
  cuando el usuario lo pida, porque se cobra por consulta.
- **Extractos:** `/statements/list` y descarga del PDF de cada mes. Se adjuntan a la conciliación de ese mes y entran
  al paquete del contador.
- **Se reutiliza de Tamio:** la sincronización por cursor, el manejo de errores de conexión (volver a entrar al banco),
  las respuestas del cuestionario de seguridad de Plaid y los textos de consentimiento.
- **Trámite:** pedir acceso de producción para Chirogra (otra app en el panel de Plaid, o el mismo equipo con otro
  perfil) y **Statements**, que se pide aparte.

## 2. Stripe (cobros de facturas)

- **Cuenta del negocio:** cada usuario conecta **su propia** cuenta de Stripe con Stripe Connect, con Stripe poniendo
  el precio. Así Stripe le cobra su comisión directamente y la plataforma (Chirogra) no paga comisiones de Connect.
  Encaja con «nada extra».
- **En la factura:** «Pagar ahora» crea una sesión de Checkout en la cuenta del negocio: tarjeta, Apple Pay, Google Pay
  y ACH. El enlace y el QR van en el PDF y el correo (sustituye al enlace de pago propio de la 1.1 para quien conecte
  Stripe; el que no, sigue con el suyo).
- **Contabilidad:** el aviso de Stripe (`checkout.session.completed`) va al buzón y la app registra el cobro de la
  factura contra una cuenta puente **«Stripe por depositar»**, con la comisión como gasto. Cuando Stripe deposita en el
  banco (payout), ese depósito llega por Plaid y se empareja con la cuenta puente: traspaso, no ingreso doble.
- **Apple:** el cobro de una factura por un trabajo o producto fuera de la app no es compra dentro de la app; va por
  Stripe sin problema. La suscripción de Chirogra sigue siendo compra dentro de la app.

## 3. El contador dentro de los libros (la pieza más difícil)

Con los libros en iCloud, la forma de que el contador entre desde su propio aparato es **compartir la empresa por
iCloud** (CKShare): el cliente invita, el contador acepta con su Apple ID y ve esa empresa en su Chirogra.

- **El problema:** SwiftData no sabe compartir por iCloud; solo sincroniza la base privada. Hay que llevar la empresa
  compartida a una zona de CloudKit propia y sincronizarla con **CKSyncEngine** (el motor de Apple que sí trabaja con
  la base compartida) o con `NSPersistentCloudKitContainer` y un almacén compartido. En los foros hay fallos de CKShare
  en iOS 26, así que **lo primero es una prueba de concepto** (una empresa compartida entre dos Apple ID, editando desde
  los dos lados) antes de comprometer el diseño.
- **Permisos:** iCloud solo distingue «solo lectura» y «lectura y escritura». «Ver» = solo lectura. «Editar» = lectura y
  escritura. «Ver y preguntar» = libros en solo lectura y las preguntas en una zona aparte con escritura (o en el
  servidor). La app además oculta lo que el permiso no deja hacer.
- **Preguntas al cliente:** el contador marca un movimiento y escribe la pregunta; al cliente le sale en Inicio y
  contesta allí. Aviso por notificación (CloudKit o el servidor).
- **Marcas:** lo que hace el contador ya sale como «del contador» (`EntrySource.accountantAdjustment`, bitácora con el
  aparato); se añade quién (nombre del participante de iCloud).
- **El servidor aquí** solo guarda la invitación y su estado (para el panel de clientes del contador). Los libros no pasan
  por él.
- **Exportar a programas de fuera:** además del paquete actual (PDF y CSV), formatos que importen QuickBooks y Xero
  (asientos y plan de cuentas en sus CSV).
- **Espacio de iCloud:** lo compartido cuenta en el iCloud del dueño, no en el del contador.
- **Para el futuro (web):** la web para contadores necesitará los libros en el servidor. Cuando llegue, se decide si se
  hace un espejo de los libros en Supabase (con permiso del cliente) o se cambia de arquitectura. No se prepara ahora.

## 4. Nómina

- **Proveedor:** Gusto Embedded o Check. Ninguno publica precios de socio: **pedir cotización a los dos** (cuota fija,
  por empleado, mínimos) y elegir con números. Los dos traen pantallas ya hechas para incrustar (alta de la empresa,
  empleados, W-4), que ahorran mucho trabajo.
- **Qué cubre:** empleados, W-4, corridas de nómina, depósito directo, retenciones federales y estatales, 941/940, W-2 y
  altas estatales. Los datos de los empleados (SSN, cuentas) **se quedan en el proveedor**, ni en el servidor ni en iCloud.
- **Contabilidad:** cada corrida de nómina llega al buzón y se registra sola como asiento (6850 Sueldos y salarios,
  impuestos de nómina, 2300 Nómina por pagar) y su pago se empareja con el cargo del banco que trae Plaid.
- **Cobro (base + por empleado):** la compra dentro de la app no permite un precio por empleado libre. Lo seguro es
  **escalones de suscripción por número de empleados** (por ejemplo 1–5, 6–10, 11–20). Revisar antes las reglas
  vigentes de Apple sobre enlaces de pago externos en EE. UU., que cambiaron en 2025.
- **Trámite largo:** la aprobación como socio de nómina puede tardar. Se pide al principio, en paralelo.

## 5. Privacidad y tienda

- **Etiqueta de la tienda:** deja de ser «Data Not Collected». Pasan a declararse: información financiera (movimientos
  de Plaid y cobros de Stripe que cruzan el servidor), contacto (correo de Iniciar sesión con Apple) e identificador de
  usuario. Ligados al usuario y **sin rastreo**.
- **Política de privacidad, bienvenida y guía:** los libros siguen solo en tu iCloud; el servidor solo ve lo que
  conectes (banco, Stripe, nómina) y lo borra al pasarlo a tus libros.
- **Plaid** exige su texto de consentimiento antes de Link. **Nómina** también tiene sus términos.

## 6. Esquema 6 de CloudKit (solo añadir)

Las reglas de PLAN-FASE2 siguen: solo añadir, nunca renombrar ni reutilizar, probar en Producción antes de publicar.

- `BankTransaction`: `isPending: Bool = false`, `plaidAccountID: String?`, `merchantName: String?` (`sourceRaw` ya
  admite `plaid`).
- `Account`: `bankConnectionID: String?`, `bankMask: String?`, `bankInstitution: String?`, `lastBankSyncAt: Date?`.
- `Reconciliation`: `statementFileName: String?` (el PDF de Plaid, guardado como los recibos).
- `Invoice`: `stripeCheckoutID: String?`, `stripePaymentURL: String?`. `Payment`: `stripeFee: Int64 = 0`,
  `externalID: String?`.
- `JournalEntry`: orígenes nuevos en `EntrySource` (`plaid`, `stripe`, `payroll`) y `externalID: String?`.
- `AccountantQuestion` (nuevo): empresa, movimiento o asiento, texto, respuesta, estado, quién y cuándo.
- Lo de compartir (zona propia de la empresa compartida) sale de la prueba de concepto del punto 3.

## 7. Orden de trabajo

0. **Trámites, ya y en paralelo (sin código):** Plaid producción y Statements; perfil de plataforma en Stripe Connect;
   solicitudes y cotizaciones a Gusto Embedded y Check; productos nuevos en App Store Connect («Chirogra + Banco» y
   escalones de nómina, en el grupo «Chirogra»).
1. **Prueba de concepto de compartir por iCloud** (punto 3). Va primero porque es lo más arriesgado y puede cambiar el
   esquema 6.
2. **Base del servidor:** proyecto Supabase, Iniciar sesión con Apple, verificación del plan, buzón y su recogida en la
   app, rama `version-2.0`.
3. **Plaid** (movimientos, saldos, extractos).
4. **Stripe** (enlace en la factura, registro del cobro, cuenta puente).
5. **El contador dentro** (invitación, permisos, preguntas, panel de clientes).
6. **Nómina** (va última porque depende de la aprobación del proveedor).
7. **QA completa** (como la de Hudson), privacidad, textos y capturas, envío.

**Riesgo:** como la 2.0 sale con todo junto, si la aprobación de nómina tarda, retrasa también Plaid, Stripe y el
contador. Se revisa cuando lleguen las respuestas de los proveedores.

## 8. Costos (para decidir el precio de «Chirogra + Banco»)

| Concepto | Quién paga | Cifra conocida (13-nov, sin confirmar) |
|---|---|---|
| Supabase Pro | Chirogra, fijo | Unos **$25 al mes** más el cómputo (incluye $10 de crédito, que cubre la instancia más pequeña). |
| Plaid Transactions | Chirogra, por cuenta conectada al mes | Plaid no publica tarifa; fuentes de terceros hablan de unos **$0.25–$0.50**. **Pedir la tarifa.** |
| Plaid Balance | Chirogra, por consulta | Terceros: unos **$0.05** por consulta. |
| Plaid Statements | Chirogra | Sin cifra pública. **Pedir la tarifa.** |
| Stripe | El negocio, directo a Stripe | ~2.9 % + 30¢ con tarjeta; ACH más barato. Chirogra: $0. |
| Nómina | Chirogra al proveedor | Negociado. Referencia de mercado: $35–70 por empresa + $6–10 por empleado al mes. |
| Apple | Sobre cada suscripción | 15 % (Small Business Program, y desde el segundo año de cada suscriptor). |

**Cómo se fija:** con la tarifa de Plaid en la mano, suponer 3 cuentas conectadas por negocio, sumar extractos y saldos,
y poner un precio que, quitado el 15 % de Apple, cubra Plaid con margen holgado. Lo mismo con los escalones de nómina
cuando lleguen las cotizaciones.

## Preguntas abiertas

1. **Precio de «Chirogra + Banco»:** cuando llegue la tarifa de Plaid.
2. **¿El plan de contadores ($99.99) incluye el banco** en sus empresas, o cada empresa con banco paga aparte?
3. **Gusto Embedded o Check:** cuando lleguen las cotizaciones.
4. **Sales tax exacto por dirección** (Stripe Tax, TaxJar o Avalara, con costo por cálculo): ¿entra en la 2.0 o sigue la
   tabla por código postal de la 1.2?
5. **Cobro de la nómina:** escalones dentro de la app, o pago fuera si las reglas de Apple lo permiten.
6. **Buzón:** ¿se borra al confirmar o se guarda unos días (para reintentar si un aparato falla)?
