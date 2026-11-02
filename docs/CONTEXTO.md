# Chirogra: contexto para retomar en otro chat

Resumen del chat de coordinación de Chirogra (desarrollo + QA), al 2 de noviembre de 2026. Léelo antes de seguir. El diseño técnico completo está en [DISEÑO.md](DISEÑO.md); aquí solo va el estado, las decisiones del usuario y cómo se trabaja.

## Estado actual

- **Versión aprobada:** `038b168`. Pasó QA y es la última de `main` en GitHub (github.com/ivanngarcia81/Chirogra).
- **Instalada en:** iPhone 17 Pro Max y Mac (`/Applications/Chirogra.app`) con `038b168`. El **iPad sigue en `68ebad9`** porque la instalación falló con el iPad bloqueado: falta desbloquearlo y reinstalar.
- **Rediseño nativo descartado:** se probó un rediseño con estilo nativo de iOS (commit `7a8b97f`) y el usuario lo descartó. Nunca se subió y el repo volvió a `038b168`.

## Qué se hizo en este chat (de lo más antiguo a lo más nuevo)

| Commit | Qué |
|---|---|
| `430ccf7` | Barra lateral, estados de iCloud, detalles menores |
| `1d3a31d` | Confirmación de borradores |
| `9df80c1`, `9a4990c`, `46c3cfd` | Aviso de «¿Descartar los cambios?» en 12 editores, sin avisos fantasma (token débil por editor + 1,2 s de margen) |
| `68ebad9` | Ícono de la app desde Icon Composer (`App/AppIcon.icon`) |
| `f21e0bf` | Cabecera, botones de la barra y botones primarios en Liquid Glass del sistema, sin morado |
| `752c879` | Columna maestro-detalle en Facturas, Clientes, Gastos, Proveedores, Por pagar, Banca, Asientos y Plan de cuentas (`Shell/MasterDetail.swift`, nuevo `BillDetailView`) |
| `10bf2c5`, `281d573` | Mac: que no parezca un iPhone estirado (densidad de Mac, un solo título, barra lateral de 220 pt, hojas con `.confirmationAction` / `.cancellationAction`, contraste AA de la fila seleccionada) |
| `6bb7a97`, `038b168` | Títulos de la columna maestro visibles en el iPad; «+» solo como ícono en Por pagar y Plan de cuentas |

## Decisiones del usuario (no deshacer sin preguntar)

- **Liquid Glass** en cabecera, barra y botones primarios, en todas las páginas. Nada de botones morados.
- **Maestro-detalle** en las páginas de lista en iPad y Mac, aunque se aparte del canvas de Claude Design.
- **Mac con densidad de Mac**, no de iPhone (objetivos de 28 pt en Mac, 44 pt en iOS: `Metrics.target`).
- **Ícono de la app** = el de Icon Composer. El **logo de la empresa** queda para después.
- **Modo oscuro en Mac:** «salta por ahora esa parte». QA prueba el Mac solo en claro.
- **Rediseño nativo estilo Ajustes/Mail:** descartado.
- Todo esto también está anotado en [DISEÑO.md §7.4](DISEÑO.md).

## Reglas de trabajo

- **Subir a GitHub solo cuando el usuario lo pida.** Subir el commit aprobado explícitamente: `git push origin <hash>:refs/heads/main`, para no subir un commit sin revisar.
- **Instalar en los aparatos** cuando el usuario lo pida (ver abajo).
- Fase 2 queda fuera: OCR, bandeja del banco y conciliación, presupuestos, usuarios y permisos, varias empresas.
- Las claves de Plaid solo irán en un backend futuro (fase 3), nunca en la app.
- Accesibilidad: 44 pt en iOS, Dynamic Type, VoiceOver, contraste AA.
- Bilingüe español/inglés; las fechas numéricas siguen la región del aparato.
- Avisar al usuario antes de borrar cualquier cosa de su computadora. No cambiar ajustes del sistema ni de Xcode.
- El canvas de Claude Design es de solo lectura: https://claude.ai/artifact/Ai344mUq54BECC4Pw4quV9

### Flujo con dos sesiones

1. **Desarrollo** hace un bloque, termina con «SECCIÓN LISTA» y un commit local, sin subir.
2. El coordinador lee el commit (`git show`) y lo pasa a **QA** con los puntos a probar.
3. QA da un veredicto y la ruta de su informe; QA no edita el repo.
4. El coordinador pasa los hallazgos a desarrollo y le informa al usuario en español.

## Compilar e instalar en los aparatos

- Equipo de firma: `4N9XEU7F4P`. Bundle id: `com.chirogra.app`.
- iPhone 17 Pro Max: `00008150-0005793E3EC0401C`
- iPad Pro 12,9″ (5.ª gen.): `00008103-001439A91E6B001E`

Compilar desde un clon limpio del commit aprobado, en una carpeta temporal (`$T`):

```bash
git clone -q ~/Documents/GitHub/Chirogra $T/src && git -C $T/src checkout -q <hash>
```

```bash
cd $T/src && xcodebuild -project Chirogra.xcodeproj -scheme Chirogra -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath $T/dd DEVELOPMENT_TEAM=4N9XEU7F4P -allowProvisioningUpdates build
```

```bash
xcrun devicectl list devices | grep physical
```

```bash
xcrun devicectl device install app --device <UDID> $T/dd/Build/Products/Debug-iphoneos/Chirogra.app
```

Para el Mac, compilar con `-configuration Release -destination 'platform=macOS'` y luego:

```bash
osascript -e 'tell application id "com.chirogra.app" to quit'; rm -rf /Applications/Chirogra.app && ditto $T/dd/Build/Products/Release/Chirogra.app /Applications/Chirogra.app && codesign -v /Applications/Chirogra.app
```

Problemas conocidos: si el aparato sale «desconectado», reintentar. «The developer disk image could not be mounted» = el aparato está bloqueado; desbloquearlo y reintentar.

## Pendiente

- Instalar `038b168` en el iPad (desbloqueado).
- Que el usuario pruebe en el Mac, en **Nuevo gasto** y **Nueva factura**: Escape cierra (o pregunta si hay cambios) y Return guarda o emite. Ni desarrollo ni QA pudieron mandar teclas.
- Sin verificar todavía: iPad en vertical, VoiceOver en iOS, el estado vacío del Mac, modo oscuro del Mac (aplazado por el usuario).
- Logo de la empresa: para después.
- QA no debe tocar el simulador de iPad `BEB1EA39`: ahí corren las pruebas de interfaz de otro proyecto (Tamio).
