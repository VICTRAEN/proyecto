# Anime Battle v11 — cambios

1. **Tema de David + Lucy al doble de volumen** (+6 dB) solo para esa pista (`SLOT_GAIN_DB` en `audio/audio.gd`); el resto de la musica no cambia y el ajuste de volumen sigue mandando.
2. **Combate despejado:** tarjetas en modo minimo (sprite sin marco + barra de vida). Orden de ataque, registro y barra grande quedan ocultos tras el boton **INFO**; tocar una tarjeta abre su ficha. La linea de turno muestra quien actua y su SP. AUTO, x1/x2 y los botones de accion se mantienen.
3. **Orden aleatorio del equipo:** cada ronda se sortea QUIEN de tus personajes ocupa cada turno de tu bando; la velocidad sigue repartiendo turnos entre bandos y cada aliado vivo actua una vez.
4. **Enemigos:** vigia_alfa=Itadori, vigia_beta=Reze, void_warden=Makima, torre_guardian=Asta, torre_verdugo=Denji, torre_avatar=Goku (ids y estadisticas originales; solo cambia la identidad: nombre, tipo, rareza, arte, pasiva y habilidades). Todos tienen sprite real.
5. **Copias:** nuevo libro de copias (`copy_ledger`): total = disponibles + usadas (la unidad cuenta como 1). 12 copias -> total 12, disponibles 11, usadas 1. Visible en Coleccion (`11/12`, tooltip), ficha > DUPES e Inventario > COPIAS.
6. **Invocaciones:** al terminar se abre directamente el resumen (sin la pantalla VER RESUMEN / VOLVER AL BANNER).
7. **Evolucion** y 8. **Mutaciones:** buscador por nombre y filtros (LISTOS / FALTAN / SSR>UR / UR>LR; SIN / CON MUTACION / RANGO), contador y orden util. Los que cumplen requisitos van primero; los demas, atenuados con el motivo.
9. **Sprites:** en combate van con los pies en la misma linea de suelo, sin marco; el retrato sigue encuadrando sin deformar ni recortar.

Pruebas nuevas: `--dbg23` (50 comprobaciones). DBG19 y DBG22/E ajustados a los cambios pedidos (resumen directo, volumen del tema).
