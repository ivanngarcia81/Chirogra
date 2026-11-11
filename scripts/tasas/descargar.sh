#!/bin/zsh
# Descarga los archivos oficiales para la tabla de sales tax por ZIP (docs/DATOS-V5.md, «Pendiente para la 1.2»).
# Uso: scripts/tasas/descargar.sh <carpeta>   y luego   python3 -I scripts/tasas/generar.py --datos <carpeta> --salida …
# Cada trimestre cambian los nombres de algunos archivos (llevan la fecha): este programa los busca en las páginas.
set -euo pipefail
D=${1:?Uso: descargar.sh <carpeta>}
AQUI=${0:A:h}
UA="Mozilla/5.0 (Chirogra; tabla de tasas)"
mkdir -p $D/sst $D/census $D/tx $D/ca $D/il $D/fl $D/ny

baja() { curl -sfL -A "$UA" -o "$2" "$1" || { echo "No se pudo descargar $1" >&2; exit 1 }; }

# Streamlined Sales Tax: los archivos de tasas (R) y de límites (B) de cada estado miembro.
SST=https://www.streamlinedsalestax.org
for pagina in "state's-rate-files" state-boundary-files; do
  curl -sfL -A "$UA" "$SST/for-businesses/rate-and-boundary-files/$pagina" \
    | grep -oiE 'href="/ratesandboundry/(Rates|Boundary)/[^"]+"' | sed -E 's/^href="//I; s/"$//'
done | sort -u | while read -r ruta; do
  f=$D/sst/${ruta:t}
  [[ -s $f ]] || baja "$SST$ruta" "$f"
done

# Census: nombres (Gazetteer) y relación ZIP–condado y ZIP–lugar (2020).
G=https://www2.census.gov/geo/docs/maps-data/data
for f in 2024_Gaz_counties_national 2024_Gaz_place_national; do
  [[ -s $D/census/$f.txt ]] || { baja "$G/gazetteer/2024_Gazetteer/$f.zip" $D/census/$f.zip && unzip -o -q $D/census/$f.zip -d $D/census }
done
for f in tab20_zcta520_county20_natl tab20_zcta520_place20_natl; do
  [[ -s $D/census/$f.txt ]] || baja "$G/rel2020/zcta520/$f.txt" $D/census/$f.txt
done

# Texas: tasas por ciudad del Comptroller.
baja https://comptroller.texas.gov/taxes/sales/docs/city-rates.xlsx $D/tx/city-rates.xlsx

# California: el Excel del CDTFA (el nombre lleva la fecha: «SalesTaxRates10-1-26.xlsx»).
CA=$(curl -sfL -A "$UA" https://www.cdtfa.ca.gov/taxes-and-fees/sales-use-tax-rates.htm \
  | grep -oE 'href="/taxes-and-fees/SalesTaxRates[^"]*\.xlsx"' | head -1 | sed -E 's/^href="//; s/"$//')
baja "https://www.cdtfa.ca.gov$CA" $D/ca/SalesTaxRates.xlsx

# Illinois: tasas por municipio y condado, y el archivo por dirección (para las ciudades con tasa por dirección).
IL=https://tax.illinois.gov/content/dam/soi/en/web/tax/research/taxrates/documents/salestaxrates
baja $IL/ordmache-current.txt $D/il/ordmache-current.txt
baja $IL/ordmacha-current.txt $D/il/ordmacha-current.txt

# Florida: DR-15DSS del año (si aún no está el del año, el del anterior), pasado a texto.
ANIO=$(date +%y)
curl -sfL -A "$UA" -o $D/fl/dr15dss.pdf "https://floridarevenue.com/Forms_library/current/dr15dss_$ANIO.pdf" \
  || baja https://floridarevenue.com/Forms_library/current/dr15dss.pdf $D/fl/dr15dss.pdf
swift $AQUI/pdf_texto.swift $D/fl/dr15dss.pdf > $D/fl/dr15dss.txt

# New York: Publication 718, pasada a texto.
baja https://www.tax.ny.gov/pdf/publications/sales/pub718.pdf $D/ny/pub718.pdf
swift $AQUI/pdf_texto.swift $D/ny/pub718.pdf > $D/ny/pub718.txt

echo "Descargado en $D"
