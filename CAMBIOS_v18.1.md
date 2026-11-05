# v18.1 — Objetos en el roguelike y 2 mundos de Historia

## Roguelike con objetos
- Tras cada victoria, cada una de las 3 opciones puede ser un **objeto equipable** (34 % por opción, rareza ponderada; `item_choices` en `data/modes/roguelike.json`) en vez de una mejora. Se elige a qué personaje vivo se le da.
- Son **temporales**: valen solo en esa partida (sustituyen al objeto guardado durante los combates), no entran en tu inventario, no cambian lo equipado y desaparecen al terminar. Se guardan con la partida y las opciones siguen siendo deterministas por semilla.

## Historia: 2 mundos nuevos (jugables, 4 niveles x 3 dificultades)
- **Chainsaw Man** (Denji, Makima, Reze; ya tienes los 3). Se abre al superar 3 niveles de Black Clover. Jefe final: Makima (2 fases).
- **Las Quintillizas** (Miku, Nino, Itsuki; ya tienes las 3). Se abre al superar los 4 niveles de Chainsaw Man. Jefe final: Itsuki (2 fases).
- Enemigos nuevos con `based_on` (`story_reze`, `story_makima`, `story_nino`, `story_miku`, `story_itsuki`) y un diálogo de entrada por mundo.
- Pruebas: `--dbg30` ampliada a 202 comprobaciones; resto de suites en verde.
