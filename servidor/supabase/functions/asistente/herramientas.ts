// Las herramientas del asistente (docs/PLAN-1.4.md §2). Las define el servidor, pero las ejecuta la app con los libros
// del aparato: el servidor nunca ve los libros, solo las cifras ya sumadas que devuelve cada herramienta.
// El orden y el texto no cambian entre peticiones: van en la parte del prompt que se guarda en caché.

import type Anthropic from "npm:@anthropic-ai/sdk@1.14.0";

const fecha = { type: "string", description: "Fecha en formato AAAA-MM-DD." } as const;

const periodo = {
  type: "object",
  properties: {
    desde: { ...fecha, description: "Primer día del periodo, AAAA-MM-DD." },
    hasta: { ...fecha, description: "Último día del periodo, AAAA-MM-DD (incluido)." },
  },
  required: ["desde", "hasta"],
  additionalProperties: false,
} as const;

const sinDatos = { type: "object", properties: {}, additionalProperties: false } as const;

export const HERRAMIENTAS: Anthropic.Beta.BetaTool[] = [
  {
    name: "resumen_periodo",
    description:
      "Ingresos, gastos (con el costo de ventas) y ganancia neta del negocio en un periodo, con la base contable " +
      "(caja o devengado) que el usuario tiene elegida en Reportes. Úsala para «cuánto gané», «cómo voy este mes», " +
      "comparar meses (llámala una vez por periodo).",
    input_schema: periodo,
    strict: true,
  },
  {
    name: "gastos_por_categoria",
    description:
      "Gastos del periodo por categoría (cuenta de gasto y costo de ventas), de mayor a menor. Úsala para «en qué " +
      "gasto más», «cuánto gasté en publicidad».",
    input_schema: periodo,
    strict: true,
  },
  {
    name: "ingresos_por_categoria",
    description: "Ingresos del periodo por cuenta de ingreso, de mayor a menor.",
    input_schema: periodo,
    strict: true,
  },
  {
    name: "por_cobrar",
    description:
      "Facturas abiertas con saldo por cobrar hoy: cliente, número, vencimiento, saldo y días de atraso. Úsala para " +
      "«quién me debe», «qué facturas están vencidas».",
    input_schema: sinDatos,
    strict: true,
  },
  {
    name: "por_pagar",
    description:
      "Facturas de proveedores abiertas con saldo por pagar hoy: proveedor, número, vencimiento, saldo y días de " +
      "atraso. Úsala para «qué tengo que pagar», «qué vence esta semana».",
    input_schema: sinDatos,
    strict: true,
  },
  {
    name: "apartado_impuestos",
    description:
      "Cuánto apartar para los impuestos estimados del IRS (1040-ES): porcentaje que eligió el usuario, ganancia y " +
      "apartado de cada periodo del año, lo ya pagado y el próximo vencimiento. Es una guía, no asesoría fiscal.",
    input_schema: sinDatos,
    strict: true,
  },
  {
    name: "saldos_cuentas",
    description: "Saldo de hoy de las cuentas de dinero: bancos, caja y tarjetas de crédito (lo que se debe en cada tarjeta).",
    input_schema: sinDatos,
    strict: true,
  },
  {
    name: "citas",
    description: "Citas de la agenda en un periodo: fecha y hora, cliente, título, lugar y estado.",
    input_schema: periodo,
    strict: true,
  },
];

/// Las pantallas a las que la app sabe llevar (`AssistantScreens` en la app; los ids tienen que ser los mismos).
const PANTALLAS_IDS = [
  "inicio", "agenda", "ajustes", "facturas", "estimados", "clientes", "gastos", "proveedores", "facturas_por_pagar",
  "gastos_recurrentes", "banca_cuentas", "banca_por_revisar", "banca_reglas", "conciliacion", "reporte_resultados",
  "reporte_balance_general", "reporte_balanza", "reporte_flujo_de_efectivo", "reporte_por_cobrar", "reporte_por_pagar",
  "reporte_sales_tax", "presupuestos", "plan_de_cuentas", "asientos_de_diario", "libro_mayor", "cierre_de_periodo",
  "bitacora", "impuesto_sobre_ventas", "impuestos_estimados",
];

/// Para la app del build 69 en adelante (manda `capacidades: ["pantallas"]`).
export const PANTALLAS: Anthropic.Beta.BetaTool[] = [
  {
    name: "sales_tax",
    description:
      "Sales tax según los libros: lo pendiente de pagar hoy, el periodo de declaración en curso y el anterior (ventas, " +
      "ventas gravables, impuesto cobrado por tasa, fecha límite y lo pendiente al cierre). Úsala para «cuánto sales tax " +
      "debo», «cuándo declaro».",
    input_schema: sinDatos,
    strict: true,
  },
  {
    name: "buscar_movimientos",
    description:
      "Busca gastos, facturas por pagar, facturas y cobros que nombren a alguien o algo (proveedor, cliente, número o " +
      "nota), con el total por tipo y los 40 más recientes. Úsala para «cuánto le pagué a Home Depot este año», «qué le " +
      "he facturado a Ana», «busca la factura 1043».",
    input_schema: {
      type: "object",
      properties: {
        texto: { type: "string", description: "Nombre, número o palabra a buscar." },
        desde: { ...fecha, description: "Primer día, AAAA-MM-DD, si la pregunta tiene periodo." },
        hasta: { ...fecha, description: "Último día, AAAA-MM-DD (incluido), si la pregunta tiene periodo." },
      },
      required: ["texto"],
      additionalProperties: false,
    },
  },
  {
    name: "abrir_pantalla",
    description:
      "Pone debajo de tu respuesta un botón «Ir a…» que lleva a esa pantalla de la app. Úsala al explicar cómo hacer " +
      "algo (la pantalla donde se empieza) o cuando el usuario quiera ver algo en detalle. Una por respuesta.",
    input_schema: {
      type: "object",
      properties: { pantalla: { type: "string", enum: PANTALLAS_IDS } },
      required: ["pantalla"],
      additionalProperties: false,
    },
    strict: true,
  },
];

/// Las de registrar, solo para la app que enseña sus tarjetas (manda `capacidades: ["borradores"]`, build 69 y
/// siguientes). Van detrás de las de consulta.
export const BORRADORES: Anthropic.Beta.BetaTool[] = [
  // Registrar con una frase. Ninguna guarda: enseñan una tarjeta con el borrador y el usuario pulsa «Guardar» o
  // «Editar». Devuelven lo que la app entendió («borrador»), lo que falta («faltan») y, si algo no se encontró en los
  // libros, las opciones que hay. Los nombres (proveedor, categoría, cuenta, cliente) se dicen como los dijo el
  // usuario: la app los busca en sus libros.
  {
    name: "preparar_gasto",
    description:
      "Prepara un gasto para que el usuario lo guarde: «gasté $85 en Adobe con la tarjeta», «pagué 40 de gasolina». " +
      "Pon solo lo que dijo o se deduce con seguridad; lo demás déjalo fuera. La categoría la elige la app por el " +
      "proveedor si no la dices.",
    input_schema: {
      type: "object",
      properties: {
        monto: { type: "number", description: "Total pagado en dólares (85.5 = $85.50)." },
        proveedor: { type: "string", description: "A quién se pagó (tienda, empresa, persona)." },
        categoria: { type: "string", description: "Categoría de gasto, si la dijo o es obvia (Software, Gasolina, Comidas, Publicidad…)." },
        pagado_con: {
          type: "string",
          description: "Con qué pagó: el nombre de la cuenta o «tarjeta de crédito», «débito», «efectivo», «cheque», «transferencia».",
        },
        fecha: { ...fecha, description: "Día del gasto, AAAA-MM-DD. Sin decirlo, hoy." },
        nota: { type: "string", description: "Para qué fue, si lo dijo." },
      },
      required: ["monto"],
      additionalProperties: false,
    },
  },
  {
    name: "preparar_factura",
    description:
      "Prepara una factura nueva como borrador para un cliente que ya está en los libros: «factúrale a Ana 3 horas a " +
      "$60». Al guardar queda en borrador (no se emite ni se envía); el impuesto se calcula al abrirla.",
    input_schema: {
      type: "object",
      properties: {
        cliente: { type: "string", description: "Nombre del cliente." },
        lineas: {
          type: "array",
          items: {
            type: "object",
            properties: {
              descripcion: { type: "string", description: "Qué se cobra." },
              cantidad: { type: "number", description: "Cantidad u horas (1 si no lo dijo)." },
              precio: { type: "number", description: "Precio por unidad en dólares." },
            },
            required: ["descripcion", "precio"],
            additionalProperties: false,
          },
        },
        fecha: { ...fecha, description: "Fecha de la factura, AAAA-MM-DD. Sin decirlo, hoy." },
        mensaje: { type: "string", description: "Mensaje para el cliente, si lo pidió." },
      },
      required: ["cliente", "lineas"],
      additionalProperties: false,
    },
  },
  {
    name: "preparar_cobro",
    description:
      "Prepara un cobro de una factura abierta: «Ana me pagó la factura», «me pagaron $200 de la 1043 en efectivo». " +
      "Busca la factura por número o por cliente; sin monto, el saldo entero.",
    input_schema: {
      type: "object",
      properties: {
        cliente: { type: "string", description: "Quién pagó." },
        factura: { type: "string", description: "Número de la factura, si lo dijo." },
        monto: { type: "number", description: "Lo cobrado en dólares, si no es el saldo entero." },
        metodo: { type: "string", description: "Cómo pagó: transferencia, Zelle, cheque, efectivo, tarjeta." },
        deposito: { type: "string", description: "Cuenta donde entró el dinero, si la dijo." },
        fecha: { ...fecha, description: "Día del cobro, AAAA-MM-DD. Sin decirlo, hoy." },
      },
      additionalProperties: false,
    },
  },
  {
    name: "preparar_cita",
    description: "Prepara una cita en la agenda: «cita con Ana el jueves a las 3 para medir la cocina».",
    input_schema: {
      type: "object",
      properties: {
        inicio: { type: "string", description: "Día y hora de inicio, «AAAA-MM-DD HH:mm» (24 h, hora local)." },
        minutos: { type: "integer", description: "Duración en minutos (60 si no lo dijo)." },
        cliente: { type: "string", description: "Nombre del cliente, si es con un cliente." },
        titulo: { type: "string", description: "Servicio o asunto." },
        lugar: { type: "string" },
        notas: { type: "string" },
      },
      required: ["inicio"],
      additionalProperties: false,
    },
  },
];
