extends CanvasLayer
## Gold MartinB window bar (shared look of every MartinB app): logo + name on the left,
## window buttons on the right. Shown on Android, where the game has no window frame;
## on Windows the native title bar already has minimize / maximize / close.
## Set MB_BAR=1 to show it on a desktop build (used by the screenshot test).

const H := 44
const BAR := Color(0.043, 0.039, 0.031)
const GOLD := Color(0.831, 0.678, 0.384)
const INK := Color(0.953, 0.937, 0.902)

var _full_button: Button


static func wanted() -> bool:
	return OS.has_feature("android") or OS.get_environment("MB_BAR") == "1"


func _ready() -> void:
	layer = 100
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = H
	var sb := StyleBoxFlat.new()
	sb.bg_color = BAR
	sb.border_color = Color(GOLD, 0.22)
	sb.border_width_bottom = 1
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -2
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var logo := TextureRect.new()
	logo.texture = load("res://icon.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(24, 24)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(logo)

	var name_label := Label.new()
	name_label.text = "True North Command"
	name_label.add_theme_color_override("font_color", INK)
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	if _can_minimize():
		row.add_child(_button("min", "Réduire", _minimize))
	_full_button = _button("restore" if _is_full() else "max", "Plein écran", _toggle_full)
	row.add_child(_full_button)
	row.add_child(_button("close", "Fermer", func(): get_tree().quit()))


func _can_minimize() -> bool:
	# Godot 4.3 can minimize desktop windows; Android has no minimize call in this version.
	return not OS.has_feature("android")


func _is_full() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func _minimize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


func _toggle_full() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if _is_full() else DisplayServer.WINDOW_MODE_FULLSCREEN)
	_full_button.set_meta("kind", "restore" if _is_full() else "max")
	_full_button.queue_redraw()


func _button(kind: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(46, H)
	b.set_meta("kind", kind)
	b.pressed.connect(action)
	b.draw.connect(_draw_icon.bind(b))
	return b


func _draw_icon(b: Button) -> void:
	var c := b.size / 2.0
	var k: String = b.get_meta("kind")
	var w := 2.0
	match k:
		"min":
			b.draw_line(c + Vector2(-7, 0), c + Vector2(7, 0), GOLD, w)
		"max":
			for p in [[-8, -3, -8, -8, -3, -8], [3, -8, 8, -8, 8, -3], [8, 3, 8, 8, 3, 8], [-3, 8, -8, 8, -8, 3]]:
				b.draw_polyline(PackedVector2Array([c + Vector2(p[0], p[1]), c + Vector2(p[2], p[3]), c + Vector2(p[4], p[5])]), GOLD, w)
		"restore":
			for p in [[-3, -8, -3, -3, -8, -3], [8, -3, 3, -3, 3, -8], [3, 8, 3, 3, 8, 3], [-8, 3, -3, 3, -3, 8]]:
				b.draw_polyline(PackedVector2Array([c + Vector2(p[0], p[1]), c + Vector2(p[2], p[3]), c + Vector2(p[4], p[5])]), GOLD, w)
		"close":
			b.draw_line(c + Vector2(-7, -7), c + Vector2(7, 7), GOLD, w)
			b.draw_line(c + Vector2(7, -7), c + Vector2(-7, 7), GOLD, w)
