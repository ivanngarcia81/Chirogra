"""Tasas por ZIP para los estados que publican sus tasas por ciudad y condado, sin límites por ZIP (Texas, California,
New York, Illinois, Florida), con los archivos de relación ZIP–lugar y ZIP–condado del Census 2020.

Cada ZIP mira solo la parte de su superficie que cae en algún lugar habitado (ciudades y «CDP»): si el mayor de esos
lugares es una ciudad, toma su tasa; si es un CDP (zona sin gobierno propio) o no hay ninguno, la del condado. Así, en
un ZIP de Ventura rodeado de montaña, la ciudad cuenta aunque ocupe poco. Es aproximado: la app lo dice («aproximada:
compruébala con tu estado»)."""
import re
import unicodedata


def normalized(name: str) -> str:
    """«St. Louis» y «Saint Louis», «Cañon City» y «Canon City»: misma clave."""
    text = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode().lower()
    text = re.sub(r"^(city|town|village) of ", "", text.strip())
    text = re.sub(r"\bsaint\b", "st", text)
    text = re.sub(r"\b(city|town|village|borough|county|co)\b", "", text)
    return re.sub(r"[^a-z0-9]", "", text)


def zip_rates(state: str, names, state_rate: int, city_rate, county_rate) -> list:
    """`city_rate(ciudad, condado)` y `county_rate(condado)` dan la tasa local en millonésimas (o `None` si no la saben).
    Los nombres que reciben son los del Census, sin «city» ni «County»."""
    fips = names.state_fips(state)
    out = []
    for z in names.all_zips(fips):
        counties = names.zip_counties(z)
        county = names.county_name(counties[0][0]) if counties else None
        county_short = re.sub(r"\s+(County|Parish|Borough|city)$", "", county or "")
        places = [(g, share) for g, share in names.zip_places(z) if g[:2] == fips and names.place_name(g)]
        local, region = None, None
        if places and names.is_city(places[0][0]):
            city = names.place_name(places[0][0])
            # «El Paso de Robles (Paso Robles)», «San Buenaventura (Ventura)»: el nombre de uso va entre paréntesis.
            short = re.search(r"\((.+)\)", city)
            for candidate in ([short.group(1)] if short else []) + [re.sub(r"\s*\(.*\)", "", city)]:
                local = city_rate(candidate, county_short)
                if local is not None:
                    region = candidate
                    break
        if local is None and county:
            local = county_rate(county_short)
            region = county
        if local is None:
            continue
        out.append({"postalCode": z, "state": state, "region": region or "", "stateRateMillionths": state_rate,
                    "localRateMillionths": max(local, 0)})
    return out
