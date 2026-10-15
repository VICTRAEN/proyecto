# Arte de objetos (ITEMS)

Los PNG de los objetos los aporta el usuario. Aqui no se genera nada.

## Lo unico que tienes que hacer

1. Crea el PNG del objeto (cuadrado, con fondo transparente).
2. Dejalo en esta carpeta con el **nombre exacto** que pide la tabla de abajo.
3. Abre el juego.

**No hay que editar ningun JSON ni ningun script.** El sistema busca el archivo por
su nombre y lo usa solo.

## Nombres de archivo

| Archivo | Objeto | Donde se usa |
|---|---|---|
| `rabbit_costume.png` | Uniforme de conejita | INVENTARIO y como recompensa del evento |
| `mai_token.png` | Ficha dorada de Mai | INVENTARIO y como requisito de la evolucion UR -> LR |

## Formato recomendado

| Archivo | Tamano | Formato |
|---|---|---|
| Cualquier objeto | Cuadrado, 256x256 o 512x512 px | PNG con fondo transparente |

Recomendaciones:

- **PNG con transparencia**, no JPG.
- Cuadrado: el icono se muestra en un hueco cuadrado.
- No hace falta que todos midan lo mismo: el juego encuadra solo.

## Si falta el PNG

El juego dibuja un **placeholder** con el color de la rareza del objeto y su
nombre. **No hay error, ni hueco vacio, ni pantalla rota.** Puedes ir metiendo
los PNG poco a poco: cada uno que dejes aparece solo.

## Anadir un objeto nuevo

1. Crea `res://data/items/<id>.json` copiando otro objeto.
2. Si quieres su imagen, deja `res://art/items/<id>.png`.

Aparece solo en el inventario. El catalogo de objetos es generico: sirve igual
para materiales, tickets, objetos evolutivos y cualquier cosa que se pueda
guardar en la mochila.
