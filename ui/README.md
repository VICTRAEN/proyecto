# Identidad visual del juego

Guia corta para que todas las pantallas parezcan del mismo juego. Si algo de
aqui se cambia, se cambia **en un solo sitio** y aparece en todo el juego:
`res://ui/visual_identity.gd`.

## La regla

**Ningun color suelto en una pantalla.** Si hace falta un color nuevo, se anade a
`visual_identity.gd` con un nombre que diga para que sirve. Los colores de tipo
(STR, AGL, INT, TEQ, PHY) son la excepcion y viven en `res://ui/type_colors.gd`,
que es su unica fuente.

## Colores

| Token | Uso |
|---|---|
| `BG` | Fondo base del juego |
| `PANEL` | Panel normal, semitransparente para que se intuya el fondo |
| `PANEL_STRONG` | Panel solido: fichas, dialogos, resultado |
| `GOLD` | Lo importante: titulos, turno activo, subir de nivel, premios |
| `BLUE` | Accion normal: botones, barras de informacion |
| `GREEN` / `RED` / `VIOLET` | Confirmar, peligro, efectos |
| `INK` / `INK_SOFT` / `INK_DIM` | Texto principal, secundario y de aviso |

## Texto

| Tamano | Uso |
|---|---|
| `FONT_TITLE` (62) | Titulo de portada |
| `FONT_BIG` (40) | Titulo de pantalla |
| `FONT_SECTION` (30) | Subtitulo de seccion |
| `FONT_BODY` (24) | Texto normal |
| `FONT_SMALL` (20) | Texto de apoyo |
| `FONT_TINY` (17) | Avisos, notas, contadores |

Un titulo de pantalla se pinta con `VisualIdentity.style_title(label)`; el texto
de apoyo con `style_subtitle(label)`; los avisos con `style_note(label)`.

## Formas y tacto

- `RADIUS_PANEL` (22) en paneles y botones; `RADIUS_CARD` (18) en cartas;
  `RADIUS_CHIP` (12) en etiquetas pequenas.
- `TOUCH` (104) es la altura minima de un boton. El juego es **movil vertical**:
  nada importante por debajo de esa altura.

## Botones

`VisualIdentity.tint_button(button, color)` da a un boton el acento que toque
(dorado para la accion principal, azul para las demas, verde para lo disponible).
El estilo normal, el hover y el pulsado salen de ahi, asi que un boton nunca se
queda con el color de otra pantalla.

## Cartas

`VisualIdentity.card(tint, selected, rarity, strong)`:

- `tint` es el color del **tipo** del personaje (`TypeColors.color_for`).
- `selected = true` la pinta en dorado (es la que estas eligiendo).
- `rarity` anade el **brillo** de la rareza.

## Rarezas

| Rareza | Color | Brillo |
|---|---|---|
| R | Gris azulado | Ninguno |
| SR | Azul | Suave |
| SSR | Dorado | Medio |
| UR | Rosa | Fuerte |

Una rareza nueva es **una linea** en el diccionario `RARITY` de
`visual_identity.gd`: aparece sola en las cartas, en la coleccion y en el
combate. Las pantallas preguntan el color con `VisualIdentity.rarity_color()` y
el brillo con `rarity_glow()`.

## Fondos

Cada pantalla tiene un fondo **reemplazable**: un nodo `Background` con su
propiedad `slot`. Basta con meter `res://art/backgrounds/<slot>.png`. Ver
`res://art/backgrounds/README.md`.

## Sonido

Los botones suenan solos y la musica se pide con `GameAudio.play_music("menu")`.
Ver `res://audio/README.md`.

## Arte de personajes

Tres PNG por personaje en `res://art/characters/<id>/`: `front.png`, `back.png`
e `icon.png`. Ver `res://art/README.md`.

## Anadir una pantalla nueva

1. Reescala el fondo de la escena: nodo `Background` con `script =
   background.gd` y su `slot`.
2. El titulo con `VisualIdentity.style_title`.
3. Los botones con `VisualIdentity.tint_button`.
4. Nada de colores escritos a mano en la escena.

## Lo que NO se pinta nunca

El **rol** de un personaje (Damage Dealer, Tank, Support, Healer, Utility) es un
dato interno de diseno para balancear. Vive en el JSON y **no aparece en ninguna
pantalla del jugador**.
