# Fondos de pantalla (reemplazables)

## Lo unico que tienes que hacer

1. Mira el nombre que pide la pantalla en la tabla de abajo.
2. Mete un PNG con **ese nombre exacto** en `res://art/backgrounds/`.
3. Abre el juego.

**No hay que editar ningun script ni ningun JSON.** El juego busca la imagen por
su nombre cada vez que abre la pantalla.

## ARTE PROVISIONAL (rediseno artistico global)

Los `.webp` que hay en esta carpeta (menu, collection, summon, team, stages,
battle, battle_forest, battle_ruins, results, missions, events, history, map,
inventory, mutation, shop, tower, evolution, settings) son **fondos provisionales
generados por codigo** (`tools/gen_backgrounds.py`, 1080x1920): ciudades
futuristas al atardecer, cielos violeta/magenta, portal magico, etc. **No son arte
final.** Para sustituir uno basta meter un `.png` con el mismo nombre: **el `.png`
gana al `.webp`** y no se toca ningun script. Para regenerarlos todos:
`python3 tools/gen_backgrounds.py` (necesita numpy, scipy y Pillow).

## Nombres de archivo

| Archivo | Pantalla donde se ve |
|---|---|
| `menu.png` | Menu principal |
| `collection.png` | Coleccion |
| `team.png` | Equipo |
| `stages.png` | Seleccionar batalla |
| `battle.png` | Combate |
| `results.png` | Resultado del combate |
| `missions.png` | Misiones |
| `history.png` | Historia (lista de mundos) |
| `map.png` | Mapa de un mundo |
| `events.png` | Eventos |
| `inventory.png` | Mochila |
| `mutation.png` | Mutaciones |
| `summon.png` | Invocar (portal) |
| `shop.png` | Tienda |
| `tower.png` | Torre |
| `evolution.png` | Evolucion |
| `settings.png` | Ajustes |

Tambien valen `.jpg` y `.webp`. Si existen dos, gana el `.png`.

## Escenarios distintos por batalla

Cada batalla puede pedir su propio escenario con el campo `background` de su JSON
(`res://data/stages/<id>.json`):

```json
"background": "battle_plain"
```

Ese nombre es el del archivo: si metes `res://art/backgrounds/battle_plain.png`,
esa batalla pasa a usar esa imagen. **No hay que tocar ningun script.**

Ahora mismo hay tres preparados, uno por batalla: `battle_plain`, `battle_forest`
y `battle_ruins`. Mientras no exista el PNG, cada uno dibuja su escenario
provisional (llanura, bosque y ruinas), asi que las batallas ya se distinguen
entre si sin arte real.

## Como se coloca la imagen

El juego la **escala para cubrir toda la pantalla sin deformarla**: recorta el
sobrante por el lado que sobra. Asi que no importa que la proporcion no sea
exacta.

- Formato recomendado: **vertical**, unos **1080x1920 px** (movil) o **1440x2560**.
- Horizontal tambien funciona, pero se recortara bastante por los lados.
- Encima se pinta un **oscurecido** y un degradado en la parte de abajo, para que
  los botones y los paneles se lean siempre.

## Ajustar el oscurecido

El nodo `Background` de cada pantalla tiene una propiedad `scrim`:

- `0.0` = sin oscurecer (fondo muy visible, texto mas dificil de leer).
- `0.20` = valor por defecto (el fondo se ve; los paneles ya oscurecen lo justo).
- `0.7` = fondo casi decorativo.

Se cambia desde el inspector, escena por escena.

## Si falta una imagen

El juego dibuja un **fondo provisional por codigo**: un cielo con su punto de luz
y unas siluetas de terreno, con el tono propio de esa pantalla. **No hay error ni
pantalla negra.** Puedes ir metiendo los fondos poco a poco: cada uno que dejes
aparece solo.

## Anadir un fondo para una pantalla nueva

1. Elige un nombre corto en minusculas, por ejemplo `arena`.
2. En la escena, pon ese nombre en la propiedad `slot` del nodo `Background`.
3. Mete `res://art/backgrounds/arena.png`.

Si quieres que su fondo provisional tenga buen tono antes de tener arte, anade
una entrada con ese nombre al diccionario `PALETTES` de `res://ui/background.gd`.
Es una linea de colores, no hace falta nada mas.
