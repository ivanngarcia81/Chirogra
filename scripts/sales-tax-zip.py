#!/usr/bin/env python3
"""Tabla de sales tax por código postal para chirogra.com (PLAN-FASE2 §7, `PostalTaxTable` en la app).

Convierte un CSV con las tasas por ZIP —sacado de una fuente cuya licencia permita republicarlo; hoy **no hay ninguna
decidida** (ver el informe del 8-nov en la rama de recibos y cobro)— al JSON que descarga la app, y lo comprueba.

Uso:
    scripts/sales-tax-zip.py entrada.csv salida.json --source "SST Governing Board, WA DOR…" --effective 2026-12-01

CSV con cabecera: postalCode,state,region,stateRate,localRate   (tasas en %, p. ej. 6.25 y 2)
Salida (la que lee `PostalTaxTable(json:)`):
    {"source": "…", "effectiveDate": "2026-12-01", "rates": [{"postalCode": "78702", "state": "TX", "region": "Austin",
     "stateRateMillionths": 62500, "localRateMillionths": 20000}, …]}

Reglas: ZIP de 5 dígitos (se quita el +4), estado de 2 letras, tasas entre 0 y 20 % en total; un ZIP repetido se queda
con la tasa total más común (un ZIP puede cruzar varias jurisdicciones: la app avisa de que es aproximada).
"""
import argparse
import collections
import csv
import decimal
import json
import re
import sys


def millionths(percent: str) -> int:
    value = decimal.Decimal(percent.strip().rstrip("%") or "0")
    return int((value * 10_000).to_integral_value(rounding=decimal.ROUND_HALF_UP))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("csv")
    parser.add_argument("json")
    parser.add_argument("--source", required=True, help="De dónde salen las tasas (sale en la confirmación de la app)")
    parser.add_argument("--effective", required=True, help="Fecha desde la que valen, AAAA-MM-DD")
    args = parser.parse_args()
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", args.effective):
        sys.exit("--effective debe ser AAAA-MM-DD")

    candidates = collections.defaultdict(list)
    errors = 0
    with open(args.csv, newline="", encoding="utf-8") as handle:
        for line, row in enumerate(csv.DictReader(handle), start=2):
            try:
                zip5 = row["postalCode"].strip().split("-")[0]
                state = row["state"].strip().upper()
                state_rate, local_rate = millionths(row["stateRate"]), millionths(row["localRate"])
                if not re.fullmatch(r"\d{5}", zip5) or not re.fullmatch(r"[A-Z]{2}", state):
                    raise ValueError("ZIP o estado no válidos")
                if state_rate < 0 or local_rate < 0 or state_rate + local_rate > 200_000:
                    raise ValueError("tasa fuera de 0–20 %")
            except (KeyError, ValueError, decimal.InvalidOperation) as error:
                errors += 1
                print(f"renglón {line}: {error}", file=sys.stderr)
                continue
            candidates[zip5].append((state, row.get("region", "").strip(), state_rate, local_rate))

    rates = []
    ambiguous = 0
    for zip5 in sorted(candidates):
        options = candidates[zip5]
        counts = collections.Counter(options)
        if len({o[2] + o[3] for o in options}) > 1:
            ambiguous += 1
        state, region, state_rate, local_rate = counts.most_common(1)[0][0]
        rates.append({"postalCode": zip5, "state": state, "region": region,
                      "stateRateMillionths": state_rate, "localRateMillionths": local_rate})

    with open(args.json, "w", encoding="utf-8") as handle:
        json.dump({"source": args.source, "effectiveDate": args.effective, "rates": rates}, handle,
                  ensure_ascii=False, separators=(",", ":"))
    print(f"{len(rates)} códigos postales ({ambiguous} con varias tasas; se usó la más común), {errors} renglones malos")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
