"""Illinois: archivo de tasas por municipio y condado del IDOR (`ordmache-current.txt`, tax.illinois.gov, «Sales Tax
Rate - Machine Readable Files»). Ancho fijo: id (10), municipio (25), condado (25), marca «Y» si la tasa va por
dirección (1), fecha de inicio (8) y tasa general de mercancía en millonésimas (6: «105000» = 10.5 %), y luego
lo demás. Los «X COUNTY» son la tasa fuera de los municipios. Si la tasa va por dirección (Springfield, Peoria…), se
toma la general del municipio del archivo por dirección (`ordmacha-current.txt`, el registro «R00» sin dirección: id
(10), registro (3), municipio (25), condado (25), dirección (35), fecha (8), tasa (6))."""
from collections import Counter, defaultdict
from pathlib import Path

import ciudades


def _base_rates(path: Path) -> dict:
    """id del municipio → su tasa general sin dirección (registro «R00» del archivo por dirección)."""
    out = {}
    if path.exists():
        for line in path.read_text(encoding="latin-1").splitlines():
            if line[10:13] == "R00" and line[106:112].isdigit():
                out[line[0:10]] = int(line[106:112])
    return out


def zip_rates(path: Path, names, state_rate: int) -> list:
    base = _base_rates(path.with_name(path.name.replace("ordmache", "ordmacha")))
    cities, any_county, counties = {}, defaultdict(Counter), {}
    for line in path.read_text(encoding="latin-1").splitlines():
        if len(line) < 75 or not line[61:69].isdigit():
            continue
        name, county, by_address = line[10:35].strip(), line[35:60].strip(), line[60] == "Y"
        total = int(line[69:75])  # «105000» = 10.5 % = 105 000 millonésimas
        if by_address:
            total = base.get(line[0:10], 0)
        if total == 0:
            continue
        if name.endswith(" COUNTY") and ciudades.normalized(name[:-7]) == ciudades.normalized(county):
            counties[ciudades.normalized(county)] = total
        else:
            cities[(ciudades.normalized(name), ciudades.normalized(county))] = total
            any_county[ciudades.normalized(name)][total] += 1

    def city_rate(city, county):
        total = cities.get((ciudades.normalized(city), ciudades.normalized(county)))
        if total is None and any_county.get(ciudades.normalized(city)):
            # La ciudad está en varios condados y en este va por dirección (Aurora en DuPage): la más común.
            total = any_county[ciudades.normalized(city)].most_common(1)[0][0]
        return None if total is None else total - state_rate

    def county_rate(county):
        total = counties.get(ciudades.normalized(county))
        return None if total is None else total - state_rate

    return ciudades.zip_rates("IL", names, state_rate, city_rate, county_rate)
