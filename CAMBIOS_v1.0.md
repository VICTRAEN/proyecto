# ANIME BATTLE 1.0 (version oficial)
- Icono del juego: `icon.png` (1024) e `icon.ico` (Windows) a partir de la imagen aportada; `project.godot` -> `config/icon`.
- `config/version="1.0.0"`. Contenido = v15 (sin cambios de juego).
- Builds de escritorio listos para jugar sin instalar nada (Godot embebido): Windows x86_64 y Linux x86_64.
  `export_presets.cfg` (excluye dev/, scenes/debug/, tools/, *.md): el diagnostico y el panel de desarrollo NO existen en el build.
- Icono en el .exe: Godot no puede incrustarlo desde Linux, asi que se parchea la plantilla con `tools/patch_win_icon.py` (LIEF).
- Probado: el build de Linux arranca sin editor, carga los datos y no incluye `dev/`. El .exe NO se ha podido ejecutar aqui (no hay Windows/Wine):
  se entrega ademas `AnimeBattle_sin_icono.exe` (exportacion estandar) por si el parcheado diera problemas.
- No hay build para Android/iOS/macOS (requieren plantillas, firma y SDK). El .exe no esta firmado: SmartScreen puede avisar.

## Android (APK arm64-v8a)
- `releases/AnimeBattle_1.0.apk` (paquete `com.victraen.animebattle`, v1.0.0 codigo 1, minSdk 24, vertical, sin permisos).
- Preset "Android" en `export_presets.cfg`; iconos en `android_icons/`; ETC2/ASTC activado; orientacion corregida (`window/handheld/orientation=1`:
  estaba como texto y Android la leia como horizontal).
- Sin el SDK oficial (bloqueado en este entorno) se firma con `tools/apksigner_v2.py` (firma APK v2, verificada con apksigtool).
- Firmado con una clave propia (`animebattle-release.keystore`, no esta en el repo). Guardala: sin ella no podras publicar actualizaciones
  que se instalen encima de esta version.
- NO probado en un movil ni emulador. Renderer "mobile" (Vulkan): necesita un movil con Vulkan (practicamente cualquiera reciente).
- Para instalarlo: permitir "instalar apps de origen desconocido". No es AAB, asi que no sirve tal cual para Google Play.
