# Cinematicas

## Video de invocacion del duo: `david_lucy_summon.ogv`

Ruta exacta: `res://art/cinematics/david_lucy_summon.ogv` (**la aportas tu**; el proyecto no
incluye ni descarga ningun video). Mientras no exista, el juego usa una transicion alternativa
(`ui/duo_fallback_fx.gd`) y continua con el revelado: nunca hay pantalla negra ni error.

### Formato (Godot 4.7)
`VideoStreamPlayer` solo reproduce de serie **Ogg Theora (.ogv)**. MP4/H.264, WebM, MOV... NO.

Conversion con ffmpeg (video vertical pensado para movil, 720x1280):

```
ffmpeg -i tu_video.mp4 -vf "scale=720:1280:force_original_aspect_ratio=decrease,pad=720:1280:(ow-iw)/2:(oh-ih)/2" \
       -c:v libtheora -q:v 7 -an david_lucy_summon.ogv
```

`-an` quita el audio: el video se reproduce **sin sonido** a proposito. La musica la controla el
sistema de audio del juego (tema `david_lucy_theme`), asi que no se superpone nada.
Si tu video ya trae sonido y no lo quitas, el juego igualmente lo silencia (volume_db = -80).
