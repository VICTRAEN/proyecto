# COMO AÑADIR IMAGENES

No hay que tocar JSON, ni scripts, ni registrar nada. Solo dejar los PNG en su
carpeta y ejecutar el juego.

## Paso a paso

1. Abre la carpeta del personaje. Ejemplo:

```
res://art/characters/gojo/
```

2. Arrastra dentro estos tres archivos, con EXACTAMENTE estos nombres:

```
front.png   ->  el personaje DE FRENTE   (se usa cuando es el RIVAL)
back.png    ->  el personaje DE ESPALDAS (se usa cuando es del JUGADOR)
icon.png    ->  la CARA   (coleccion, equipo, orden de ataque, ficha)
```

3. Ejecuta el juego. Ya esta.

## Carpetas preparadas

| Personaje | Carpeta | Que va dentro |
|---|---|---|
| Satoru Gojo | `res://art/characters/gojo/` | `front.png`, `back.png`, `icon.png` |
| Yoichi Isagi | `res://art/characters/isagi/` | `front.png`, `back.png`, `icon.png` |
| Frieren | `res://art/characters/frieren/` | `front.png`, `back.png`, `icon.png` |
| Mai Sakurajima | `res://art/characters/mai/` | `front.png`, `back.png`, `icon.png` |
| Vigia del Vacio (rival) | `res://art/characters/void_warden/` | `front.png`, `back.png`, `icon.png` |

El nombre de la carpeta es el `id` del personaje en su JSON. Personaje nuevo =
carpeta nueva con su mismo id.

## Tamanos recomendados

| Ranura | Tamano | Forma | Fondo |
|---|---|---|---|
| `front.png` / `back.png` | 1024 x 1536 | vertical, cuerpo completo | transparente |
| `icon.png` | 512 x 512 | cuadrado, cara y hombros | transparente |

PNG con transparencia. Nada de JPG. El motor escala solo, asi que no pasa nada si
tus originales son mas grandes; esto es solo una recomendacion para que pesen
poco en movil.

## Si falta un PNG

No hay error: se dibuja una silueta del color del tipo del personaje y las
pantallas de coleccion y equipo avisan con "sin icono". Puedes meter las imagenes
de una en una, en el orden que quieras.

## ARTE PROPIO DE CADA FORMA (evoluciones)

Un personaje evolucionado puede tener su **propia imagen**, distinta de la forma
base. No hace falta tocar codigo: se crea una subcarpeta con el nombre de la
forma.

```
res://art/characters/gojo/
	icon.png          <- forma base (SSR): se usa si no hay nada mas especifico
	front.png
	back.png
	ssr/              <- (opcional) arte explicito de la forma SSR
		front.png
		back.png
		icon.png
	ur/               <- arte de la forma UR
		front.png
		back.png
		icon.png
	lr/               <- arte de la forma LR
		front.png
		back.png
		icon.png
```

Las carpetas de forma se llaman **igual que la rareza, en minusculas**:
`r`, `sr`, `ssr`, `ur`, `lr`.

### Que imagen se usa, en orden

1. La ruta que diga el JSON del personaje (si trae una).
2. `res://art/characters/<id>/<forma>/<ranura>.png` (la forma actual).
3. `res://art/characters/<id>/<ranura>.png` (la forma base).

Es decir: **si todavia no tienes el dibujo de UR, se sigue viendo el de SSR**.
Puedes ir metiendo las imagenes de cada forma poco a poco, cuando quieras.

### Reglas

- Un personaje que solo tiene forma base funciona exactamente como antes.
- Un personaje no tiene por que tener todas las formas: solo las que tenga su
  cadena de evolucion en el JSON.
- Para darle a una forma un arte con OTRA ruta, se puede declarar en el JSON, en
  el bloque `evolution`:

```json
"evolution": {
	"art": {
		"front": "res://art/characters/gojo/ur/front.png",
		"back":  "res://art/characters/gojo/ur/back.png",
		"icon":  "res://art/characters/gojo/ur/icon.png"
	}
}
```

Si ese bloque no existe, manda la convencion de carpetas de arriba.

## Si quieres otro nombre o carpeta

Por defecto se usa la convencion de arriba. Si prefieres otra ruta, se puede
sobreescribir por personaje en su JSON:

```json
"art": {
	"front": "res://art/characters/gojo/front.png",
	"back": "res://art/characters/gojo/back.png",
	"icon": "res://art/characters/gojo/icon.png"
}
```

## Licencias

Imagenes de personajes con copyright valen para desarrollo y pruebas privadas,
pero no se pueden distribuir en un juego publicado. Para una version comercial,
sustituyelas por arte propio o con licencia: el sistema es el mismo y no requiere
ningun cambio de codigo.
