# v21 - Asta & Liebe: primera unidad con transformacion (unidad especial de banner)

- DOS unidades: el **Asta normal** (`asta`, SSR -> UR, sin transformacion, como siempre) y la unidad especial de banner **Asta & Liebe** (`asta_liebe`, SSR -> UR, `banner_only`).
- Banner propio **Union Demoniaca** (`banner_asta_liebe`): 15% SSR por tirada, Asta & Liebe destacada con 3% propio, exclusiva de ese banner, sin pity (como el resto de banners sin LR).
- Solo Asta & Liebe tiene transformacion (`min_rarity: UR`: siendo SSR no se transforma). El resto de reglas del sistema no cambian: 1 por equipo y combate, hasta que muere, se revierte al acabar.
- Al activarla: destello, banner y "Pacto de Liebe: Union Demoniaca" (230% a todos los rivales, quitan efectos positivos y DEF -25% 2 turnos); cambian nombre, estadisticas (x1.5, +15 pts critico, +10% dano), habilidades (Tajo Demoniaco / Divisor Negro) y pasivas (Anti-magia desatada, Voluntad de Liebe, Nunca me rendire).
- Revertir devuelve tambien las cargas de "no morir" y el estado de las pasivas de la forma.
- Ficha: bloque TRANSFORMACION cuando la forma actual la tiene. Diagnostico valida transformaciones.
- ARTE (lo pone el usuario): `art/characters/asta_liebe/{front,back,icon}.png`, `.../ur/` y `.../transform/`. Mientras no existan se ve el arte del Asta normal (art_fallback_ids), con tinte rosado en la forma transformada. El arte del Asta normal no se toca.
- Pruebas: `--dbg33` (comprobaciones con datos reales de Asta & Liebe y su banner); dbg31 actualizada.
