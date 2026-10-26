extends SceneTree

## Regenera res://ui/theme.tres a partir de VI (ui/theme_factory.gd).
##   godot --headless --path . --script res://tools/build_theme.gd
## Conserva el UID del tema (lo referencian las escenas) para no generar avisos.

const THEME_PATH := "res://ui/theme.tres"
const THEME_UID := "uid://ctdecel0skgic"


func _init() -> void:
	var factory = load("res://ui/theme_factory.gd")
	var theme: Theme = factory.build()
	var err := ResourceSaver.save(theme, THEME_PATH)
	if err == OK:
		var text := FileAccess.get_file_as_string(THEME_PATH)
		if not text.contains("uid=\"%s\"" % THEME_UID):
			var first_end := text.find("\n")
			var first := text.substr(0, first_end)
			if first.begins_with("[gd_resource") and not first.contains("uid="):
				first = first.replace("format=3]", "format=3 uid=\"%s\"]" % THEME_UID)
				var f := FileAccess.open(THEME_PATH, FileAccess.WRITE)
				f.store_string(first + text.substr(first_end))
				f.close()
	print("[THEME] guardado: ", error_string(err))
	quit(0 if err == OK else 1)
