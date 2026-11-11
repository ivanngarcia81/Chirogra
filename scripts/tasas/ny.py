"""New York: Publication 718 del Department of Taxation and Finance (tax.ny.gov/pdf/publications/sales/pub718.pdf), pasada
a texto con `pdf_texto.swift`. Da el total (estatal 4 % incluido) por condado y por las ciudades con tasa propia
(«Yonkers (city) 8⅞»); «– except» quiere decir «el condado, salvo esas ciudades». Los cinco condados de la ciudad de
New York («Kings (Brooklyn) – see New York City») toman la de la ciudad. El estado advierte que el ZIP no coincide con
sus límites: por eso la app dice «aproximada»."""
import re
from pathlib import Path

import ciudades

_FRACTIONS = {"": 0, "⅛": 1_250, "¼": 2_500, "⅜": 3_750, "½": 5_000, "⅝": 6_250, "¾": 7_500, "⅞": 8_750}
_RATE = re.compile(r"^\*?(.+?)\s+(\d+)([⅛¼⅜½⅝¾⅞]?)\s+\d{4}$")
_NYC = re.compile(r"^\*?(\w[\w .]*?)\s+\([^)]*\)\s+– see New York City$|^\*?(\w[\w .]*?)\s+– see New York City$")


def rates(text_path: Path):
    counties, cities, nyc_counties = {}, {}, []
    for line in text_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if m := _NYC.match(line):
            nyc_counties.append(m.group(1) or m.group(2))
            continue
        m = _RATE.match(line)
        if not m or m.group(1).startswith("New York State"):
            continue
        name = m.group(1).replace("– except", "").strip()
        total = int(m.group(2)) * 10_000 + _FRACTIONS[m.group(3)]
        if name.endswith("(city)"):
            cities[ciudades.normalized(name[:-6])] = total
        elif name == "New York City":
            cities[ciudades.normalized(name)] = total
        else:
            counties[ciudades.normalized(re.sub(r"\s*\(.*\)", "", name))] = total
    nyc = cities.get(ciudades.normalized("New York City"))
    for county in nyc_counties:
        counties[ciudades.normalized(county)] = nyc
    return counties, cities


def zip_rates(text_path: Path, names, state_rate: int) -> list:
    counties, cities = rates(text_path)
    # Los alias de los distritos («Brooklyn», «Manhattan») también entran: se comprueba que estén los 62 condados.
    fips = names.state_fips("NY")
    missing = [name for geoid, name in names._counties.items()
               if geoid[:2] == fips and ciudades.normalized(name) not in counties]
    if missing:
        raise SystemExit(f"New York: faltan condados en la Publication 718 ({', '.join(missing)}); revisa el PDF.")

    def city_rate(city, county):
        total = cities.get(ciudades.normalized(city))
        return None if total is None else total - state_rate

    def county_rate(county):
        total = counties.get(ciudades.normalized(county))
        return None if total is None else total - state_rate

    out = ciudades.zip_rates("NY", names, state_rate, city_rate, county_rate)
    for rate in out:
        if rate["region"] == "New York":
            rate["region"] = "New York City"
    return out
