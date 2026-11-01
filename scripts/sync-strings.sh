#!/bin/zsh
# Actualiza App/Localizable.xcstrings con los textos que el compilador extrae de la app y de ChirograKit.
# Las vistas viven en el paquete, así que Xcode no sincroniza el catálogo de la app por sí solo.
# Uso: scripts/sync-strings.sh   (luego traduce en Xcode los textos nuevos al inglés)
set -euo pipefail
cd "$(dirname "$0")/.."
derived=build/strings
xcodebuild -project Chirogra.xcodeproj -scheme Chirogra -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO build -quiet
files=()
while IFS= read -r f; do files+=(--stringsdata "$f"); done < <(find "$derived/Build/Intermediates.noindex" -name '*.stringsdata' -path '*arm64*' ! -name 'ExtractedAppShortcuts*')
xcrun xcstringstool sync App/Localizable.xcstrings "${files[@]}"
echo "Catálogo sincronizado. Las pruebas de ChirograUITests avisan de los textos sin traducir."
