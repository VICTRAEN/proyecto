# Anime Battle v10 — cambios

- **Combate: AUTO y velocidad x1/x2.** Dos botones bajo el numero de ronda. AUTO elige por ti
  (ultimate > especial > basico) y se puede apagar en cualquier momento; empieza apagado en cada
  batalla. x1/x2 cambia el ajuste de velocidad (se guarda) y se aplica EN el combate en curso.
- **Fallo corregido:** con velocidad rapida, la espera de los enemigos y la pausa entre turnos no se
  acortaban (solo algunas pausas). Ahora todas las pausas siguen el ajuste.
- **Equipo: selector de ORDEN** (Rareza / Nivel / Nombre / Tipo) en la lista de personajes.
- **Guardado seguro:** se escribe un temporal y se conserva `save.json.bak`; si el guardado
  principal se corta o se rompe, se recupera la copia anterior en vez de perder el progreso.
- **Prueba corregida:** una comprobacion de DBG19 sobre la Leader Skill del duo no comprobaba nada
  (siempre daba OK); ahora lee el dato real.
- Pruebas nuevas: `--dbg22` (30 comprobaciones).
