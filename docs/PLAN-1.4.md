# Plan de la 1.4: agenda y asistente con IA (16-nov-2026)

Sale de los testers de Userbrain del 16-nov: una pidió **citas o agenda con los clientes** («todo en un solo sitio») y
otro esperaba un **asistente con IA** dentro de la app. El usuario decidió adelantarlos a la 1.4 en vez de esperar a la
2.0, y hacer el asistente con **Claude y servidor**, de modo que ese servidor sea la base del de la 2.0 (Plaid, Stripe,
nómina, contador; [PLAN-2.0.md](PLAN-2.0.md)). El 25-nov se añadió el **apartado para impuestos estimados** (§3) y se
decidió que **Plaid va justo después, en la 1.5**, reutilizando este servidor.

## Decisiones del usuario (16-nov)

| Tema | Decisión |
|---|---|
| Versión | **1.4 aparte**, rama `version-1.4` que sale de `version-1.3`. La 1.3 solo recibe los arreglos de los testers (build 49) y se envía sin esperar a esto. |
| IA | **Claude con servidor** (Supabase), no la IA de Apple en el aparato. El mismo proyecto de Supabase servirá a la 2.0. |
| Qué hace el asistente | **Las cuatro:** guiar en la app, registrar con una frase, contestar preguntas sobre los números y avisos automáticos. |
| Agenda | **Las cuatro:** citas con cliente, cita → factura o presupuesto, recordatorios y el Calendario de iOS/macOS. |
| Modelo | **Se decide tras medir** (16-nov): en la QA, Opus 5.5 y Sonnet 5.5 con las mismas preguntas reales; se elige con el costo y la calidad medidos. |
| Límite | **100 preguntas al mes** por suscripción (16-nov). Al llegar, se avisa y se reinicia el mes siguiente. |
| Citas que se repiten | **Desde el principio** (16-nov): cada día, semana, 2 semanas o mes, con fin opcional; cambiar «solo esta» o «esta y las siguientes». |
| Cómo se abre el asistente | **B: burbuja flotante** abajo a la derecha, en todas las pantallas (25-nov, canvas https://claude.ai/artifact/GDQsZiSZRruwx3PhhLytyt, tableros `EntradaB`, `EntradaBAgenda`, `iPadEntradaB`). En el Mac, además, ⌘K. |
| Pronunciación | «Kairogra» (griego). Ver CONTEXTO, «Decisiones del usuario». |

## 1. Agenda (citas con clientes)

**Qué es una cita:** cliente (opcional, para una cita sin cliente todavía), servicio o título, inicio y duración, lugar,
notas, estado (programada, hecha, cancelada, no vino), recordatorio (minutos antes) y repetición (cada día, semana,
2 semanas o mes, con fin opcional; al cambiar una, «solo esta» o «esta y las siguientes»; cada repetición hecha se
factura por separado). Si se factura, queda enlazada a la
factura o el presupuesto.

- **Dónde se ve:**
  - **Mac e iPad:** «Agenda» en la barra lateral, con vista de día, semana y lista.
  - **iPhone:** herramienta nueva en Más (`PhoneTool.agenda`), que se puede poner en la barra desde Más › Personalizar.
  - **En la ficha del cliente:** sus citas, próximas y pasadas.
  - **En Inicio:** «Hoy», con las citas del día.
- **Cita → factura:** en una cita hecha, «Crear factura» o «Crear presupuesto» abre el documento con el cliente, la
  fecha y el servicio ya puestos. La cita guarda el enlace y enseña «Facturada».
- **Recordatorios:** notificaciones locales (`UNUserNotificationCenter`). Cada aparato programa las suyas a partir de las
  citas que tiene, también las que llegan por iCloud, y las rehace al cambiar una cita. Se pueden apagar por aparato en
  Ajustes.
- **Calendario del sistema:** opción por aparato «Añadir las citas a Calendario», con el permiso de solo escritura de
  EventKit (`requestWriteOnlyAccessToEvents`) y un calendario elegido. El identificador del evento es distinto en cada
  aparato, así que **no va en iCloud**: se guarda en el propio aparato (cita → evento). Si se borra o cambia la cita, se
  cambia el evento.
- **Datos:** modelo nuevo `Appointment` en el **esquema 6** de CloudKit. Solo se añade, con las reglas de siempre
  (DATOS-V5.md): valores por defecto en todo, nunca renombrar ni reutilizar, probarlo en Producción antes de publicar.
  **La 2.0 pasa a ser el esquema 7.** También entran en la copia de seguridad (`Backup`), en la bitácora, en «Borrar
  todo» y en los datos de ejemplo.
- **Sin servidor:** la agenda vive en los libros, como todo lo demás.

## 2. Asistente con IA (Claude)

### Cómo queda armado

```
 Chirogra (iPhone/iPad/Mac)                 Supabase «chirogra»                Anthropic
 ┌──────────────────────────────┐   HTTPS   ┌───────────────────────────┐      ┌───────────┐
 │ Pantalla del asistente       │ ────────► │ función `asistente`       │ ───► │ Messages  │
 │ Ejecuta las herramientas     │ ◄──────── │ - comprueba la suscripción│ ◄─── │ API       │
 │ sobre los libros del aparato │  stream   │ - límite de uso al mes    │      └───────────┘
 │ y pide confirmación antes de │           │ - prompt y herramientas   │
 │ guardar nada                 │           │ - clave de la API (secreto)│
 └──────────────────────────────┘           └───────────────────────────┘
```

- **Los libros no se guardan en el servidor.** La conversación pasa por la función hacia Claude y vuelve. La función
  no la guarda: solo apunta el uso (cuántas preguntas y tokens al mes por suscripción) para el límite y los costos.
- **Las herramientas se ejecutan en el aparato.** Cuando Claude pide un dato («gastos por categoría de enero a
  noviembre»), la app lo calcula con `Bookkeeper` y manda solo ese resultado. Así Claude nunca recibe los libros
  enteros, solo lo que hace falta para contestar.
- **El prompt y la lista de herramientas viven en la función**, no en la app: la app no puede cambiarlos, y se mejoran
  sin subir un build.
- **Sin cuenta nueva:** la app manda la transacción firmada de StoreKit (JWS). La función verifica la firma de Apple y
  que la suscripción esté vigente, prueba gratis incluida, y usa `originalTransactionID` para el límite de uso. «Iniciar
  sesión con Apple» queda para la 2.0, como ya decía su plan.
- **Proyecto de Supabase «chirogra», aparte del de Tamio** (decisión de la 2.0). Carpeta `servidor/` en el repo
  (`supabase/functions/asistente`, `supabase/migrations`). La clave de Anthropic va solo en los secretos de Supabase,
  nunca en el repo ni en la app.

### Qué puede hacer (las herramientas)

| Grupo | Herramientas | Qué hace la app |
|---|---|---|
| Guiar | `abrir_pantalla(seccion, filtro?)` | Lleva a la pantalla («Registrar cobro» de una factura, Reportes › P&L…). La guía (es/en) va en el prompt, guardada en caché. |
| Números | `resumen_periodo`, `gastos_por_categoria`, `por_cobrar`, `por_pagar`, `sales_tax`, `buscar_movimientos`, `citas` | Calcula con `ReportBuilder` y `Bookkeeper` y devuelve cifras ya sumadas. |
| Registrar | `preparar_gasto`, `preparar_factura`, `preparar_cobro`, `preparar_cita` | **Nunca guarda.** Enseña una tarjeta con el borrador («Gasto $85 · Adobe · Software · Tarjeta») y el usuario pulsa «Guardar» o «Editar». Con libros en solo lectura, abre la hoja de planes. |

- **Avisos automáticos:** la campana ya calcula facturas vencidas, pagos por vencer, pagos programados y sales tax por
  declarar (`Bookkeeper+Notices.swift`). Se añaden presupuesto excedido y las citas, y la opción de recibirlos como
  **notificación** del aparato, una vez al día. Esto es local y no gasta IA. Desde el aviso, «Pregúntale al asistente»
  abre la conversación con el contexto puesto.
- **Dónde se abre:** burbuja flotante abajo a la derecha en todas las pantallas (decisión del 25-nov), más ⌘K en el
  Mac. En español o inglés, según el idioma de la app.
- **Sin conexión, o sin suscripción:** el botón explica por qué no está disponible. El resto de la app no cambia.

### Modelo y costo

- **Modelo:** Claude Opus 5.5 (`claude-opus-5-5`, $4 / $20 por millón de tokens de entrada y salida; leer de la caché,
  $0.20), con pensamiento adaptativo y esfuerzo `low` (las preguntas de un negocio pequeño son cortas). Se encienden los
  `fallbacks` del servidor por si una petición se rechaza. Elegir un modelo más barato es decisión del usuario:
  Sonnet 5.5 cuesta la mitad ($2 / $10) y Haiku 5.5 unas cuarenta veces menos ($0.10 / $0.50).
- **Costo estimado por pregunta con Opus 5.5** (sin medir; se mide en la QA con `usage`):
  - prompt, guía y herramientas, unos 15 mil tokens en caché: ~$0.003 por vuelta;
  - la pregunta y los resultados, unos 3 mil tokens: ~$0.012 por vuelta;
  - la respuesta, unos mil tokens: ~$0.02 por vuelta;
  - con 2 o 3 vueltas por pregunta: **unos $0.05–0.10**.

  Con 100 preguntas al mes salen $5–10 por suscriptor, frente a los $29.99 (menos el 15 % de Apple): de ahí el límite
  de 100 al mes (decisión del 16-nov).
- **Caché:** el prompt, la guía y las herramientas no cambian entre preguntas. Van primero y con `cache_control`; la
  fecha de hoy y los datos de la empresa van después del último punto de caché.

### Privacidad y tienda

- **Permiso explícito antes del primer uso** (regla 5.1.2(i) de Apple para mandar datos personales a una IA de
  terceros): una pantalla que dice qué se envía (la pregunta y las cifras que pida el asistente), a quién (Anthropic,
  a través del servidor de Chirogra) y que no se guarda. Sin aceptarla, el asistente no se abre.
- **Etiqueta de privacidad de la tienda:** deja de ser «Data Not Collected». Hay que declarar el contenido del usuario y
  la información financiera que cruzan el servidor, y revisar con la definición de Apple si al no guardarse cuenta como
  «recogido». Sin rastreo.
- **Política de privacidad (es/en), bienvenida, guía y ficha de la tienda:** se añaden el asistente y la agenda.

## 3. Apartado para impuestos (impuestos estimados)

Lo pidió un cliente el 25-nov: que la app le diga **cuánto apartar para los impuestos** durante el año («¿tiene R&B?»,
los *estimated taxes*, formulario **1040-ES**; **confirmado con él el 25-nov**: apartar lo de cada trimestre). Quien trabaja por su cuenta no
tiene patrón que le retenga, así que paga al IRS por adelantado **4 veces al año** (15-abr, 15-jun, 15-sep y 15-ene),
no cada semestre. Hoy Chirogra no lo tiene: «estimate» en el código son las cotizaciones.

- **Base:** la ganancia neta del trimestre, que ya sale del estado de resultados (`Reports.swift`, `netIncome`).
- **Porcentaje que elige el usuario** (sugerido 25–30 %, con un texto claro de que es una guía y no asesoría fiscal; el
  monto real depende de su contador). Opcional más adelante: cálculo con el impuesto de autoempleo (15.3 %) y las tablas
  federales; en la 1.4 solo porcentaje.
- **Tarjeta en Inicio** y en Reportes: «Este trimestre ganaste $X → aparta $Y. Vence el 15 de junio (faltan N días)».
- **Recordatorios** antes de cada fecha (con los avisos automáticos y las notificaciones de la §2).
- **Pagos hechos:** registrar el pago al IRS como un asiento a una cuenta «Impuestos estimados pagados» (patrimonio del
  dueño, no gasto del negocio en una LLC de un solo dueño / sole prop) y mostrar apartado frente a pagado en el año.
- **El asistente** puede contestar «¿cuánto debo apartar?» con esta misma cuenta.
- **Con el banco (2.0):** ver si el dinero apartado está de verdad en una cuenta de ahorro aparte.
- **Corporaciones (C-corp) y S-corp** tienen reglas distintas (1120-W, nómina del dueño): en la 1.4 se avisa que la
  tarjeta está pensada para dueños únicos y LLC de un solo dueño, y se puede apagar en Ajustes.

## 4. Orden de trabajo

0. **Trámites del usuario (sin código):** cuenta u organización de la API de Anthropic con su clave y un límite de gasto
   mensual, y el proyecto de Supabase «chirogra». Yo no busco ni creo claves: él pone la de Anthropic en los secretos
   de Supabase.
1. **Diseño en un canvas**, como se hizo con la bienvenida y el panel de clientes: agenda (día, semana, lista, ficha de
   la cita, la cita en el cliente), la pantalla del asistente con la tarjeta de borrador y el permiso. Con opciones, y
   él elige.
2. **Agenda:** esquema 6, `Appointment`, vistas, cita → factura, copia de seguridad y pruebas.
3. **Recordatorios y Calendario** (EventKit).
4. **Servidor:** proyecto, función `asistente`, verificación de StoreKit y tabla de uso.
5. **Asistente en la app:** pantalla, herramientas, tarjetas de borrador y permiso.
6. **Avisos automáticos** como notificación, más los dos tipos nuevos.
7. **Apartado para impuestos** (§3): porcentaje, tarjeta, fechas del IRS, pagos hechos y recordatorios.
8. **QA completa** (como la de Hudson), costo medido por pregunta, privacidad, textos, guía y capturas, y builds de la
   1.4 en TestFlight y Userbrain.

## Preguntas abiertas

1. **Modelo:** se decide tras medir en la QA (Opus 5.5 frente a Sonnet 5.5).
2. **¿Cuesta más la suscripción con el asistente?** ¿O se mantiene el precio y se cubre con el límite de 100 al mes?
3. **¿Agenda en las pestañas de entrada del iPhone?** Se decide junto con lo de Reportes (testers, build 49).
4. **Apartado para impuestos** (el cliente confirmó el 25-nov que son los impuestos estimados trimestrales): ¿porcentaje
   fijo o cálculo con las tablas del IRS? ¿Para todos o solo para el plan de pago?
