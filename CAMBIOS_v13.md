# Anime Battle v13 - Pity, historial, banners y copias

Base: v12 (estable). Se conserva todo lo anterior (combate, links, equipos guardados, favoritos),
los guardados y las probabilidades actuales de cada banner.

## 1. Pity
- **Que cuenta**: un personaje del pool que PUEDA ALCANZAR LR. La rareza maxima alcanzable se calcula
  desde los datos (cadena de evolucion + evolucion especial; el paso a LR exige `evolution.lr`).
- **Contenido real**: entre los personajes invocables SOLO David + Lucy llega a LR. Por eso el pity
  (10 tiradas, LR) esta activo unicamente en el banner "Edgerunners". Los otros cuatro banners NO tienen pity,
  y asi lo dice su ventana de informacion: no se promete una garantia que su pool no puede cumplir.
  Si mas adelante otro personaje declara `evolution.lr`, bastara con poner `pity` en el JSON del banner.
- **Reglas**: si las 9 primeras tiradas seguidas no dan al duo, la 10a lo garantiza. Si sale antes (por la
  tirada normal, 7%), el contador vuelve a 0. El contador es por banner.
- **x1 y x10**: la multi son tiradas secuenciales; la garantizada puede caer en cualquier posicion y lo que
  sigue empieza de cero, sin contar nada dos veces.
- **Persistencia**: el contador se guarda en el mismo guardado (atomico) que el cobro, la entrega y el
  historial. Cerrar el juego no reinicia el pity ni permite repetir una tirada. Un revelado interrumpido recupera
  los mismos resultados sin volver a cobrar.
- **Se muestra**: en INVOCAR ("PITY 4/10 - garantizado en 6 tiradas"), en la animacion ("PITY GARANTIZADO"),
  en la carta (PITY GARANTIZADO), en el resumen, en la ventana de info y en el historial.
- **Efecto en la economia del banner** (medido, 3000 tiradas): el duo sale en ~13,7% de las tiradas
  (con la tasa propia del 7% sola serian ~7%). Toda x10 contiene al duo. Es consecuencia directa del pity pedido;
  si quieres frenarlo, la palanca es `pity.pulls` o la tasa `featured_rates` del duo (no he tocado ninguna).

## 2. Animacion de invocacion
Ya existia (portal con el color de la mejor rareza, destello, revelado carta a carta, cinematica del duo con
SALTAR). Auditada y reforzada:
- Tocar la pantalla salta la animacion previa; nuevo boton **OMITIR TODO** en las multis (va al resumen sin tirar
  ni cobrar de nuevo, los resultados ya estan guardados).
- Tirada con pity garantizado: el portal dice "PITY GARANTIZADO".
- Un toque cobra una vez; el doble toque durante la animacion, o con un revelado pendiente, no cobra ni tira.
  Navegar a otra pantalla y volver retoma el revelado pendiente con los mismos resultados.
- La cinematica especial de David + Lucy se conserva (probada).

## 3. Historial
Pantalla nueva **HISTORIAL** (boton en INVOCAR): fecha y hora, banner, coste, personajes (rareza, nuevo,
garantizado), progreso del pity (antes -> despues), total de invocaciones y filtro por banner; las ultimas 300
invocaciones, y los totales no caducan. Se escribe dentro de `summon()` (una entrada por invocacion), asi que el
revelado no la duplica. Empieza en la v13: las invocaciones anteriores no estan registradas (no hay datos).

## 4. Informacion de banners
Boton **INFO DEL BANNER**: probabilidad por rareza, tasas propias (duo 7%), probabilidad por personaje,
rareza maxima alcanzable de cada uno, destacados y reglas + progreso del pity. Sale de las mismas funciones que
usa `summon()` (`banner_rate_table`, `banner_character_rate`, `pity_status`): probado que las probabilidades por
personaje suman 1 y cuadran con cada rareza en los 5 banners.

## 5. Coleccion
- Libro de copias: `total = disponibles + usadas + convertidas`. Probado al equipar (sin cambios), mejorar
  (disponibles -coste, usadas +coste, total igual), evolucionar (sin cambios) y convertir sobrantes.
  Nuevo: las copias convertidas en monedas se anotan (antes el total bajaba) y se conservan al evolucionar especial.
- Filtros **CON COPIAS** y **FAVORITOS**; estrella en las cartas favoritas.
- Boton FAVORITO en la pestana DUPES de la ficha. Un favorito no se consume en evolucion especial (v12) ni puede
  convertir sus copias en monedas hasta quitarle la marca.

## Pruebas (Godot headless, copia limpia)
| Suite | Resultado |
|---|---|
| DBG25 nueva (pity x1/x10/multiples, reinicio, persistencia, revelado pendiente, historial, info, pantallas, cinematica, copias, coleccion) | 101 / 101 |
| DBG15, 17, 18, 19, 20, 21, 22, 23, 24 | 0 fallos |

## Problemas pendientes / limites
- Pantallas probadas en headless (construccion y logica), no en movil real ni con capturas.
- El historial no incluye invocaciones anteriores a la v13.
- Con el pity el duo sale casi el doble de lo que daria su tasa sola (ver arriba): decision de balance tuya.
- Solo un banner tiene pity porque solo un personaje invocable puede llegar a LR.
- Favorito solo protege frente a evolucion especial y conversion de copias.
- Heredados: aviso ObjectDB al salir, fondos/SFX provisionales, icono del duo UR.
