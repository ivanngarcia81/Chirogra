#!/bin/zsh
# Pruebas de interfaz (UITests/, objetivo PruebasInterfaz): flujos de verdad en el simulador del iPhone con los datos de
# ejemplo (cobrar, anular un cobro, emitir una factura, base caja en Reportes). Unos minutos.
#
# Uso: scripts/interfaz.sh           (el iPhone disponible con el iOS más nuevo)
#      scripts/interfaz.sh <UDID>    (un simulador concreto)
set -euo pipefail
cd "$(dirname "$0")/.."

udid=${1:-$(xcrun simctl list devices available -j | python3 -I -c '
import json, re, sys
runtimes = json.load(sys.stdin)["devices"]
# «com.apple.CoreSimulator.SimRuntime.iOS-27-0» (en las máquinas de GitHub puede llevar más detrás).
def version(runtime):
    found = re.search(r"\.iOS-(\d+)-(\d+)", runtime)
    return tuple(int(x) for x in found.groups()) if found else (0, 0)
ios = sorted((r for r in runtimes if ".iOS-" in r), key=version, reverse=True)
for runtime in ios:
    phones = [d for d in runtimes[runtime] if d["name"].startswith("iPhone")]
    if phones:
        print(phones[0]["udid"]); break
')}
[[ -n "$udid" ]] || { echo "No hay ningún simulador de iPhone disponible."; exit 1; }
echo "▸ Pruebas de interfaz en $(xcrun simctl list devices | grep "$udid" | sed 's/^ *//')"
# Una prueba que falla se repite (hasta 3 veces): en las máquinas de GitHub el simulador a veces no arranca la app a
# la primera («does not have a process ID»). Un fallo de verdad falla las tres.
set +e
xcodebuild test -project Chirogra.xcodeproj -scheme Chirogra -destination "id=$udid" -derivedDataPath build/interfaz \
  -only-testing:PruebasInterfaz -retry-tests-on-failure -test-iterations 3 CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E "Test Case .*(passed|failed)|error:|\*\* TEST"
estado=${pipestatus[1]}
set -e
exit $estado
