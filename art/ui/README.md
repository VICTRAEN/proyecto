# Iconos y logotipo de la interfaz (PROVISIONALES)

Todo lo de esta carpeta esta **generado por codigo** como arte provisional de la
identidad visual premium (semi-3D: volumen, brillo y sombra). **No es arte final**:
sustituyelo metiendo un PNG con el mismo nombre; ningun script cambia.

- `logo.png` (900x280): logotipo "ANIME BATTLE" (`tools/gen_logo.py`). Si falta, el
  menu usa el titulo de texto de siempre.
- `icons/<nombre>.png` (256x256, fondo transparente) (`tools/gen_icons.py`):
  `coin`, `gem`, `crystal`, `summon`, `team`, `collection`, `missions`, `history`,
  `events`, `tower`, `evolution`, `inventory`, `mutations`, `shop`, `settings`,
  `play`, `lock`, `check`, `mai_token`, `rabbit_costume`.

`mai_token` y `rabbit_costume` solo se usan como icono de objeto cuando el objeto
no tiene su PNG propio en `res://art/items/<id>.png` (ese siempre manda).
Si falta un icono, la pantalla se dibuja sin el: nada falla.

Regenerar: `python3 tools/gen_icons.py` y `python3 tools/gen_logo.py`, y despues
`godot --headless --path . --import`.
