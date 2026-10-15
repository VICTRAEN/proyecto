extends Node

## AJUSTES DEL JUGADOR (autoload GameSettings).
##
## Son preferencias de este dispositivo, no progreso de la partida: viven en su
## propio archivo (user://settings.json) y NO tocan el guardado (user://save.json),
## asi que borrar uno no afecta al otro.
##
## Las opciones estan aqui, una sola vez, con su valor por defecto:
##
##   AUDIO         music_volume, sfx_volume, ui_volume        0.0 - 1.0
##   COMBATE       battle_speed, anim_speed                   normal | fast
##   INTERFAZ      text_size                                  normal | large
##                 show_damage, show_advantage                true | false
##   ACCESIBILIDAD reduce_motion                              true | false
##
## Quien necesite un ajuste lo pregunta con volume() / choice() / flag() o con los
## atajos de abajo. Cuando algo cambia se emite `changed(key)` (el audio lo usa
## para actualizar el volumen al instante). Un archivo con claves desconocidas,
## valores raros o roto NUNCA da error: se usan los valores por defecto.

signal changed(key: String)

const PATH := "user://settings.json"
const VERSION := 1

const DEFAULTS := {
	"music_volume": 0.8,
	"sfx_volume": 0.8,
	"ui_volume": 0.8,
	"battle_speed": "normal",
	"anim_speed": "normal",
	"text_size": "normal",
	"show_damage": true,
	"show_advantage": true,
	"reduce_motion": false,
}

## Opciones de las claves de texto. La primera es la de por defecto.
const CHOICES := {
	"battle_speed": ["normal", "fast"],
	"anim_speed": ["normal", "fast"],
	"text_size": ["normal", "large"],
}

## Cuanto mas rapido va cada eleccion (1.0 = tal cual).
const SPEED_FACTOR := {
	"normal": 1.0,
	"fast": 1.75,
}

## Escala de toda la interfaz. "large" agranda texto y controles a la vez: el
## juego usa contenedores y anclas, asi que se recoloca solo en el espacio que queda.
const UI_SCALE := {
	"normal": 1.0,
	"large": 1.2,
}

var values: Dictionary = {}


func _ready() -> void:
	load_settings()
	apply_ui_scale()


## --- Lectura ----------------------------------------------------------------

## Valor tal cual esta guardado (numero, texto o si/no) de cualquier ajuste.
func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func volume(key: String) -> float:
	return clampf(float(values.get(key, DEFAULTS.get(key, 1.0))), 0.0, 1.0)


func choice(key: String) -> String:
	return String(values.get(key, DEFAULTS.get(key, "")))


func flag(key: String) -> bool:
	return bool(values.get(key, DEFAULTS.get(key, false)))


## Multiplicador de las PAUSAS entre turnos del combate: 1.0 normal, menos con
## velocidad rapida (esperar menos).
func battle_pause_scale() -> float:
	return 1.0 / float(SPEED_FACTOR.get(choice("battle_speed"), 1.0))


## Velocidad de las animaciones del combate: 1.0 normal, mas con velocidad rapida.
## Con animaciones reducidas tambien se aceleran, para que duren lo minimo.
func anim_speed_scale() -> float:
	var speed := float(SPEED_FACTOR.get(choice("anim_speed"), 1.0))
	if reduce_motion():
		speed = maxf(speed, 2.0)
	return speed


func reduce_motion() -> bool:
	return flag("reduce_motion")


func show_damage() -> bool:
	return flag("show_damage")


func show_advantage() -> bool:
	return flag("show_advantage")


## --- Escritura --------------------------------------------------------------

## Cambia un ajuste. Con persist=false no escribe el archivo (un slider arrastrado
## cambia muchas veces por segundo: la pantalla llama a save_settings() al soltar).
func set_value(key: String, value: Variant, persist: bool = true) -> void:
	if not DEFAULTS.has(key) or not _is_valid(key, value):
		return
	var clean: Variant = _sanitize(key, value)
	var was: Variant = values.get(key, DEFAULTS[key])
	values[key] = clean
	if key == "text_size":
		apply_ui_scale()
	if was != clean:
		changed.emit(key)
	if persist:
		save_settings()


## Escribe user://settings.json. Si no se puede escribir, se avisa en el log y el
## juego sigue con los valores en memoria.
func save_settings() -> void:
	var payload := { "version": VERSION }
	for key in DEFAULTS.keys():
		payload[key] = values.get(key, DEFAULTS[key])
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("GameSettings: no se pudo escribir %s." % PATH)
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()


## Lee user://settings.json. Cualquier problema deja los valores por defecto.
func load_settings() -> void:
	values = DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary):
		push_warning("GameSettings: %s no es valido; se usan los ajustes por defecto." % PATH)
		return
	var stored: Dictionary = parsed
	for key in DEFAULTS.keys():
		if stored.has(key):
			values[key] = _sanitize(String(key), stored[key])


## Vuelve a los valores por defecto y los guarda.
func reset_to_defaults() -> void:
	for key in DEFAULTS.keys():
		set_value(String(key), DEFAULTS[key], false)
	save_settings()


## Aplica la escala de interfaz a la ventana principal.
func apply_ui_scale() -> void:
	var window := get_tree().root
	if window == null:
		return
	window.content_scale_factor = float(UI_SCALE.get(choice("text_size"), 1.0))


## Un valor es aceptable para esa clave? (numero para un volumen, si/no para un
## interruptor, una de las opciones para un texto). Uno que no lo es se ignora.
func _is_valid(key: String, value: Variant) -> bool:
	var default_value: Variant = DEFAULTS.get(key)
	if default_value is float:
		return value is float or value is int
	if default_value is bool:
		return value is bool
	if default_value is String:
		var options: Array = CHOICES.get(key, [])
		return value is String and options.has(String(value))
	return false


## Deja un valor en el tipo y rango que le toca a esa clave; lo que no encaja
## vuelve al valor por defecto.
func _sanitize(key: String, value: Variant) -> Variant:
	var default_value: Variant = DEFAULTS.get(key)
	if default_value is float:
		if value is float or value is int:
			return clampf(float(value), 0.0, 1.0)
		return default_value
	if default_value is bool:
		if value is bool:
			return value
		return default_value
	if default_value is String:
		var options: Array = CHOICES.get(key, [])
		if value is String and options.has(String(value)):
			return String(value)
		return default_value
	return default_value
