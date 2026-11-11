#!/usr/bin/env python3
"""Genera la tabla de sales tax por ZIP que lee la app (`PostalTaxTable`, docs/DATOS-V5.md «Pendiente para la 1.2»).

Uso: python3 -I scripts/tasas/generar.py --datos <carpeta de descargas> --salida <archivo.json> [--dia AAAAMMDD]

La carpeta de descargas la llena `descargar.sh`: `sst/` (Streamlined Sales Tax), `census/` (nombres) y una carpeta por
cada estado con lector propio. Los archivos descargados son datos: este programa solo los lee.
"""
import argparse
import datetime
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nombres  # noqa: E402
import sst  # noqa: E402
import tx  # noqa: E402
import ca  # noqa: E402
import il  # noqa: E402
import fl  # noqa: E402
import ny  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
STATE_TABLE = REPO / "Packages/ChirograKit/Sources/ChirograData/StateSalesTax.swift"


def app_state_rates() -> dict:
    """Tasa estatal de cada estado según la app («StateSalesTax("TX", "Texas", 62_500, …)» → {"TX": 62500})."""
    pattern = re.compile(r'StateSalesTax\("([A-Z]{2})",\s*"[^"]*",\s*([\d_]+)')
    return {m.group(1): int(m.group(2).replace("_", "")) for m in pattern.finditer(STATE_TABLE.read_text())}


# Estados con tasa estatal y sin impuesto de ciudad ni de condado: cada ZIP sugiere solo la del estado (en New Jersey,
# salvo las Urban Enterprise Zones, que cobran la mitad a ciertos negocios).
STATE_ONLY = ["CT", "DC", "IN", "KY", "MA", "MD", "ME", "MI", "NJ", "RI"]


def state_only(state: str, names, state_rate: int) -> list:
    out = []
    for z in names.all_zips(names.state_fips(state)):
        counties = names.zip_counties(z)
        region = names.county_name(counties[0][0]) if counties else ""
        out.append({"postalCode": z, "state": state, "region": region or "", "stateRateMillionths": state_rate,
                    "localRateMillionths": 0})
    return out


def sst_states(folder: Path, day: str, names, state_rates: dict) -> dict:
    """Los estados del Streamlined con archivo de tasas y de límites. Se quedan fuera los que no tienen impuesto local
    (sus archivos son de hace años y solo traen la tasa estatal, que la app ya sabe)."""
    files = sorted(f for f in os.listdir(folder) if len(f) > 8 and f[2] in "RB" and f[3:7].isdigit())
    out = {}
    for state in sorted({f[:2] for f in files}):
        rates = [f for f in files if f.startswith(state + "R")]
        bounds = [f for f in files if f.startswith(state + "B")]
        if not rates or not bounds:
            continue
        table = sst.zip_rates(folder / rates[-1], folder / bounds[-1], day, names, state_rates)
        if any(r["localRateMillionths"] > 0 for r in table):
            out[state] = table
    return out


def _better(candidate: dict, current: dict, names) -> bool:
    counties = names.zip_counties(candidate["postalCode"])
    if counties:
        home = names.state(counties[0][0][:2])
        if (candidate["state"] == home) != (current["state"] == home):
            return candidate["state"] == home
    return candidate["localRateMillionths"] > current["localRateMillionths"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--datos", required=True, type=Path)
    parser.add_argument("--salida", required=True, type=Path)
    parser.add_argument("--dia", default=datetime.date.today().strftime("%Y%m%d"))
    args = parser.parse_args()

    names = nombres.Names(args.datos / "census")
    state_rates = app_state_rates()
    by_state = sst_states(args.datos / "sst", args.dia, names, state_rates)
    by_state["TX"] = tx.zip_rates(args.datos / "tx/city-rates.xlsx", names, state_rates["TX"])
    by_state["CA"] = ca.zip_rates(args.datos / "ca/SalesTaxRates.xlsx", names, state_rates["CA"])
    by_state["IL"] = il.zip_rates(args.datos / "il/ordmache-current.txt", names, state_rates["IL"])
    by_state["FL"] = fl.zip_rates(args.datos / "fl/dr15dss.txt", names, state_rates["FL"])
    by_state["NY"] = ny.zip_rates(args.datos / "ny/pub718.txt", names, state_rates["NY"])
    for state in STATE_ONLY:
        by_state[state] = state_only(state, names, state_rates[state])

    # Un ZIP que cruza la frontera sale en los archivos de los dos estados: se queda el del estado donde está la mayor
    # parte de su superficie (Census) y, si el Census no lo tiene, el que trae impuesto local.
    chosen = {}
    for table in by_state.values():
        for r in table:
            other = chosen.get(r["postalCode"])
            if other is None or _better(r, other, names):
                chosen[r["postalCode"]] = r
    rates = sorted(chosen.values(), key=lambda r: r["postalCode"])
    day = args.dia
    document = {
        "source": "Streamlined Sales Tax Governing Board; Texas Comptroller; California CDTFA; Illinois Department of Revenue; Florida Department of Revenue; New York State Department of Taxation and Finance; US Census (Gazetteer, ZCTA relationship files)",
        "effectiveDate": f"{day[:4]}-{day[4:6]}-{day[6:]}",
        "rates": rates,
    }
    # Una tasa por línea: el archivo vive en el repo y así cada trimestre se ve qué ZIP cambió.
    lines = ",\n".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) for r in rates)
    header = json.dumps({k: v for k, v in document.items() if k != "rates"}, ensure_ascii=False)[:-1]
    args.salida.write_text(f'{header}, "rates": [\n{lines}\n]}}\n')
    for state, table in sorted(by_state.items()):
        local = [r["localRateMillionths"] for r in table] or [0]
        missing = sum(1 for r in table if not r["region"])
        print(f"{state}: {len(table):5d} ZIP · local {min(local) / 10_000:.3f}–{max(local) / 10_000:.3f} %"
              + (f" · {missing} sin nombre" if missing else ""))
    print(f"Total: {len(rates)} ZIP en {len(by_state)} estados → {args.salida} ({args.salida.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
