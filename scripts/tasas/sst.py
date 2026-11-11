#!/usr/bin/env python3
"""Tasas por ZIP de los estados del Streamlined Sales Tax (docs/DATOS-V5.md, «Pendiente para la 1.2»).

Lee el archivo de tasas (R) y el de límites (B) de un estado, tal como los publica streamlinedsalestax.org, y da una
tasa por ZIP de 5 dígitos: la combinación de condado + ciudad + distritos especiales que más cubre en ese ZIP.

Formato (SST, «Rate and Boundary Files»):
- Tasas: estado FIPS, tipo de jurisdicción (45 estado, 00 condado, 01 ciudad, otros: distritos), código, tasa general,
  …, fecha de inicio, fecha de fin.
- Límites: tipo de registro (A dirección, 4 ZIP+4, Z ZIP), inicio, fin, …, ZIP (16), ZIP+4 (17), ZIP bajo (18),
  extensión baja (19), ZIP alto (20), extensión alta (21), SER (22), estado FIPS (23), (24), condado FIPS (25),
  lugar FIPS (26), (27), (28), (29) y 20 distritos de 3 campos (fuente, código, tipo) desde el 30.

Cada ZIP se decide con sus direcciones (cada rango cuenta 1); sin direcciones, con los ZIP+4 (cada uno cuenta sus
extensiones); y sin ninguno, con el registro Z del ZIP entero. Los nombres salen de los archivos «Gazetteer» del Census.
"""
import csv
import io
import zipfile
from collections import defaultdict
from pathlib import Path


def _rows(path: Path):
    """Filas CSV de un .csv o del primer .csv dentro de un .zip."""
    if path.suffix.lower() == ".zip":
        with zipfile.ZipFile(path) as z:
            name = next(n for n in z.namelist() if n.lower().endswith((".csv", ".txt")))
            with z.open(name) as f:
                yield from csv.reader(io.TextIOWrapper(f, encoding="latin-1", newline=""))
    else:
        with open(path, encoding="latin-1", newline="") as f:
            yield from csv.reader(f)


def _effective(begin: str, end: str, day: str) -> bool:
    return (begin or "0") <= day <= (end or "99999999")


def _clean(value: str) -> str:
    """Sin la marca BOM del principio del archivo («\ufeff19» o «ï»¿19») ni espacios."""
    return value.strip().lstrip("\ufeffï»¿")


def _key(kind: str, code: str) -> tuple:
    """Clave de una jurisdicción con los ceros que algunos estados quitan (Nevada pone «0» y no «00»; Vermont, «1»)."""
    kind = kind.strip().zfill(2)
    width = {"00": 3, "01": 5}.get(kind, len(code.strip()))
    return kind, code.strip().zfill(width)


def load_rates(path: Path, day: str) -> dict:
    """(tipo, código) → tasa en millonésimas, vigente el día `day` (AAAAMMDD)."""
    rates = {}
    for r in _rows(path):
        r[0] = _clean(r[0]) if r else ""
        if len(r) < 9 or not r[0].isdigit():
            continue
        if _effective(r[7].strip(), r[8].strip(), day):
            rates[_key(r[1], r[2])] = round(float(r[3]) * 1_000_000)
    return rates


def zip_rates(rates_path: Path, boundary_path: Path, day: str, names, app_state_rates: dict) -> list:
    """`app_state_rates`: la tasa estatal de la app por estado (`StateSalesTax.swift`). La tabla da el total del archivo
    partido en esa tasa y el resto como local: así cuadra con la tasa estatal que la app crea en el alta (Nevada, por
    ejemplo, pone el total en el condado y 0 en el estado)."""
    rates = load_rates(rates_path, day)
    file_state_rate = next((v for (t, _), v in rates.items() if t == "45"), 0)
    # ZIP → {(condado, lugar, distritos): peso}, por clase de registro.
    weights = {"4": defaultdict(lambda: defaultdict(float)), "A": defaultdict(lambda: defaultdict(float)),
               "Z": defaultdict(lambda: defaultdict(float))}
    # Nombre de ciudad de los registros de dirección (el del correo), por si el ZIP no tiene ni ciudad ni condado.
    postal_cities = defaultdict(lambda: defaultdict(int))
    state_fips = None
    for r in _rows(boundary_path):
        if len(r) < 30 or _clean(r[0]) not in weights or not _effective(r[1], r[2], day):
            continue
        r[0] = _clean(r[0])
        state_fips = state_fips or r[22].strip()
        districts = tuple(sorted(_key(r[i + 2], r[i + 1]) for i in range(29, min(len(r) - 2, 89), 3)
                                 if r[i + 1].strip()))
        county = r[24].strip().zfill(3) if r[24].strip() else ""
        place = r[25].strip().zfill(5) if r[25].strip() else ""
        key = (county, place, districts)
        if r[0] == "A":
            zips, weight = [r[15].strip()[:5]], 1.0
            if r[14].strip():
                postal_cities[zips[0]][r[14].strip()] += 1
        else:
            low, high = r[17].strip()[:5], r[19].strip()[:5] or r[17].strip()[:5]
            if low != high:
                # Rango de varios ZIP (raro): uno por ZIP, con peso 1.
                zips, weight = [f"{z:05d}" for z in range(int(low), int(high) + 1)], 1.0
            elif r[0] == "4" and r[18].strip().isdigit() and r[20].strip().isdigit():
                zips, weight = [low], float(int(r[20]) - int(r[18]) + 1)
            else:
                zips, weight = [low], 1.0
        for z in zips:
            if len(z) == 5 and z.isdigit():
                weights[r[0]][z][key] += weight

    out = []
    all_zips = set(weights["4"]) | set(weights["A"]) | set(weights["Z"])
    for z in sorted(all_zips):
        # Primero las direcciones (son las que traen la ciudad: en Vermont, los ZIP+4 son apartados de correos y rangos
        # enteros sin ciudad, y por su tamaño tapaban a Burlington); luego los ZIP+4 y, al final, el ZIP entero.
        options = weights["A"].get(z) or weights["4"].get(z) or weights["Z"].get(z)
        (county, place, districts), _ = max(options.items(), key=lambda kv: (kv[1], kv[0]))
        county_rate = rates.get(("00", county), 0)
        place_rate = rates.get(("01", place), 0) if place else 0
        district_rate = sum(rates.get(d, 0) for d in districts)
        state = names.state(state_fips)
        combined = file_state_rate + county_rate + place_rate + district_rate
        state_rate = app_state_rates.get(state, file_state_rate)
        local = max(combined - state_rate, 0)
        region = None
        if place and place_rate > 0:
            region = names.place(state_fips, place)
        region = region or (names.county(state_fips, county) if county else None)
        if not region and postal_cities.get(z):
            region = max(postal_cities[z].items(), key=lambda kv: kv[1])[0].title()
        if not region and names.zip_counties(z):
            region = names.county_name(names.zip_counties(z)[0][0])
        out.append({"postalCode": z, "state": state, "region": region or "",
                    "stateRateMillionths": state_rate, "localRateMillionths": local})
    return out
