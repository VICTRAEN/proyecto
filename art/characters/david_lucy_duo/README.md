# David Martinez & Lucy (`david_lucy_duo`) - arte

El duo **aun no tiene retratos propios**. Mientras falten, el juego los compone provisionalmente
con el arte de David y Lucy individuales (`art_fallback_ids` en su JSON) y lo marca como provisional;
no se afirma que exista arte nuevo. Los PNG de David y Lucy NO se tocan.

Rutas exactas donde poner el arte definitivo (el resolver por ID las busca en este orden: forma
y luego base):

| Forma | front | back | icon |
|---|---|---|---|
| SSR | `res://art/characters/david_lucy_duo/ssr/front.png` | `.../ssr/back.png` | `.../ssr/icon.png` |
| UR  | `res://art/characters/david_lucy_duo/ur/front.png`  | `.../ur/back.png`  | `.../ur/icon.png` |
| LR  | `res://art/characters/david_lucy_duo/lr/front.png`  | `.../lr/back.png`  | `.../lr/icon.png` |
| Base (cualquier forma sin arte propio) | `res://art/characters/david_lucy_duo/front.png` | `back.png` | `icon.png` |

Cualquier forma sin PNG cae a la base, y esta al arte provisional de David + Lucy.
