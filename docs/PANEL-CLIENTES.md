# Chirogra — Panel de clientes (encargo de diseño)

## Qué es
Chirogra es una app de contabilidad para pequeños negocios de EE. UU. (iPhone, iPad y Mac; iOS 26, iPadOS 26 y
macOS Tahoe, con Liquid Glass). El plan **Chirogra para contadores** ($99.99/mes) permite llevar los libros de
empresas sin límite. El **Panel de clientes** es la pantalla de trabajo diario del contador: de un vistazo ve todas las
empresas que lleva, cuáles necesitan atención y por qué, y salta directo a lo pendiente.

Solo existe en el plan para contadores. Con el plan normal (una empresa) no aparece.

## Estilo
- Mismo sistema que el canvas «Chirogra — Diseño de app»: fondos agrupados del sistema, un solo color propio,
  **Tinta** (`#3A3FD1` en claro, `#9A9EFF` en oscuro), para iconos, enlaces, filtro activo y fila elegida; listas
  nativas y Liquid Glass en barras y botones.
- Botón principal en **vidrio**, no relleno de color.
- **Sin cápsulas de estado:** el estado se marca con un **punto de color más texto** («● Urgente»), como en Ajustes.
  El color nunca va solo, siempre lleva palabra.
- Modo claro y oscuro. Letra dinámica (que aguante tamaños grandes) y toques de 44 pt en iOS.
- Bilingüe español/inglés: dejar aire, porque en inglés los textos cambian de largo.

## Dónde vive
- **Mac e iPad:** primer elemento de la barra lateral, «Clientes», encima de las secciones de la empresa activa. Al
  abrir la app, el contador cae aquí.
- **iPhone:** pantalla «Clientes» a la que se llega desde el selector de empresa (arriba en Inicio). Proponer si
  conviene que sea la primera pantalla al abrir.
- Al elegir un cliente, la app cambia a esa empresa (como hoy con el selector).

## Encabezado
- Título «Clientes».
- Resumen en una línea: «4 de 5 clientes necesitan atención».
- Buscador por nombre.
- Filtro: **Todos · Necesitan atención · Al día · Archivados**.
- Orden: **Urgencia** (por defecto) · Nombre · Próxima fecha límite.
- Botón «+» o «Añadir cliente».

## Cada cliente (fila en iPhone; tabla en Mac e iPad horizontal)
1. **Nombre** con su monograma (iniciales en círculo, como ya existe), tipo de empresa y estado
   («LLC · Texas», «S corporation · California»).
2. **Estado general** con punto de color:
   - **● Urgente (rojo):** sales tax vencido o que vence en 7 días o menos, o un banco sin conciliar hace más de 60 días.
   - **● Pendiente (naranja):** movimientos del banco por revisar, facturas vencidas, conciliación de más de 30 días o
     avisos sin leer.
   - **● Al día (verde):** nada de lo anterior.
3. **Pendientes**, solo los que tenga, cada uno tocable y lleva directo a esa pantalla de ese cliente:
   - **Banco:** «23 por revisar» → bandeja del banco.
   - **Facturas vencidas:** «4 vencidas · $3,120» → facturas filtradas por vencidas.
   - **Sales tax:** «$842 · vence el 14 nov» o «Vencido hace 3 días» → impuestos.
   - **Conciliación:** la cuenta más atrasada, «Chase ··· 4410: conciliada hasta 30 sep», o «Conciliación en curso» →
     conciliación de esa cuenta.
   - **Avisos:** «2 avisos» → avisos de la campana.
4. **Situación de los libros** (texto secundario, más discreto):
   - «Cerrado hasta 30 sep» o «Sin cierre».
   - «Último movimiento hace 12 días».
   - Por cobrar y por pagar: «Por cobrar $12,400 · Por pagar $3,050».

En **Mac** (y iPad ancho): tabla con columnas ordenables, por ejemplo: Cliente, Estado, Banco por revisar, Vencidas,
Sales tax, Conciliado hasta, Cerrado hasta y Última actividad. Doble clic abre el cliente. En **iPhone**: lista de
filas con nombre y estado arriba, pendientes debajo.

## Acciones por cliente (menú «···» o menú contextual)
- Abrir
- Paquete para el contador (PDF + CSV; ya existe)
- Respaldo de esta empresa (ya existe)
- Cerrar periodo… (ya existe)
- Archivar / Mostrar
- Borrar… (con confirmación)

## Estados que hay que dibujar
- **Todo al día:** mensaje tranquilo («Todos tus clientes están al día») con la lista debajo.
- **Un solo cliente:** el panel con una sola fila y una invitación suave a añadir el siguiente.
- **Cargando o sincronizando iCloud.**
- **Suscripción vencida (solo lectura):** se ve el panel, pero sin «Añadir cliente» ni acciones que escriban.
- **Búsqueda sin resultados.**

## Datos de ejemplo para el diseño
| Cliente | Tipo · estado | Estado | Pendientes | Libros |
|---|---|---|---|---|
| Rivera Landscaping LLC | LLC · Texas | ● Urgente | Sales tax $842, vence 14 nov · 23 por revisar | Cerrado hasta 30 sep · hace 2 días |
| Bella Nails Studio | Negocio propio · Florida | ● Urgente | Chase ··· 4410 conciliada hasta 31 jul | Sin cierre · hace 12 días |
| Ortiz Plumbing Inc. | S corporation · California | ● Pendiente | 4 vencidas · $3,120 · 2 avisos | Cerrado hasta 30 sep · hoy |
| Café La Esquina | LLC · Nueva York | ● Pendiente | 8 por revisar | Cerrado hasta 31 ago · hace 3 días |
| Lopez Consulting | Negocio propio · Texas | ● Al día | — | Cerrado hasta 31 oct · ayer |

## Fuera de este diseño (vendrá después)
Compartir los libros con el cliente, preguntas al cliente, notas por cliente, tareas y horas, y la conexión
automática con el banco (Plaid). No dibujarlos.

## Qué entregar
iPhone (claro y oscuro), iPad horizontal y Mac. Incluir una fila con cada estado, el menú de acciones y los estados vacíos.

---

**Diseño:** canvas «Chirogra — Panel de clientes» (https://claude.ai/artifact/46eihuFoKbh8RrMEvHHNxA), hecho por el
usuario en Claude Design el 10-nov. Programado el mismo día (CONTEXTO, «Siguiente», punto 3). Diferencias con el canvas:
«Crear copia…» en vez de «Respaldo de esta empresa…» (es el nombre que ya usa la app), y el aviso de borrar solo
menciona iCloud si está encendido.
