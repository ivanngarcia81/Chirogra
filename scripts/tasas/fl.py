"""Florida: el 6 % del estado más el recargo del condado («discretionary sales surtax»), del formulario DR-15DSS del
Department of Revenue (floridarevenue.com/Forms_library/current/dr15dss_<año>.pdf), pasado a texto con
`pdf_texto.swift`. En Florida no hay impuesto de ciudad: todo el ZIP toma el recargo de su condado."""
import re
from pathlib import Path

import ciudades

# «Alachua 1.5% (.5%) Jan 1, 2019 …», «Citrus None», «Miami-Dade 1% (.5%) …», «St. Johns .5% …»: el primer % es el total.
_LINE = re.compile(r"^([A-Z][A-Za-z.\- ]+?)\s+(None|\d*\.?\d+%)")


def county_surtaxes(text_path: Path) -> dict:
    out = {}
    for line in text_path.read_text(encoding="utf-8").splitlines():
        m = _LINE.match(line.strip())
        if not m or m.group(1).split()[0] in ("Discretionary", "Total", "County", "Page", "Current", "New", "For", "In"):
            continue
        rate = 0 if m.group(2) == "None" else round(float(m.group(2).rstrip("%")) * 10_000)
        out[ciudades.normalized(m.group(1))] = rate
    return out


def zip_rates(text_path: Path, names, state_rate: int) -> list:
    surtax = county_surtaxes(text_path)
    if len(surtax) != 67:
        raise SystemExit(f"Florida: se leyeron {len(surtax)} condados del DR-15DSS y son 67; revisa el PDF.")

    def county_rate(county):
        rate = surtax.get(ciudades.normalized(county))
        return None if rate is None else rate + 60_000 - state_rate

    return ciudades.zip_rates("FL", names, state_rate, lambda city, county: None, county_rate)
