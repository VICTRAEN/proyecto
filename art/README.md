# Arte de personajes (ASSET GUIDE)

## Lo unico que tienes que hacer

1. Abre la carpeta del personaje: `res://art/characters/<id>/`
2. Mete dentro **tres PNG**: `front.png`, `back.png`, `icon.png`
3. Ejecuta el juego.

Ya esta. **No hay que editar ningun JSON, ni ningun script, ni ninguna ruta.**
El juego busca esos tres archivos por su nombre y los usa solo.

## Que es cada imagen

| Archivo | Que es | Donde se ve |
|---|---|---|
| `front.png` | El personaje **de frente** | Cuando esa unidad es el **rival** |
| `back.png` | El personaje **de espaldas** | Cuando esa unidad es del **jugador** en combate |
| `icon.png` | Retrato de la **cara** | Coleccion, equipo, orden de ataque y ficha |

## Las carpetas ya estan creadas

Todas las carpetas existen y llevan dentro un `_pon_tus_imagenes_aqui.txt` que
puedes borrar (o dejar, no molesta). Solo tienes que arrastrar los PNG.

```
res://art/characters/
	gojo/       isagi/      frieren/    mai/        asta/
	yuno/       yami/       goku/       vegeta/     deku/
	lucy/       david/      denji/      makima/     reze/
	maomao/     senku/      hinata/     kageyama/   marin/
	itadori/    sukuna/     tanjiro/    akaza/      subaru/
	miku/       nino/       itsuki/
```

Cada carpeta es un personaje. El nombre de la carpeta es el `id` del personaje.

## Si falta una imagen

El juego dibuja una silueta del color del tipo. **No hay error ni pantalla
rota.** La coleccion y el equipo avisan con "sin icono".

Puedes ir metiendo las imagenes poco a poco: cada una que dejes aparece sola.

## Formato recomendado

| Archivo | Tamano | Formato |
|---|---|---|
| `front.png` / `back.png` | Vertical, unos 1024x1536 px | PNG con fondo transparente |
| `icon.png` | Cuadrado, 512x512 px | PNG con fondo transparente |

Recomendaciones:

- **PNG con transparencia, no JPG.** El fondo tiene que ser transparente.
- Vertical para `front` y `back`: el personaje de cuerpo entero.
- Cuadrado para `icon`: cara y hombros.
- No hace falta que todos midan lo mismo.

## El juego encuadra las imagenes solo

**No tienes que recortar nada.** El juego:

- busca la parte visible de la imagen y **ignora el espacio transparente** de
  alrededor;
- **centra** al personaje;
- lo **escala sin deformarlo**, manteniendo su proporcion;
- lo deja lo mas grande posible dentro de su hueco.

Asi que da igual que un PNG sea 600x900 y otro 900x600, que el personaje este
descentrado o que tenga mucho margen vacio: se vera bien en todas las pantallas
(coleccion, equipo, orden de ataque, ficha y combate).

## Cambiar la ruta de una ranura (opcional)

Si quieres usar otro nombre o poner el archivo en otro sitio, se puede
sobreescribir en el JSON del personaje:

```json
"art": {
	"front": "res://art/characters/gojo/front.png",
	"back": "res://art/characters/gojo/back.png",
	"icon": "res://art/characters/gojo/icon.png"
}
```

Sin ese bloque, se usa la convencion de carpetas. **No hace falta para nada.**

## Anadir un personaje nuevo

1. Crea `res://data/characters/<id>.json` copiando otro personaje.
2. Crea la carpeta `res://art/characters/<id>/`.
3. Mete `front.png`, `back.png`, `icon.png`.

Aparece solo en la coleccion, la ficha, el equipo y el combate.

## Nota sobre licencias

Meter imagenes de personajes de anime con copyright es valido para desarrollo y
pruebas privadas, pero no se pueden distribuir en un juego publicado. Para una
version comercial, sustituye estos PNG por arte propio o con licencia: el
sistema es el mismo y no requiere cambios de codigo.
