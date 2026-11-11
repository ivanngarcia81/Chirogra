"""Nombres de condados y lugares (ciudades) por código FIPS, de los archivos «Gazetteer» del Census (dominio público)."""
import re
from pathlib import Path

# Sufijos del Census que no van en el nombre que ve el usuario («Wichita city» → «Wichita»).
_PLACE_SUFFIX = re.compile(r"\s+(city|town|village|borough|CDP|municipality|city and borough|consolidated government"
                           r"|metropolitan government|unified government|urban county|plantation)(\s*\(.*\))?$",
                           re.IGNORECASE)


class Names:
    def __init__(self, gazetteer_dir: Path):
        self._counties, self._places, self._states, self._cdps = {}, {}, {}, set()
        for line in (gazetteer_dir / "2024_Gaz_counties_national.txt").read_text(encoding="utf-8").splitlines()[1:]:
            f = line.split("\t")
            self._counties[f[1].strip()] = f[3].strip()
            self._states[f[1].strip()[:2]] = f[0].strip()
        for line in (gazetteer_dir / "2024_Gaz_place_national.txt").read_text(encoding="utf-8").splitlines()[1:]:
            f = line.split("\t")
            self._places[f[1].strip()] = _PLACE_SUFFIX.sub("", f[3].strip())
            if f[3].strip().endswith(" CDP"):
                # Lugar censal sin gobierno propio: no cobra impuesto de ciudad.
                self._cdps.add(f[1].strip())
        self._zip_counties = self._relationship(gazetteer_dir / "tab20_zcta520_county20_natl.txt")
        self._zip_places = self._relationship(gazetteer_dir / "tab20_zcta520_place20_natl.txt")

    @staticmethod
    def _relationship(path: Path) -> dict:
        """ZIP (ZCTA) → [(GEOID, superficie de tierra compartida)], de mayor a menor (archivos de relación del Census
        2020)."""
        out = {}
        if not path.exists():
            return out
        for line in path.read_text(encoding="utf-8-sig").splitlines()[1:]:
            f = line.split("|")
            if len(f) < 18 or not f[1]:
                continue
            out.setdefault(f[1], []).append((f[9], int(f[16] or 0)))
        for parts in out.values():
            parts.sort(key=lambda p: -p[1])
        return out

    def zip_counties(self, zip_code: str) -> list:
        """[(GEOID de 5 dígitos del condado, fracción de la superficie del ZIP)] de mayor a menor."""
        return self._fractions(self._zip_counties.get(zip_code, []))

    def zip_places(self, zip_code: str) -> list:
        """[(GEOID de 7 dígitos del lugar, fracción de la superficie del ZIP)] de mayor a menor."""
        return self._fractions(self._zip_places.get(zip_code, []))

    def all_zips(self, state_fips: str) -> list:
        """Los ZIP (ZCTA) que tienen la mayor parte de su superficie en el estado."""
        return sorted(z for z, parts in self._zip_counties.items() if parts and parts[0][0][:2] == state_fips)

    def _fractions(self, parts: list) -> list:
        total = sum(area for _, area in parts) or 1
        return [(geoid, area / total) for geoid, area in parts]

    def county_name(self, geoid: str):
        return self._counties.get(geoid)

    def is_city(self, geoid: str) -> bool:
        """Lugar con gobierno propio (ciudad, pueblo, villa); los «CDP» del Census no lo son."""
        return geoid in self._places and geoid not in self._cdps

    def place_name(self, geoid: str):
        return self._places.get(geoid)

    def state_fips(self, abbreviation: str) -> str:
        return next((fips for fips, abbr in self._states.items() if abbr == abbreviation), "")

    def state(self, fips: str) -> str:
        return self._states.get(fips, fips)

    def county(self, state_fips: str, county_fips: str):
        return self._counties.get(f"{state_fips}{county_fips}")

    def place(self, state_fips: str, place_fips: str):
        return self._places.get(f"{state_fips}{place_fips}")
