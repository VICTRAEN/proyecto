# v19 / X.5 - Transformaciones en combate (estilo Mega Evolucion)

- Boton circular TRANSFORMAR (ui/transform_button.gd, dibujado por codigo: rayos giratorios, aro de energia, estrella evolutiva o `icon` propio) en el turno del aliado capaz.
- Al pulsarlo: destello, nombre de la forma, ataque especial de la transformacion y cambio total (sprite, estadisticas, habilidades, pasivas, tipo, roles, ultimate...).
- Dura hasta que el personaje muere o acaba el combate; entonces TODO vuelve al original (incluidos buffs de las pasivas de la forma). No se guarda nada en el save.
- Un solo personaje por equipo y combate, aunque varios puedan; el cupo no se libera si el transformado muere.
- Modo auto: el capaz se transforma en cuanto puede.
- Preparado por datos: `transformations` en el JSON del personaje (ver data/SCHEMA.md). NINGUN personaje tiene ninguna todavia.
- Pruebas: `--dbg31` (48 comprobaciones, con definicion inyectada solo en memoria). dbg17-18, 20-27, 29-31 y diag en verde.
- Nota: dbg19 y dbg28 (gacha/invocar) fallan tambien sin estos cambios (ya ocurre en HEAD); pendiente de revisar.
