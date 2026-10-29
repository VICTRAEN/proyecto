# Anime Battle v12 - Combate y sinergias

Base: v11 (estable). Godot 4.7 / GDScript. Sin transformaciones, sin cambiar las
reglas fijas (equipo de 4, torre 5 = 3 activos + 2 reserva, Leader Skill solo del
puesto 1, mutacion 150 con confirmacion, gacha 15% SSR/tirada, reglas F2P de Sakuta/Mai).
Los 65 personajes, sus ids y los guardados antiguos se conservan.

## 1. Auditoria de lo que habia (antes de tocar nada)
- Pasivas: solo 21 firmas distintas y 2 disparadores (inicio de combate / turno): casi
  todo era "+X% a una stat". Los 13 links daban un unico bonus plano a partir de 2 portadores.
- Habilidades: casi todas "dano + un buff/debuff"; sin multigolpe, perforacion, robo de vida,
  escudos, dano periodico, limpieza ni control de SP.
- Se reutilizo todo lo existente: `StatBlock` sigue siendo el unico sitio que calcula stats,
  `EffectEngine` el unico que interpreta efectos, `BattleMath` el unico que calcula dano.
  No se creo un sistema paralelo: se ampliaron esos tres.

## 2. Motor de combate (nuevo vocabulario)
- Efectos: shield, periodic (sangrado/quemadura/veneno/regeneracion), cleanse, dispel, sp_drain, undying.
- Estado `taunt` (provocar), stat_mod acumulable (`stacks_max`).
- Estadisticas de combate: dmg_dealt, dmg_taken, dmg_reduction, pierce, lifesteal, crit_dmg.
- Habilidades: hits, pierce, lifesteal, recoil, sp_refund y `bonus` condicional (ejecutar, aprovechar debuffs...).
- Disparadores: 11 (antes 2): battle_start, round_start, turn_start, on_attack, on_special, on_hit,
  on_crit, on_kill, on_dodge, on_ally_down, low_hp; con chance, once, cooldown, threshold y condicion.
- Objetivos y ~20 condiciones nuevas. Ver `data/SCHEMA.md`.
- Las descripciones que lee el jugador se GENERAN desde los datos, no se escriben a mano.

## 3. Pasivas y habilidades rediseñadas
- 65 personajes con kit nuevo: mas de 100 firmas de pasiva distintas (antes 21) y 11 disparadores usados.
- Habilidades diferenciadas: multigolpe, perforacion, robo de vida, ejecucion, DoT, stun, drenaje de SP,
  escudos, limpieza, retroceso.
- Los enemigos/jefes conservan la pasiva v11 del personaje en el que se basan (la dificultad del contenido
  no cambia por la pasiva) y usan las habilidades nuevas.

## 4. Links por niveles (13 links)
- Niveles 2 / 3 / 4 portadores. Cada regla dice quien la recibe (portadores, equipo o primer portador)
  y cuando se dispara. El bonus plano antiguo sigue como regla "base" del nivel 2.
- Las reglas de cada link usan disparadores y efectos distintos en vez de repetir "+X% a una stat".
- La ficha (pestaña LINKS) muestra nivel alcanzado, reglas, condiciones y A QUIEN benefician; dentro del
  combate el mismo informe esta bajo demanda en la ficha de la unidad (no en la pantalla de combate).
- Los links se basan solo en los datos de `links` que ya tenia cada personaje: no se inventaron relaciones.
  No existen datos de serie/anime, asi que no hay sinergias por serie.

## 5. Equipos guardados, favoritos y autoconfiguracion
- Hasta 20 equipos guardados: guardar, elegir, editar (cargar y ACTUALIZAR), duplicar, renombrar, borrar (2 pasos).
- Ventana EQUIPOS en: pantalla EQUIPO, torre (5 puestos), y boton EQUIPO antes de combatir en historia y eventos.
  Cada equipo muestra si falta alguien o si no vale para el contenido (p. ej. evento que pide un personaje).
- Si falta un personaje NO se cambia el equipo activo y se dice quien falta; solo "USAR IGUAL (con huecos)" lo aplica.
  El equipo guardado nunca se modifica en silencio.
- Favoritos: marca en la pantalla EQUIPO; un favorito no se consume en una evolucion especial. La evolucion avisa
  de los equipos guardados y estos siguen al personaje nuevo.
- AUTO: propone equipo segun requisitos de la fase (personaje obligatorio, 1 VS 1, tamaño), estadisticas, links,
  roles, ventaja de tipo y lider. Muestra la propuesta con sus motivos y solo la aplica al confirmar; despues se puede cambiar.

## 6. Interfaz de combate
- Sin cambios en la pantalla de combate (escenario y sprites siguen siendo lo principal). Efectos activos,
  escudos, DoT, provocacion y sinergias aparecen en la ficha de la unidad, bajo demanda.

## 7. Pruebas (copia limpia, Godot headless)
| Suite | Resultado |
|---|---|
| DBG24 (nueva: motor, kits, links, equipos guardados, favoritos, AUTO, pantallas) | 104 / 104 |
| DBG15, 17 (+write/read), 18, 19, 20, 21, 22, 23 | 0 fallos |
- Se detecto y corrigio una regresion real: la ventana de mutacion listaba 12 filas de stats (se colaron las nuevas).
- Se detecto y corrigio un error con equipos guardados mal formados en un guardado corrupto.
- Simulacion de balance (80 partidas/nivel, mismos equipos): ningun personaje roto; dispersion por personaje
  similar a v11 (desv. tip. 8.9 vs 9.2).
  | | v11 | v12 |
  |---|---|---|
  | Victorias totales nivel 1 | 56.6% | 66.6% |
  | Victorias totales nivel 10 | 90.3% | 91.6% |
  | Torre nivel 1 | 3.8% | 7.5% |
  | Torre nivel 10 (solo medido en v12) | - | 67.5% |
  En nivel 1 el contenido (vigias, warden, sdp) sale mas facil que en v11 (p. ej. sdp 30% -> 62.5%). No se ha
  reequilibrado: queda como decision tuya.

## 8. Problemas pendientes / limites honestos
- Las pantallas se probaron en Godot headless (construccion y logica), NO en un movil real ni con capturas.
  Conviene revisar a ojo la ventana EQUIPOS y los botones nuevos en pantalla pequeña.
- Equipos guardados de torre: guardar/elegir/AUTO funcionan; la torre no avisa de requisitos de piso (no tiene).
- AUTO de torre no mira los enemigos del piso (solo estadisticas, links y roles).
- El favorito solo protege frente a evoluciones especiales (es lo unico que consume personajes hoy).
- Quedan: aviso ObjectDB al salir, fondos provisionales, SFX provisionales, icono del duo UR.
- La vida no se rellena tras bonus de link/lider (comportamiento heredado de v11, se mantiene).
- sakuta_mai_lr / duo: pasivas rediseñadas, definitivas sin cambios.
