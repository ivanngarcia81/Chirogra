# Chirogra 1.4 — Agenda, asistente e impuestos estimados (encargo de diseño)

Para pegar en Claude Design y hacer el canvas «Chirogra — 1.4». El plan completo está en [PLAN-1.4.md](PLAN-1.4.md);
aquí solo lo que hay que dibujar.

## Qué es
Chirogra es una app de contabilidad para pequeños negocios de EE. UU. (iPhone, iPad y Mac; iOS 26, iPadOS 26 y
macOS Tahoe, con Liquid Glass). Sus usuarios son dueños de negocio sin formación contable: plomeros, diseñadores,
limpieza, consultores. La 1.4 añade tres cosas:

1. **Agenda:** citas con los clientes, que se convierten en factura.
2. **Asistente con IA:** preguntas sobre los números, ayuda para encontrar cosas y registrar con una frase.
3. **Apartado para impuestos:** cuánto guardar cada trimestre para los impuestos estimados del IRS (1040-ES).

## Estilo
- Mismo sistema que el canvas «Chirogra — Diseño de app»: fondos agrupados del sistema, un solo color propio,
  **Tinta** (`#3A3FD1` en claro, `#9A9EFF` en oscuro), para iconos, enlaces, filtro activo y fila elegida; listas
  nativas y Liquid Glass en barras y botones.
- Botón principal en **vidrio**, no relleno de color.
- **Sin cápsulas de estado:** punto de color más texto («● Hecha»). El color nunca va solo.
- Cifras: ingresos en verde, gastos en rojo, ganancia en Tinta (como Inicio hoy).
- Modo claro y oscuro. Letra dinámica y toques de 44 pt en iOS.
- Bilingüe español/inglés: dejar aire. Probar con importes largos («2 400,00 US$», formato europeo).
- **iPad:** barra lateral propia a la izquierda; las listas van en una tarjeta con el detalle al lado; detalles a
  720 pt y reportes a 820 pt, centrados.

## 1. Agenda

### Una cita
Cliente (opcional), servicio o título, día, hora de inicio y duración, lugar, notas, estado (**programada, hecha,
cancelada, no vino**), recordatorio (minutos antes) y repetición (cada día, semana, 2 semanas o mes; con fin
opcional). Si ya se facturó, enlace a su factura o presupuesto («Facturada · F-1012»).

### Pantallas
- **Agenda:** vistas **Día · Semana · Lista** (un selector arriba). Botón «+» para una cita nueva. Hoy marcado.
  - Día: franjas por hora, citas como bloques con cliente, servicio y hora.
  - Semana: 7 columnas (iPad y Mac); en iPhone, proponer cómo se ve (tira de días arriba + lista del día elegido).
  - Lista: próximas citas agrupadas por día; las pasadas sin facturar, aparte («Por facturar»).
- **Ficha de la cita:** los datos, el estado con su punto, y las acciones: **Marcar como hecha**, **Crear factura**,
  **Crear presupuesto**, Cancelar, Editar. Una cita hecha sin factura destaca «Crear factura».
- **Editor de la cita** (hoja): cliente, servicio, fecha y hora, duración, lugar, recordatorio, repetición, notas.
  Al cambiar una cita que se repite: «Solo esta» o «Esta y las siguientes».
- **En la ficha del cliente:** sección «Citas» con la próxima y las últimas.
- **En Inicio:** tarjeta «Hoy» con las citas del día (o «Sin citas hoy» y nada más si no hay). Que no empuje hacia
  abajo lo que ya hay en Inicio más de lo necesario.

### Dónde vive
- **Mac e iPad:** «Agenda» en la barra lateral, en el grupo «Negocio» (proponer posición: después de Ventas).
- **iPhone:** herramienta en Más, que se puede poner en la barra de abajo desde Más › Personalizar.

## 2. Asistente

### Cómo se abre — **dos opciones para elegir**
- **A. Botón:** un botón con su icono arriba en Inicio (iPhone) y en la barra de herramientas (iPad y Mac). ⌘K en
  el Mac.
- **B. Burbuja flotante:** un botón redondo flotando abajo a la derecha, en todas las pantallas.

Dibujar las dos en iPhone e iPad para compararlas.

### La conversación
- Hoja (iPhone) o panel lateral (iPad y Mac) con la conversación. Campo de texto abajo con micrófono para dictar.
- **Sugerencias al empezar** (3 o 4 botones): «¿Cuánto gané este mes?», «¿Quién me debe?», «Anota un gasto»,
  «¿Cuánto aparto para impuestos?».
- Respuestas con cifras en el estilo de la app (no texto plano): una cifra grande o una mini tabla cuando toque.
- **Botón «Ir a…»** en una respuesta que lleva a una pantalla («Ver Por cobrar»).
- **Tarjeta de borrador** cuando pide registrar algo: «Gasto · $85.00 · Adobe · Software · Tarjeta Visa» con
  **Guardar** y **Editar**. Nada se guarda sin tocar Guardar. Dibujar también la de factura (cliente, líneas, total)
  y la de cita.
- Contador discreto: «Te quedan 87 preguntas este mes».

### Estados
- **Permiso la primera vez** (lo exige Apple): pantalla que explica qué se envía (la pregunta y las cifras que pida
  el asistente), a quién (Anthropic, a través del servidor de Chirogra) y que no se guarda. «Aceptar y empezar» /
  «Ahora no».
- Sin conexión, sin suscripción (libros en solo lectura) y límite del mes alcanzado: qué ve en cada caso.
- Pensando / escribiendo la respuesta.

## 3. Apartado para impuestos

- **Tarjeta en Inicio** (y en Reportes): «Este trimestre ganaste $8,450 → aparta $2,110 (25 %). Vence el 15 de enero
  · faltan 51 días». Debajo, en el año: apartado frente a pagado.
- **Ajuste:** el porcentaje (sugerido 25–30 %), con una línea clara: «Es una guía, no asesoría fiscal; tu contador
  te dice el monto real». Interruptor para apagar la tarjeta.
- **Registrar un pago al IRS:** hoja corta (fecha, monto, cuenta de la que salió, trimestre).
- Las 4 fechas del año (15-abr, 15-jun, 15-sep, 15-ene) en algún sitio visible.
- Aviso de que está pensado para dueño único y LLC de un solo dueño (las corporaciones lo pueden apagar).

## Fuera de esta entrega
El banco con Plaid (1.5), el contador dentro de la app, Stripe y nómina (2.0). No dibujarlos.

## Qué entregar
iPhone (claro y oscuro), iPad horizontal y Mac. Con los estados vacíos, el permiso del asistente y las dos opciones de
cómo se abre (A y B).

---

**Diseño:** canvas «Chirogra 1.4 — Agenda, asistente e impuestos estimados»
(https://claude.ai/artifact/GDQsZiSZRruwx3PhhLytyt), hecho por el usuario en Claude Design el 25-nov. Se lee con la
herramienta Artifact (`path: project/<tablero>.dc.html`; la lista de tableros en `project/canvas.json`). Al leerlo el
25-nov, los tableros de la §3 (Reportes, Apartado, PagoIRS, iPadApartado, MacApartado) estaban en `canvas.json` pero sin
publicar; la tarjeta del apartado sí está en Inicio (`Main`, `iPadInicio`). Pendiente de él: elegir A (botón) o B
(burbuja) para abrir el asistente.
