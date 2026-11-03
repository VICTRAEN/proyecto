# v17 / X.2 - Objetos equipables

## Datos (todo editable sin tocar codigo)
- `data/equipment/<id>.json` (30 objetos): nombre, anime, rareza FIJA (N/R/SR/SSR/UR/LR), descripcion, `passive` (texto visible), `rules` (efectos reales), `icon`, `obtain` {banner, event}.
- `rules` usa el MISMO formato que pasivas y links (trigger static / battle_start / turn_start / on_hit / on_attack / on_crit / on_special / on_dodge / on_kill / low_hp, `chance`, `once`, `threshold`, `effects`). Cambiar rareza, numeros, probabilidades o textos = editar el JSON.
- `data/equipment_banners/banner_objetos.json`: banner de objetos (tasas por rareza, coste, destacados opcionales).
- `art/equipment/<id>.png`: un icono placeholder propio por objeto (+ README). Sustituir el PNG basta.
- Reparto: LR 1, UR 4, SSR 9, SR 7, R 5, N 4.

## Logica (`core/equipment.gd`, sin duplicar sistemas)
- Estado guardado (aditivo): `equipment.owned {id: n}` y `equipment.equipped {personaje: id}`. Guardados anteriores cargan sin perder nada.
- Equipar: valida propiedad, copias disponibles y que dos companeros del mismo equipo (party o torre) no lleven el mismo objeto; sustituir y retirar.
- Combate: el `BattleManager` monta el objeto en cada ALIADO (y reservas) al empezar la batalla: mods `static` por `StatBlock` con origen `equip:*` y reglas por disparador en `CombatUnit.equipment_rules`. Nada se guarda ni se acumula entre batallas, cambios de equipo o recargas. Las stats base no se tocan.
- Obtencion: banner de objetos (x1 20 gemas / x10 180), recompensas (`"equipment": {id: n}` en `Rewards`) y drops raros de evento (`{"equipment": id, "chance": 0.1}`; Traje de conejita en el stage 3 de Sindromes de la Pubertad).

## Pantalla OBJETOS (menu principal)
Icono, nombre, rareza, descripcion y pasiva de cada objeto; quien lo lleva; EQUIPAR / RETIRAR; invocar objetos.

## Rueda de la Adaptabilidad (LR)
- Cada golpe recibido: +10% de reduccion de dano, maximo 4 acumulaciones (40%), sumada a la base.
- CRITICO +30 puntos.
- Al empezar su turno: 5% de curar un 40% de la vida max.
- Un golpe cuenta una vez por accion y victima; los esquivados no cuentan.

## Efectos por objeto
Ver el campo `passive.description` de cada JSON (se ve tambien en la pantalla).

## Pruebas
- DBG29 (`--dbg29`): 95 comprobaciones. DBG17-28 y `--diag` sin errores.
