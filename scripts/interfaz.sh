#!/bin/zsh
# Pruebas de interfaz (UITests/, objetivo PruebasInterfaz): flujos de verdad en el simulador del iPhone con los datos de
# ejemplo (cobrar, anular un cobro, emitir una factura, base caja en Reportes). Unos minutos.
#
# Uso: scripts/interfaz.sh           (el iPhone disponible con el iOS más nuevo)
#      scripts/interfaz.sh <UDID>    (un simulador concreto)
set -euo pipefail
cd "$(dirname "$0")/.."

udid=${1:-$(xcrun simctl list devices available -j | python3 -I -c '
import json, sys
runtimes = json.load(sys.stdin)["devices"]
ios = sorted((r for r in runtimes if ".iOS-" in r), key=lambda r: [int(x) for x in r.split(".iOS-")[1].split("-")], reverse=True)
for runtime in ios:
    phones = [d for d in runtimes[runtime] if d["name"].startswith("iPhone")]
    if phones:
        print(phones[0]["udid"]); break
')}
[[ -n "$udid" ]] || { echo "No hay ningún simulador de iPhone disponible."; exit 1; }
echo "▸ Pruebas de interfaz en $(xcrun simctl list devices | grep "$udid" | sed 's/^ *//')"
xcodebuild test -project Chirogra.xcodeproj -scheme Chirogra -destination "id=$udid" -derivedDataPath build/interfaz \
  -only-testing:PruebasInterfaz CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E "Test Case .*(passed|failed)|error:|\*\* TEST" || true
# `grep` se come el código de salida de xcodebuild: se mira el resultado.
[[ ${pipestatus[1]} -eq 0 ]]
