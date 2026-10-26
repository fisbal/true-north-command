extends SceneTree
## Screen check: opens every screen of the game on phone, tablet, PC and Mac sizes, in English and French,
## and fails when anything runs off the screen, HUD panels overlap, or text and buttons are too small.
## Run: godot --headless -s tests/screens.gd

const SIZES := {
	"small-phone": Vector2i(320, 568), "phone": Vector2i(390, 844), "phone-landscape": Vector2i(844, 390),
	"tablet": Vector2i(820, 1180), "tablet-landscape": Vector2i(1180, 820), "pc": Vector2i(1440, 900),
}
const MIN_TAP := 28.0   # px on the real screen
const MIN_TEXT := 10.0  # px on the real screen

var main
var problems: PackedStringArray = []
var views := 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	for lang in ["en", "fr"]:
		for size_name in SIZES:
			root.size = SIZES[size_name]
			if main:
				main.queue_free()
				await _frames(1)
			main = load("res://main.tscn").instantiate()
			root.add_child(main)
			await _frames(2)
			await _check(lang, size_name, "language")
			main._on_language(0 if lang == "en" else 1)
			await _check(lang, size_name, "title")
			main._start_mission(1)
			await _check(lang, size_name, "briefing")
			main.modal_root.hide()
			main._start_sail("test", [])
			main._set_telegraph(2)
			main._on_update_available("https://example.invalid/")
			await _frames(4)
			await _check(lang, size_name, "mission 1 helm")
			main.copilot.open_panel()
			await _check(lang, size_name, "ask claude")
			main.copilot.close_panel()
			main._break_m1()
			await _check(lang, size_name, "the break")
			main._debrief("Planned text for the review", "History text for the review", ["Next mission", "Replay"], func(_i): pass)
			await _check(lang, size_name, "after action review")
			main._echo_intro()
			await _check(lang, size_name, "echo 1942 brief")
			main.modal_root.hide()
			main._echo_start()
			main.modal_root.hide()
			await _frames(4)
			await _check(lang, size_name, "echo 1942 helm")
			main._start_mission(2)
			main.modal_root.hide()
			main.stage = 0
			main._start_sail("test", [])
			main._launch_helo()
			await _frames(4)
			await _check(lang, size_name, "mission 2 helm")
	if problems.is_empty():
		print("All screens fit: %d screens (%d sizes x 2 languages)." % [views, SIZES.size()])
		quit(0)
	else:
		for p in problems:
			print("SCREEN PROBLEM: ", p)
		print("%d screen problems." % problems.size())
		quit(1)


func _check(lang: String, size_name: String, screen: String) -> void:
	await _frames(12)
	views += 1
	var canvas: Vector2 = root.get_visible_rect().size
	var scale: float = float(root.size.y) / canvas.y
	var where := "%s %s %s: " % [size_name, lang, screen]
	var bounds := Rect2(Vector2.ZERO, canvas).grow(1.0)
	var modal: bool = main.modal_root.visible
	var hud: Array = [main.hud_top, main.radar, main.hud_zoom, main.hud_radio, main.hud_log, main.hud_helm]
	for c in _controls(main.ui):
		var r: Rect2 = c.get_global_rect()
		if not bounds.encloses(r):
			problems.append(where + "%s runs off the screen %s (screen %s)" % [_name(c), r, canvas])
		if c is Button and r.size.y * scale < MIN_TAP:
			problems.append(where + "%s is too small to tap (%.0f px)" % [_name(c), r.size.y * scale])
		if c is Label or c is Button:
			var fs: int = c.get_theme_font_size("font_size")
			if fs * scale < MIN_TEXT:
				problems.append(where + "%s text is too small (%.1f px)" % [_name(c), fs * scale])
	if not modal:
		for i in hud.size():
			for j in range(i + 1, hud.size()):
				var a: Control = hud[i]
				var b: Control = hud[j]
				if a.is_visible_in_tree() and b.is_visible_in_tree() and a.get_global_rect().grow(-1.0).intersects(b.get_global_rect().grow(-1.0)):
					problems.append(where + "%s overlaps %s" % [_name(a), _name(b)])


## Visible controls, without the ones inside a scroll box (the box itself is checked) or full-screen layers.
func _controls(n: Node) -> Array:
	var out: Array = []
	for ch in n.get_children():
		if ch is Control and not ch.is_visible_in_tree():
			continue
		if ch is Control and ch.size.x > 0 and ch.size.y > 0 and ch != main.modal_root and not (ch is ColorRect and ch.mouse_filter == Control.MOUSE_FILTER_IGNORE):
			if not (ch is CenterContainer) and not (ch.get_parent() == main.ui):
				out.append(ch)
		if not (ch is ScrollContainer):
			out.append_array(_controls(ch))
	return out


func _name(c: Control) -> String:
	var t := ""
	if c is Button or c is Label:
		t = " \"" + str(c.text).left(24) + "\""
	return c.get_class() + t
