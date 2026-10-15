# DEVELOPER TOOLS - TEMPORAL

Panel de pruebas para el desarrollador (recursos y personajes). **No es una funcion del
juego**: es temporal y esta aislado en esta carpeta.

## Archivos

| Archivo | Que es |
|---|---|
| `dev/dev_tools.gd` | Logica. Todas las acciones comprueban `enabled()` antes de tocar nada. |
| `dev/dev_tools_panel.gd` | Interfaz del panel (seccion `DEVELOPER TOOLS - TEMPORAL` de Ajustes). |
| `dev/README.md` | Este documento. |
| `scenes/screens/settings.gd` | UNA linea (marcada `DEV TOOLS`) que monta el panel si `enabled()`. |

## Cuando esta disponible

Solo si se cumplen las dos condiciones:

1. `OS.is_debug_build()` es verdadero (ejecutando desde el editor o con una exportacion
   de **depuracion**). En una exportacion **release** (distribucion) es falso: no se crea
   el panel ni se ejecuta ninguna accion (las acciones devuelven `ok:false`).
2. `MASTER_SWITCH` de `dev/dev_tools.gd` es `true`.

## Como desactivarlo / eliminarlo

- Desactivar: pon `const MASTER_SWITCH := false` en `dev/dev_tools.gd`.
- Eliminar: borra la carpeta `dev/` y la linea `DEV TOOLS` de `scenes/screens/settings.gd`.
- Para distribuir: exporta con el preset **Release** (sin "Export With Debug") y, por
  seguridad, pon `MASTER_SWITCH := false` o borra `dev/` antes de generar la build final.

## Que puede hacer

- Sumar monedas, gemas, materiales de evolucion y objetos del inventario (uniformes de
  conejita, fichas doradas de Mai...) con botones rapidos o una cantidad propia.
  Solo existen los recursos reales del juego; no hay tickets ni una segunda moneda.
- Anadir un personaje por ID (si ya lo tienes no lo duplica) y anadir
  `david_lucy_duo` (SSR) con un boton.
- Usa `GameState.add_coins/add_gems/add_materials/add_item/add_character` y el guardado
  normal. No toca probabilidades del gacha ni estadisticas.

## Verificacion

Ver los checks `DBG19` de `scenes/debug/hito_e_checks.gd`. Una exportacion release real
no se ha podido probar en este entorno (no hay plantillas de exportacion): se simula con
`DevTools.simulate_release(true)`.
