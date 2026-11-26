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
