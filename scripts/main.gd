extends Node2D
## True North Command: Operation Alpha (internal code name MI-Alpha).
## Operation GHOST CONVOY
##   Mission 1 "Harbour Departure, Halifax" (+ Echo 1942)
##   Mission 2 "Sable Island Boarding"
## English and French. One scene; each mission is a small state machine.

const WorldScript := preload("res://scripts/world.gd")
const VesselScript := preload("res://scripts/vessel.gd")
const View3DScript := preload("res://scripts/view3d.gd")
const CopilotScript := preload("res://scripts/copilot.gd")
const UpdaterScript := preload("res://scripts/updater.gd")

const POINT_ECHO := Vector2(980, 3250)
const SEA_BUOY := Vector2(1000, 5000)
const M2_RENDEZVOUS := Vector2(-1900, 1700)
const VISUAL_RANGE := 430.0
const NM := 370.0  # world units per nautical mile on the chart

const TELE := {
	"en": {-1: "Slow astern", 0: "Stop engines", 1: "Slow ahead", 2: "Half ahead", 3: "Full ahead", 4: "Flank speed"},
	"fr": {-1: "En arrière lente", 0: "Stoppez", 1: "En avant lente", 2: "En avant demie", 3: "En avant toute", 4: "Vitesse maximale"},
}
const RUDDER := {
	"en": {-2: "Port thirty", -1: "Port fifteen", 0: "Midships", 1: "Starboard fifteen", 2: "Starboard thirty"},
	"fr": {-2: "À gauche trente", -1: "À gauche quinze", 0: "Barre à zéro", 1: "À droite quinze", 2: "À droite trente"},
}
const TELE_BTN := {"en": ["Astern", "Stop", "Slow", "Half", "Full", "Flank"], "fr": ["Arrière", "Stop", "Lente", "Demie", "Toute", "Max"]}
const RUDDER_BTN := {"en": ["Port 30", "Port 15", "Midships", "Stbd 15", "Stbd 30"], "fr": ["Gauche 30", "Gauche 15", "Zéro", "Droite 15", "Droite 30"]}
const PILLARS := ["awareness", "discipline", "initiative", "team", "execution"]
const PILLAR_NAME := {
	"en": {"awareness": "Awareness", "discipline": "Discipline", "initiative": "Initiative", "team": "Team", "execution": "Execution"},
	"fr": {"awareness": "Vigilance", "discipline": "Discipline", "initiative": "Initiative", "team": "Équipe", "execution": "Exécution"},
}

const FOG_SHADER := """
shader_type canvas_item;
uniform vec4 fog_color : source_color = vec4(0.86, 0.88, 0.89, 1.0);
uniform float inner = 0.10;
uniform float outer = 0.36;
uniform float strength = 0.93;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float n = sin(UV.x * 11.0 + TIME * 0.25) * 0.018 + sin(UV.y * 8.0 - TIME * 0.18) * 0.018;
	float a = smoothstep(inner, outer, length(uv) + n) * strength;
	COLOR = vec4(fog_color.rgb, a);
}
"""

# --- world ---
var world
var player
var vessels: Array = []
var cam: Camera2D
var overlay: Node2D
var trail_layer: Node2D
var zoom_level := 0.8
var view          # the 3D view (view3d.gd); the 2D chart nodes only hold the simulation
var view_button: Button

# --- state ---
var lang := "en"
var mission := 1
var era := "modern"   # modern (M1), 1942 (Echo), sable (M2)
var phase := "title"  # title, sail, done
var paused := true
var stage := 0
var mission_time := 0.0
var player_idx := 0
var scores := {}
var aar: Array = []
var radar_range := 1300.0
var port_royal
var ferry
var unlit
var lady_hannah
var rhib
var trawler
var helo
var helo_state := ""
var helo_target
var helo_timer := 0.0
var helo_used := false
var rhib_state := ""
var rhib_timer := 0.0
var waited_warned := false
var break_choice := -1
var safe_positions: Array = []
var safe_timer := 0.0
var over_limit_t := 0.0
var limit_warned := false
var limit_penalty := 0
var gap_t := 0.0
var gap_penalty := 0
var mayday_t := -1.0
var hailed := false
var trawler_stopped := false
var drift_warned := false
var ground_cooldown := 0.0
var echo_orders: Array = []
var echo_rudder_order := 0
var echo_tele_order := 1
var echo_wp := 0
var echo_last_order_t := -10.0
var gate_t := -1.0
var objective := ""

# --- ui ---
var ui: CanvasLayer
var fog_mat: ShaderMaterial
var top_obj: Label
var top_nav: Label
var log_box: RichTextLabel
var radio_box: VBoxContainer
var radio_title: Label
var radio_keys := ""
var radar: Control
# HUD panels, placed by _layout() for phones, tablets, PC and Mac
var hud_top: PanelContainer
var hud_zoom: HBoxContainer
var hud_radio: PanelContainer
var hud_log: PanelContainer
var hud_helm: PanelContainer
var modal_panel: PanelContainer
var modal_scroll: ScrollContainer
var modal_options := 0
var claude_button: Button
var update_button: Button
var update_url := ""
var copilot
var updater
var zoom_buttons: Array = []
var tele_buttons := {}
var rudder_buttons := {}
var toast: Label
var toast_t := 0.0
var order_label: Label
var modal_root: Control
var modal_title: Label
var modal_body: RichTextLabel
var modal_extra: VBoxContainer
var modal_buttons: Container
var modal_cb: Callable


func T(en: String, fr: String) -> String:
	return fr if lang == "fr" else en


func _ready() -> void:
	randomize()
	world = WorldScript.new()
	add_child(world)
	trail_layer = Node2D.new()
	trail_layer.z_index = 2
	add_child(trail_layer)
	trail_layer.draw.connect(_draw_trails)
	overlay = Node2D.new()
	overlay.z_index = 5
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	world.visible = false
	trail_layer.visible = false
	overlay.visible = false
	view = View3DScript.new()
	view.main = self
	add_child(view)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	cam.zoom = Vector2(zoom_level, zoom_level)
	cam.position = Vector2(300, 900)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 4.0
	_build_ui()
	get_window().size_changed.connect(_apply_screen)
	_apply_screen()
	_show_language()


# ======================================================================
# Names that depend on language and the chosen officer
# ======================================================================

func player_name() -> String:
	if player_idx == 0:
		return T("Lt(N) Élise Tremblay", "Ltv Élise Tremblay")
	return T("Lt(N) Liam MacLeod", "Ltv Liam MacLeod")


func player_short() -> String:
	return "Tremblay" if player_idx == 0 else "MacLeod"


func sir_maam() -> String:
	if lang == "fr":
		return "lieutenant"
	return "ma'am" if player_idx == 0 else "sir"


func hale() -> String:
	return T("Capt(N) Hale", "Capv Hale")


func captain_address() -> String:
	return T("ma'am", "Commandant")


func who(key: String) -> String:
	var names := {
		"helm": ["Helm", "Barreur"], "ops": ["Ops room", "Salle des opérations"], "lookout": ["Lookout", "Vigie"],
		"cox": ["Coxswain", "Capitaine d'armes"], "medic": ["Medic", "Technicien médical"], "you": ["You", "Vous"],
		"radio": ["Radio", "Radio"], "ch16": ["Channel 16", "Canal 16"], "oow": ["OOW", "Officier de quart"],
		"signal": ["Signalman", "Signaleur"], "marsh": ["LCdr Marsh", "Capc Marsh"], "flight": ["Cyclone", "Cyclone"],
		"board": ["Boarding officer", "Officier d'arraisonnement"],
	}
	var n: Array = names.get(key, [key, key])
	return n[1] if lang == "fr" else n[0]


func tele_name(k: int) -> String:
	return TELE[lang][k]


func rudder_name(k: int) -> String:
	return RUDDER[lang][k]


# ======================================================================
# UI construction
# ======================================================================

func _theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 18
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.05, 0.11, 0.17, 0.86)
	panel.border_color = Color(0.72, 0.6, 0.35, 0.8)
	panel.set_border_width_all(1)
	panel.set_content_margin_all(10)
	th.set_stylebox("panel", "PanelContainer", panel)
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0.11, 0.2, 0.28, 0.95)
	b.border_color = Color(0.45, 0.55, 0.6)
	b.set_border_width_all(1)
	b.set_corner_radius_all(3)
	b.set_content_margin_all(8)
	var bh := b.duplicate()
	bh.bg_color = Color(0.17, 0.3, 0.4, 0.95)
	var bp := b.duplicate()
	bp.bg_color = Color(0.7, 0.16, 0.13, 0.95)
	th.set_stylebox("normal", "Button", b)
	th.set_stylebox("hover", "Button", bh)
	th.set_stylebox("pressed", "Button", bp)
	th.set_stylebox("focus", "Button", bh)
	th.set_color("font_color", "Button", Color(0.92, 0.94, 0.95))
	th.set_color("font_color", "Label", Color(0.92, 0.94, 0.95))
	th.set_color("default_color", "RichTextLabel", Color(0.9, 0.92, 0.93))
	return th


func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var fog := ColorRect.new()
	fog.set_anchors_preset(Control.PRESET_FULL_RECT)
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = FOG_SHADER
	fog_mat = ShaderMaterial.new()
	fog_mat.shader = sh
	fog.material = fog_mat
	ui.add_child(fog)
	fog.visible = false  # the 3D view has real fog

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	ui.add_child(root)

	var top := PanelContainer.new()
	hud_top = top
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 60
	var top_style: StyleBoxFlat = root.theme.get_stylebox("panel", "PanelContainer").duplicate()
	top_style.content_margin_top = 8
	top_style.content_margin_bottom = 8
	top.add_theme_stylebox_override("panel", top_style)
	root.add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 20)
	top.add_child(th)
	top_obj = Label.new()
	top_obj.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_obj.clip_text = true
	th.add_child(top_obj)
	top_nav = Label.new()
	top_nav.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	th.add_child(top_nav)
	update_button = Button.new()
	update_button.focus_mode = Control.FOCUS_NONE
	update_button.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	update_button.pressed.connect(func(): OS.shell_open(update_url))
	update_button.hide()
	th.add_child(update_button)
	claude_button = Button.new()
	claude_button.focus_mode = Control.FOCUS_NONE
	for b in [update_button, claude_button]:
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb: StyleBoxFlat = root.theme.get_stylebox(st, "Button").duplicate()
			sb.content_margin_top = 7
			sb.content_margin_bottom = 7
			b.add_theme_stylebox_override(st, sb)
	claude_button.pressed.connect(func(): copilot.open_panel())
	th.add_child(claude_button)

	radar = Control.new()
	radar.custom_minimum_size = Vector2(190, 190)
	radar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	radar.offset_left = -202
	radar.offset_right = -12
	radar.offset_top = 58
	radar.offset_bottom = 248
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar.draw.connect(_draw_radar)
	root.add_child(radar)

	var zb := HBoxContainer.new()
	hud_zoom = zb
	zb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	zb.offset_left = -330
	zb.offset_right = -12
	zb.offset_top = 252
	zb.offset_bottom = 290
	root.add_child(zb)
	for z in [["−", 0.85], ["+", 1.18]]:
		var btn := Button.new()
		btn.set_meta("sign", z[0])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 46)
		btn.pressed.connect(_zoom.bind(z[1]))
		zb.add_child(btn)
		zoom_buttons.append(btn)
	view_button = Button.new()
	view_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_button.focus_mode = Control.FOCUS_NONE
	view_button.custom_minimum_size = Vector2(0, 46)
	view_button.pressed.connect(_cycle_view)
	zb.add_child(view_button)

	var rp := PanelContainer.new()
	hud_radio = rp
	rp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	rp.offset_left = -340
	rp.offset_right = -12
	rp.offset_top = 298
	root.add_child(rp)
	var rv := VBoxContainer.new()
	rp.add_child(rv)
	radio_title = Label.new()
	radio_title.add_theme_font_size_override("font_size", 16)
	radio_title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	rv.add_child(radio_title)
	radio_box = VBoxContainer.new()
	rv.add_child(radio_box)

	var lp := PanelContainer.new()
	hud_log = lp
	lp.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	lp.offset_left = 12
	lp.offset_right = 560
	lp.offset_top = -200
	lp.offset_bottom = -12
	root.add_child(lp)
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.add_theme_font_size_override("normal_font_size", 16)
	log_box.add_theme_font_size_override("bold_font_size", 16)
	lp.add_child(log_box)

	var hp := PanelContainer.new()
	hud_helm = hp
	hp.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hp.offset_left = -640
	hp.offset_right = -12
	hp.offset_top = -128
	hp.offset_bottom = -12
	root.add_child(hp)
	var hv := VBoxContainer.new()
	hp.add_child(hv)
	var trow := HBoxContainer.new()
	hv.add_child(trow)
	for k in [-1, 0, 1, 2, 3, 4]:
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 46)
		btn.pressed.connect(_set_telegraph.bind(k))
		trow.add_child(btn)
		tele_buttons[k] = btn
	var rrow := HBoxContainer.new()
	hv.add_child(rrow)
	for k in [-2, -1, 0, 1, 2]:
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 46)
		btn.pressed.connect(_set_rudder.bind(k))
		rrow.add_child(btn)
		rudder_buttons[k] = btn

	toast = Label.new()
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.offset_top = 62
	toast.offset_left = -320
	toast.offset_right = 320
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_theme_font_size_override("font_size", 20)
	toast.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	toast.add_theme_constant_override("outline_size", 6)
	root.add_child(toast)
	order_label = Label.new()
	order_label.set_anchors_preset(Control.PRESET_CENTER)
	order_label.offset_top = 90
	order_label.offset_bottom = 150
	order_label.offset_left = -360
	order_label.offset_right = 360
	order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	order_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	order_label.add_theme_font_size_override("font_size", 30)
	order_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	order_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	order_label.add_theme_constant_override("outline_size", 8)
	root.add_child(order_label)

	modal_root = ColorRect.new()
	(modal_root as ColorRect).color = Color(0.02, 0.05, 0.08, 0.72)
	modal_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal_root)
	var mc := CenterContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_root.add_child(mc)
	var mp := PanelContainer.new()
	modal_panel = mp
	mp.custom_minimum_size = Vector2(780, 0)
	mc.add_child(mp)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 12)
	mp.add_child(mv)
	modal_title = Label.new()
	modal_title.add_theme_font_size_override("font_size", 28)
	modal_title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	modal_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mv.add_child(modal_title)
	var sc := ScrollContainer.new()
	modal_scroll = sc
	sc.custom_minimum_size = Vector2(760, 240)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mv.add_child(sc)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(inner)
	modal_body = RichTextLabel.new()
	modal_body.bbcode_enabled = true
	modal_body.fit_content = true
	modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(modal_body)
	modal_extra = VBoxContainer.new()
	inner.add_child(modal_extra)
	modal_buttons = VBoxContainer.new()
	modal_buttons.add_theme_constant_override("separation", 8)
	mv.add_child(modal_buttons)
	modal_root.hide()
	copilot = CopilotScript.new(self)
	root.add_child(copilot)
	updater = UpdaterScript.new()
	updater.update_available.connect(_on_update_available)
	updater.update_installed.connect(func(v): show_toast(T("Updated to %s. The new version opens next time.", "Mis à jour vers %s. La nouvelle version s'ouvre la prochaine fois.") % v))
	add_child(updater)
	_relabel()


# ======================================================================
# Screens: phones, tablets, PC and Mac (tests/screens.gd checks every layout)
# ======================================================================

## Picks the size of the 2D canvas from the screen's real size, so text and buttons stay readable
## and easy to tap on a phone, and the HUD is laid out for portrait or landscape.
func _apply_screen() -> void:
	var win := get_window()
	var px := Vector2(win.size)
	if px.x < 1 or px.y < 1:
		return
	var density := DisplayServer.screen_get_scale()
	if OS.has_feature("android") or OS.has_feature("ios"):
		density = maxf(1.0, DisplayServer.screen_get_dpi() / 160.0)
	var css := px / maxf(density, 0.5)
	if css.x >= css.y:
		# Landscape: 560 to 720 tall (a phone on its side gets the 560 one); at least 1280 wide on a PC or Mac,
		# 1100 on smaller screens so a phone on its side keeps big enough buttons.
		win.content_scale_size = Vector2i(1280 if css.x >= 1280.0 else 1100, int(clampf(css.y, 560.0, 720.0)))
	else:
		# Portrait: 480 to 900 wide, so a phone shows the HUD at about 70 % of a PC's size.
		win.content_scale_size = Vector2i(int(clampf(css.x * 1.4, 480.0, 900.0)), 10)
	_layout()


func _canvas() -> Vector2:
	return get_viewport().get_visible_rect().size


func _place(c: Control, al: float, at: float, ar: float, ab: float, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b


func _layout() -> void:
	if hud_helm == null:
		return
	var cv := _canvas()
	var portrait := cv.x < 1000.0
	var short := cv.y < 700.0
	var side := minf(330.0, cv.x - 24.0)
	var rsize := 150.0 if (portrait or short) else 190.0
	radar.custom_minimum_size = Vector2(rsize, rsize)
	_place(radar, 1, 0, 1, 0, -12 - rsize, 70, -12, 70 + rsize)
	_place(hud_zoom, 1, 0, 1, 0, -12 - side, 78 + rsize, -12, 124 + rsize)
	hud_radio.grow_vertical = Control.GROW_DIRECTION_END
	if portrait:
		# Bottom up: helm, log, radio; the 3D view keeps the top half.
		_place(hud_helm, 0, 1, 1, 1, 12, -128, -12, -12)
		_place(hud_log, 0, 1, 1, 1, 12, -278, -12, -138)
		_place(hud_radio, 0, 1, 1, 1, 12, -288, -12, -288)
		hud_radio.grow_vertical = Control.GROW_DIRECTION_BEGIN
	else:
		_place(hud_helm, 1, 1, 1, 1, -640, -128, -12, -12)
		_place(hud_log, 0, 1, 0, 1, 12, -200, minf(560.0, cv.x - 664.0), -12)
		if short:
			_place(hud_radio, 0, 0, 0, 0, 12, 70, 12 + side, 70)
		else:
			_place(hud_radio, 1, 0, 1, 0, -12 - side, 132 + rsize, -12, 132 + rsize)
	# Narrow phones: slightly smaller helm and status text so French labels fit on one row.
	var narrow := cv.x < 600.0
	for b in tele_buttons.values() + rudder_buttons.values():
		if narrow:
			b.add_theme_font_size_override("font_size", 16)
		else:
			b.remove_theme_font_size_override("font_size")
	if narrow:
		top_nav.add_theme_font_size_override("font_size", 15)
	else:
		top_nav.remove_theme_font_size_override("font_size")
	top_nav.get_parent().add_theme_constant_override("separation", 4 if narrow else 20)
	claude_button.text = "✦" if narrow else "✦ Claude"
	update_button.text = "⬇" if narrow else T("⬇ Update", "⬇ Mettre à jour")
	var tw := minf(640.0, cv.x - 24.0)
	_place(toast, 0.5, 0, 0.5, 0, -tw / 2, 74, tw / 2, 74)
	var ow := minf(720.0, cv.x - 24.0)
	_place(order_label, 0.5, 0.5, 0.5, 0.5, -ow / 2, 90, ow / 2, 150)
	_layout_modal()
	if copilot:
		copilot.layout(cv)


func _on_update_available(url: String) -> void:
	update_url = url
	update_button.show()
	show_toast(T("A new version is ready: tap Update.", "Une nouvelle version est prête : touchez Mettre à jour."))


func _layout_modal() -> void:
	if modal_panel == null:
		return
	var cv := _canvas()
	var w := minf(780.0, cv.x - 24.0)
	modal_panel.custom_minimum_size = Vector2(w, 0)
	# Title and buttons first; the text scrolls in what is left.
	var room := cv.y - 24.0 - 20.0 - 12.0 * 3 - 80.0 - modal_options * 62.0
	modal_scroll.custom_minimum_size = Vector2(w - 20.0, clampf(room, 110.0, 240.0 if cv.y < 900.0 else 360.0))


func _relabel() -> void:
	for k in tele_buttons:
		tele_buttons[k].text = TELE_BTN[lang][k + 1]
	for k in rudder_buttons:
		rudder_buttons[k].text = RUDDER_BTN[lang][k + 2]
	for b in zoom_buttons:
		b.text = T("Zoom ", "Zoom ") + str(b.get_meta("sign"))
	if view_button:
		view_button.text = view.view_name()
	_layout()
	radio_title.text = T("RADIO / ACTIONS  [Space]", "RADIO / ACTIONS  [Espace]")
	radio_keys = "-"
	world.lang = lang
	world.queue_redraw()


func show_modal(title: String, body: String, options: Array, cb: Callable, extra: Control = null) -> void:
	paused = true
	modal_title.text = title
	modal_body.text = body
	for c in modal_extra.get_children():
		c.queue_free()
	if extra:
		modal_extra.add_child(extra)
	for c in modal_buttons.get_children():
		c.queue_free()
	modal_cb = cb
	modal_options = options.size()
	_layout_modal()
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# A known width lets the button wrap its text to the right height.
		b.custom_minimum_size = Vector2(modal_panel.custom_minimum_size.x - 20.0, 46)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_modal_pick.bind(i))
		modal_buttons.add_child(b)
	modal_root.show()


func _modal_pick(i: int) -> void:
	modal_root.hide()
	paused = false
	if modal_cb.is_valid():
		modal_cb.call(i)


func log_line(speaker: String, text: String, color := "") -> void:
	var c := color
	if c == "":
		c = "#f2c46d" if speaker == who("you") else "#a9d3e3"
	log_box.append_text("[color=%s][b]%s:[/b][/color] %s\n" % [c, speaker, text])


func show_toast(text: String, good := true) -> void:
	toast.text = text
	toast.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6) if good else Color(1.0, 0.5, 0.45))
	toast_t = 2.8


# ======================================================================
# Title: language, officer, mission
# ======================================================================

func _show_language() -> void:
	phase = "title"
	mission = 1
	_setup_m1()
	show_modal("TRUE NORTH COMMAND\nOperation Alpha",
		"[b]Choose your language · Choisissez votre langue[/b]",
		["English", "Français"], _on_language)


func _on_language(i: int) -> void:
	lang = "fr" if i == 1 else "en"
	_relabel()
	_show_title()


func _show_title() -> void:
	phase = "title"
	show_modal(T("TRUE NORTH COMMAND\nOperation Alpha", "COMMANDEMENT DU NORD\nOpération Alpha"),
		T("[b]Operation GHOST CONVOY[/b]\n\nYou are an Officer of the Watch in the Royal Canadian Navy. You are scored on how well you read the situation, follow orders, use initiative inside your Captain's intent, look after your team, and get the job done.\n\n" +
		"[color=#9fb4bf]Controls: W/S or buttons = engine telegraph · A/D or buttons = rudder · Space = first radio action · mouse wheel or Zoom = zoom · V or the view button = chase, bridge or tactical camera · drag = look around.[/color]\n\nChoose your officer:",
		"[b]Opération CONVOI FANTÔME[/b]\n\nVous êtes officier de quart dans la Marine royale canadienne. Vous êtes évalué sur votre lecture de la situation, le respect des ordres, l'initiative dans le cadre de l'intention du commandant, le soin de votre équipe et l'exécution de la mission.\n\n" +
		"[color=#9fb4bf]Commandes : W/S ou boutons = transmetteur d'ordres · A/D ou boutons = barre · Espace = première action radio · molette ou Zoom = zoom · V ou le bouton de vue = caméra poursuite, passerelle ou tactique · glisser = regarder autour.[/color]\n\nChoisissez votre officier :"),
		[T("Lt(N) Élise Tremblay  ·  navigation officer, Rimouski QC", "Ltv Élise Tremblay  ·  officière de navigation, Rimouski QC"),
		T("Lt(N) Liam MacLeod  ·  navigation officer, Sydney NS", "Ltv Liam MacLeod  ·  officier de navigation, Sydney NS")],
		_on_pick_character)


func _on_pick_character(i: int) -> void:
	player_idx = i
	_choose_mission()


func _choose_mission() -> void:
	show_modal(T("CHOOSE YOUR MISSION", "CHOISISSEZ VOTRE MISSION"),
		T("Operation GHOST CONVOY", "Opération CONVOI FANTÔME"),
		[T("Mission 1 · Harbour Departure, Halifax  (fog, the Narrows, a mayday, Echo 1942)", "Mission 1 · Appareillage, Halifax  (brume, le Goulet, un mayday, Écho 1942)"),
		T("Mission 2 · Sable Island Boarding  (helicopter search, a false order, boarding)", "Mission 2 · Arraisonnement à l'île de Sable  (recherche par hélicoptère, un faux ordre, arraisonnement)")],
		func(i): _start_mission(i + 1))


func _start_mission(m: int) -> void:
	mission = m
	if m == 1:
		_setup_m1()
		_brief_m1(0)
	else:
		_setup_m2()
		_brief_m2(0)


# ======================================================================
# Shared setup
# ======================================================================

func _clear_vessels() -> void:
	for v in vessels:
		if is_instance_valid(v):
			v.queue_free()
	vessels.clear()
	port_royal = null
	ferry = null
	unlit = null
	lady_hannah = null
	rhib = null
	trawler = null
	helo = null


func _spawn(kind: String, pos: Vector2, hdg: float, vname := ""):
	var v = VesselScript.new()
	v.kind = kind
	v.vname = vname
	v.position = pos
	v.heading = hdg
	v.rotation = deg_to_rad(hdg)
	v.z_index = 3 if kind != "helo" else 6
	v.visible = false
	add_child(v)
	vessels.append(v)
	return v


func _despawn(v) -> void:
	if v and is_instance_valid(v):
		vessels.erase(v)
		v.queue_free()


func _reset_common() -> void:
	_clear_vessels()
	stage = 0
	mission_time = 0.0
	aar.clear()
	scores = {"awareness": 60, "discipline": 60, "initiative": 55, "team": 60, "execution": 70}
	log_box.clear()
	safe_positions.clear()
	over_limit_t = 0.0
	limit_warned = false
	limit_penalty = 0
	gap_t = 0.0
	gap_penalty = 0
	mayday_t = -1.0
	hailed = false
	waited_warned = false
	break_choice = -1
	rhib_state = ""
	helo_state = ""
	helo_target = null
	helo_used = false
	trawler_stopped = false
	drift_warned = false
	ground_cooldown = 0.0
	order_label.text = ""
	radio_keys = "-"


func _start_sail(obj: String, lines: Array) -> void:
	phase = "sail"
	paused = false
	objective = obj
	for l in lines:
		log_line(l[0], l[1])


# ======================================================================
# Scoring
# ======================================================================

func score(pillar: String, delta: int, why: String) -> void:
	scores[pillar] = clampi(scores[pillar] + delta, 0, 100)
	aar.append({"pillar": pillar, "delta": delta, "why": why, "t": mission_time})
	show_toast("%s %+d · %s" % [PILLAR_NAME[lang][pillar], delta, why], delta >= 0)


# ======================================================================
# Controls
# ======================================================================

func _set_telegraph(k: int) -> void:
	if paused or player == null or player.telegraph == k:
		return
	player.telegraph = k
	if era == "1942":
		log_line(who("you"), T("Telegraph to ", "Transmetteur : ") + tele_name(k).to_lower() + ".")
		_echo_check_obey()
	else:
		log_line(who("you"), tele_name(k) + ".")
		log_line(who("helm"), tele_name(k) + T(", aye.", ", bien reçu."))


func _set_rudder(k: int) -> void:
	if paused or player == null or player.rudder == k:
		return
	player.rudder = k
	if era == "1942":
		log_line(who("you"), rudder_name(k) + T(", aye, sir.", ", à vos ordres, lieutenant."))
		_echo_check_obey()
	else:
		log_line(who("you"), rudder_name(k) + ".")
		log_line(who("helm"), rudder_name(k) + T(", aye.", ", bien reçu."))


func _zoom(f: float) -> void:
	zoom_level = clampf(zoom_level * f, 0.2, 1.8)
	cam.zoom = Vector2(zoom_level, zoom_level)
	view.zoom = zoom_level


func _cycle_view() -> void:
	view.cycle_view()
	view_button.text = view.view_name()


func _unhandled_input(event: InputEvent) -> void:
	if copilot and copilot.visible:
		return
	if event is InputEventMagnifyGesture:  # two-finger pinch on phones, tablets and trackpads
		_zoom(event.factor)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(0.9)
	if event is InputEventKey and event.pressed and not event.echo and player:
		match event.keycode:
			KEY_W, KEY_UP:
				_set_telegraph(mini(player.telegraph + 1, 4))
			KEY_S, KEY_DOWN:
				_set_telegraph(maxi(player.telegraph - 1, -1))
			KEY_A, KEY_LEFT:
				_set_rudder(maxi(player.rudder - 1, -2))
			KEY_D, KEY_RIGHT:
				_set_rudder(mini(player.rudder + 1, 2))
			KEY_SPACE, KEY_R:
				var acts := _radio_actions()
				if acts.size() > 0 and not paused:
					_do_action(acts[0][0])
			KEY_EQUAL, KEY_KP_ADD:
				_zoom(1.15)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_zoom(0.87)


# ======================================================================
# Radio actions
# ======================================================================

func _radio_actions() -> Array:
	var a: Array = []
	if phase != "sail" or player == null or era == "1942":
		return a
	for v in vessels:
		if is_instance_valid(v) and v.needs_report and not v.reported and v.detected_at >= 0.0:
			a.append(["report", T("Report contact to the Captain", "Signaler le contact au commandant")])
			break
	if mission == 1:
		if unlit and is_instance_valid(unlit) and unlit.reported and not hailed and player.position.distance_to(unlit.position) < 1000:
			a.append(["hail", T("Hail the unknown craft on Channel 16", "Héler l'embarcation inconnue sur le canal 16")])
		if stage == 5 and lady_hannah and rhib_state == "" and player.position.distance_to(lady_hannah.position) < 220:
			a.append(["rhib", T("Launch the RHIB (5 knots or less)", "Mettre l'embarcation à l'eau (5 nœuds max)")])
	else:
		var near = _nearest_unidentified(VISUAL_RANGE)
		if near:
			a.append(["identify", T("Identify contact visually (binoculars)", "Identifier le contact à vue (jumelles)")])
		if helo_state == "" and _nearest_unidentified(INF) != null:
			a.append(["helo", T("Launch the Cyclone to identify the nearest unknown contact", "Lancer le Cyclone pour identifier le contact inconnu le plus proche")])
		if stage == 3 and trawler and not trawler_stopped and player.position.distance_to(trawler.position) < 1400:
			a.append(["stop", T("Order the trawler to stop (Channel 16)", "Ordonner au chalutier de stopper (canal 16)")])
		if stage == 3 and trawler and trawler_stopped and rhib_state == "" and player.position.distance_to(trawler.position) < 260:
			a.append(["board", T("Away the boarding party (5 knots or less)", "Envoyer l'équipe d'arraisonnement (5 nœuds max)")])
	return a


func _do_action(key: String) -> void:
	match key:
		"report":
			_report_contact()
		"hail":
			_hail()
		"rhib":
			_launch_rhib()
		"identify":
			_identify_visual()
		"helo":
			_launch_helo()
		"stop":
			_order_stop()
		"board":
			_launch_boarding()


func _bearing_words(target: Vector2) -> String:
	var to: Vector2 = target - player.position
	var brg := rad_to_deg(atan2(to.x, -to.y))
	var rel := wrapf(brg - player.heading, -180.0, 180.0)
	var side := T("green", "tribord") if rel >= 0 else T("red", "bâbord")
	var deg := int(round(absf(rel) / 5.0) * 5)
	var nm := to.length() / NM
	return T("%s %s, %.1f miles", "%s %s, %.1f milles") % [side, _say_deg(deg), nm]


func _say_deg(d: int) -> String:
	var words := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
	if lang == "fr":
		words = ["zéro", "un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf"]
	var out: PackedStringArray = []
	for ch in str(d):
		out.append(words[int(ch)])
	return "-".join(out)


func _report_contact() -> void:
	var best = null
	for v in vessels:
		if is_instance_valid(v) and v.needs_report and not v.reported and v.detected_at >= 0.0:
			if best == null or v.detected_at < best.detected_at:
				best = v
	if best == null:
		return
	best.reported = true
	var dt: float = mission_time - best.detected_at
	log_line(who("you"), T("Captain, %s: contact %s, %s.", "Commandant, contact %s, %s.") % ([captain_address(), _bearing_words(best.position), best.contact_desc] if lang == "en" else [_bearing_words(best.position), best.contact_desc]))
	if dt < 12.0:
		score("awareness", 8, T("Reported a contact quickly", "Contact signalé rapidement"))
	elif dt < 25.0:
		score("awareness", 4, T("Reported a contact", "Contact signalé"))
	else:
		score("awareness", 1, T("Reported a contact, late", "Contact signalé, en retard"))
	if best == unlit:
		log_line(hale(), T("Very good. No lights in fog is either careless or deliberate. Keep watching it.", "Très bien. Sans feux dans la brume, c'est de la négligence ou c'est voulu. Gardez-le à l'œil."))
	else:
		log_line(hale(), T("Very good.", "Très bien."))


func _detect_contacts() -> void:
	var p: Vector2 = player.position
	for v in vessels:
		if not is_instance_valid(v) or not v.needs_report or v.reported:
			continue
		var d := p.distance_to(v.position)
		var small: bool = v.kind == "unlit"
		var seen: bool = d < VISUAL_RANGE or d < radar_range * (0.6 if small else 0.85)
		if seen and v.detected_at < 0.0:
			v.detected_at = mission_time
			log_line(who("ops"), T("New radar contact, %s.", "Nouveau contact radar, %s.") % _bearing_words(v.position), "#9fb4bf")
		if v.detected_at >= 0.0 and mission_time - v.detected_at > 30.0:
			v.reported = true
			log_line(who("lookout"), T("Bridge, lookout: contact %s, %s! Was nobody reporting it?", "Passerelle, ici la vigie : contact %s, %s ! Personne ne l'avait signalé ?") % [_bearing_words(v.position), v.contact_desc])
			score("awareness", -6, T("The lookout had to report a contact for you", "La vigie a dû signaler un contact à votre place"))


# ======================================================================
# Main loop
# ======================================================================

func _process(delta: float) -> void:
	if toast_t > 0.0:
		toast_t -= delta
		if toast_t <= 0.0:
			toast.text = ""
	if player:
		cam.position = player.position
	if not paused and phase == "sail":
		mission_time += delta
		for v in vessels.duplicate():
			if is_instance_valid(v):
				v.step(delta)
		_check_ground(delta)
		match era:
			"modern":
				_m1_logic(delta)
			"1942":
				_echo_logic(delta)
			"sable":
				_m2_logic(delta)
	_update_fog()
	_update_hud()
	overlay.queue_redraw()
	trail_layer.queue_redraw()
	radar.queue_redraw()


func _update_fog() -> void:
	if player == null:
		return
	match era:
		"modern":
			var at_sea: float = clampf((player.position.y - 3400.0) / 800.0, 0.0, 1.0)
			fog_mat.set_shader_parameter("inner", lerpf(0.16, 0.24, at_sea))
			fog_mat.set_shader_parameter("outer", lerpf(0.48, 0.62, at_sea))
			fog_mat.set_shader_parameter("strength", lerpf(0.82, 0.7, at_sea))
		"1942":
			fog_mat.set_shader_parameter("inner", 0.16)
			fog_mat.set_shader_parameter("outer", 0.5)
			fog_mat.set_shader_parameter("strength", 0.85)
		"sable":
			fog_mat.set_shader_parameter("inner", 0.26)
			fog_mat.set_shader_parameter("outer", 0.75)
			fog_mat.set_shader_parameter("strength", 0.45)


func _check_ground(delta: float) -> void:
	ground_cooldown = maxf(0.0, ground_cooldown - delta)
	var bow: Vector2 = player.position + player.dir() * 36.0
	var stern: Vector2 = player.position - player.dir() * 36.0
	var blocked: bool = (not world.is_water(bow)) or (not world.is_water(stern)) or world.gate_blocks(bow)
	if not blocked:
		safe_timer += delta
		if safe_timer > 0.5 and world.is_water(player.position, 40.0):
			safe_timer = 0.0
			safe_positions.append([player.position, player.heading])
			if safe_positions.size() > 12:
				safe_positions.pop_front()
		return
	player.speed = 0.0
	player.telegraph = 0
	player.rudder = 0
	var back = safe_positions[maxi(0, safe_positions.size() - 5)] if safe_positions.size() > 0 else [player.position - player.dir() * 60.0, player.heading]
	player.position = back[0]
	player.heading = back[1]
	safe_positions.clear()
	if ground_cooldown <= 0.0:
		ground_cooldown = 3.0
		if world.gate_blocks(bow):
			log_line(who("oow"), T("Stop! The gate is closed. Back off the net!", "Stoppez ! La porte est fermée. Dégagez du filet !"), "#ff8a7a")
		else:
			log_line(hale(), T("We've touched bottom! I have the ship... All right, you have the ship again. Keep to deep water.", "Nous avons touché le fond ! Je prends la manœuvre... Bon, vous reprenez la manœuvre. Restez en eau profonde."), "#ff8a7a")
		if era != "1942":
			score("execution", -12, T("Ran the ship aground", "Échouement du navire"))
			score("team", -4, T("Crew put at risk by grounding", "Équipage mis en danger par l'échouement"))


func _escort_gap(delta: float, limit: float) -> void:
	if port_royal == null:
		return
	if player.position.distance_to(port_royal.position) > limit:
		gap_t += delta
		if gap_t > 5.0 and gap_penalty < 12:
			gap_t = 0.0
			gap_penalty += 3
			score("execution", -3, T("Port Royal left far behind; slow down for your charge", "Port Royal laissé loin derrière ; ralentissez pour votre protégé"))
	else:
		gap_t = 0.0


# ======================================================================
# MISSION 1: Harbour Departure, Halifax
# ======================================================================

func _setup_m1() -> void:
	era = "modern"
	_reset_common()
	world.set_era("modern")
	radar_range = 1300.0
	RenderingServer.set_default_clear_color(Color("d9cfae"))
	fog_mat.set_shader_parameter("fog_color", Color(0.86, 0.88, 0.89))
	player = _spawn("frigate", Vector2(40, 150), 160.0, "HMCS Laurentian")
	player.is_player = true
	player.hull_no = "344"
	player.max_kn = 26.0
	for p in [[Vector2(-420, -200), 70.0], [Vector2(-300, 260), 20.0], [Vector2(380, -260), 300.0]]:
		_spawn("merchant", p[0], p[1], "")
	ferry = _spawn("ferry", Vector2(560, 1870), 75.0, T("harbour ferry", "traversier"))
	ferry.cruise_kn = 6.0
	ferry.needs_report = true
	ferry.contact_desc = T("harbour ferry, lit, crossing", "traversier, feux allumés, en traversée")
	unlit = _spawn("unlit", Vector2(760, 2980), 250.0, T("unknown small craft", "embarcation inconnue"))
	unlit.lit = false
	unlit.cruise_kn = 1.0
	unlit.needs_report = true
	unlit.contact_desc = T("small craft, no lights", "petite embarcation, sans feux")
	port_royal = _spawn("merchant", POINT_ECHO + Vector2(170, -60), 190.0, "MV Port Royal")
	port_royal.hold = true
	cam.position = player.position


func _brief_m1(page: int) -> void:
	var pages := [
		[T("ORDERS 1/3 · SITUATION", "ORDRES 1/3 · SITUATION"),
		T("[b]Situation.[/b] Thick fog over Halifax Harbour; visibility under a mile. Last week the container ship [i]Atlantic Meridian[/i] vanished off Sable Island carrying a prototype sonar. Tonight MV [i]Port Royal[/i] sails with the replacement. An unknown small craft has been reported in the outer harbour.\n\n[b]Mission.[/b] HMCS [i]Laurentian[/i] sails from Bedford Basin, meets [i]Port Royal[/i] at Point Echo, and escorts her to open sea.",
		"[b]Situation.[/b] Brume épaisse sur le port de Halifax ; visibilité inférieure à un mille. La semaine dernière, le porte-conteneurs [i]Atlantic Meridian[/i] a disparu au large de l'île de Sable avec un sonar prototype. Ce soir, le NM [i]Port Royal[/i] appareille avec le remplaçant. Une petite embarcation inconnue a été signalée dans l'avant-port.\n\n[b]Mission.[/b] Le NCSM [i]Laurentian[/i] appareille du bassin de Bedford, rejoint le [i]Port Royal[/i] au point Écho et l'escorte jusqu'au large.")],
		[T("ORDERS 2/3 · EXECUTION", "ORDRES 2/3 · EXÉCUTION"),
		T("[b]Execution.[/b] You have the watch.\n  Phase 1: Bedford Basin to the Narrows.\n  Phase 2: Through the Narrows. [color=#f2c46d]Maximum ten knots (Half ahead).[/color]\n  Phase 3: Meet [i]Port Royal[/i] at Point Echo.\n  Phase 4: Escort her south to the sea buoy.\n\n[b]Service support.[/b] Fuel full. Boarding team and RHIB at five minutes' notice. Helicopter grounded by fog.\n\n[b]Command & signal.[/b] Captain: Capt(N) Margaret Hale. Shore operations call sign: [i]Trafalgar Ops[/i]. Report every contact to the Captain. On the radio: read back, say \"wilco\", end with \"out\".",
		"[b]Exécution.[/b] Vous avez le quart.\n  Phase 1 : du bassin de Bedford au Goulet.\n  Phase 2 : traversée du Goulet. [color=#f2c46d]Dix nœuds maximum (en avant demie).[/color]\n  Phase 3 : rejoindre le [i]Port Royal[/i] au point Écho.\n  Phase 4 : l'escorter vers le sud jusqu'à la bouée de mer.\n\n[b]Soutien.[/b] Plein de carburant. Équipe d'arraisonnement et embarcation à cinq minutes de préavis. Hélicoptère cloué au sol par la brume.\n\n[b]Commandement et transmissions.[/b] Commandant : Capv Margaret Hale. Indicatif des opérations à terre : [i]Trafalgar Ops[/i]. Signalez chaque contact au commandant. À la radio : collationnez, dites « compris, j'exécute », terminez par « terminé ».")],
		[T("ORDERS 3/3 · COMMANDER'S INTENT", "ORDRES 3/3 · INTENTION DU COMMANDANT"),
		T("[i]\"Port Royal reaches open sea safely. And in my waters, nobody who needs help is left behind.\"[/i]\n          Capt(N) M. Hale\n\n[color=#9fb4bf]The intent is the [b]why[/b] behind the orders. When the plan breaks, act inside the intent, and tell your Captain.[/color]",
		"[i]« Le Port Royal atteint le large en sécurité. Et dans mes eaux, personne qui a besoin d'aide n'est laissé derrière. »[/i]\n          Capv M. Hale\n\n[color=#9fb4bf]L'intention, c'est le [b]pourquoi[/b] des ordres. Quand le plan déraille, agissez dans le cadre de l'intention, et informez votre commandant.[/color]")],
	]
	var p: Array = pages[page]
	if page < 2:
		show_modal(p[0], p[1], [T("Next", "Suivant")], func(_i): _brief_m1(page + 1))
	else:
		show_modal(p[0], p[1], [T("Read back the orders", "Collationner les ordres")], func(_i): _readback_m1())


func _readback_m1() -> void:
	show_modal(T("READ-BACK", "COLLATIONNEMENT"),
		T("Captain Hale: \"Officer of the Watch, before you take her out: what is my intent?\"", "Commandant Hale : « Officier de quart, avant d'appareiller : quelle est mon intention ? »"),
		[T("\"Get Laurentian to sea as fast as possible.\"", "« Mettre le Laurentian au large le plus vite possible. »"),
		T("\"Port Royal reaches open sea safely, and nobody who needs help in our waters is left behind, ma'am.\"", "« Le Port Royal atteint le large en sécurité, et personne qui a besoin d'aide dans nos eaux n'est laissé derrière, Commandant. »"),
		T("\"Find the ship that vanished off Sable Island.\"", "« Retrouver le navire disparu au large de l'île de Sable. »")],
		_on_readback_m1)


func _on_readback_m1(i: int) -> void:
	if i == 1:
		score("discipline", 6, T("Read back the Captain's intent correctly", "Intention du commandant correctement collationnée"))
		log_line(hale(), T("Correct. You have the watch, %s. Take her out.", "Exact. Vous avez le quart, %s. Appareillez.") % player_short())
	else:
		score("discipline", -4, T("Misread the Captain's intent at the briefing", "Intention du commandant mal comprise au briefing"))
		log_line(hale(), T("No. My intent: Port Royal safe at sea, and nobody left without help. Remember it. You have the watch.", "Non. Mon intention : le Port Royal en sécurité au large, et personne laissé sans aide. Retenez-le. Vous avez le quart."))
	_start_sail(T("Phase 1 · Steer for the Narrows (south-east). Half ahead is a good speed.", "Phase 1 · Cap sur le Goulet (sud-est). En avant demie est une bonne vitesse."),
		[[hale(), T("Officer of the Watch, half ahead, steer for the Narrows. Ten knots maximum in the Narrows.", "Officier de quart, en avant demie, cap sur le Goulet. Dix nœuds maximum dans le Goulet.")],
		[who("helm"), T("Ready on the wheel, %s.", "Paré à la barre, %s.") % sir_maam()]])


func _hail() -> void:
	hailed = true
	log_line(who("you"), T("Unknown vessel south of Point Pleasant, this is Canadian warship Laurentian, Channel one-six. Show your lights and state your intentions. Over.",
		"Navire inconnu au sud de Point Pleasant, ici le navire de guerre canadien Laurentian, canal un-six. Allumez vos feux et indiquez vos intentions. À vous."), "#f2c46d")
	log_line(who("radio"), T("(no reply)", "(aucune réponse)"), "#9fb4bf")
	unlit.cruise_kn = 22.0
	unlit.heading = 215.0
	score("awareness", 4, T("Hailed the unlit craft; its escape is logged for intelligence", "Embarcation sans feux hélée ; sa fuite est consignée pour le renseignement"))
	log_line(who("ops"), T("Contact accelerating to twenty knots, heading south-west into the fog. Logged.", "Le contact accélère à vingt nœuds, cap sud-ouest dans la brume. Consigné."))


func _launch_rhib() -> void:
	if player.speed > 5.5:
		log_line(who("cox"), T("Too fast to launch, %s. Five knots or less.", "Trop vite pour la mise à l'eau, %s. Cinq nœuds maximum.") % sir_maam())
		score("team", -3, T("Ordered a boat launch at unsafe speed", "Mise à l'eau ordonnée à une vitesse dangereuse"))
		return
	rhib = _spawn("rhib", player.position + player.dir().orthogonal() * 20.0, player.heading, T("RHIB", "Embarcation"))
	rhib.follow = lady_hannah
	rhib.follow_gap = 18.0
	rhib.max_follow_kn = 24.0
	rhib_state = "out"
	log_line(who("you"), T("Away the RHIB. Recover the crew of Lady Hannah.", "Embarcation à l'eau. Récupérez l'équipage du Lady Hannah."))
	log_line(who("cox"), T("RHIB away. Four aboard, plus the medic.", "Embarcation à l'eau. Quatre à bord, plus le technicien médical."))
	score("execution", 6, T("Launched the RHIB safely", "Embarcation mise à l'eau en sécurité"))


func _m1_logic(delta: float) -> void:
	var p: Vector2 = player.position
	_detect_contacts()
	if ferry and ferry.position.x > 1300:
		ferry.position = Vector2(520, 1880)
	if unlit and is_instance_valid(unlit) and unlit.position.distance_to(p) > 2600 and unlit.cruise_kn > 10:
		_despawn(unlit)
		unlit = null
	elif unlit and is_instance_valid(unlit) and unlit.reported and not hailed and stage >= 4:
		hailed = true
		unlit.cruise_kn = 22.0
		unlit.heading = 215.0
		log_line(who("ops"), T("The unlit craft is running south-west at twenty knots. Lost in the fog.", "L'embarcation sans feux file vers le sud-ouest à vingt nœuds. Perdue dans la brume."))
	if world.in_narrows(p) and player.speed > 10.5:
		over_limit_t += delta
		if not limit_warned:
			limit_warned = true
			log_line(hale(), T("Officer of the Watch, you're over the limit in the Narrows. Ten knots.", "Officier de quart, vous dépassez la limite dans le Goulet. Dix nœuds."), "#ff8a7a")
		if over_limit_t > 3.0 and limit_penalty < 16:
			over_limit_t = 0.0
			limit_penalty += 2
			score("discipline", -2, T("Over the 10-knot limit in the Narrows", "Au-delà de 10 nœuds dans le Goulet"))
	match stage:
		0:
			if p.distance_to(Vector2(290, 740)) < 280:
				stage = 1
				objective = T("Phase 2 · Transit the Narrows · 10 knots max · under the two bridges", "Phase 2 · Traversée du Goulet · 10 nœuds max · sous les deux ponts")
				log_line(hale(), T("Entering the Narrows. Watch your speed and keep to the middle.", "Nous entrons dans le Goulet. Surveillez la vitesse et restez au milieu."))
		1:
			if p.distance_to(WorldScript.NARROWS_B) < 260:
				stage = 2
				objective = T("Phase 3 · Proceed to Point Echo (marked) and meet MV Port Royal", "Phase 3 · Rejoindre le point Écho (marqué) et le NM Port Royal")
				if limit_penalty == 0:
					score("discipline", 5, T("Kept the Narrows speed limit", "Limite de vitesse respectée dans le Goulet"))
				log_line(hale(), T("Through the Narrows. Proceed to Point Echo. You may increase speed.", "Goulet franchi. Rejoignez le point Écho. Vous pouvez augmenter la vitesse."))
		2:
			if p.distance_to(POINT_ECHO) < 320:
				stage = 3
				_ops_order()
		4:
			_escort_gap(delta, 1100.0)
			if p.y > 3880 and mayday_t < 0.0:
				mayday_t = mission_time
				log_line(who("ch16"), T("MAYDAY MAYDAY MAYDAY. This is fishing vessel Lady Hannah... taking water... four persons... west of Chebucto Head...",
					"MAYDAY MAYDAY MAYDAY. Ici le bateau de pêche Lady Hannah... voie d'eau... quatre personnes... à l'ouest du cap Chebucto..."), "#ff8a7a")
				lady_hannah = _spawn("fishing", Vector2(330, 4420), 300.0, "FV Lady Hannah")
				lady_hannah.distress = true
			if mayday_t >= 0.0 and mission_time - mayday_t > 2.5:
				stage = 41
				_break_m1()
		5:
			_rhib_logic(delta)
		6:
			if port_royal and p.distance_to(port_royal.position) < 380:
				stage = 7
				port_royal.hold = false
				port_royal.follow = player
				objective = T("Phase 4 · Escort Port Royal south to the sea buoy (marked)", "Phase 4 · Escorter le Port Royal vers le sud jusqu'à la bouée de mer (marquée)")
				log_line(who("you"), T("Port Royal, Laurentian. Resuming escort, follow in my wake. Over.", "Port Royal, ici Laurentian. Reprise de l'escorte, suivez dans mon sillage. À vous."))
				log_line("MV Port Royal", T("Laurentian, Port Royal. Following. Good work out there. Out.", "Laurentian, ici Port Royal. Nous suivons. Beau travail. Terminé."))
		7:
			_escort_gap(delta, 1100.0)
			if p.distance_to(SEA_BUOY) < 300:
				if port_royal and port_royal.position.distance_to(SEA_BUOY) < 900:
					_m1_complete()
				elif not waited_warned:
					log_line(hale(), T("We don't leave our charge behind. Wait for Port Royal.", "On ne laisse pas notre protégé derrière. Attendez le Port Royal."))
					waited_warned = true


func _ops_order() -> void:
	player.telegraph = mini(player.telegraph, 1)
	log_line("Trafalgar Ops", T("Laurentian, this is Trafalgar Ops. Escort MV Port Royal from Point Echo to the sea buoy. Over.", "Laurentian, ici Trafalgar Ops. Escortez le NM Port Royal du point Écho à la bouée de mer. À vous."))
	show_modal(T("RADIO · TRAFALGAR OPS", "RADIO · TRAFALGAR OPS"),
		T("[i]\"Laurentian, this is Trafalgar Ops. Escort MV Port Royal from Point Echo to the sea buoy. Over.\"[/i]\n\nHow do you answer?",
		"[i]« Laurentian, ici Trafalgar Ops. Escortez le NM Port Royal du point Écho à la bouée de mer. À vous. »[/i]\n\nQue répondez-vous ?"),
		[T("\"Trafalgar Ops, Laurentian. Escort Port Royal from Point Echo to the sea buoy. Wilco. Out.\"", "« Trafalgar Ops, ici Laurentian. Escorter le Port Royal du point Écho à la bouée de mer. Compris, j'exécute. Terminé. »"),
		T("\"Roger wilco, over and out.\"", "« Reçu, j'exécute, à vous, terminé. »"),
		T("\"Copy that, we'll take care of it.\"", "« OK, on s'en occupe. »")],
		_on_ops_ack)


func _on_ops_ack(i: int) -> void:
	match i:
		0:
			score("discipline", 6, T("Correct read-back and radio procedure", "Collationnement et procédure radio corrects"))
		1:
			score("discipline", 1, T("\"Over and out\" contradicts itself: over expects a reply, out ends the call", "« À vous, terminé » se contredit : « à vous » attend une réponse, « terminé » clôt l'appel"))
		2:
			score("discipline", -3, T("No read-back and informal radio language", "Pas de collationnement et langage radio familier"))
	stage = 4
	port_royal.hold = false
	port_royal.follow = player
	port_royal.follow_gap = 280.0
	objective = T("Phase 4 · Escort Port Royal south to the sea buoy. Keep her close.", "Phase 4 · Escorter le Port Royal vers le sud jusqu'à la bouée de mer. Gardez-le près.")
	log_line("MV Port Royal", T("Laurentian, Port Royal. Following in your wake. Out.", "Laurentian, ici Port Royal. Nous suivons dans votre sillage. Terminé."))


func _break_m1() -> void:
	show_modal(T("THE BREAK · MAYDAY", "LE POINT DE RUPTURE · MAYDAY"),
		T("Fishing vessel [i]Lady Hannah[/i] is taking water, four people aboard, about two miles to the west. You are escorting [i]Port Royal[/i]. The Captain is on the bridge, looking at you.\n\n[color=#9fb4bf]Remember the intent.[/color]",
		"Le bateau de pêche [i]Lady Hannah[/i] fait eau, quatre personnes à bord, à environ deux milles à l'ouest. Vous escortez le [i]Port Royal[/i]. Le commandant est sur la passerelle et vous regarde.\n\n[color=#9fb4bf]Souvenez-vous de l'intention.[/color]"),
		[T("Keep escorting. The mayday is not our tasking.", "Continuer l'escorte. Le mayday ne fait pas partie de notre mission."),
		T("Turn toward Lady Hannah right now. Tell the Captain later.", "Virer vers le Lady Hannah immédiatement. Informer le commandant plus tard."),
		T("\"Captain, ma'am: mayday, Lady Hannah, two miles west. Recommend we divert and launch the RHIB; Port Royal holds here.\"", "« Commandant : mayday, Lady Hannah, deux milles à l'ouest. Je recommande de dérouter et de mettre l'embarcation à l'eau ; le Port Royal reste ici. »"),
		T("Call Trafalgar Ops and wait for instructions.", "Appeler Trafalgar Ops et attendre des instructions.")],
		_on_break_m1)


func _on_break_m1(i: int) -> void:
	break_choice = i
	match i:
		0:
			score("initiative", -15, T("Ignored a mayday inside the Captain's intent", "Mayday ignoré alors qu'il relevait de l'intention du commandant"))
			score("team", -8, T("Left mariners in danger", "Marins laissés en danger"))
			log_line(hale(), T("No. Every mariner answers a mayday, and my intent was clear. I have the ship.", "Non. Tout marin répond à un mayday, et mon intention était claire. Je prends la manœuvre."), "#ff8a7a")
		1:
			score("initiative", 8, T("Acted at once on the mayday", "Réaction immédiate au mayday"))
			score("discipline", -8, T("Changed the ship's tasking without telling the Captain", "Mission du navire changée sans informer le commandant"))
			score("execution", -4, T("Port Royal left without orders", "Port Royal laissé sans ordres"))
			log_line(hale(), T("Right call, wrong way. Next time you tell me first. Carry on.", "Bonne décision, mauvaise façon. La prochaine fois, prévenez-moi d'abord. Continuez."))
		2:
			score("initiative", 12, T("Proposed a plan inside the Captain's intent", "Plan proposé dans le cadre de l'intention du commandant"))
			score("discipline", 6, T("Reported up before acting", "Rapport à la chaîne de commandement avant d'agir"))
			score("team", 5, T("Kept Port Royal informed and safe", "Port Royal tenu informé et en sécurité"))
			log_line(hale(), T("Approved. Make it so.", "Approuvé. Exécutez."))
			log_line(who("you"), T("Port Royal, Laurentian. Hold this position, we are answering a mayday. Over.", "Port Royal, ici Laurentian. Maintenez cette position, nous répondons à un mayday. À vous."))
			log_line("MV Port Royal", T("Laurentian, Port Royal. Holding. Good luck. Out.", "Laurentian, ici Port Royal. Nous maintenons. Bonne chance. Terminé."))
		3:
			score("initiative", -6, T("Waited for permission while lives were at risk", "Attente d'une permission alors que des vies étaient en jeu"))
			log_line(hale(), T("A mayday doesn't wait for a phone call. We're going. Your plan next time, %s.", "Un mayday n'attend pas un coup de fil. On y va. La prochaine fois, votre plan, %s.") % player_short())
	port_royal.follow = null
	port_royal.hold = true
	stage = 5
	objective = T("Rescue · Close Lady Hannah (west), slow to 5 knots or less, launch the RHIB", "Sauvetage · Approchez le Lady Hannah (ouest), ralentissez à 5 nœuds ou moins, mettez l'embarcation à l'eau")


func _rhib_logic(delta: float) -> void:
	if rhib == null:
		return
	match rhib_state:
		"out":
			if rhib.position.distance_to(lady_hannah.position) < 30.0:
				rhib_state = "recover"
				rhib_timer = 4.0
				rhib.follow = null
				rhib.hold = true
				log_line(who("cox"), T("Alongside Lady Hannah. Taking off the crew... one, two, three, four. All aboard.", "À couple du Lady Hannah. Évacuation de l'équipage... un, deux, trois, quatre. Tous à bord."))
		"recover":
			rhib_timer -= delta
			if rhib_timer <= 0.0:
				rhib_state = "back"
				rhib.hold = false
				rhib.follow = player
				rhib.follow_gap = 20.0
				lady_hannah.distress = false
		"back":
			if rhib.position.distance_to(player.position) < 40.0:
				rhib_state = "done"
				_despawn(rhib)
				rhib = null
				score("execution", 10, T("Four fishermen recovered alive", "Quatre pêcheurs récupérés vivants"))
				score("team", 6, T("RHIB crew brought home safely", "Équipage de l'embarcation ramené en sécurité"))
				log_line(who("medic"), T("Four survivors aboard, cold but fine.", "Quatre rescapés à bord, frigorifiés mais en bon état."))
				log_line(hale(), T("Well done, everyone. Now get us back to Port Royal.", "Bien joué, tout le monde. Maintenant, ramenez-nous au Port Royal."))
				stage = 6
				objective = T("Rejoin Port Royal (marked) and resume the escort", "Rejoindre le Port Royal (marqué) et reprendre l'escorte")


func _m1_complete() -> void:
	phase = "done"
	paused = true
	log_line(hale(), T("Sea buoy abeam. Port Royal is clear. Fall out from harbour stations.", "Bouée de mer par le travers. Le Port Royal est dégagé. Rompez les postes de manœuvre."))
	if unlit and is_instance_valid(unlit) and not unlit.reported:
		score("awareness", -5, T("Never reported the unlit craft", "Embarcation sans feux jamais signalée"))
	_debrief(T("Escort Port Royal to sea; nobody left without help.", "Escorter le Port Royal au large ; personne laissé sans aide."),
		T("History: in 1942 these same waters held the convoys of the Battle of the Atlantic, guarded by an anti-submarine net and gate off Point Pleasant. Play the Echo to sail them.",
		"Histoire : en 1942, ces mêmes eaux abritaient les convois de la bataille de l'Atlantique, protégés par un filet et une porte anti-sous-marins au large de Point Pleasant. Jouez l'Écho pour les parcourir."),
		[T("Play Echo: Halifax, 1942", "Jouer l'Écho : Halifax, 1942"), T("Next: Mission 2 · Sable Island Boarding", "Suivant : Mission 2 · Arraisonnement à l'île de Sable"), T("Sail this mission again", "Rejouer cette mission")],
		_on_m1_debrief)


func _on_m1_debrief(i: int) -> void:
	match i:
		0: _echo_intro()
		1: _start_mission(2)
		2: _start_mission(1)


# ======================================================================
# Debrief (shared)
# ======================================================================

func _debrief(planned: String, history: String, options: Array, cb: Callable) -> void:
	var total := 0
	for k in scores:
		total += scores[k]
	var avg := int(round(total / 5.0))
	var grade := ""
	if avg >= 85:
		grade = T("Mentioned in Dispatches", "Citation à l'ordre du jour")
	elif avg >= 72:
		grade = T("Well done", "Bien joué")
	elif avg >= 58:
		grade = T("Satisfactory", "Satisfaisant")
	else:
		grade = T("Needs improvement", "À améliorer")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	for k in PILLARS:
		var l := Label.new()
		l.text = PILLAR_NAME[lang][k]
		l.custom_minimum_size = Vector2(140, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(l)
		var pb := ProgressBar.new()
		pb.max_value = 100
		pb.value = scores[k]
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(clampf(modal_panel.custom_minimum_size.x - 260.0, 140.0, 440.0), 22)
		grid.add_child(pb)
		var n := Label.new()
		n.text = str(scores[k])
		grid.add_child(n)
	var good: PackedStringArray = []
	var bad: PackedStringArray = []
	for e in aar:
		if e["delta"] > 0:
			good.append("• " + e["why"])
		else:
			bad.append("• " + e["why"])
	var body := T("[b]Command Rating: %d · %s[/b]\n\n", "[b]Cote de commandement : %d · %s[/b]\n\n") % [avg, grade]
	body += T("[color=#f2c46d]PLANNED[/color]  ", "[color=#f2c46d]PRÉVU[/color]  ") + planned + "\n"
	body += T("[color=#f2c46d]SUSTAIN[/color]\n", "[color=#f2c46d]À MAINTENIR[/color]\n") + ("\n".join(good) if good.size() else "• —") + "\n"
	body += T("[color=#f2c46d]IMPROVE[/color]\n", "[color=#f2c46d]À AMÉLIORER[/color]\n") + ("\n".join(bad) if bad.size() else T("• Nothing. Clean watch.", "• Rien. Quart impeccable.")) + "\n\n"
	body += "[color=#9fb4bf]" + T("Promotion points earned: %d. ", "Points de promotion gagnés : %d. ") % (avg * 10) + history + "[/color]"
	show_modal(T("AFTER ACTION REVIEW", "RETOUR D'EXPÉRIENCE"), body, options, cb, grid)


# ======================================================================
# ECHO 1942: you are the helmsman. Follow the Officer of the Watch's orders exactly.
# ======================================================================

func _echo_intro() -> void:
	era = "1942"
	_reset_common()
	world.set_era("1942")
	world.gate_open = false
	world.queue_redraw()
	RenderingServer.set_default_clear_color(Color("2b2a24"))
	fog_mat.set_shader_parameter("fog_color", Color(0.01, 0.03, 0.05))
	player = _spawn("corvette", Vector2(40, 150), 160.0, "HMCS Rosedale")
	player.is_player = true
	player.max_kn = 16.0
	player.darkened = true
	for i in 10:
		var m = _spawn("merchant", Vector2(-600 + (i % 5) * 230, -380 + int(i / 5.0) * 260), 180.0, "")
		m.darkened = true
	echo_orders.clear()
	echo_rudder_order = 0
	echo_tele_order = 1
	echo_wp = 0
	echo_last_order_t = -10.0
	gate_t = -1.0
	cam.position = player.position
	show_modal(T("ECHO · HALIFAX, NOVEMBER 1942", "ÉCHO · HALIFAX, NOVEMBRE 1942"),
		T("Bedford Basin is full of merchant ships forming convoy for the crossing to Britain. U-boats wait offshore. The city is blacked out.\n\nYou are [b]Leading Seaman Tom MacLeod[/b], helmsman of the corvette HMCS [i]Rosedale[/i]. Tonight you do not give orders. You [b]follow[/b] them, exactly and at once.\n\nThe Officer of the Watch will call rudder and engine orders. Repeat them by setting the wheel and telegraph. An anti-submarine net guards the harbour mouth; the gate opens only for ships that answer the challenge.\n\n[color=#9fb4bf]Ashore at the signal station, Wren Rose Tremblay is on watch.[/color]",
		"Le bassin de Bedford est rempli de navires marchands qui forment un convoi pour traverser vers la Grande-Bretagne. Les U-boote attendent au large. La ville est plongée dans le black-out.\n\nVous êtes le [b]matelot de 1re classe Tom MacLeod[/b], barreur de la corvette NCSM [i]Rosedale[/i]. Ce soir, vous ne donnez pas d'ordres. Vous les [b]exécutez[/b], exactement et sur-le-champ.\n\nL'officier de quart annoncera les ordres de barre et de machine. Exécutez-les avec la barre et le transmetteur. Un filet anti-sous-marins garde l'entrée du port ; la porte ne s'ouvre qu'aux navires qui répondent au signal de reconnaissance.\n\n[color=#9fb4bf]À terre, à la station de signalisation, la Wren Rose Tremblay est de quart.[/color]"),
		[T("Take the wheel", "Prendre la barre")], func(_i): _echo_start())


func _echo_start() -> void:
	phase = "sail"
	paused = false
	objective = T("Echo 1942 · Follow every helm and engine order. Leave harbour through the net gate.", "Écho 1942 · Exécutez chaque ordre de barre et de machine. Sortez du port par la porte du filet.")
	log_line(who("oow"), T("Darken ship. Slow ahead.", "Obscurcissez le navire. En avant lente."), "#e0c27a")
	_echo_issue("tele", 1)


func _echo_issue(kind: String, value: int) -> void:
	echo_last_order_t = mission_time
	var text: String
	if kind == "tele":
		echo_tele_order = value
		text = tele_name(value)
	else:
		echo_rudder_order = value
		text = rudder_name(value)
	echo_orders.append({"kind": kind, "value": value, "at": mission_time, "obeyed": -1.0})
	order_label.text = T("ORDER: ", "ORDRE : ") + text.to_upper()
	log_line(who("oow"), text + ".", "#e0c27a")
	_echo_check_obey()


func _echo_check_obey() -> void:
	for o in echo_orders:
		if o["obeyed"] >= 0.0:
			continue
		var cur: int = player.telegraph if o["kind"] == "tele" else player.rudder
		if cur == o["value"]:
			o["obeyed"] = mission_time - o["at"]
	var pending := false
	for o in echo_orders:
		if o["obeyed"] < 0.0:
			pending = true
	if not pending:
		order_label.text = ""


func _echo_logic(_delta: float) -> void:
	var p: Vector2 = player.position
	var route: Array = WorldScript.ROUTE
	if echo_wp < route.size() and p.distance_to(route[echo_wp]) < 240.0:
		echo_wp += 1
	var gate_y := 2725.0
	var want_tele := 2
	if p.y < 500.0:
		want_tele = 1
	if p.y > gate_y - 700.0 and p.y < gate_y + 80.0:
		want_tele = 1 if world.gate_open else (0 if p.y > gate_y - 260.0 else 1)
	if want_tele != echo_tele_order and mission_time - echo_last_order_t > 2.5:
		_echo_issue("tele", want_tele)
	if not world.gate_open and p.y > gate_y - 750.0 and gate_t < 0.0:
		gate_t = mission_time
		log_line(who("signal"), T("Challenge flashed to the gate vessel by lamp... reply correct. Gate opening.", "Signal de reconnaissance envoyé au projecteur au navire-porte... réponse correcte. La porte s'ouvre."), "#e0c27a")
	if gate_t >= 0.0 and not world.gate_open and mission_time - gate_t > 7.0:
		world.gate_open = true
		world.queue_redraw()
		log_line(who("oow"), T("Gate's open. Steady as she goes through the middle.", "La porte est ouverte. Comme ça, droit au milieu."), "#e0c27a")
	if echo_wp < route.size():
		var to: Vector2 = route[echo_wp] - p
		var want := rad_to_deg(atan2(to.x, -to.y))
		var err := wrapf(want - player.heading, -180.0, 180.0)
		var want_r := echo_rudder_order
		if absf(err) > 35.0:
			want_r = 2 if err > 0 else -2
		elif absf(err) > 12.0:
			want_r = 1 if err > 0 else -1
		elif absf(err) < 5.0:
			want_r = 0
		if want_r != echo_rudder_order and mission_time - echo_last_order_t > 2.5 and player.speed > 1.0:
			_echo_issue("rudder", want_r)
	if p.y > 3900.0:
		_echo_end()


func _echo_end() -> void:
	phase = "done"
	paused = true
	order_label.text = ""
	var n := echo_orders.size()
	var ok := 0
	var total_t := 0.0
	for o in echo_orders:
		if o["obeyed"] >= 0.0 and o["obeyed"] < 5.0:
			ok += 1
			total_t += o["obeyed"]
	var avg_t := total_t / maxf(1.0, ok)
	var body := T("[b]Orders carried out within five seconds: %d of %d · average response %.1f s[/b]\n\n", "[b]Ordres exécutés en moins de cinq secondes : %d sur %d · temps de réaction moyen %.1f s[/b]\n\n") % [ok, n, avg_t]
	body += T("[i]Dear Tom,\nThe Basin is quiet tonight now your convoy has gone. I watched your lamp answer the challenge at the gate, and I knew it was you on the wheel. Come home to me in one piece, and come home a better sailor than you left.\nYours, Rose[/i]\n\n",
		"[i]Cher Tom,\nLe bassin est calme ce soir depuis que ton convoi est parti. J'ai vu ton projecteur répondre au signal à la porte, et j'ai su que c'était toi à la barre. Reviens-moi entier, et reviens meilleur marin que tu n'es parti.\nÀ toi, Rose[/i]\n\n")
	body += "[color=#9fb4bf]" + T("History: Canada began the Second World War with only a handful of warships and ended it with one of the largest navies in the world, much of it corvettes like this one, escorting convoys out of Halifax. HMCS [i]Sackville[/i], the last Flower-class corvette, is preserved in Halifax today. About 6,700 women served in the Women's Royal Canadian Naval Service, many as signallers.",
		"Histoire : le Canada a commencé la Seconde Guerre mondiale avec une poignée de navires de guerre et l'a terminée avec l'une des plus grandes marines du monde, composée en grande partie de corvettes comme celle-ci, qui escortaient les convois au départ de Halifax. Le NCSM [i]Sackville[/i], dernière corvette de la classe Flower, est conservé à Halifax. Environ 6 700 femmes ont servi dans le Service féminin de la Marine royale du Canada, beaucoup comme signaleuses.") + "[/color]\n\n"
	body += T("Everything you did as Officer of the Watch depends on sailors who do this well. That is why leaders learn to follow first.", "Tout ce que vous avez fait comme officier de quart repose sur des marins qui font bien ce travail. C'est pourquoi les chefs apprennent d'abord à obéir.")
	show_modal(T("ECHO COMPLETE", "ÉCHO TERMINÉ"), body, [T("Next: Mission 2 · Sable Island Boarding", "Suivant : Mission 2 · Arraisonnement à l'île de Sable"), T("Back to the title screen", "Retour à l'écran titre")],
		func(i):
			if i == 0:
				_start_mission(2)
			else:
				_show_title())


# ======================================================================
# MISSION 2: Sable Island Boarding
# ======================================================================

func _setup_m2() -> void:
	era = "sable"
	_reset_common()
	world.set_era("sable")
	radar_range = 2600.0
	RenderingServer.set_default_clear_color(Color("4f8299"))
	fog_mat.set_shader_parameter("fog_color", Color(0.78, 0.84, 0.88))
	player = _spawn("frigate", Vector2(-1700, 900), 70.0, "HMCS Laurentian")
	player.is_player = true
	player.hull_no = "344"
	player.max_kn = 26.0
	port_royal = _spawn("merchant", Vector2(-2050, 1050), 70.0, "MV Port Royal")
	port_royal.follow = player
	port_royal.follow_gap = 420.0
	port_royal.max_follow_kn = 14.0
	var boats := [
		[Vector2(300, 300), 200.0, "FV Marie-Claire", T("fishing vessel Marie-Claire of Lunenburg, AIS on, hauling gear. Normal.", "bateau de pêche Marie-Claire de Lunenburg, AIS actif, relève ses filets. Normal.")],
		[Vector2(1400, 1400), 120.0, "FV Cape Sable Rose", T("fishing vessel Cape Sable Rose, AIS on, steaming to the bank. Normal.", "bateau de pêche Cape Sable Rose, AIS actif, fait route vers le banc. Normal.")],
		[Vector2(3300, 900), 250.0, "FV Ocean Venture", T("fishing vessel Ocean Venture, AIS on, crew waving. Normal.", "bateau de pêche Ocean Venture, AIS actif, l'équipage salue. Normal.")],
	]
	for b in boats:
		var v = _spawn("fishing", b[0], b[1], b[2])
		v.cruise_kn = 2.0
		v.needs_report = true
		v.contact_desc = T("small vessel, AIS on", "petit navire, AIS actif")
		v.set_meta("id_text", b[3])
	trawler = _spawn("trawler", Vector2(4500, -1400), 290.0, T("unknown trawler", "chalutier inconnu"))
	trawler.lit = false
	trawler.ais = false
	trawler.cruise_kn = 2.5
	trawler.needs_report = true
	trawler.contact_desc = T("medium vessel, no AIS", "navire moyen, sans AIS")
	trawler.set_meta("id_text", T("trawler, no name painted on the hull, AIS switched off, crew pulling tarps over deck cargo. Suspicious.",
		"chalutier, aucun nom peint sur la coque, AIS éteint, l'équipage tire des bâches sur une cargaison en pontée. Suspect."))
	cam.position = player.position


func _brief_m2(page: int) -> void:
	var pages := [
		[T("ORDERS 1/3 · SITUATION", "ORDRES 1/3 · SITUATION"),
		T("[b]Situation.[/b] Two days out of Halifax, escorting MV [i]Port Royal[/i]. Clear weather, light haze. The craft that ran from you in the fog was tracked toward Sable Island Bank, where the [i]Atlantic Meridian[/i] vanished. Several fishing vessels are working the bank. One radar contact near the Gully has no AIS.\n\n[b]Mission.[/b] Identify every vessel near Sable Island, find the one carrying the stolen sonar, stop and board it, and keep [i]Port Royal[/i] safe.",
		"[b]Situation.[/b] À deux jours de Halifax, en escorte du NM [i]Port Royal[/i]. Temps clair, légère brume sèche. L'embarcation qui vous a échappé dans la brume a été suivie vers le banc de l'île de Sable, là où l'[i]Atlantic Meridian[/i] a disparu. Plusieurs bateaux de pêche travaillent sur le banc. Un contact radar près du Gully n'a pas d'AIS.\n\n[b]Mission.[/b] Identifier chaque navire près de l'île de Sable, trouver celui qui transporte le sonar volé, l'arrêter et l'arraisonner, tout en gardant le [i]Port Royal[/i] en sécurité.")],
		[T("ORDERS 2/3 · EXECUTION", "ORDRES 2/3 · EXÉCUTION"),
		T("[b]Execution.[/b] You have the watch.\n  Phase 1: Search east along the bank. Identify contacts by eye or with the CH-148 Cyclone.\n  Phase 2: When the suspect is found, close it and order it to stop on Channel 16.\n  Phase 3: Slow to 5 knots within 250 m and send the boarding party. [color=#f2c46d]Keep station close while they are aboard.[/color]\n  Phase 4: Lead [i]Port Royal[/i] to the rendezvous point. Keep her within about four miles.\n\n[b]Service support.[/b] Cyclone ready on deck. Naval Boarding Party at five minutes' notice. Sable Island is sand: stay off it.\n\n[b]Command & signal.[/b] Captain: Capt(N) Hale. Intelligence officer: LCdr Julian Marsh. [color=#f2c46d]Orders that change the mission come from the Captain.[/color]",
		"[b]Exécution.[/b] Vous avez le quart.\n  Phase 1 : fouiller le banc vers l'est. Identifier les contacts à vue ou avec le CH-148 Cyclone.\n  Phase 2 : une fois le suspect trouvé, s'en approcher et lui ordonner de stopper sur le canal 16.\n  Phase 3 : ralentir à 5 nœuds à moins de 250 m et envoyer l'équipe d'arraisonnement. [color=#f2c46d]Restez tout près pendant qu'elle est à bord.[/color]\n  Phase 4 : conduire le [i]Port Royal[/i] au point de rendez-vous. Gardez-le à moins de quatre milles environ.\n\n[b]Soutien.[/b] Cyclone prêt sur le pont. Équipe d'arraisonnement à cinq minutes de préavis. L'île de Sable n'est que du sable : restez-en à l'écart.\n\n[b]Commandement et transmissions.[/b] Commandant : Capv Hale. Officier du renseignement : Capc Julian Marsh. [color=#f2c46d]Les ordres qui changent la mission viennent du commandant.[/color]")],
		[T("ORDERS 3/3 · COMMANDER'S INTENT", "ORDRES 3/3 · INTENTION DU COMMANDANT"),
		T("[i]\"Find what was taken from the Atlantic Meridian and bring it home. Nothing we have not identified gets near Port Royal.\"[/i]\n          Capt(N) M. Hale",
		"[i]« Retrouver ce qui a été pris à l'Atlantic Meridian et le ramener. Rien que nous n'ayons identifié ne s'approche du Port Royal. »[/i]\n          Capv M. Hale")],
	]
	var p: Array = pages[page]
	if page < 2:
		show_modal(p[0], p[1], [T("Next", "Suivant")], func(_i): _brief_m2(page + 1))
	else:
		show_modal(p[0], p[1], [T("Read back the orders", "Collationner les ordres")], func(_i): _readback_m2())


func _readback_m2() -> void:
	show_modal(T("READ-BACK", "COLLATIONNEMENT"),
		T("Captain Hale: \"Who can change this mission's orders, Officer of the Watch?\"", "Commandant Hale : « Qui peut modifier les ordres de cette mission, officier de quart ? »"),
		[T("\"Any officer senior to me, ma'am.\"", "« N'importe quel officier plus haut gradé que moi, Commandant. »"),
		T("\"You, ma'am. The Captain.\"", "« Vous, Commandant. »"),
		T("\"Whoever is on the radio from Halifax.\"", "« Quiconque appelle de Halifax à la radio. »")],
		_on_readback_m2)


func _on_readback_m2(i: int) -> void:
	if i == 1:
		score("discipline", 6, T("Knows who commands the ship", "Sait qui commande le navire"))
		log_line(hale(), T("Correct. Remember that today. You have the watch.", "Exact. Souvenez-vous-en aujourd'hui. Vous avez le quart."))
	else:
		score("discipline", -3, T("Unsure who can change the mission", "Incertain de qui peut modifier la mission"))
		log_line(hale(), T("No. On this ship, mission changes come from me. Remember that today. You have the watch.", "Non. Sur ce navire, les changements de mission viennent de moi. Souvenez-vous-en aujourd'hui. Vous avez le quart."))
	_start_sail(T("Phase 1 · Search east along Sable Island Bank. Identify every contact (eyes or Cyclone).", "Phase 1 · Fouiller le banc de l'île de Sable vers l'est. Identifier chaque contact (à vue ou avec le Cyclone)."),
		[[hale(), T("Officer of the Watch, half ahead, search east. Use the helicopter, that's what it's for.", "Officier de quart, en avant demie, fouillez vers l'est. Servez-vous de l'hélicoptère, il est là pour ça.")],
		[who("helm"), T("Ready on the wheel, %s.", "Paré à la barre, %s.") % sir_maam()]])


func _nearest_unidentified(max_d: float):
	var best = null
	var bd := max_d
	for v in vessels:
		if not is_instance_valid(v) or v.identified or not v.has_meta("id_text"):
			continue
		if v == helo_target and helo_state != "":
			continue
		var d: float = player.position.distance_to(v.position)
		if d < bd:
			bd = d
			best = v
	return best


func _identify(v, by_helo: bool) -> void:
	if v.identified:
		return
	v.identified = true
	v.reported = true
	if v == trawler:
		trawler.vname = T("trawler (no name)", "chalutier (sans nom)")
	var src := who("flight") if by_helo else who("lookout")
	log_line(src, T("Contact identified: ", "Contact identifié : ") + str(v.get_meta("id_text")))
	if by_helo:
		score("awareness", 3, T("Used the helicopter to identify a contact", "Hélicoptère utilisé pour identifier un contact"))
		if not helo_used:
			helo_used = true
			score("team", 3, T("Put the whole team to work: air and sea", "Toute l'équipe mise à contribution : air et mer"))
	else:
		score("awareness", 4, T("Identified a contact by eye", "Contact identifié à vue"))
	if v == trawler and stage < 1:
		stage = 1
		objective = T("Phase 2 · Close the suspect trawler (marked)", "Phase 2 · Approcher le chalutier suspect (marqué)")
		log_line(hale(), T("That's our ghost. Close her, Officer of the Watch. Boarding party, stand by.", "Voilà notre fantôme. Approchez-le, officier de quart. Équipe d'arraisonnement, paré."))
		trawler.cruise_kn = 6.0
		trawler.heading = 60.0


func _identify_visual() -> void:
	var v = _nearest_unidentified(VISUAL_RANGE)
	if v:
		_identify(v, false)


func _launch_helo() -> void:
	var target = _nearest_unidentified(INF)
	if target == null:
		return
	helo_target = target
	helo = _spawn("helo", player.position, player.heading, "Cyclone")
	helo.follow = target
	helo.follow_gap = 40.0
	helo.max_follow_kn = 60.0
	helo_state = "out"
	log_line(who("you"), T("Flight deck, launch the Cyclone. Investigate contact %s.", "Pont d'envol, lancez le Cyclone. Enquêtez sur le contact %s.") % _bearing_words(target.position))
	log_line(who("flight"), T("Cyclone airborne, en route.", "Cyclone en vol, en route."))


func _helo_logic(delta: float) -> void:
	if helo == null:
		return
	match helo_state:
		"out":
			if not is_instance_valid(helo_target):
				helo_state = "back"
				helo.follow = player
			elif helo.position.distance_to(helo_target.position) < 70.0:
				helo_state = "look"
				helo_timer = 3.0
		"look":
			helo.follow = helo_target
			helo.follow_gap = 30.0
			helo_timer -= delta
			if helo_timer <= 0.0:
				_identify(helo_target, true)
				helo_state = "back"
				helo.follow = player
				helo.follow_gap = 10.0
		"back":
			if helo.position.distance_to(player.position) < 40.0:
				log_line(who("flight"), T("Cyclone on deck, secured.", "Cyclone posé et saisi."))
				_despawn(helo)
				helo = null
				helo_state = ""
				helo_target = null


func _order_stop() -> void:
	trawler_stopped = true
	trawler.cruise_kn = 0.0
	trawler.hold = true
	log_line(who("you"), T("Fishing vessel south of Sable Island, this is Canadian warship Laurentian on Channel one-six. Stop your vessel and prepare to be boarded. Over.",
		"Bateau de pêche au sud de l'île de Sable, ici le navire de guerre canadien Laurentian sur le canal un-six. Stoppez votre navire et préparez-vous à être arraisonné. À vous."), "#f2c46d")
	log_line(who("ch16"), T("...Laurentian... stopping. Out.", "...Laurentian... nous stoppons. Terminé."))
	score("discipline", 5, T("Hailed and ordered the stop before boarding", "Ordre de stopper donné avant l'arraisonnement"))
	objective = T("Phase 3 · Close to 250 m at 5 knots or less and send the boarding party", "Phase 3 · Approchez à 250 m à 5 nœuds ou moins et envoyez l'équipe d'arraisonnement")


func _launch_boarding() -> void:
	if player.speed > 5.5:
		log_line(who("cox"), T("Too fast to launch, %s. Five knots or less.", "Trop vite pour la mise à l'eau, %s. Cinq nœuds maximum.") % sir_maam())
		score("team", -3, T("Ordered a boat launch at unsafe speed", "Mise à l'eau ordonnée à une vitesse dangereuse"))
		return
	rhib = _spawn("rhib", player.position + player.dir().orthogonal() * 22.0, player.heading, T("Boarding party", "Équipe d'arraisonnement"))
	rhib.follow = trawler
	rhib.follow_gap = 22.0
	rhib.max_follow_kn = 24.0
	rhib_state = "out"
	log_line(who("you"), T("Away the boarding party.", "Équipe d'arraisonnement, à l'eau."))
	log_line(who("board"), T("Boarding party away. Eight aboard.", "Équipe d'arraisonnement à l'eau. Huit à bord."))
	score("execution", 5, T("Launched the boarding party safely", "Équipe d'arraisonnement mise à l'eau en sécurité"))


func _boarding_logic(delta: float) -> void:
	if rhib == null:
		return
	match rhib_state:
		"out":
			if rhib.position.distance_to(trawler.position) < 32.0:
				rhib_state = "aboard"
				rhib_timer = 12.0
				rhib.follow = null
				rhib.hold = true
				log_line(who("board"), T("Boarding party aboard. Crew of five mustered on the foredeck. Searching.", "Équipe d'arraisonnement à bord. Équipage de cinq rassemblé sur le pont avant. Fouille en cours."))
		"aboard":
			rhib_timer -= delta
			if player.position.distance_to(trawler.position) > 600.0 and not drift_warned:
				drift_warned = true
				score("team", -5, T("Drifted away from the boarding party", "Éloigné de l'équipe d'arraisonnement"))
				log_line(who("board"), T("Laurentian, you're opening the range! Stay close, we may need to get off fast.", "Laurentian, vous vous éloignez ! Restez près, on pourrait devoir évacuer vite."), "#ff8a7a")
			if rhib_timer <= 0.0:
				if not drift_warned:
					score("team", 5, T("Kept close station while the boarding party was aboard", "Position tenue près de l'équipe d'arraisonnement"))
				score("execution", 12, T("Recovered the stolen sonar", "Sonar volé récupéré"))
				log_line(who("board"), T("Under the tarps: six crates stamped with the Atlantic Meridian's cargo numbers. Prototype sonar recovered. Master detained.",
					"Sous les bâches : six caisses portant les numéros de cargaison de l'Atlantic Meridian. Sonar prototype récupéré. Capitaine détenu."))
				log_line(who("board"), T("One more thing: the master had a printout of our patrol plan. Somebody aboard Laurentian gave it to them.",
					"Autre chose : le capitaine avait une copie imprimée de notre plan de patrouille. Quelqu'un à bord du Laurentian le leur a donné."), "#ff8a7a")
				rhib_state = "back"
				rhib.hold = false
				rhib.follow = player
				rhib.follow_gap = 20.0
		"back":
			if rhib.position.distance_to(player.position) < 40.0:
				rhib_state = "done"
				_despawn(rhib)
				rhib = null
				stage = 4
				objective = T("Phase 4 · Lead Port Royal to the rendezvous point (marked, west)", "Phase 4 · Conduire le Port Royal au point de rendez-vous (marqué, à l'ouest)")
				log_line(hale(), T("Boarding party recovered. The trawler will be escorted in by the Coast Guard. Take us to the rendezvous.", "Équipe d'arraisonnement récupérée. La Garde côtière escortera le chalutier. Conduisez-nous au rendez-vous."))


func _m2_logic(delta: float) -> void:
	var p: Vector2 = player.position
	_detect_contacts()
	_helo_logic(delta)
	_escort_gap(delta, 1500.0)
	match stage:
		1:
			if p.distance_to(trawler.position) < 1100.0:
				stage = 2
				_break_m2()
		3:
			_boarding_logic(delta)
		4:
			if p.distance_to(M2_RENDEZVOUS) < 320.0:
				if port_royal.position.distance_to(M2_RENDEZVOUS) < 1000.0:
					_m2_complete()
				elif not waited_warned:
					waited_warned = true
					log_line(hale(), T("Not without Port Royal. Wait for her.", "Pas sans le Port Royal. Attendez-le."))
		5:
			if trawler and is_instance_valid(trawler) and trawler.position.distance_to(p) > 3500.0:
				_despawn(trawler)
				trawler = null
			if p.distance_to(M2_RENDEZVOUS) < 320.0 and port_royal.position.distance_to(M2_RENDEZVOUS) < 1000.0:
				_m2_complete()


func _break_m2() -> void:
	log_line(who("marsh"), T("Bridge, Marsh here. The Captain says break off. Leave the trawler and rejoin Port Royal immediately. Her orders.",
		"Passerelle, ici Marsh. Le commandant dit de rompre. Laissez le chalutier et rejoignez le Port Royal immédiatement. Ce sont ses ordres."), "#ff8a7a")
	show_modal(T("THE BREAK · AN ORDER YOU DID NOT EXPECT", "LE POINT DE RUPTURE · UN ORDRE INATTENDU"),
		T("On the internal line, Lieutenant-Commander Marsh says the Captain wants you to break off and let the trawler go. The Captain is not on the bridge. The order goes against her intent: [i]\"Find what was taken... and bring it home.\"[/i]\n\nWhat do you do?",
		"Sur la ligne interne, le capitaine de corvette Marsh dit que le commandant veut que vous rompiez et laissiez partir le chalutier. Le commandant n'est pas sur la passerelle. L'ordre va à l'encontre de son intention : [i]« Retrouver ce qui a été pris... et le ramener. »[/i]\n\nQue faites-vous ?"),
		[T("Obey. Marsh is senior to me. Turn away and rejoin Port Royal.", "Obéir. Marsh est plus haut gradé que moi. Virer et rejoindre le Port Royal."),
		T("Ignore him and keep closing the trawler.", "L'ignorer et continuer d'approcher le chalutier."),
		T("Keep closing, and call the Captain directly: \"Captain, ma'am, LCdr Marsh relayed an order to break off. Please confirm.\"", "Continuer l'approche et appeler directement le commandant : « Commandant, le Capc Marsh a transmis un ordre de rompre. Pouvez-vous confirmer ? »")],
		_on_break_m2)


func _on_break_m2(i: int) -> void:
	break_choice = i
	match i:
		0:
			score("awareness", -6, T("Did not question an order that contradicted the Captain's intent", "Ordre contraire à l'intention du commandant non remis en question"))
			score("initiative", -8, T("Gave up the mission on an unconfirmed relay", "Mission abandonnée sur un relais non confirmé"))
			score("execution", -15, T("The trawler and the stolen sonar escaped", "Le chalutier et le sonar volé se sont échappés"))
			log_line(who("you"), T("Port fifteen, half ahead. Breaking off.", "À gauche quinze, en avant demie. Nous rompons."))
			trawler.cruise_kn = 14.0
			trawler.heading = 70.0
			stage = 5
			objective = T("Phase 4 · Lead Port Royal to the rendezvous point (marked, west)", "Phase 4 · Conduire le Port Royal au point de rendez-vous (marqué, à l'ouest)")
			log_line(hale(), T("(minutes later) Officer of the Watch, why are we turning away? I gave no such order. Who told you that? ...Marsh. I see.", "(quelques minutes plus tard) Officier de quart, pourquoi virons-nous ? Je n'ai jamais donné cet ordre. Qui vous a dit ça ? ... Marsh. Je vois."), "#ff8a7a")
		1:
			score("initiative", 3, T("Stayed on the mission", "Resté concentré sur la mission"))
			score("discipline", -8, T("Ignored a relayed order without checking it with the Captain", "Ordre relayé ignoré sans vérification auprès du commandant"))
			log_line(hale(), T("(arriving on the bridge) Good that you kept going, but if you doubt an order, you check it with me. Marsh had no such order from me.", "(arrivant sur la passerelle) Bien d'avoir continué, mais si vous doutez d'un ordre, vérifiez-le avec moi. Marsh n'avait reçu aucun ordre de ma part."))
			stage = 3
		2:
			score("discipline", 8, T("Verified an unusual order through the chain of command", "Ordre inhabituel vérifié par la chaîne de commandement"))
			score("awareness", 8, T("Spotted that the order contradicted the intent", "Contradiction entre l'ordre et l'intention repérée"))
			score("initiative", 6, T("Kept the mission moving while checking", "Mission poursuivie pendant la vérification"))
			log_line(hale(), T("I gave no such order. Continue the boarding. ...Lieutenant-Commander Marsh, my cabin. Now.", "Je n'ai jamais donné cet ordre. Poursuivez l'arraisonnement. ... Capitaine de corvette Marsh, dans ma cabine. Tout de suite."))
			stage = 3
	if stage == 3:
		objective = T("Phase 2 · Order the trawler to stop on Channel 16", "Phase 2 · Ordonner au chalutier de stopper sur le canal 16")
		trawler.cruise_kn = 7.0


func _m2_complete() -> void:
	phase = "done"
	paused = true
	log_line(hale(), T("Rendezvous reached. Port Royal is safe.", "Rendez-vous atteint. Le Port Royal est en sécurité."))
	var planned := T("Identify every vessel, recover what was stolen, keep Port Royal safe.", "Identifier chaque navire, récupérer ce qui a été volé, garder le Port Royal en sécurité.")
	var story := T("Story: Lieutenant-Commander Julian Marsh is confined to his cabin. He leaked the patrol plan. Who is he working for? Operation GHOST CONVOY continues. ",
		"Récit : le capitaine de corvette Julian Marsh est consigné dans sa cabine. Il a divulgué le plan de patrouille. Pour qui travaille-t-il ? L'opération CONVOI FANTÔME continue. ")
	if break_choice == 0:
		story = T("Story: the trawler escaped with the sonar, and Lieutenant-Commander Julian Marsh's false order is now under investigation. Operation GHOST CONVOY continues. ",
			"Récit : le chalutier s'est échappé avec le sonar, et le faux ordre du capitaine de corvette Julian Marsh fait maintenant l'objet d'une enquête. L'opération CONVOI FANTÔME continue. ")
	var history := T("History: Sable Island, the \"Graveyard of the Atlantic\", has caused hundreds of shipwrecks. It is now a national park reserve, famous for its wild horses. The Royal Canadian Navy boards vessels at sea with Naval Boarding Parties, always on lawful authority and after hailing.",
		"Histoire : l'île de Sable, « le cimetière de l'Atlantique », a causé des centaines de naufrages. C'est aujourd'hui une réserve de parc national, célèbre pour ses chevaux sauvages. La Marine royale canadienne arraisonne les navires en mer avec des équipes d'arraisonnement, toujours en vertu d'une autorité légale et après les avoir hélés.")
	_debrief(planned, story + history,
		[T("Sail this mission again", "Rejouer cette mission"), T("Back to the title screen", "Retour à l'écran titre")],
		func(i):
			if i == 0:
				_start_mission(2)
			else:
				_show_title())


# ======================================================================
# Drawing: trails, overlay, radar, HUD
# ======================================================================

func _current_target() -> Variant:
	if era == "1942":
		return WorldScript.ROUTE[mini(echo_wp, WorldScript.ROUTE.size() - 1)]
	if mission == 2:
		match stage:
			0:
				var u = _nearest_unidentified(INF)
				return u.position if u else null
			1, 2, 3:
				return trawler.position if trawler and is_instance_valid(trawler) else null
			4, 5:
				return M2_RENDEZVOUS
		return null
	match stage:
		0:
			return Vector2(290, 740)
		1:
			return WorldScript.NARROWS_B
		2:
			return POINT_ECHO
		4, 7:
			return SEA_BUOY
		5:
			return lady_hannah.position if lady_hannah else null
		6:
			return port_royal.position if port_royal else null
	return null


func _draw_trails() -> void:
	for v in vessels:
		if not is_instance_valid(v) or v.trail.size() < 2:
			continue
		var w: float = v.length() * 0.22
		for i in range(1, v.trail.size()):
			var age: float = v.t - v.trail[i][1]
			var a: float = clampf(1.0 - age / 7.0, 0.0, 1.0) * 0.45
			trail_layer.draw_line(v.trail[i - 1][0], v.trail[i][0], Color(1, 1, 1, a), w * (1.0 + age * 0.35))


func _draw_overlay() -> void:
	if player == null or phase == "title":
		return
	var tgt = _current_target()
	var col := Color(0.85, 0.15, 0.12, 0.9) if era != "1942" else Color(0.9, 0.75, 0.4, 0.8)
	if tgt != null:
		overlay.draw_arc(tgt, 60.0, 0, TAU, 40, col, 4.0)
		overlay.draw_arc(tgt, 20.0, 0, TAU, 20, col, 3.0)
		var a: Vector2 = player.position
		var b: Vector2 = tgt
		var n := int(a.distance_to(b) / 40.0)
		for i in range(1, n, 2):
			overlay.draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), Color(col, 0.5), 3.0)
	var f := ThemeDB.fallback_font
	var mark := Color(0.6, 0.1, 0.1)
	if era == "modern":
		overlay.draw_string(f, POINT_ECHO + Vector2(70, 10), T("POINT ECHO", "POINT ÉCHO"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, mark)
		overlay.draw_string(f, SEA_BUOY + Vector2(70, 10), T("SEA BUOY", "BOUÉE DE MER"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, mark)
	elif era == "sable":
		overlay.draw_string(f, M2_RENDEZVOUS + Vector2(70, 10), T("RENDEZVOUS", "RENDEZ-VOUS"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.95, 0.9, 0.8))
	var label_col := Color(0.1, 0.1, 0.1) if era == "modern" else Color(0.95, 0.92, 0.85)
	for v in vessels:
		if not is_instance_valid(v) or v == player or v.vname == "":
			continue
		var near: bool = v.position.distance_to(player.position) < VISUAL_RANGE * (1.6 if era == "sable" else 1.0)
		if near or v == port_royal or (era == "sable" and v.identified):
			var txt: String = v.vname
			if era == "sable" and v.has_meta("id_text") and not v.identified:
				txt = T("unidentified", "non identifié")
			overlay.draw_string(f, v.position + Vector2(v.length() * 0.5 + 8, -14), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, label_col)


func _draw_radar() -> void:
	var r := radar
	var s := r.size
	var c := s / 2.0
	var rad: float = minf(s.x, s.y) / 2.0 - 4.0
	r.draw_circle(c, rad + 3.0, Color(0.72, 0.6, 0.35, 0.8))
	r.draw_circle(c, rad, Color(0.02, 0.09, 0.07, 0.95))
	for i in [0.33, 0.66, 1.0]:
		r.draw_arc(c, rad * i, 0, TAU, 40, Color(0.2, 0.8, 0.45, 0.35), 1.0)
	if player == null:
		return
	var hd := deg_to_rad(player.heading)
	r.draw_line(c, c + Vector2(sin(hd), -cos(hd)) * rad, Color(0.4, 1.0, 0.6, 0.7), 1.5)
	var sweep := fmod(mission_time * 2.0, TAU)
	r.draw_line(c, c + Vector2(sin(sweep), -cos(sweep)) * rad, Color(0.4, 1.0, 0.6, 0.25), 3.0)
	var sc := rad / radar_range
	var step := radar_range / 12.0
	var y := -radar_range
	while y <= radar_range:
		var x := -radar_range
		while x <= radar_range:
			var off := Vector2(x, y)
			if off.length() < radar_range and not world.is_water(player.position + off):
				r.draw_rect(Rect2(c + off * sc - Vector2(2, 2), Vector2(4, 4)), Color(0.3, 0.75, 0.45, 0.35))
			x += step
		y += step
	for v in vessels:
		if not is_instance_valid(v) or v == player or v.kind == "helo":
			continue
		var off: Vector2 = v.position - player.position
		if off.length() > radar_range:
			continue
		var col := Color(0.6, 1.0, 0.7)
		if (v.needs_report and not v.reported) or (v.has_meta("id_text") and not v.identified):
			col = Color(1.0, 0.85, 0.3)
		if v.distress or (v == trawler and v.identified):
			col = Color(1.0, 0.35, 0.3)
		r.draw_circle(c + off * sc, 3.5, col)
	if helo and is_instance_valid(helo):
		var ho: Vector2 = helo.position - player.position
		if ho.length() < radar_range:
			r.draw_rect(Rect2(c + ho * sc - Vector2(3, 3), Vector2(6, 6)), Color(0.5, 0.8, 1.0), false, 1.5)
	r.draw_circle(c, 3.0, Color(1, 1, 1))
	r.draw_string(ThemeDB.fallback_font, Vector2(8, 16), "RADAR %.1f nm" % (radar_range / NM), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.9, 0.6))


func _update_hud() -> void:
	if player == null:
		return
	top_obj.text = objective
	top_nav.text = T("%s  ·  %04.1f kn  ·  HDG %03d°  ·  %s", "%s  ·  %04.1f nd  ·  CAP %03d°  ·  %s") % [tele_name(player.telegraph), absf(player.speed), int(round(player.heading)) % 360, rudder_name(player.rudder)]
	for k in tele_buttons:
		tele_buttons[k].modulate = Color(1.0, 0.8, 0.4) if player.telegraph == k else Color(1, 1, 1)
	for k in rudder_buttons:
		rudder_buttons[k].modulate = Color(1.0, 0.8, 0.4) if player.rudder == k else Color(1, 1, 1)
	var acts := _radio_actions()
	var keys := ""
	for a in acts:
		keys += a[0] + ","
	if keys != radio_keys:
		radio_keys = keys
		for ch in radio_box.get_children():
			ch.queue_free()
		if acts.is_empty():
			var l := Label.new()
			l.text = T("Nothing to report.", "Rien à signaler.")
			l.add_theme_color_override("font_color", Color(0.6, 0.68, 0.72))
			radio_box.add_child(l)
		for a in acts:
			var b := Button.new()
			b.text = a[1]
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(300, 44)
			b.pressed.connect(_do_action.bind(a[0]))
			radio_box.add_child(b)
