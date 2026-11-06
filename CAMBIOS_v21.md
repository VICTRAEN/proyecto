# v21 - Primera unidad con transformacion: Asta (Union Demoniaca: Asta & Liebe)

- Asta (SSR, evoluciona a UR) tiene la transformacion `asta_union_demoniaca`. Solo existe en su forma UR/LR (`min_rarity`, campo nuevo y opcional del sistema); siendo SSR no se transforma y no ve el boton.
- Al activarla (boton circular en su turno): destello, banner y ataque de activacion "Pacto de Liebe: Union Demoniaca" (230% a todos los rivales, pierden efectos positivos y DEF -25% 2 turnos). Cambia nombre, estadisticas (x1.5, +15 pts critico, +10% dano), habilidades (Tajo Demoniaco / Divisor Negro) y pasivas (Anti-magia desatada, Voluntad de Liebe, Nunca me rendire). Dura hasta que Asta muere; al acabar el combate vuelve a su estado UR.
- Las reglas generales no cambian: 1 transformacion por equipo y combate; ningun otro personaje puede transformarse.
- Revertir ahora tambien devuelve las cargas de "no morir" y el estado de las pasivas de la forma.
- Ficha de personaje: bloque TRANSFORMACION cuando la forma actual la tiene. Diagnostico valida transformaciones.
- ARTE (lo pone el usuario): `art/characters/asta/ur/{front,back,icon}.png` (forma UR) y `art/characters/asta/transform/{front,back,icon}.png` (transformado). Sin ellos se ve el arte base (con tinte rosado en la forma transformada).
- Pruebas: `--dbg33` (42 comprobaciones con los datos reales); dbg31 actualizada (Asta es el unico con transformacion).
