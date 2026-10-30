# Esquema de datos

Todo el contenido vive en `res://data/`. El codigo nunca menciona un personaje
concreto por su id: lee estos archivos. Anadir el personaje 121 = crear un
archivo en `data/characters/` y meter su arte.

## Personaje (`data/characters/<id>.json`)

| Campo | Tipo | Notas |
|---|---|---|
| id | string | Debe coincidir con el nombre del archivo. Clave unica. |
| name, title | string | Nombre visible y apodo. |
| genre | string | Shonen, Spokon, Romance, Sobrenatural, ... |
| portrait_style | string | Silueta provisional mientras no hay arte: spiky, short, long, ponytail. |
| art | objeto | Tres ranuras por personaje: front (de frente, se usa cuando la unidad es el rival), back (de espaldas, para las unidades del jugador), icon (cara). Si falta una ruta se usa la convencion res://art/characters/<id>/<ranura>.png y, si tampoco existe el archivo, una silueta. Ver res://art/README.md. |
| rarity | string | Rareza BASE: R, SR, SSR, UR, LR. Es identidad del personaje y no cambia nunca. La rareza EFECTIVA (la evolucionada) es estado del jugador y vive en el guardado; ver "Rareza base y rareza evolucionada". |
| type | string | STR, AGL, INT, TEQ, PHY. |
| roles | array | Damage Dealer, Tank, Support, Healer, Utility. Dato interno de diseno: NO se muestra en el HUD de combate. |
| stats | objeto | max_hp, atk, def, speed, crit_rate, dodge_rate. Son las estadisticas de NIVEL 1: el nivel las escala en `core/stat_block.gd`. |
| categories | array | Lista de IDS de `data/categories/`. Ya NO se escriben textos sueltos: un id que no exista es un error de carga (DB lo avisa al arrancar). |
| links | array | Lista de IDS de `data/links/`. Con dos personajes del EQUIPO que compartan un link, el link se activa y da su bonus. |
| passive | objeto | trigger, condition, effects. La pasiva del personaje sin evolucionar. |
| skills | array | La primera con kind "basic", la segunda con kind "special". |
| transformations | array | Reservado. Puede estar vacio. |
| evolution | objeto | La RECETA de su forma evolucionada: passive (la pasiva mejorada), passive_extra (la segunda pasiva que gana), links y categories nuevos. Ver "Bloque de evolucion". |

El nivel y la XP del personaje NO viven en su JSON: son estado del jugador
(`autoload/game_state.gd`, guardado en `user://save.json`). Subir de nivel nunca
reescribe un JSON.

## Enemigo (`data/enemies/<id>.json`)

Mismo esquema. Los enemigos tambien usan pasivas y efectos, con el mismo motor.
El campo `art` puede ir vacio: mientras falte el PNG se dibuja una silueta con
`portrait_style`.

## Habilidad

| Campo | Tipo | Notas |
|---|---|---|
| id | string | Unico dentro del personaje. |
| name | string | Nombre visible en el HUD y en el panel de informacion. |
| description | string | Texto que lee el jugador. Sale siempre de aqui: la interfaz nunca escribe descripciones de habilidades. |
| kind | string | "basic" (coste 0, genera SP) o "special". |
| power | number | Porcentaje sobre el ATK del atacante. 0 = habilidad sin dano. Es el "damage_multiplier" de la habilidad. |
| cost | int | Puntos de SP que consume (el "sp_cost"). |
| target | string | self, enemy, enemy_all, ally, ally_all, ally_lowest. Es el "target_type". |
| effects | array | Se aplican despues del golpe principal. |
| hits | int | (v12) Golpes del ataque; el poder se reparte entre ellos. |
| pierce | number | (v12) Fraccion de DEF del objetivo que se ignora (tope en `BattleMath.MAX_PIERCE`). |
| lifesteal | number | (v12) Fraccion del dano hecho que cura al atacante (tope en `MAX_LIFESTEAL`). |
| recoil | number | (v12) Fraccion del dano hecho que el atacante se inflige. |
| sp_refund | int | (v12) SP que devuelve el uso de la habilidad. |
| bonus | array | (v12) `[{ condition, power_mult }]`: multiplica el poder si se cumple la condicion (ejecutar, aprovechar debuffs...). |

## Efecto (vocabulario cerrado, lo interpreta `core/effect_engine.gd`)

Todos los efectos aceptan un `condition` opcional.

| type | Campos | Que hace |
|---|---|---|
| damage | power, target | Dano con la formula de `core/battle_math.gd`. |
| heal | amount, of (max_hp), target | Cura una cantidad o un porcentaje del HP maximo. |
| stat_mod | stat, kind (mult/flat), value, turns, target | Modifica una stat. turns 0 = permanente. Reaplicar el mismo origen lo sustituye, no lo acumula. |
| sp_gain | amount, target | Suma SP. |
| status | status (stun, taunt), turns, target | Aplica un estado. stun hace perder el turno; taunt (v12) obliga a los rivales a atacar a quien lo lleva. |
| shield | amount, of (max_hp), turns, target | (v12) Escudo que absorbe dano antes que la vida. Mismo origen = se sustituye. Caduca por rondas. |
| periodic | kind (bleed/burn/poison/regen), amount, of, turns, target | (v12) Dano o curacion al INICIO del turno de quien lo lleva. |
| cleanse | count, target | (v12) Quita debuffs temporales (nunca los permanentes). |
| dispel | count, target | (v12) Quita buffs temporales del rival. |
| sp_drain | amount, target | (v12) Resta SP al rival. |
| undying | charges, heal, target | (v12) Sobrevive a un golpe mortal con 1 HP y se cura (cargas limitadas). |

`stat_mod` admite ademas (v12) `stacks_max`: se acumula hasta N veces. Las
estadisticas de combate nuevas (`dmg_dealt`, `dmg_taken`, `dmg_reduction`, `pierce`,
`lifesteal`, `crit_dmg`) son siempre `flat`, se leen en puntos porcentuales y se
calculan en `core/stat_block.gd` como cualquier otra.

Objetivos nuevos (v12): `ally_others`, `ally_random`, `random_enemy`,
`enemy_strongest`, `enemy_lowest`, `trigger_target` (quien provoco el disparador).

## Condiciones (`core/effect_engine.gd`)

| type | Campos | Se cumple cuando |
|---|---|---|
| hp_below | who (self o team_lowest), value | El ratio de HP indicado esta por debajo. |
| hp_above | who, value | El ratio de HP esta por encima. |
| round_at_least | value | La ronda actual es mayor o igual. |
| team_has_category | value | Algun aliado tiene esa categoria. |
| round_at_most | value | (v12) La ronda actual es menor o igual. |
| team_category_count_at_least | category, value | (v12) Al menos N aliados con esa categoria. |
| team_has_role | value | (v12) Algun aliado tiene ese rol. |
| allies_alive_at_most / allies_alive_at_least | value | (v12) Aliados vivos. |
| allies_fallen_at_least | value | (v12) Aliados caidos. |
| enemies_alive_at_most / enemies_alive_at_least | value | (v12) Rivales vivos. |
| sp_at_least | value | (v12) SP propio. |
| self_shielded / self_debuffed | - | (v12) Estado propio. |
| target_debuffed / target_shielded | - | (v12) Estado del objetivo. |
| target_has_status | value | (v12) El objetivo tiene ese estado. |
| target_type_is / self_type_is | value | (v12) Tipo del objetivo / propio. |
| target_hp_below / target_hp_above | value | (v12) HP del objetivo. |
| hp_below.who | self, team_lowest, target | (v12) `target` anadido. |

## Pasivas y disparadores (v12)

Una pasiva es una regla `{ id, name, trigger, condition, effects, chance, once, cooldown, threshold }`.
Disparadores: `battle_start`, `round_start` (antes de ordenar los turnos), `turn_start`,
`on_attack`, `on_special`, `on_hit`, `on_crit`, `on_kill`, `on_dodge`, `on_ally_down`,
`low_hp` (con `threshold`). `chance` = probabilidad, `once` = una vez por combate,
`cooldown` = rondas entre disparos. La descripcion se genera desde estos datos.

## Links por niveles (v12)

El link v12 ya NO es un unico bonus: tiene `tiers` por numero de portadores en el equipo.

```json
{ "id": "heroes", "name": "Heroes", "description": "...",
  "legacy_effects": [ ... ],
  "tiers": [ { "need": 2, "rules": [ { "id": "base", "name": "Vinculo", "who": "holders",
      "trigger": "static", "condition": {}, "effects": [ ... ], "text": "..." } ] },
    { "need": 3, "rules": [ ... ] }, { "need": 4, "rules": [ ... ] } ] }
```

- `who`: `holders` (quien lleva el link), `team` (todo el equipo) o `first` (solo el primer portador).
- `trigger`: `static` (modificador fijo todo el combate) o cualquier disparador de arriba.
- Un nivel incluye las reglas de los niveles inferiores. `legacy_effects` es el bonus plano
  del esquema antiguo, que sigue vivo como la regla `base` del nivel 2 (los datos antiguos no se pierden).
- `GameState.team_synergy_report()` devuelve niveles, textos y A QUIEN benefician (lo pinta la ficha).

## Equipos guardados y favoritos (v12, `user://save.json`)

`saved_teams`: hasta 20 `{ id, name, members[5] }` (puesto 1 = lider; 5 puestos para la torre),
`next_team_id`, `favorites`: ids protegidos de consumo. Claves opcionales: un guardado
anterior carga con listas vacias.

## Elegir objetivo

`target` decide si el jugador tiene algo que elegir. Lo resuelve
`BattleManager.target_side()` y lo consulta la pantalla de combate:

- `enemy` / `ally` -> un unico objetivo. Si hay mas de un candidato vivo, la
  pantalla entra en modo "elige objetivo" y el jugador toca la tarjeta que
  quiere; los candidatos se encienden en verde y hay boton CANCELAR. Si solo hay
  un candidato, el combate elige por el y el turno no se alarga con un toque de
  mas. Un cambio de escenario a dos enemigos activa la eleccion sin tocar codigo.
- `enemy_all`, `ally_all`, `ally_lowest`, `self` -> no se pregunta nada.
- Si el objetivo elegido cae antes de resolver, `_pick_target()` vuelve al
  criterio por defecto (el de menos vida), asi que una habilidad nunca se queda
  sin objetivo.

## Base, actual y modificadores

- `stats` del JSON es el valor BASE y se pinta tal cual en la columna "BASE".
- El valor ACTUAL lo resuelve siempre `core/stat_block.gd`: base + mods
  (pasivas, buffs y debuffs). El panel y el motor leen el MISMO numero; el
  panel no calcula nada por su cuenta. El critico actual sale de
  `BattleMath.crit_chance()`, que es la misma funcion que tira el dado.
- Critico y esquiva son probabilidades: un `stat_mod` con `kind: "flat"` y
  `value: 0.2` suma 20 PUNTOS (14% -> 34%), no un 20% relativo. `kind: "mult"`
  siempre es relativo a la base (0.3 = +30%).
- Reaplicar el mismo origen sobre la misma stat la sustituye, no la acumula
  (`StatBlock.add_mod`). Para que dos efectos sumen tienen que venir de origenes
  distintos (una pasiva y una habilidad, por ejemplo).
- Los contadores de batalla (dano hecho, dano recibido, criticos, esquivas,
  curaciones, buffs...) NO se guardan en el JSON: viven en
  `core/battle_stats.gd`, se crean nuevos en cada batalla y anadir un contador
  es una linea en su lista `DISPLAY`.

## Ventaja de tipo

La tabla vive en `core/battle_math.gd` (`TYPE_ADVANTAGE`) y el unico sitio que la
consulta es `BattleMath.type_multiplier(attacker_type, defender_type)`. El
combate usa esa funcion; la interfaz solo lee el `type_mult` que devuelve el
golpe, asi que no puede haber dos versiones de la tabla.

| Tipo atacante | Vence a | Multiplicador |
|---|---|---|
| STR | AGL | 1.25 |
| AGL | INT | 1.25 |
| INT | TEQ | 1.25 |
| TEQ | PHY | 1.25 |
| PHY | STR | 1.25 |

Contra el tipo inverso (AGL atacando a STR, por ejemplo) el multiplicador es
0.8. Cualquier otra pareja es 1.0.

El jugador no ve el multiplicador: en el registro lee `VENTAJA DE TIPO` o
`DESVENTAJA DE TIPO`, y en pantalla aparece el mismo aviso como numero flotante.

## Dano

El dano final lo calcula `core/battle_math.gd`, y solo ese archivo:

```
ATQ x multiplicador de la habilidad (power / 100)
- DEF del objetivo x 0.45   (nunca baja de 1)
x ventaja de tipo            (1.25 / 0.8 / 1.0)
x 1.6 si es critico
x variacion aleatoria 95%-105%
= dano final
```

Dos reglas que no se deben romper:

- La variacion aleatoria se aplica al RESULTADO, nunca a las estadisticas. El
  ATQ que se ve en la ficha no cambia porque se tire el dado.
- La probabilidad de critico es UNA sola: `BattleMath.crit_chance()`. La usan el
  motor de dano para tirar el dado y el panel de informacion para pintar el
  numero. El jugador nunca ve el rango de variacion ni la formula: solo el dano
  que ha salido.

Las estadisticas de combate guardan el dano FINAL, ya con critico y variacion
aplicados.

## Stage (`data/stages/<id>.json`)

| Campo | Tipo | Notas |
|---|---|---|
| id | string | Clave unica. El orden de la cadena es el orden alfabetico de los ids. |
| name | string | Nombre visible en SELECCIONAR BATALLA. |
| difficulty | string | NORMAL por ahora. Es un dato: no cambia todavia ningun calculo. |
| enemies | array | Lista de ids de `data/enemies/`. 1, 2 o 3 enemigos: el combate ya trabaja con listas. |
| xp_reward | int | XP que recibe cada personaje que combatio. |
| coin_reward | int | Monedas al ganar. |
| energy_cost | int | Reservado (0). |

El desbloqueo es una cadena por orden de id: el stage N pide el N-1 ganado, y
el primero siempre esta abierto (`GameState.stage_unlocked`). Ganar marca el
stage con `GameState.mark_stage_completed`, que devuelve SOLO los recien
desbloqueados; la pantalla de resultado los anuncia.

## Mision (`data/missions/<id>.json`)

| Campo | Tipo | Notas |
|---|---|---|
| id | string | Clave unica. |
| name | string | Nombre visible en MISIONES. |
| description | string | Texto que lee el jugador. |
| stat | string | Contador global que la mide: `victorias`, `combates_jugados`, `derrotas`, `personajes_obtenidos`. |
| target | int | Cuanto hay que acumular para completarla. |
| reward_coins, reward_gems | int | Lo que entrega al reclamarla. |

El progreso NO se guarda: se calcula desde los contadores globales
(`GameState.counter_value`). Lo unico que persiste es `claimed`, para que una
mision completada no pague dos veces. `personajes_obtenidos` sale de
`roster.size()`, no de un contador aparte.

## Contadores globales

`combates_jugados`, `victorias` y `derrotas` suben en
`GameState.grant_battle_rewards`, que es el unico sitio que cierra una batalla.
Suben tambien cuando la batalla se pierde. `GameState.add_counter(key)` es la
puerta para anadir contadores nuevos (logros, estadisticas) sin tocar el
guardado: `save_game` los vuelca todos.

## Link (`data/links/<id>.json`)

Un link es una caracteristica COMPARTIDA: da un bonus real cuando DOS O MAS
personajes del EQUIPO lo llevan. Un link con un solo portador no hace nada.

| Campo | Tipo | Notas |
|---|---|---|
| id | string | Clave unica. Es lo que se escribe en el `links` del personaje. |
| name | string | Nombre visible. |
| description | string | Texto que lee el jugador. |
| effects | array | Efectos con el MISMO vocabulario que `core/effect_engine.gd`. Lo normal es `stat_mod` con stat/kind/value; tambien valen heal o status. |

```json
{
	"id": "rivales",
	"name": "Rivales",
	"description": "Dos rivales empujandose hacia delante.",
	"effects": [
		{ "type": "stat_mod", "stat": "atk", "kind": "mult", "value": 0.05 },
		{ "type": "stat_mod", "stat": "def", "kind": "mult", "value": 0.05 }
	]
}
```

Reglas que no se rompen:

- Los efectos se aplican SOLO a los personajes del equipo que comparten el link,
  no a todo el equipo.
- Se aplican como `add_mod` con un origen propio (`link:<id>`), asi que
  `core/stat_block.gd` sigue siendo el unico sitio que calcula el valor final y
  reaplicar el mismo link lo SUSTITUYE en vez de acumularlo.
- Quien decide que links estan activos es `GameState.active_link_ids()` (dos o
  mas portadores en el equipo). `GameState.link_status(id)` devuelve, por
  personaje, `{ id, name, active, holders, effects }` para que la ficha lo pinte
  sin saber nada de las reglas.

## Categoria (`data/categories/<id>.json`)

Clasificacion amplia, preparada para Leader Skills (todavia sin implementar),
misiones y filtros del coleccionable.

| Campo | Tipo | Notas |
|---|---|---|
| id | string | Clave unica y en minusculas. Es lo que se escribe en el `categories` del personaje. |
| name | string | Nombre visible. |
| description | string | Texto que lee el jugador. |

Los personajes llevan IDS (`"categories": ["shonen", "heroes"]`), no textos
sueltos. `DB.load_all()` comprueba todas las referencias al arrancar: si un
personaje menciona una categoria o un link que no existe, aparece como error de
carga en la consola en lugar de dar un bonus invisible.

## Evolucion (`data/evolution/rules.json`)

Un unico archivo con la lista de rutas. Toda la cadena (R->SR, SR->SSR, SSR->UR,
UR->LR) son MAS ENTRADAS en `routes`: anadir una transicion no toca ningun script.

| Campo | Tipo | Notas |
|---|---|---|
| from, to | string | Rareza de partida y de llegada. |
| level_required | int | Nivel minimo para poder evolucionar. |
| coin_cost | int | Monedas que cuesta. Se pagan con `GameState.spend_coins`. |
| stat_multiplier | number | Cuanto multiplican las estadisticas del JSON en la forma nueva. |
| description | string | Texto opcional que explica la ruta. |

```json
{
	"routes": [
		{ "from": "SSR", "to": "UR", "level_required": 100, "coin_cost": 100000, "stat_multiplier": 1.25 }
	]
}
```

`DB.evolution_rule(from, to)` consulta una ruta concreta y
`DB.evolution_routes_from(rarity)` todas las que parten de una rareza.

## Bloque de evolucion (dentro del JSON del personaje)

Es IDENTIDAD del personaje (como su nombre o su arte), no estado del jugador: por
eso vive en su propio JSON y no en el guardado.

| Campo | Tipo | Notas |
|---|---|---|
| passive | objeto | La pasiva UR: la pasiva original MEJORADA. Mismo formato que `passive`. Sustituye a la del personaje en cuanto evoluciona. |
| passive_extra | objeto | La SEGUNDA pasiva que gana al evolucionar. El combate dispara las dos. |
| links | array | Ids de `data/links/` que se SUMAN a los que ya tenia. |
| categories | array | Ids de `data/categories/` que se SUMAN a los que ya tenia. |

La logica vive en `autoload/game_state.gd` y no pinta nada:

- `GameState.can_evolve(id)` -> `{ ok, reason, route, from, to, level,
  level_required, coin_cost, coins }`. `reason` viene en texto de jugador: "Su
  rareza (SR) no tiene ruta de evolucion", "Nivel insuficiente: hace falta nivel
  100", "Faltan monedas: cuesta 100000 y tienes 4200". Un personaje sin ruta
  definida NO puede evolucionar aunque tenga bloque `evolution`.
- `GameState.evolve(id)` solo actua si `can_evolve(id).ok`: cobra las monedas,
  guarda la rareza evolucionada, devuelve al personaje a nivel 1 con 0 XP y
  devuelve el informe (rareza anterior y nueva, coste, pasiva nueva, links y
  categorias nuevas). Conserva al personaje entero: mismo id, misma entrada en el
  roster, mismo arte.
- `GameState.rarity_of(id)` es la rareza EFECTIVA y `GameState.base_rarity_of(id)`
  la del JSON. `GameState.passives_of(id)` devuelve una o dos pasivas;
  `GameState.is_evolved(id)` dice si ya ha evolucionado.

## Rareza base y rareza evolucionada

Son dos cosas distintas y conviene no mezclarlas:

- Rareza BASE: la del JSON del personaje. Nunca cambia.
- Rareza EVOLUCIONADA: ESTADO DEL JUGADOR. Vive en el guardado, en
  `GameState.rarities` (id -> "UR"). Un id ausente significa "usa la del JSON".
- Quien las junta es `GameState.character_data(id)`, que devuelve el JSON con
  `rarity` ya resuelta (la efectiva), `base_rarity`, `evolved` y `passives`. La
  ficha, la coleccion y el combate leen ese diccionario, nunca el JSON crudo.

## Banner (`data/banners/<id>.json`)

Catalogo de invocaciones. La pantalla de gacha de un hito posterior se construye
sola leyendo estos archivos: no hay ninguna lista de banners en el codigo.

| Campo | Tipo | Notas |
|---|---|---|
| id | string | Clave unica. |
| name, description | string | Lo que lee el jugador. |
| cost_gems | int | Gemas de una invocacion simple. |
| multi_pulls | int | Cuantas invocaciones entran en la tirada multiple. |
| multi_cost_gems | int | Gemas de la tirada multiple. |
| rates | objeto | Probabilidad por rareza. Deben sumar 1.0. |
| pool_categories | array | Si esta vacio, entra todo el roster. Si tiene ids, solo entran personajes de esas categorias. |
| featured | array | Personajes destacados. |
| featured_bonus | number | Cuanto sube la probabilidad de los destacados. |
| pity | objeto | (v13) `{ pulls, rarity }`. Si las `pulls - 1` tiradas anteriores seguidas no dan ningun personaje del pool que PUEDA ALCANZAR `rarity` (rareza maxima alcanzable por evolucion, no la rareza con la que sale), la tirada `pulls` garantiza uno. Si sale uno antes, el contador vuelve a 0. `pulls: 0` = sin pity. Si ningun personaje del pool puede llegar a esa rareza, el banner NO tiene pity (se informa asi). |
| exclusive_ids, featured_rates | | Unidades exclusivas del banner y su tasa propia por tirada. |

### Pity, historial y copias (v13)

- Rareza maxima alcanzable de un personaje (`GameState.max_reachable_rarity`): se calcula
  con `data/evolution/rules.json` (el paso a LR exige `evolution.lr` en el personaje) y
  `data/evolutions/special.json`. Hoy solo el duo David + Lucy (de los invocables) llega a LR,
  asi que solo `banner_david_lucy` tiene pity (10).
- El contador de pity es POR BANNER (`pity_counters`) y se guarda en `user://save.json` junto al
  cobro y la entrega (guardado atomico por invocacion).
- `summon_history` (maximo 300 entradas), `summon_total`, `summon_banner_totals`, `copies_converted`:
  claves opcionales del guardado; un guardado anterior carga con todo a cero.
- Libro de copias: `total = disponibles + usadas + convertidas`.

## Tienda (`data/shop/<id>.json`)

| Campo | Tipo | Notas |
|---|---|---|
| id | string | Clave unica. |
| name, description | string | Lo que lee el jugador. |
| cost_coins, cost_gems | int | Precio. 0 = gratis en esa moneda. Se cobra con `GameState.spend_coins` / `spend_gems`, que NUNCA dejan saldo negativo. |
| grant | objeto | Que entrega: `type` puede ser "coins", "gems", "materials" o "character"; `amount` la cantidad; `character_id` solo para "character". |

Un objeto que entrega un personaje que el jugador ya tiene se resuelve como
DUPLICADO (`GameState.add_character`), nunca como una segunda entrada en el
roster: el roster no tiene repetidos.

## Objeto (`data/items/<id>.json`)

Catalogo GENERICO de objetos: vale para materiales, tickets y objetos
evolutivos, porque todos son lo mismo (una cantidad en el inventario mas una
ficha). El guardado solo lleva la CANTIDAD; el nombre, la descripcion y el icono
salen siempre de aqui, asi que no hay dos versiones de la misma ficha.

| Campo | Tipo | Notas |
|---|---|---|
| id | string | Clave unica. Es lo que se guarda en el inventario. |
| name, description | string | Lo que lee el jugador. |
| type | string | Tipo de objeto: `evolution_material`, `material`, `ticket`, ... |
| icon | string | Ruta del PNG. Por convencion `res://art/items/<id>.png`. |
| rarity | string | R, SR, SSR, UR, LR. |
| usable | bool | Si se puede usar desde una pantalla (reservado). |
| obtained_from | string | Texto opcional que explica de donde sale. |

```json
{
	"id": "rabbit_costume",
	"name": "Uniforme de conejita",
	"description": "El uniforme que Mai no se atreve a mirar dos veces.",
	"type": "evolution_material",
	"icon": "res://art/items/rabbit_costume.png",
	"rarity": "SR",
	"usable": false
}
```

Si el PNG todavia no existe **no pasa nada**: `DB.item_icon(id)` devuelve la ruta
y la pantalla dibuja un marcador. El juego nunca se rompe por arte ausente. En
`res://art/items/` van `rabbit_costume.png` y `mai_token.png` (los aporta el
usuario; ver `res://art/items/README.md`).

API: `GameState.add_item(id, amount)`, `remove_item(id, amount)` (nunca deja
negativos), `item_count(id)`, `has_item(id, amount)`, `inventory_data()`.

## Mundo de historia (`data/worlds/world_00N.json`)

La HISTORIA son mundos con niveles. Cada nivel se juega en TRES dificultades, y
cada dificultad tiene sus enemigos y sus recompensas. Anadir un mundo o un nivel
es crear o ampliar un JSON: no hay ninguna lista de mundos en el codigo.

| Campo | Tipo | Notas |
|---|---|---|
| id | string | Clave unica del mundo. |
| name, description | string | Lo que lee el jugador. |
| genre | string | Shonen, Sobrenatural, Fantasy... |
| background | string | Slot de fondo (ver `res://art/backgrounds/`). |
| position | objeto | `{ x, y }` en 0..1 para pintar el mundo en el mapa. |
| unlock | objeto | `{ requires_world, requires_levels_completed }`: de que mundo depende y cuantos niveles hay que haber superado. Un mundo sin `unlock` esta abierto. |
| levels | array | Lista de niveles (soporta 10-15 sin cambios). |

### Nivel de historia (dentro de `levels`)

| Campo | Tipo | Notas |
|---|---|---|
| id | string | Clave unica del nivel (global: `world_001_01`). |
| name | string | Nombre visible en el mapa. |
| position | objeto | `{ x, y }` en 0..1 para pintar el nodo en el mapa. |
| next | string | Id del nivel siguiente, o `""`. |
| background | string | Slot de fondo opcional. |
| dialogue | string | Id de `data/dialogues/`, o `""`. Se muestra ANTES del combate. |
| difficulties | objeto | Las tres dificultades: `normal`, `hard`, `extreme`. |

### Dificultad (dentro de `difficulties`)

| Campo | Tipo | Notas |
|---|---|---|
| order | int | ORDEN de la dificultad (0, 1, 2). Manda sobre el nombre: completar la de orden N completa y paga todas las de orden MENOR. |
| name | string | Texto visible (NORMAL, DIFICIL, EXTREMO). |
| enemies | array | Ids de `data/enemies/`. DB avisa al arrancar si alguno no existe. |
| xp_reward | int | XP de cada personaje que combatio. |
| coin_reward | int | Monedas al ganar. |

```json
{
	"id": "world_001_01",
	"name": "El torneo de artes marciales",
	"position": { "x": 0.2, "y": 0.12 },
	"next": "world_001_02",
	"background": "battle_plain",
	"dialogue": "dlg_world_001_001",
	"difficulties": {
		"normal":  { "order": 0, "name": "NORMAL",  "enemies": ["vigia_alfa"], "xp_reward": 200, "coin_reward": 80 },
		"hard":    { "order": 1, "name": "DIFICIL", "enemies": ["vigia_beta"], "xp_reward": 320, "coin_reward": 130 },
		"extreme": { "order": 2, "name": "EXTREMO", "enemies": ["vigia_alfa", "vigia_beta"], "xp_reward": 520, "coin_reward": 220 }
	}
}
```

Reglas de la historia (en `autoload/game_state.gd`, nunca en una pantalla):

- `GameState.world_unlocked(id)` sale del bloque `unlock` del mundo, no de un
  indice ni de un `si world == 1`.
- `GameState.story_level_unlocked(id)` pide el nivel ANTERIOR del mundo ya
  superado; el primero de cada mundo esta abierto.
- `GameState.complete_story_level(level_id, difficulty, ally_ids)` cierra la
  dificultad y todas las de orden menor. **Completar EXTREMO marca y paga
  NORMAL, DIFICIL y EXTREMO a la vez, y cada recompensa se entrega UNA sola vez**.
  Devuelve `{ ok, completed, xp, coins, characters, unlocked, already }`.
- `GameState.story_level_status(id)` y `world_status(id)` dan el mapa ya resuelto
  para pintar; `story_progress` guarda `nivel -> [dificultades superadas]`.

## Dialogo (`data/dialogues/<id>.json`)

Escenas de texto data-driven con SKIP. La pantalla no escribe ninguna linea: las
lee de aqui.

| Campo | Tipo | Notas |
|---|---|---|
| id | string | Clave unica. Es lo que se escribe en `dialogue` de un nivel o un stage. |
| name | string | Titulo de la escena (opcional). |
| skippable | bool | Si el jugador puede saltarsela. |
| skip_label | string | Texto del boton de saltar. |
| lines | array | Lista de lineas, en orden. |

Cada linea: `{ "speaker", "portrait", "text", "background" }`. `portrait` es el id
de personaje cuya cara se pinta (sale de `res://art/characters/<id>/icon.png`) y
`background` es un slot de fondo.

## Evento (`data/events/<id>.json`)

Un evento es un grupo de stages con reglas propias declaradas en DATOS.

| Campo | Tipo | Notas |
|---|---|---|
| id | string | Clave unica. |
| name, description | string | Lo que lee el jugador. |
| background | string | Slot de fondo del evento. |
| position | objeto | `{ x, y }` para el mapa. |
| counter | string | Contador global que sube al completar el evento entero (lo lee una mision). |
| character_reward | string | Id del personaje que entrega el evento, una sola vez. |
| stages | array | Los stages, en orden. |

### Stage de evento (dentro de `stages`)

| Campo | Tipo | Notas |
|---|---|---|
| id | string | Clave unica del stage. |
| name | string | Nombre visible. |
| position, next, background, dialogue | | Igual que en un nivel de historia. |
| difficulty | string | Texto de dificultad (el evento no usa la regla de las tres). |
| enemies | array | Ids de `data/enemies/`. |
| xp_reward, coin_reward | int | Recompensas. |
| grant_character | string | Personaje que entrega ESTE stage (opcional). |
| requires_party_character | string | Si esta puesto, el stage exige esa unidad EN EL EQUIPO para poder entrar. |
| drops | array | `[ { "item", "min", "max" } ]`: cuantos objetos suelta (rango aleatorio). |

```json
{
	"id": "evt_sdp_02",
	"name": "El celador de la visibilidad",
	"requires_party_character": "sakuta_mai",
	"enemies": ["vigia_beta", "vigia_alfa"],
	"xp_reward": 320,
	"coin_reward": 150,
	"drops": [ { "item": "rabbit_costume", "min": 1, "max": 3 } ]
}
```

API: `GameState.event_status(id)`, `complete_event_stage(event_id, stage_id,
ally_ids)`, `claim_event_character(event_id)` (entrega la unidad UNA sola vez),
`event_stage_unlocked`, `event_times_completed`. El progreso vive en
`event_progress`: por stage superado, por recompensa entregada y el contador de
veces completado.

## Mutacion (`data/mutations/config.json`)

UN archivo con TODO el balance: coste, rangos y probabilidades. Ningun numero de
mutaciones esta escrito en el codigo.

| Campo | Tipo | Notas |
|---|---|---|
| cost | int | Monedas por tirada (150). Se cobran con `spend_coins`: si no llega, no hay tirada ni cobro. |
| currency | string | Moneda del coste. |
| max_active_per_character | int | 1: una sola mutacion activa por personaje. |
| stat_kind | string | `mult`: el bonus es RELATIVO A LA BASE. |
| source_prefix | string | Prefijo del origen con el que entra en `StatBlock.add_mod` (`mutation:<rango>`). |
| ranks | array | `{ id, name, chance_percent, bonus_percent }`, de mas comun a mas raro. |
| effects | array | `{ id, name, stats, chance_percent }`. Las probabilidades suman 100. |
| special | objeto | La mutacion Z: `{ rank, sp_cost_reduction, sp_cost_min }`. Reduce el coste de la Super 1 SP, nunca por debajo del minimo. |

| Rango | Probabilidad | Bonus sobre las stats afectadas |
|---|---|---|
| D | 50% | +1% |
| C | 25% | +2.5% |
| B | 13% | +4% |
| A | 7% | +6% |
| S | 3.5% | +10% |
| SS | 1% | +15% |
| Z | 0.5% | +20% (+1 SP de descuento en la Super) |

Segunda tirada (efecto), que decide a que estadisticas se aplica: dano (12),
defensa (12), vida (20), velocidad (30), vida+velocidad (6), ataque+velocidad (5),
defensa+vida (5), velocidad+defensa (5), ataque+defensa (4) y
ataque+vida+defensa+velocidad (1). Suman 100.

Reglas que no se rompen:

- El bonus entra por `StatBlock.add_mod` como `kind: "mult"` con origen propio
  (`mutation:<rango>`), asi que se aplica sobre la estadistica BASE y reaplicar
  la misma mutacion la SUSTITUYE. `core/stat_block.gd` sigue siendo el unico
  sitio que calcula el valor final.
- Una sola mutacion activa por personaje: una tirada nueva reemplaza la anterior.
- La mutacion pertenece al PERSONAJE y NO se pierde al evolucionar (ni en las
  evoluciones especiales, donde se muda al personaje nuevo).

API: `GameState.roll_mutation(id)` (tira y cobra), `mutation_report(id)`,
`mutation_of(id)`, `apply_mutation_mods(stat_block, id)`,
`mutation_sp_cost_reduction(id)` y `mutation_sp_cost(id, cost)`.

## Evolucion especial (`data/evolutions/special.json`)

Las evoluciones NORMALES van por RAREZA (`data/evolution/rules.json`). Las
ESPECIALES van por PERSONAJE: convierten una unidad en otra distinta. Viven en
este archivo como una lista `routes`, asi que anadir una es una entrada mas.

| Campo | Tipo | Notas |
|---|---|---|
| id | string | Clave unica de la ruta. |
| from, to | string | Id del personaje de partida y de llegada. DB avisa si alguno no existe. |
| to_rarity | string | Rareza de la forma nueva. |
| level_required | int | Nivel minimo del personaje de partida. |
| coin_cost | int | Monedas. Se pagan con `spend_coins`. |
| item_cost | array | `[ { "item", "amount" } ]`: objetos que se consumen del inventario. |
| requires_story_level | string | Nivel de historia que hay que tener superado (o `""`). |
| boss | string | Id del enemigo del combate 1 contra 1 de la evolucion. |
| dialogue | string | Id del dialogo de la escena. |
| keeps_mutation | bool | La mutacion sobrevive (siempre true hoy). |
| transfer_party | bool | La casilla del equipo pasa al personaje nuevo. |
| consume_from | bool | La forma anterior sale del roster: su identidad ahora es la nueva. |
| description, reward_text | string | Texto que lee el jugador. |

```json
{
	"id": "evo_sakuta_to_sakuta_mai_lr",
	"from": "sakuta",
	"to": "sakuta_mai_lr",
	"to_rarity": "LR",
	"level_required": 100,
	"coin_cost": 50000,
	"item_cost": [ { "item": "mai_token", "amount": 1 } ],
	"boss": "boss_sakuta",
	"dialogue": "dlg_evo_sakuta"
}
```

API: `GameState.can_special_evolve(id)` (devuelve `ok`, `reason` en texto de
jugador, la ruta, el coste, los objetos que faltan, el jefe y el dialogo) y
`GameState.evolve_special(id)`, que solo actua si `ok` es cierto.

## Dupes (`data/dupes/rules.json`)

Las copias REPETIDAS de un personaje se gastan en SU ficha (pestana DUPES) para
mejorarlo para siempre, de Dupe 0 a Dupe 5. No son nivel de combate, ni rareza, ni
evolucion: son un eje aparte. Todo numero vive en este archivo.

| Campo | Tipo | Notas |
|---|---|---|
| max_level | int | Dupe maximo (hoy 5). |
| copies_per_level | array | Coste en copias de cada mejora: `[c0->1, c1->2, ...]`. Tiene `max_level` entradas, todas >= 1. |
| levels | array | `max_level + 1` filas. La fila N son los bonus TOTALES del Dupe N (no se suman a los anteriores). La fila 0 es `{}`. |
| overflow.coins_per_copy | int | Monedas por cada copia SOBRANTE (la que ya no puede mejorar al personaje). 0 o quitar el bloque desactiva la conversion. |
| reserved | string | Hueco documentado para mejoras de habilidades/efectos. No se interpreta todavia. |

Cada fila de `levels` es `{ "estadistica": valor }`. Las estadisticas validas son las de
`StatBlock.LABELS` (`max_hp`, `atk`, `def`, `speed`, `crit_rate`, `dodge_rate`...). Un
valor de vida/ataque/defensa/velocidad es un MULTIPLICADOR relativo a la base (`0.03` =
+3 %); el de una probabilidad (critico, esquiva) se SUMA en puntos (`0.03` = +3 puntos).

Tabla actual (copias acumuladas = nivel, porque cada mejora cuesta 1):

| Dupe | HP / ATK / DEF | Critico |
|---|---|---|
| 1 | +3 % | |
| 2 | +6 % | |
| 3 | +9 % | |
| 4 | +12 % | |
| 5 | +18 % | +3 puntos |

**Como se calcula.** `StatBlock` da `valor_base * (1 + suma de multiplicadores) + planos`.
El Dupe entra como modificadores de origen `"dupe"` al construir la unidad
(`GameState.character_data` los lista en `dupe_mods`; `CombatUnit` los aplica; la vista
previa de la ficha usa el MISMO calculo). `add_mod` con el mismo origen SUSTITUYE, y el
bloque de estadisticas se crea nuevo en cada combate, asi que abrir menus, cambiar de
escena, cargar o evolucionar no acumula nada. La base (nivel, rareza, evolucion) nunca se
modifica: la ficha la ensena separada de la bonificacion.

**Copias.** `duplicates[id]` cuenta las copias EXTRA (la primera copia del personaje es el
propio personaje). Las gastadas se deducen del nivel (suma de `copies_per_level` hasta ese
nivel), asi que lo UNICO que se guarda es `dupe_levels` y las disponibles se calculan:
`disponibles = duplicates - gastadas`. Toda via de entrada (invocacion, tienda, eventos)
pasa por `GameState.add_character`, por lo que un personaje F2P tambien genera copias.

**Copias sobrantes.** En el Dupe maximo ya no sirven para mejorar. Si
`overflow.coins_per_copy > 0` la ficha ofrece convertirlas en monedas (con confirmacion).
Antes del maximo no hay sobrantes: toda copia disponible sirve para mejorar.

API (`autoload/game_state.gd`): `dupe_status(id)` (informe con `ok`, `reason`, `level`,
`cost`, `copies` y la vista previa), `dupe_upgrade(id)` (atomica: valida y solo entonces
sube un nivel y guarda), `dupe_level_of`, `dupe_copies_available`, `dupe_mods_for(id)`,
`dupe_stat_preview(id, desde, hasta)`, `dupe_overflow_copies(id)` y
`dupe_convert_overflow(id)`.

**Evolucion.** El nivel de Dupe pertenece al ID del personaje, asi que SSR -> UR -> LR lo
conserva sin tocarlo (y el bonus, al ser un porcentaje, se aplica sobre la base nueva).
En una evolucion ESPECIAL con `consume_from` (otro ID) se juntan las copias extra y el
gasto de las dos identidades, y el nivel resultante es el mas alto que ese gasto paga.

**Validaciones al cargar.** `dupe_levels` se recorta a `0..max_level`, se ignoran los IDs
que no existen y, si un guardado trae menos copias que las que su nivel ya costo, se
sube `duplicates` hasta ese gasto: un nivel nunca queda sin pagar y no se pierde nada.

## Relaciones entre personajes (`evolves_to` / `evolved_from`)

Dentro del JSON del personaje, dos campos opcionales que dicen como se relaciona
con sus formas especiales. Son IDENTIDAD del personaje (como su arte), no estado
del jugador.

| Campo | Tipo | Notas |
|---|---|---|
| evolves_to | array | Ids de los personajes a los que puede llegar. |
| evolved_from | string | Id del personaje del que viene, o `""`. |

`DB.load_all()` comprueba al arrancar que todos esos ids existan, igual que hace
con los enemigos de la historia, los objetos que sueltan los eventos y los
objetos que piden las rutas de evolucion. Un id roto sale en el log de arranque
en lugar de romper el juego.

## Guardado (`user://save.json`)

| version | Cambios |
|---|---|
| 1 | roster, progress, party, amigo, monedas, gemas, materiales, stage, enemigos de la fase, counters, completed_stages, missions_claimed, energia. |
| 2 | Anade `rarities` (rareza evolucionada por personaje) y `duplicates` (copias de mas por personaje). |
| 3 | Anade `inventory` (id de objeto -> cantidad), `mutations` (la mutacion activa de cada personaje), `story_progress` (nivel de historia -> dificultades superadas) y `event_progress` (por evento: stages superados, recompensas entregadas y veces completado). |

Anadido SIN subir la version (campo nuevo y opcional): `dupe_levels` (`{ "gojo": 3 }`,
solo niveles > 0). Un guardado sin ese campo arranca con todos los Dupes a 0 y sus
`duplicates` pasan a ser copias disponibles, sin perder ni regalar nada.

| Campo v3 | Formato |
|---|---|
| inventory | `{ "rabbit_costume": 4 }`. Solo se guardan cantidades mayores que cero; el catalogo lo pone el JSON del objeto. |
| mutations | `{ "gojo": { "rank": "S", "bonus_percent": 10.0, "effect": "atk_speed", "stats": [ { "stat", "label", "bonus", "bonus_percent", "kind", "text" } ], "sp_reduction": 0 } }`. Una entrada por personaje como maximo. |
| story_progress | `{ "world_001_01": ["normal", "hard", "extreme"] }`: las dificultades ya superadas y PAGADAS del nivel. |
| event_progress | `{ "event_sindromes_de_la_pubertad": { "stages": { "evt_sdp_01": { "completed": true, "clears": 3 } }, "rewards_claimed": { "sakuta_mai": true }, "times_completed": 1 } }`. |

Un archivo de una version ANTERIOR se MIGRA: se conserva todo lo que traia y los
campos nuevos toman su valor por defecto. Solo se ignora un archivo de una version
DESCONOCIDA (mayor que `GameState.SAVE_VERSION`), que es el que no sabemos leer.
Un guardado v1 o v2 nunca pierde roster, niveles, rarezas, duplicados, equipo,
monedas, gemas, stages, misiones ni contadores: solo estrena esos cuatro campos
vacios, que significan "no tiene objetos", "ningun personaje tiene mutacion",
"no ha jugado la historia" y "no ha jugado los eventos".

## Como ampliar

- Personaje nuevo: copia un JSON, cambia id, stats, categorias, pasiva y skills.
- Enemigo nuevo: mismo esquema que un personaje, en `data/enemies/`. Anadirlo a
  la lista `enemies` de un stage es todo lo necesario; con dos o mas, la pantalla
  de combate entra sola en modo de varios rivales y la seleccion de objetivo.
- Stage nuevo: copia un JSON en `data/stages/`. Su posicion en la cadena de
  desbloqueo la fija su id, y la pantalla de seleccion se construye sola.
- Mision nueva: copia un JSON en `data/missions/` apuntando a un contador global.
- Link nuevo: crea `data/links/<id>.json` y escribelo en el campo `links` de los
  personajes que lo compartan. Con dos en el equipo ya se activa. Ningun script.
- Categoria nueva: crea `data/categories/<id>.json` y usalo en el campo
  `categories` de los personajes. Si te equivocas de id, DB lo avisa al arrancar.
- Ruta de evolucion nueva (R->SR, SR->SSR, UR->LR...): una entrada mas en
  `routes` de `data/evolution/rules.json`. El bloque `evolution` del personaje ya
  esta listo para usarla; no hay ninguna tabla en el codigo.
- Banner nuevo: crea `data/banners/<id>.json`. Aparece solo en la lista de
  banners (`DB.all_banners()`), igual que un stage aparece solo en la suya.
- Objeto de tienda nuevo: crea `data/shop/<id>.json` y elige que entrega en
  `grant`. Una tienda nueva que lea `DB.all_shop_items()` se construye sola.
- **Objeto nuevo**: crea `data/items/<id>.json` (y su PNG en `art/items/<id>.png`).
  Aparece solo en el inventario y en `DB.all_items()`; lo que suelta un stage, un
  evento o lo que pide una evolucion se escribe en SU JSON, no en el codigo.
- **Mundo nuevo**: crea `data/worlds/world_00N.json` con sus niveles. Aparece solo
  en `DB.all_worlds()` y en el mapa; su desbloqueo sale de su bloque `unlock`.
- **Nivel nuevo**: una entrada mas en el `levels` de su mundo, con su `position`,
  su `next` y sus tres dificultades. Nada mas.
- **Evento nuevo**: crea `data/events/<id>.json` con sus stages, sus enemigos,
  sus objetos y la unidad que entrega. Se construye solo en `DB.all_events()`.
- **Mutacion nueva (rango o efecto)**: una linea en `ranks` o en `effects` de
  `data/mutations/config.json`. Ningun porcentaje vive en el codigo.
- **Dialogo nuevo**: crea `data/dialogues/<id>.json` y escribelo en el campo
  `dialogue` de un nivel o de un stage del evento.
- **Evolucion especial nueva**: una entrada mas en `routes` de
  `data/evolutions/special.json`, con su `from`, su `to`, su coste y sus objetos.
  No hay ninguna rama del tipo "si el personaje es sakuta".
- **Dupe**: cambiar un bonus o un coste es editar `data/dupes/rules.json`. Un nivel
  nuevo es subir `max_level` y anadir su fila en `levels` y su coste en
  `copies_per_level`. DB avisa al arrancar si las longitudes no cuadran.
- Contador nuevo: una linea en `GameState.DEFAULT_COUNTERS`; se guarda solo.
- Tipo o rol nuevo: se anade al esquema de datos y a la tabla de ventajas de
  `core/battle_math.gd` si debe afectar al dano.
- Efecto nuevo: un caso mas en el match de `core/effect_engine.gd`. Una sola vez.
