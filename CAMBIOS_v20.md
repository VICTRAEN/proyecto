# v20 / X.6 - Mecanica de DOMINIO

- Boton circular DOMINIO (segundo boton, junto a TRANSFORMAR) en el turno del aliado que tenga `domain` en su JSON. Hoy NINGUN personaje lo tiene.
- Al abrirlo: destello, banner EXPANSION DE DOMINIO, cambia el FONDO del combate (PNG tuyo) y el titulo muestra el dominio activo.
- Bonus y penalizaciones por categoria (`categories`), por `ids`, por `types` o a todos, sobre aliados, rivales o ambos; multiplicadores o mods sueltos.
- Un solo dominio activo a la vez y una expansion por equipo y combate. Dura hasta que cae el lanzador (o `duration_rounds`). Al acabar vuelven fondo y estadisticas. Las reservas que entran lo reciben.
- Opcional: `cost` de SP y `attack` que acompana a la expansion. Compatible con transformaciones (se acumulan).
- Fondo: `art/backgrounds/domain_<id>.png` o `"background"` con ruta completa; sin PNG, fondo rojo provisional.
- Diagnostico (`--diag`) avisa de dominios mal definidos (categoria inexistente, falta PNG).
- Documentado en data/SCHEMA.md ("Bloque de dominio") y art/backgrounds/README.md.
- Pruebas: `--dbg32` (47 comprobaciones, definicion inyectada solo en memoria). dbg17-32 y diag en verde.
- Test dbg30 (Boss Rush, desgaste) era inestable por azar: ya no falla si el jefe cae en 1-2 rondas sin tocar al equipo.
