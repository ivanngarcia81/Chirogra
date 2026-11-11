"""Texas: tasas por ciudad del Comptroller (`city-rates.xlsx`, comptroller.texas.gov/taxes/sales/city.php).

Cada fila es una combinación ciudad · condado · distritos especiales · transporte, con el total (estatal 6.25 % incluido).
Para cada ciudad y condado se toma el total más común de sus filas (casi siempre el tope de 8.25 %); fuera de las
ciudades, la tasa del condado. Los archivos por dirección del Comptroller (formato Streamlined) no se pueden descargar
sin navegador (la página responde 403 a los programas)."""
from collections import Counter, defaultdict
from pathlib import Path

import ciudades
import hoja

STATE_RATE = 62_500


def _millionths(text: str) -> int:
    try:
        return round(float(text) * 1_000_000)
    except ValueError:
        return 0


def zip_rates(path: Path, names, state_rate: int) -> list:
    rows = hoja.rows(path)
    header = rows[0]
    col = {name: header.index(name) for name in ("CityName", "CityNumber", "CityTax", "CountyName", "CountyTax", "TotalTax")}
    by_city = defaultdict(Counter)
    by_county = defaultdict(Counter)
    for r in rows[1:]:
        if len(r) <= col["TotalTax"]:
            continue
        city, county = r[col["CityName"]], r[col["CountyName"]]
        by_county[ciudades.normalized(county)][_millionths(r[col["CountyTax"]])] += 1
        if "/" in city or r[col["CityNumber"]].lower() == "n/a":
            continue
        by_city[(ciudades.normalized(city), ciudades.normalized(county))][_millionths(r[col["TotalTax"]]) - STATE_RATE] += 1

    def mode(counter):
        return max(counter.items(), key=lambda kv: (kv[1], kv[0]))[0]

    def city_rate(city, county):
        counter = by_city.get((ciudades.normalized(city), ciudades.normalized(county)))
        return mode(counter) + STATE_RATE - state_rate if counter else None

    def county_rate(county):
        counter = by_county.get(ciudades.normalized(county))
        return mode(counter) + STATE_RATE - state_rate if counter else 0 + STATE_RATE - state_rate

    return ciudades.zip_rates("TX", names, state_rate, city_rate, county_rate)
