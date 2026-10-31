extends Node

## Sonido del juego, PREPARADO para que anadir audio sea dejar archivos.
##
## Todavia no hay banda sonora: este nodo existe para que el dia que la haya no
## haya que tocar ningun script. Busca los archivos por su NOMBRE dentro de la
## carpeta de su categoria:
##
##   res://audio/music/menu.ogg          -> musica de menus (en bucle)
##   res://audio/music/battle.ogg        -> musica de combate (en bucle)
##   res://audio/music/history.ogg       -> musica de la historia
##   res://audio/music/events.ogg        -> musica de eventos
##   res://audio/music/results.ogg       -> musica de resultados
##   res://audio/music/boss.ogg          -> musica de jefe (opcional; si falta suena la de combate)
##   res://audio/music/david_lucy_theme.ogg -> tema del duo David & Lucy (lo aportas tu)
##   res://audio/ui/click.ogg            -> sonidos de interfaz
##   res://audio/combat/attack.ogg       -> sonidos de combate
##   res://audio/progression/summon.ogg  -> sonidos de progresion
##
## Valen .ogg, .wav y .mp3. Ver res://audio/README.md.
##
## SI FALTA UN ARCHIVO NO PASA NADA. El juego arranca y se queda en silencio en
## ese sonido, sin dar ningun error: asi se puede desarrollar y probar todo el
## sistema antes de tener el audio definitivo. missing_events() dice que falta.
##
## Los botones se enganchan SOLO: al arrancar se escucha el arbol de nodos y
## cualquier Button que aparezca en el juego queda conectado al sonido de boton.
## Asi no hay que tocar ninguna pantalla.

## Catalogo COMPLETO de sonidos del juego, por categoria. Es la unica lista: una
## pantalla pide un nombre de aqui y missing_events() sabe que falta.
##
## Anadir un sonido nuevo es anadir su nombre a esta tabla y dejar el archivo en
## su carpeta. No hay que tocar ninguna pantalla.
const CATALOG := {
	"music": ["menu", "battle", "history", "events", "results", "david_lucy_theme", "boss"],
	"ui": ["click", "select", "back", "open", "close", "equip", "remove", "claim", "tab", "buy"],
	"combat": ["attack", "special", "critical", "heal", "victory", "defeat"],
	"progression": ["summon", "evolution", "level_up", "mutation"],
}

const DIR := "res://audio"
const EXTS := [".ogg", ".wav", ".mp3"]

## Nombre del archivo que suena al pulsar cualquier boton.
const BUTTON_SFX := "click"
## Volumen general. 1.0 = tal cual viene el archivo.
const SFX_VOLUME := -6.0
const MUSIC_VOLUME := -12.0
## Ganancia extra por pista (dB). El tema del duo David & Lucy suena al DOBLE de
## volumen que el resto de la musica (+6 dB ~ x2 de amplitud); las demas no cambian.
const SLOT_GAIN_DB := { "david_lucy_theme": 6.0 }

## Categoria de un sonido, o "" si no esta en el catalogo.
var _category_of: Dictionary = {}

var _music: AudioStreamPlayer = null
var _music_slot := ""
## Ruta del archivo de musica que esta sonando, o "" si no hay ninguno. Es lo que
## permite comprobar desde fuera que pista esta puesta sin tocar el reproductor.
var _music_path := ""

## --- Transiciones (v15) ---------------------------------------------------------
## Un SOLO reproductor de musica: las pistas nunca se solapan. Al cambiar de pista la
## actual baja (MUSIC_FADE_OUT), se cambia el archivo y la nueva sube (MUSIC_FADE_IN). Si
## llega otra peticion durante el fundido gana la ultima (no hay reinicios de pistas que
## ya no tocan) y pedir la misma pista que ya suena o que esta entrando no hace nada.
## En headless (pruebas, sin salida de audio) los fundidos se desactivan y el cambio es
## instantaneo; las pruebas de v15 los activan a proposito.
const MUSIC_FADE_OUT := 0.30
const MUSIC_FADE_IN := 0.50
var fades_enabled := DisplayServer.get_name() != "headless"
var _fade_tween: Tween = null
## Pista que espera a que termine el fundido de salida ("" = ninguna).
var _pending_slot := ""
## Cuantas veces se ha puesto un archivo de musica en el reproductor (para comprobar
## que pedir la misma pista no la reinicia).
var music_starts := 0
## Bajada temporal de la musica (dB, <= 0) para que se oigan las intros y los jingles.
var _duck_db := 0.0
var _duck_tween: Tween = null
## Efectos: hueco minimo entre el mismo sonido y tope de reproductores simultaneos.
const SFX_MIN_GAP_MS := 45
const SFX_MAX_PLAYERS := 14
var _sfx_last_ms: Dictionary = {}


func _ready() -> void:
	# Indice inverso nombre -> categoria, montado una vez desde el catalogo.
	for category in CATALOG.keys():
		for event_name in CATALOG[category]:
			_category_of[String(event_name)] = String(category)
	# Cada boton que aparezca en el juego suena al pulsarlo, sin que ninguna
	# pantalla tenga que pedirlo.
	get_tree().node_added.connect(_on_node_added)
	if GameSettings != null and not GameSettings.changed.is_connected(_on_setting_changed):
		GameSettings.changed.connect(_on_setting_changed)
	_wire_existing(get_tree().root)


## Volumen en dB a partir del ajuste del jugador (0..1). 0 = silencio total.
static func _db_for(setting: String, base_db: float) -> float:
	var v := 1.0
	if GameSettings != null:
		v = GameSettings.volume(setting)
	if v <= 0.001:
		return -80.0
	return base_db + linear_to_db(v)


func _on_setting_changed(key: String) -> void:
	if key == "music_volume" and _music != null and _fade_tween == null:
		_music.volume_db = _music_db(_music_slot) + _duck_db


## Volumen de una pista de musica: el del ajuste del jugador + su ganancia propia.
static func _music_db(slot: String) -> float:
	var db := _db_for("music_volume", MUSIC_VOLUME)
	if db <= -79.0:
		return db
	return db + float(SLOT_GAIN_DB.get(slot, 0.0))


func _on_node_added(node: Node) -> void:
	if node is Button:
		_wire_button(node)


## Los nodos que ya existian antes de conectar la senal (por ejemplo el boton de
## una escena que se cargo primero) se enganchan aqui.
func _wire_existing(node: Node) -> void:
	if node is Button:
		_wire_button(node)
	for child in node.get_children():
		_wire_existing(child)


func _wire_button(button: Button) -> void:
	if button.pressed.is_connected(play_button):
		return
	button.pressed.connect(play_button)


## --- Catalogo -----------------------------------------------------------------

## Categoria de un sonido ("music", "ui", "combat", "progression"), o "" si ese
## nombre no esta en el catalogo. No mira el disco: es una pregunta sobre datos.
func category_of(slot: String) -> String:
	return String(_category_of.get(String(slot), ""))


## Nombres del catalogo que TODAVIA no tienen archivo, en orden. Es la lista de
## lo que falta por componer, no un error: el juego funciona igual sin ellos.
func missing_events() -> Array:
	var out: Array = []
	for category in CATALOG.keys():
		for event_name in CATALOG[category]:
			if USER_SUPPLIED.has(String(event_name)):
				continue
			if load_stream(String(event_name)) == null:
				out.append(String(event_name))
	return out


## Entradas del catalogo cuyo archivo APORTA EL DESARROLLADOR (no se genera ni se
## incluye): faltar no es un fallo, el juego sigue sin ellas.
## "boss" (v15): musica de jefe OPCIONAL. Sin archivo, los jefes siguen con la de combate.
const USER_SUPPLIED := ["david_lucy_theme", "boss"]


## Entradas aportadas por el usuario que aun no tienen archivo.
func missing_user_supplied() -> Array:
	var out: Array = []
	for event_name in USER_SUPPLIED:
		if load_stream(String(event_name)) == null:
			out.append(String(event_name))
	return out


## Todos los nombres del catalogo, en orden de categoria.
func all_events() -> Array:
	var out: Array = []
	for category in CATALOG.keys():
		for event_name in CATALOG[category]:
			out.append(String(event_name))
	return out


## Sonido generico de boton. Es publico por si una pantalla quiere pedirlo.
func play_button() -> void:
	play(BUTTON_SFX)


## Efecto puntual. Si el archivo no existe todavia, no pasa nada.
func play(slot: String, volume_db: float = SFX_VOLUME) -> void:
	var stream := load_stream(slot)
	if stream == null:
		return
	# Anti-solape (v15): el mismo sonido no se repite en menos de SFX_MIN_GAP_MS y no
	# hay mas de SFX_MAX_PLAYERS efectos a la vez (un combate con muchos golpes no
	# satura el audio ni se come la musica).
	var now_ms := Time.get_ticks_msec()
	if now_ms - int(_sfx_last_ms.get(slot, -100000)) < SFX_MIN_GAP_MS:
		return
	if _count_sfx_players() >= SFX_MAX_PLAYERS:
		return
	_sfx_last_ms[slot] = now_ms
	var player := AudioStreamPlayer.new()
	player.stream = stream
	# El volumen por defecto sigue el ajuste del jugador: sonidos de interfaz con su
	# propio deslizador y el resto de efectos con el de efectos.
	if is_equal_approx(volume_db, SFX_VOLUME):
		player.volume_db = _db_for("ui_volume" if category_of(slot) == "ui" else "sfx_volume", SFX_VOLUME)
	else:
		player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Musica en bucle. Llamar dos veces con el mismo slot no la reinicia, asi que
## una pantalla puede pedirla en cada refresh() sin cortar la cancion.
func play_music(slot: String) -> void:
	# Misma pista: ni se reinicia ni se toca el fundido en curso.
	if slot == _music_slot and not slot.is_empty() and ((_music != null and _music.playing) or _pending_slot == slot):
		return
	var stream := load_stream(slot)
	_music_slot = slot
	_music_path = path_for(slot) if stream != null else ""
	if stream == null:
		_kill_fade()
		_pending_slot = ""
		stop_music()
		return
	if _music == null:
		_music = AudioStreamPlayer.new()
		add_child(_music)
	var switching := fades_enabled and _music.playing and _music.stream != null
	if not switching:
		_kill_fade()
		_pending_slot = ""
		_start_stream(stream, slot)
		if fades_enabled:
			_fade_in()
		return
	# Cambio de pista: bajar la actual y, al terminar, entrar la ultima pedida.
	_pending_slot = slot
	if _fade_tween != null and _fade_tween.is_valid() and _fading_out:
		return   # ya esta bajando: cuando llegue abajo cogera _pending_slot (la ultima)
	_kill_fade()
	_fading_out = true
	_fade_tween = create_tween()
	_fade_tween.tween_property(_music, "volume_db", -60.0, MUSIC_FADE_OUT)
	_fade_tween.tween_callback(_finish_switch)


var _fading_out := false


func _finish_switch() -> void:
	_fading_out = false
	_fade_tween = null
	var wanted := _pending_slot
	_pending_slot = ""
	if wanted.is_empty() or wanted != _music_slot:
		# Nadie pidio otra pista durante el fundido (fade_out_music): se corta del todo.
		if _music != null and _music_slot.is_empty():
			_music.stop()
			_music.stream = null
		return
	var stream := load_stream(wanted)
	if stream == null or _music == null:
		return
	_start_stream(stream, wanted)
	_fade_in()


func _fade_in() -> void:
	if _music == null:
		return
	var target := _music_db(_music_slot) + _duck_db
	_music.volume_db = -60.0 if target > -60.0 else target
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_music, "volume_db", target, MUSIC_FADE_IN)
	_fade_tween.tween_callback(func():
		_fade_tween = null
		_apply_duck(0.2))


func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	_fading_out = false


## Pone el archivo en el reproductor unico, con bucle, al volumen de su pista.
func _start_stream(stream: AudioStream, slot: String) -> void:
	music_starts += 1
	_music.stream = stream
	_music.volume_db = _music_db(slot) + _duck_db
	# Bucle: si el archivo es un ogg sin metadatos de loop, se le pone aqui.
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		# Sin loop_end el bucle de un WAV sin metadatos no se cierra: se fija al final.
		if stream.loop_end <= 0:
			var bytes_per_sample := (2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if stream.stereo else 1)
			stream.loop_end = stream.data.size() / bytes_per_sample
	elif stream is AudioStreamMP3:
		stream.loop = true
	_music.play()


func _count_sfx_players() -> int:
	var n := 0
	for child in get_children():
		if child is AudioStreamPlayer and child != _music and (child as AudioStreamPlayer).playing:
			n += 1
	return n


## Musica de un combate: la de jefe si hay archivo y el combate tiene jefe; si no, la de
## combate de siempre.
func battle_slot(has_boss: bool) -> String:
	if has_boss and has_stream("boss"):
		return "boss"
	return "battle"


## Baja la musica `db` dB (negativo) durante una intro o un jingle. No cambia de pista.
func duck(db: float = -9.0, seconds: float = 0.25) -> void:
	_duck_db = minf(0.0, db)
	_apply_duck(seconds)


func unduck(seconds: float = 0.45) -> void:
	_duck_db = 0.0
	_apply_duck(seconds)


func is_ducked() -> bool:
	return _duck_db < -0.01


func _apply_duck(seconds: float) -> void:
	if _music == null or not _music.playing or _fade_tween != null:
		return
	var target := _music_db(_music_slot) + _duck_db
	if not fades_enabled:
		_music.volume_db = target
		return
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(_music, "volume_db", target, maxf(0.01, seconds))


## Corta la musica con un fundido corto (la pista deja de contar como puesta YA, asi
## nada vuelve a arrancarla). Sin fundidos equivale a stop_music().
func fade_out_music(seconds: float = 0.35) -> void:
	if not fades_enabled or _music == null or not _music.playing:
		stop_music()
		return
	_music_slot = ""
	_music_path = ""
	_pending_slot = ""
	_kill_fade()
	_fading_out = true
	_fade_tween = create_tween()
	_fade_tween.tween_property(_music, "volume_db", -60.0, maxf(0.01, seconds))
	_fade_tween.tween_callback(_finish_switch)


## --- Musica ESPECIAL (override) ---------------------------------------------------
## Un tema especial (el del duo) se pone por encima de la musica de la pantalla
## mientras dura un momento concreto (la invocacion del duo, o el combate tras su
## ultimate). Mientras hay override, la musica de pantalla NO lo pisa. Si el
## archivo no existe, override_start devuelve false y no cambia nada: el juego sigue
## con su musica habitual. Quien lo pide (owner) es quien lo suelta.
var _override_slot := ""
var _override_owner := ""


## Pone el tema especial. Devuelve true si suena (o ya sonaba) y false si falta.
## Pedirlo dos veces seguidas NO reinicia la cancion ni crea otro reproductor.
func override_start(slot: String, owner_name: String) -> bool:
	if not has_stream(slot):
		return false
	_override_slot = slot
	_override_owner = owner_name
	play_music(slot)
	return true


func override_active() -> bool:
	return not _override_slot.is_empty()


func override_owner() -> String:
	return _override_owner


## Suelta el override. NO elige que suena despues: lo hace quien llama (la pantalla
## pide su musica o los resultados), asi la prioridad la decide el contexto.
func override_clear(owner_name: String = "") -> void:
	if not owner_name.is_empty() and owner_name != _override_owner:
		return
	_override_slot = ""
	_override_owner = ""


func stop_music() -> void:
	_kill_fade()
	_pending_slot = ""
	_duck_db = 0.0
	_music_slot = ""
	_music_path = ""
	if _music != null:
		_music.stop()
		_music.stream = null


## Pista de musica que esta puesta ("" si no hay ninguna). Lo usan las pruebas y
## la pantalla de ajustes para saber que suena sin tocar el reproductor.
func current_music_path() -> String:
	return _music_path


## Hay archivo para ese slot? (util para documentar lo que falta sin romper nada).
static func has_stream(slot: String) -> bool:
	return load_stream(slot) != null


## Ruta del archivo de un slot, o "" si todavia no existe. Solo devuelve rutas que
## se pueden cargar.
static func path_for(slot: String) -> String:
	if String(slot).is_empty():
		return ""
	for candidate in _candidates(String(slot)):
		if ResourceLoader.exists(candidate):
			var res = load(candidate)
			if res is AudioStream:
				return candidate
	return ""


## Carga el archivo del slot, o null si todavia no existe.
static func load_stream(slot: String) -> AudioStream:
	var path := path_for(slot)
	if path.is_empty():
		return null
	var res = load(path)
	return res if res is AudioStream else null


## Donde se busca un sonido, en orden. La carpeta de su categoria es lo normal;
## la raiz de res://audio/ se sigue mirando para no romper los archivos que ya
## estuvieran puestos ahi. La categoria sale del CATALOGO; un nombre que no este
## en el catalogo solo se busca en la raiz.
static func _candidates(slot: String) -> Array:
	var out: Array = []
	var category := ""
	for key in CATALOG.keys():
		if (CATALOG[key] as Array).has(slot):
			category = String(key)
			break
	for ext in EXTS:
		if not category.is_empty():
			out.append("%s/%s/%s%s" % [DIR, category, slot, ext])
		out.append("%s/%s%s" % [DIR, slot, ext])
	return out
