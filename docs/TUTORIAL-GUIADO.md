# Tutorial de seguir («Aprende haciendo»), 1.4

Pedido del usuario del 26-nov: «en vez de poner por escrito lo que hay que hacer, uno sigue las instrucciones: si dice
presione aquí, va y presiona». Rama `tutorial-seguir` (desde `version-1.4` en `7f3d0e4`, build 68), para no chocar con
el otro chat que trabajaba en el asistente.

## Qué hace

- Sale **una vez, al crear su propia empresa** (`OnboardingView.createCompany` → `Recorrido.pedirGuiado()`; no al añadir
  otra empresa del contador ni con los datos de ejemplo). Empieza en Inicio con «Aprende haciendo» (Empezar / Ahora no).
- La persona **hace de verdad** lo más importante, y lo que crea se queda en sus libros:
  1. **Cliente:** toca la fila de «Primeros pasos», escribe el nombre («Siguiente» se enciende al escribirlo), «Guardar».
  2. **Factura:** la fila, elige el cliente, escribe qué vendió y el precio, ve el sales tax, «Emitir».
  3. **Gasto:** la fila, el monto, «Pagado a», la categoría (las tres las exige la app para guardar), «Guardar».
  4. **Impuestos:** el apartado para el IRS (tarjeta en iPhone y Mac, fila de la columna en el iPad) y lo que toca
     apartar; si no sale (S/C-corp), el sales tax («Configura tu sales tax» → lo que le debes al estado).
  5. **Despedida:** «Terminar», la guía de chirogra.com y, en el iPhone, «Encender el tutorial completo».
- Lo demás sigue igual: el recorrido corto de cada pestaña al abrirla, el tutorial completo en Más › Ayuda y la guía.
- **Repetirlo:** «Aprende haciendo» en Más › Ayuda (iPhone) y en Ajustes (iPad y Mac). Lo ya hecho se toca con los
  botones rápidos de Inicio (Factura, Gasto, Cliente) si su fila de «Primeros pasos» ya no está.

## Cómo está hecho

Sobre el recorrido de la primera vez (`DesignSystem/Recorrido.swift`, mismo velo, anillo y tarjeta); los pasos en
`DesignSystem/RecorridoGuiado.swift` (`RecorridoID.guiado`).

- **Lo iluminado se toca:** en la pantalla el velo deja pasar el toque solo por el hueco; en las hojas no detiene nada
  (hay que escribir, abrir menús y tocar «Guardar» de la barra, que es UIKit y se busca con `ax:`).
- **Cada paso espera algo** (`Paso.espera`): `.aparece(id)` (se abrió la pantalla que trae ese objetivo),
  `.evento(id)` (`Recorrido.ocurrio`: `cliente.guardado`, `factura.cliente`, `factura.emitida`, `gasto.guardado`) o
  `.listo(id)` («Siguiente» se enciende con `recorridoCumple`). Si la persona se adelanta (guarda sin tocar
  «Siguiente»), el tutorial salta a lo que sigue.
- **Grupos:** si el primer paso de un grupo no está (ya hay cliente), se salta el grupo; un paso de Inicio espera a que
  se cierren las hojas abiertas («Factura emitida», enviar). Si cancela un editor, vuelve al primer paso del grupo.
- **Objetivos con alternativas** separadas por «|» (la fila o el botón rápido; «Emitir» de la barra de abajo del
  iPhone o «Emitir factura» de la hoja ancha).
- El teclado se cierra en los pasos que no piden escribir (`Paso.escribe`), y la tarjeta y el desplazamiento cuentan con
  él. En los pasos que piden hacer algo la tarjeta no es modal para VoiceOver (si no, la fila no se alcanzaba).
- El Mac ahora monta el `Recorrido` solo para esto (no tiene recorrido por secciones).
- Mientras un paso de Inicio espera a que se cierren las hojas, no se dibuja nada (`esperandoHojas`): si no, la hoja de
  enviar que se abre al emitir («Send» en vez de «Not now») quedaba gris, sin tarjeta (lo vio el usuario en el Mac,
  26-nov). La prueba pulsa ahora «Enviar a …» y luego «Cancelar».
- Arreglo de paso: con el mismo objetivo en dos sitios (la fila de la primera vez y la del tablero), la vista que se
  iba borraba el marco de la nueva (`RecorridoObjetivo.ultimo`).

## Comprobado

- **iPhone y iPad (simulador, iOS 27):** `TutorialGuiadoTests` (en `UITests/FlujosTests.swift`) recorre todo tocando
  como una persona y pasa en los dos; con `TEST_RUNNER_CAPTURAS=<carpeta>` guarda una captura de cada paso.
- **Mac:** copia de prueba (`com.chirogra.qa.tutorial`) hasta «Escribe su nombre» (presentación, fila iluminada, hoja del
  cliente con su campo); más allá no se puede escribir sin tomar el teclado del usuario.
- **En sus aparatos (26-nov):** copia «Chirogra Prueba» Debug sin iCloud en su iPhone (`com.chirogra.qa.bienvenida`) y
  en el Mac (`~/Applications`, `com.chirogra.qa.tutorial`, firma ad hoc), compiladas desde una copia en el scratchpad
  con `resolveSyncPreference` → `false` y `CFBundleDisplayName` «Chirogra Prueba».
- QA a mano: `-iCloudSyncEnabled NO -qa.alta 1 -qa.altaCrear 1 -qa.altaEstado TX -qa.recorrido guiado`.

## Pendiente

- Que el usuario lo vea en su aparato y decida textos y orden.
- Mac: «Guardar» y «Emitir factura» de la barra de la hoja no se iluminan (son AppKit; la tarjeta lo dice en el texto).
- Unir `tutorial-seguir` a `version-1.4` cuando el otro chat termine (el catálogo se une con `scripts/merge-xcstrings.py`
  si choca) y apuntarlo en RESUMEN/CONTEXTO.
