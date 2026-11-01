# CAMBIOS v1.1 - correcciones de rareza, banners, ventanas y Perfil

## Corregido
1. **Nadie nace UR.** Goku, Frieren, Makima y Sukuna nacian UR en su JSON; ahora nacen SSR y evolucionan a UR como el resto
   (su bloque `evolution` ya era la forma UR). UR y LR solo se consiguen evolucionando (Sakuta/Sakuta LR son formas de evolucion).
   - Los banners ya no tienen UR (1 % y 2 %). Se restablece el **15 % de SSR por tirada en todos** (como en las reglas).
   - "Invocacion superior" (25 gemas) mantiene su gracia: Goku, Frieren, Makima y Sukuna con tasa propia del 3 % cada uno (dentro del SSR).
   - La coleccion UR pasa a "Leyendas" (esos cuatro); las colecciones de rareza admiten lista `members` explicita.
2. **"Info del banner" salia vacia**: la ventana se quedaba en 0x0 (esquina) porque `set_anchors_preset` no ajusta los margenes.
   Cambiado a `set_anchors_and_offsets_preset` en todo el proyecto (21 sitios), lo que tambien protege a los demas paneles creados por codigo.
3. Recompensas de cosmetico decian "Ilustracion: Ilustracion: Asta": nombres de cosmetico sin prefijo (lo pone la pantalla).
4. Comparar mostraba categorias como ids ("shonen"); ahora nombres.
5. Tabla de estadisticas de evolucion: cabeceras solapadas y letra diminuta; mas legible.

## Perfil rediseñado
Cabecera con retrato (ilustracion equipada o lider), nivel grande, titulo, barra de XP, tres estadisticas, tarjetas por nivel con
boton, cosmeticos en cuadricula, fuentes >= 22 y fondo oscurecido. Boton de perfil del menu mas grande.

## Diagnostico (dev)
Nuevas reglas: personaje que nace UR/LR (error) y SSR sin bloque `evolution` (aviso).

## Pruebas
DBG27: 252 comprobaciones, 0 fallos (incluye panel de info con tamano real, rareza natural, 300 tiradas por banner, Goku a UR, perfil).
DBG17-26 sin fallos tras adaptar 2 tests (SSR 15 %, Dupes de Frieren). `--diag`: 0 errores. Capturas con xvfb (`--shots-h`).

## Pendiente
- 11 personajes SSR sin bloque `evolution` (no llegan a UR): Ai Hoshino, Arthur, Edward Elric, Geto, Gon, Kaori, Momo, Okarun,
  Reinhard, Rem, Sunraku. Faltan sus pasivas de forma UR (contenido de diseno, no inventado aqui).
- Goku/Frieren/Makima/Sukuna parten ahora de SSR: sus estadisticas base no se tocaron, pero al evolucionar suben x1.25 (balance sin simular).
- Los builds (Windows/Linux/Android) NO se han regenerado con estos cambios.
