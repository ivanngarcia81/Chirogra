"""California: tasas por ciudad y condado del CDTFA (`SalesTaxRates<fecha>.xlsx`, cdtfa.ca.gov/taxes-and-fees/
sales-use-tax-rates.htm). Cada fila es una ciudad (con su total) o un condado (el total fuera de las ciudades). El total
incluye el 7.25 % de todo el estado."""
from pathlib import Path

import ciudades
import hoja


def _millionths(text: str) -> int:
    try:
        return round(float(text) * 1_000_000)
    except ValueError:
        return -1


def zip_rates(path: Path, names, state_rate: int) -> list:
    rows = hoja.rows(path)
    h = next(i for i, r in enumerate(rows) if "Location" in r and "Rate" in r)
    col = {name: rows[h].index(name) for name in ("Location", "Rate", "County", "Type")}
    cities, counties = {}, {}
    for r in rows[h + 1:]:
        if len(r) <= col["Type"]:
            continue
        total = _millionths(r[col["Rate"]])
        if total < 0:
            continue
        if r[col["Type"]] == "City":
            cities[(ciudades.normalized(r[col["Location"]]), ciudades.normalized(r[col["County"]]))] = total
        elif r[col["Type"]] == "County":
            counties[ciudades.normalized(r[col["County"]])] = total

    def city_rate(city, county):
        total = cities.get((ciudades.normalized(city), ciudades.normalized(county)))
        return None if total is None else total - state_rate

    def county_rate(county):
        total = counties.get(ciudades.normalized(county))
        return None if total is None else total - state_rate

    return ciudades.zip_rates("CA", names, state_rate, city_rate, county_rate)
