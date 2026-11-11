"""Lector mínimo de .xlsx (solo la biblioteca estándar): filas de la primera hoja como listas de textos."""
import re
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

_NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


def _column(ref: str) -> int:
    letters = re.match(r"[A-Z]+", ref).group(0)
    n = 0
    for ch in letters:
        n = n * 26 + ord(ch) - 64
    return n - 1


def rows(path: Path, sheet: int = 1) -> list:
    with zipfile.ZipFile(path) as z:
        shared = []
        if "xl/sharedStrings.xml" in z.namelist():
            for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", _NS):
                shared.append("".join(t.text or "" for t in si.iter(f"{{{_NS['m']}}}t")))
        sheet_xml = ET.fromstring(z.read(f"xl/worksheets/sheet{sheet}.xml"))
    out = []
    for row in sheet_xml.iter(f"{{{_NS['m']}}}row"):
        values = []
        for cell in row.findall("m:c", _NS):
            index = _column(cell.get("r"))
            while len(values) < index:
                values.append("")
            v = cell.find("m:v", _NS)
            text = v.text if v is not None else ""
            if cell.get("t") == "s" and text:
                text = shared[int(text)]
            elif cell.get("t") == "inlineStr":
                text = "".join(t.text or "" for t in cell.iter(f"{{{_NS['m']}}}t"))
            values.append((text or "").strip())
        out.append(values)
    return out
