extends Node2D
## True North Command: Operation Alpha — Mission 1 "Harbour Departure, Halifax".
## Internal code name MI-Alpha. One scene; the mission is a small state machine.

const WorldScript := preload("res://scripts/world.gd")
const VesselScript := preload("res://scripts/vessel.gd")

const GAME_TITLE := "TRUE NORTH COMMAND"
const GAME_SUB := "Operation Alpha"
const POINT_ECHO := Vector2(980, 3250)
const SEA_BUOY := Vector2(1000, 5000)
const RADAR_RANGE := 1300.0
const VISUAL_RANGE := 430.0
const NM := 370.0  # world units per nautical mile on the chart

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
var zoom_level := 0.8

# --- state ---
var era := "modern"
var phase := "title"   # title, modal, sail, done
var paused := true
var stage := 0
var mission_time := 0.0
var player_name := "Lt(N) Élise Tremblay"
var player_short := "Tremblay"
var sir_maam := "Ma'am"
var scores := {}
var aar: Array = []
var port_royal
var ferry
var unlit
var lady_hannah
var rhib
var waited_warned := false
var rhib_state := ""
var rhib_timer := 0.0
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
var ground_cooldown := 0.0
var echo_orders: Array = []      # issued orders {type, value, at, obeyed}
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
var radio_keys := ""
var radar: Control
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


func _ready() -> void:
	randomize()
	world = WorldScript.new()
	add_child(world)
	overlay = Node2D.new()
	overlay.z_index = 5
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	cam.zoom = Vector2(zoom_level, zoom_level)
	cam.position = Vector2(300, 900)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 4.0
	_build_ui()
	_show_title()


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

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	ui.add_child(root)

	# top bar
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 48
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

	# radar (top right)
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

	# zoom
	var zb := HBoxContainer.new()
	zb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	zb.offset_left = -202
	zb.offset_right = -12
	zb.offset_top = 252
	zb.offset_bottom = 290
	root.add_child(zb)
	for z in [["−", 0.85], ["+", 1.18]]:
		var btn := Button.new()
		btn.text = "Zoom " + z[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_zoom.bind(z[1]))
		zb.add_child(btn)

	# radio actions (right, below radar)
	var rp := PanelContainer.new()
	rp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	rp.offset_left = -330
	rp.offset_right = -12
	rp.offset_top = 298
	root.add_child(rp)
	var rv := VBoxContainer.new()
	rp.add_child(rv)
	var rl := Label.new()
	rl.text = "RADIO / ACTIONS  [Space]"
	rl.add_theme_font_size_override("font_size", 14)
	rl.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	rv.add_child(rl)
	radio_box = VBoxContainer.new()
	rv.add_child(radio_box)

	# comms log (bottom left)
	var lp := PanelContainer.new()
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

	# helm (bottom right)
	var hp := PanelContainer.new()
	hp.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hp.offset_left = -620
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
		btn.text = ["Astern", "Stop", "Slow", "Half", "Full", "Flank"][k + 1]
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
		btn.text = ["Port 30", "Port 15", "Midships", "Stbd 15", "Stbd 30"][k + 2]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 46)
		btn.pressed.connect(_set_rudder.bind(k))
		rrow.add_child(btn)
		rudder_buttons[k] = btn

	# toast + echo order prompt
	toast = Label.new()
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.offset_top = 62
	toast.offset_left = -300
	toast.offset_right = 300
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	order_label.add_theme_font_size_override("font_size", 30)
	order_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	order_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	order_label.add_theme_constant_override("outline_size", 8)
	root.add_child(order_label)

	# modal
	modal_root = ColorRect.new()
	(modal_root as ColorRect).color = Color(0.02, 0.05, 0.08, 0.72)
	modal_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal_root)
	var mc := CenterContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_root.add_child(mc)
	var mp := PanelContainer.new()
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
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 46)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_modal_pick.bind(i))
		modal_buttons.add_child(b)
	modal_root.show()


func _modal_pick(i: int) -> void:
	modal_root.hide()
	paused = false
	if modal_cb.is_valid():
		modal_cb.call(i)


func log_line(who: String, text: String, color := "") -> void:
	var c := color
	if c == "":
		c = "#f2c46d" if who == "You" else "#a9d3e3"
	log_box.append_text("[color=%s][b]%s:[/b][/color] %s\n" % [c, who, text])


func show_toast(text: String, good := true) -> void:
	toast.text = text
	toast.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6) if good else Color(1.0, 0.5, 0.45))
	toast_t = 2.6


# ======================================================================
# Title, briefing, read-back
# ======================================================================

func _show_title() -> void:
	era = "modern"
	_setup_modern()
	show_modal("%s\n%s" % [GAME_TITLE, GAME_SUB],
		"[b]Operation GHOST CONVOY · Mission 1: Harbour Departure, Halifax[/b]\n\n" +
		"Fog over Halifax Harbour. You are the Officer of the Watch on the frigate HMCS [i]Laurentian[/i].\n" +
		"You will be scored on how well you read the situation, follow orders, use initiative inside your Captain's intent, look after your team, and get the job done.\n\n" +
		"[color=#9fb4bf]Controls: W/S or buttons = engine telegraph · A/D or buttons = rudder · Space = first radio action · mouse wheel or Zoom = zoom.[/color]\n\n" +
		"Choose your officer:",
		["Lt(N) Élise Tremblay  ·  navigation officer, Rimouski QC", "Lt(N) Liam MacLeod  ·  navigation officer, Sydney NS"],
		_on_pick_character)


func _on_pick_character(i: int) -> void:
	if i == 0:
		player_name = "Lt(N) Élise Tremblay"
		player_short = "Tremblay"
		sir_maam = "Ma'am"
	else:
		player_name = "Lt(N) Liam MacLeod"
		player_short = "MacLeod"
		sir_maam = "Sir"
	_brief(0)


func _brief(page: int) -> void:
	var pages := [
		["ORDERS 1/3 · SITUATION",
		"[b]Situation.[/b] Thick fog over Halifax Harbour; visibility under a mile. Last week the container ship [i]Atlantic Meridian[/i] vanished off Sable Island carrying a prototype sonar. Tonight MV [i]Port Royal[/i] sails with the replacement. An unknown small craft has been reported in the outer harbour.\n\n" +
		"[b]Mission.[/b] HMCS [i]Laurentian[/i] sails from Bedford Basin, meets [i]Port Royal[/i] at Point Echo, and escorts her to open sea."],
		["ORDERS 2/3 · EXECUTION",
		"[b]Execution.[/b] You have the watch.\n" +
		"  Phase 1: Bedford Basin to the Narrows.\n" +
		"  Phase 2: Through the Narrows. [color=#f2c46d]Maximum ten knots (Half ahead).[/color]\n" +
		"  Phase 3: Meet [i]Port Royal[/i] at Point Echo.\n" +
		"  Phase 4: Escort her south to the sea buoy.\n\n" +
		"[b]Service support.[/b] Fuel full. Boarding team and RHIB at five minutes' notice. Helicopter grounded by fog.\n\n" +
		"[b]Command & signal.[/b] Captain: Capt(N) Margaret Hale. Shore operations call sign: [i]Trafalgar Ops[/i]. Report every contact to the Captain. On the radio: read back, say \"wilco\", end with \"out\"."],
		["ORDERS 3/3 · COMMANDER'S INTENT",
		"[i]\"Port Royal reaches open sea safely. And in my waters, nobody who needs help is left behind.\"[/i]\n          Capt(N) M. Hale\n\n" +
		"[color=#9fb4bf]The intent is the [b]why[/b] behind the orders. When the plan breaks, act inside the intent, and tell your Captain.[/color]"],
	]
	var p: Array = pages[page]
	if page < 2:
		show_modal(p[0], p[1], ["Next"], func(_i): _brief(page + 1))
	else:
		show_modal(p[0], p[1], ["Read back the orders"], func(_i): _readback())


func _readback() -> void:
	show_modal("READ-BACK",
		"Captain Hale: \"Officer of the Watch, before you take her out: what is my intent?\"",
		["\"Get Laurentian to sea as fast as possible.\"",
		"\"Port Royal reaches open sea safely, and nobody who needs help in our waters is left behind, ma'am.\"",
		"\"Find the ship that vanished off Sable Island.\""],
		_on_readback)


func _on_readback(i: int) -> void:
	if i == 1:
		score("discipline", 6, "Read back the Captain's intent correctly")
		log_line("Capt(N) Hale", "Correct. You have the watch, %s. Take her out." % player_short)
	else:
		score("discipline", -4, "Misread the Captain's intent at the briefing")
		log_line("Capt(N) Hale", "No. My intent: Port Royal safe at sea, and nobody left without help. Remember it. You have the watch.")
	_start_sail()


# ======================================================================
# Mission setup
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


func _spawn(kind: String, pos: Vector2, hdg: float, vname := ""):
	var v = VesselScript.new()
	v.kind = kind
	v.vname = vname
	v.position = pos
	v.heading = hdg
	v.rotation = deg_to_rad(hdg)
	v.z_index = 3
	add_child(v)
	vessels.append(v)
	return v


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
	ground_cooldown = 0.0
	order_label.text = ""


func _setup_modern() -> void:
	_reset_common()
	world.set_era("modern")
	RenderingServer.set_default_clear_color(Color("d9cfae"))
	fog_mat.set_shader_parameter("fog_color", Color(0.86, 0.88, 0.89))
	player = _spawn("frigate", Vector2(40, 150), 160.0, "HMCS Laurentian")
	player.is_player = true
	player.max_kn = 26.0
	for p in [[Vector2(-420, -200), 70.0], [Vector2(-300, 260), 20.0], [Vector2(380, -260), 300.0]]:
		_spawn("merchant", p[0], p[1], "anchored merchant")
	ferry = _spawn("ferry", Vector2(560, 1870), 75.0, "harbour ferry")
	ferry.cruise_kn = 6.0
	ferry.needs_report = true
	ferry.contact_desc = "harbour ferry, lit, crossing"
	unlit = _spawn("unlit", Vector2(760, 2980), 250.0, "unknown small craft")
	unlit.lit = false
	unlit.cruise_kn = 1.0
	unlit.needs_report = true
	unlit.contact_desc = "small craft, no lights"
	port_royal = _spawn("merchant", POINT_ECHO + Vector2(170, -60), 190.0, "MV Port Royal")
	port_royal.hold = true
	cam.position = player.position


func _setup_echo() -> void:
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
		var m = _spawn("merchant", Vector2(-600 + (i % 5) * 230, -380 + int(i / 5.0) * 260), 180.0, "convoy merchant")
		m.darkened = true
	echo_orders.clear()
	echo_rudder_order = 0
	echo_tele_order = 1
	echo_wp = 0
	echo_last_order_t = -10.0
	gate_t = -1.0
	cam.position = player.position


func _start_sail() -> void:
	phase = "sail"
	paused = false
	objective = "Phase 1 · Steer for the Narrows (south-east). Half ahead is a good speed."
	log_line("Capt(N) Hale", "Officer of the Watch, half ahead, steer for the Narrows. Ten knots maximum in the Narrows.")
	log_line("Helm", "Ready on the wheel, %s." % sir_maam.to_lower())


# ======================================================================
# Scoring
# ======================================================================

func score(pillar: String, delta: int, why: String) -> void:
	scores[pillar] = clampi(scores[pillar] + delta, 0, 100)
	aar.append({"pillar": pillar, "delta": delta, "why": why, "t": mission_time})
	var label := pillar.capitalize()
	show_toast("%s %+d · %s" % [label, delta, why], delta >= 0)


# ======================================================================
# Controls
# ======================================================================

func _set_telegraph(k: int) -> void:
	if paused or player == null:
		return
	if player.telegraph == k:
		return
	player.telegraph = k
	if era == "modern":
		log_line("You", VesselScript.TELE_NAME[k] + ".")
		log_line("Helm", VesselScript.TELE_NAME[k] + ", aye.")
	else:
		log_line("You", "Telegraph to " + VesselScript.TELE_NAME[k].to_lower() + ".")
		_echo_check_obey()


func _set_rudder(k: int) -> void:
	if paused or player == null:
		return
	if player.rudder == k:
		return
	player.rudder = k
	if era == "modern":
		log_line("You", VesselScript.RUDDER_NAME[k] + ".")
		log_line("Helm", VesselScript.RUDDER_NAME[k] + ", aye.")
	else:
		log_line("You", VesselScript.RUDDER_NAME[k] + ", aye, sir.")
		_echo_check_obey()


func _zoom(f: float) -> void:
	zoom_level = clampf(zoom_level * f, 0.25, 1.6)
	cam.zoom = Vector2(zoom_level, zoom_level)


func _unhandled_input(event: InputEvent) -> void:
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
	if phase != "sail" or player == null:
		return a
	if era == "modern":
		for v in vessels:
			if v.needs_report and not v.reported and v.detected_at >= 0.0:
				a.append(["report", "Report contact to Captain"])
				break
		if unlit and is_instance_valid(unlit) and unlit.reported and not hailed and player.position.distance_to(unlit.position) < 1000:
			a.append(["hail", "Hail unknown craft on Channel 16"])
		if stage == 5 and lady_hannah and rhib_state == "" and player.position.distance_to(lady_hannah.position) < 220:
			a.append(["rhib", "Launch the RHIB (need 5 knots or less)"])
	return a


func _do_action(key: String) -> void:
	match key:
		"report":
			_report_contact()
		"hail":
			_hail()
		"rhib":
			_launch_rhib()


func _bearing_words(target: Vector2) -> String:
	var to: Vector2 = target - player.position
	var brg := rad_to_deg(atan2(to.x, -to.y))
	var rel := wrapf(brg - player.heading, -180.0, 180.0)
	var side := "green" if rel >= 0 else "red"
	var deg := int(round(absf(rel) / 5.0) * 5)
	var nm := to.length() / NM
	return "%s %s, %.1f miles" % [side, _say_deg(deg), nm]


func _say_deg(d: int) -> String:
	var words := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
	var s := str(d)
	var out: PackedStringArray = []
	for ch in s:
		out.append(words[int(ch)])
	return "-".join(out)


func _report_contact() -> void:
	var best = null
	for v in vessels:
		if v.needs_report and not v.reported and v.detected_at >= 0.0:
			if best == null or v.detected_at < best.detected_at:
				best = v
	if best == null:
		return
	best.reported = true
	var dt: float = mission_time - best.detected_at
	log_line("You", "Captain, %s: contact %s, %s." % [_hale_title(), _bearing_words(best.position), best.contact_desc])
	if dt < 12.0:
		score("awareness", 8, "Reported the %s quickly" % best.vname)
	elif dt < 25.0:
		score("awareness", 4, "Reported the %s" % best.vname)
	else:
		score("awareness", 1, "Reported the %s, late" % best.vname)
	if best == unlit:
		log_line("Capt(N) Hale", "Very good. No lights in fog is either careless or deliberate. Keep watching it.")
	else:
		log_line("Capt(N) Hale", "Very good. Keep clear of it.")


func _hale_title() -> String:
	return "ma'am"


func _hail() -> void:
	hailed = true
	log_line("You", "Unknown vessel in position south of Point Pleasant, this is Canadian warship Laurentian, Channel one-six. Show your lights and state your intentions. Over.", "#f2c46d")
	log_line("Radio", "(no reply)", "#9fb4bf")
	unlit.cruise_kn = 22.0
	unlit.heading = 215.0
	score("awareness", 4, "Hailed the unlit craft; its escape is logged for intelligence")
	log_line("Ops room", "Contact accelerating to twenty knots, heading south-west into the fog. Logged.")


func _launch_rhib() -> void:
	if player.speed > 5.5:
		log_line("Coxswain", "Too fast to launch, %s. Five knots or less." % sir_maam.to_lower())
		score("team", -3, "Ordered a boat launch at unsafe speed")
		return
	rhib = _spawn("rhib", player.position + player.dir().orthogonal() * 20.0, player.heading, "RHIB")
	rhib.follow = lady_hannah
	rhib.follow_gap = 18.0
	rhib_state = "out"
	log_line("You", "Away the RHIB. Recover the crew of Lady Hannah.")
	log_line("Coxswain", "RHIB away. Four aboard, plus the medic.")
	score("execution", 6, "Launched the RHIB safely")


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
		for v in vessels:
			if is_instance_valid(v):
				v.step(delta)
		_check_ground(delta)
		if era == "modern":
			_modern_logic(delta)
		else:
			_echo_logic(delta)
	_update_fog()
	_update_hud()
	overlay.queue_redraw()
	radar.queue_redraw()


func _update_fog() -> void:
	if player == null:
		return
	var at_sea: float = clampf((player.position.y - 3400.0) / 800.0, 0.0, 1.0)
	if era == "modern":
		fog_mat.set_shader_parameter("inner", lerpf(0.16, 0.24, at_sea))
		fog_mat.set_shader_parameter("outer", lerpf(0.48, 0.62, at_sea))
		fog_mat.set_shader_parameter("strength", lerpf(0.82, 0.7, at_sea))
	else:
		fog_mat.set_shader_parameter("inner", 0.16)
		fog_mat.set_shader_parameter("outer", 0.5)
		fog_mat.set_shader_parameter("strength", 0.85)


func _check_ground(delta: float) -> void:
	ground_cooldown = maxf(0.0, ground_cooldown - delta)
	var bow: Vector2 = player.position + player.dir() * 32.0
	var stern: Vector2 = player.position - player.dir() * 32.0
	var blocked: bool = (not world.is_water(bow)) or (not world.is_water(stern)) or world.gate_blocks(bow)
	if not blocked:
		safe_timer += delta
		if safe_timer > 0.5 and world.is_water(player.position, 40.0):
			safe_timer = 0.0
			safe_positions.append([player.position, player.heading])
			if safe_positions.size() > 12:
				safe_positions.pop_front()
		return
	# aground or against the net
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
			log_line("OOW", "Stop! The gate is closed. Hard astern, back off the net!", "#ff8a7a")
		else:
			log_line("Capt(N) Hale", "We've touched bottom! I have the ship... All right, you have the ship again. Keep to the channel.", "#ff8a7a")
		if era == "modern":
			score("execution", -12, "Ran the ship aground")
			score("team", -4, "Crew put at risk by grounding")


func _modern_logic(delta: float) -> void:
	var p: Vector2 = player.position
	# contact detection
	for v in vessels:
		if not is_instance_valid(v) or not v.needs_report or v.reported:
			continue
		var d := p.distance_to(v.position)
		var seen: bool = d < VISUAL_RANGE or d < RADAR_RANGE * (0.6 if v.kind == "unlit" else 0.85)
		if seen and v.detected_at < 0.0:
			v.detected_at = mission_time
			log_line("Ops room", "New radar contact, %s." % _bearing_words(v.position), "#9fb4bf")
		if v.detected_at >= 0.0 and mission_time - v.detected_at > 30.0:
			v.reported = true
			log_line("Lookout", "Bridge, lookout: contact %s, %s! Was nobody reporting it?" % [_bearing_words(v.position), v.contact_desc])
			score("awareness", -6, "The lookout had to report the %s for you" % v.vname)
	# ferry loop
	if ferry and ferry.position.x > 1300:
		ferry.position = Vector2(520, 1880)
	# unlit craft leaves the chart
	if unlit and is_instance_valid(unlit) and unlit.position.distance_to(p) > 2600 and unlit.cruise_kn > 10:
		unlit.queue_free()
		vessels.erase(unlit)
		unlit = null
	elif unlit and is_instance_valid(unlit) and unlit.reported and not hailed and stage >= 4:
		hailed = true
		unlit.cruise_kn = 22.0
		unlit.heading = 215.0
		log_line("Ops room", "The unlit craft is running south-west at twenty knots. Lost in the fog.")
	# Narrows speed limit
	if world.in_narrows(p) and player.speed > 10.5:
		over_limit_t += delta
		if not limit_warned:
			limit_warned = true
			log_line("Capt(N) Hale", "Officer of the Watch, you're over the limit in the Narrows. Ten knots.", "#ff8a7a")
		if over_limit_t > 3.0 and limit_penalty < 16:
			over_limit_t = 0.0
			limit_penalty += 2
			score("discipline", -2, "Over the 10-knot limit in the Narrows")
	# stages
	match stage:
		0:
			if p.distance_to(Vector2(290, 740)) < 280:
				stage = 1
				objective = "Phase 2 · Transit the Narrows · 10 knots max · under the two bridges"
				log_line("Capt(N) Hale", "Entering the Narrows. Watch your speed and keep to the middle.")
		1:
			if p.distance_to(WorldScript.NARROWS_B) < 260:
				stage = 2
				objective = "Phase 3 · Proceed to Point Echo (marked) and meet MV Port Royal"
				if limit_penalty == 0:
					score("discipline", 5, "Kept the Narrows speed limit")
				log_line("Capt(N) Hale", "Through the Narrows. Proceed to Point Echo. You may increase speed.")
		2:
			if p.distance_to(POINT_ECHO) < 320:
				stage = 3
				_ops_order()
		4:
			_escort_gap(delta)
			if p.y > 3880 and mayday_t < 0.0:
				mayday_t = mission_time
				log_line("Channel 16", "MAYDAY MAYDAY MAYDAY. This is fishing vessel Lady Hannah... taking water... four persons... west of Chebucto Head...", "#ff8a7a")
				lady_hannah = _spawn("fishing", Vector2(330, 4420), 300.0, "FV Lady Hannah")
				lady_hannah.distress = true
			if mayday_t >= 0.0 and mission_time - mayday_t > 2.5:
				stage = 41
				_break_choice()
		5:
			_rhib_logic(delta)
		6:
			if port_royal and p.distance_to(port_royal.position) < 380:
				stage = 7
				port_royal.hold = false
				port_royal.follow = player
				objective = "Phase 4 · Escort Port Royal south to the sea buoy (marked)"
				log_line("You", "Port Royal, Laurentian. Resuming escort, follow in my wake. Over.")
				log_line("MV Port Royal", "Laurentian, Port Royal. Following. Good work out there. Out.")
		7:
			_escort_gap(delta)
			if p.distance_to(SEA_BUOY) < 300:
				if port_royal and port_royal.position.distance_to(SEA_BUOY) < 900:
					_mission_complete()
				elif not waited_warned:
					log_line("Capt(N) Hale", "We don't leave our charge behind. Wait for Port Royal.")
					waited_warned = true


func _ops_order() -> void:
	player.telegraph = mini(player.telegraph, 1)
	log_line("Trafalgar Ops", "Laurentian, this is Trafalgar Ops. Escort MV Port Royal from Point Echo to the sea buoy. Over.", "#a9d3e3")
	show_modal("RADIO · TRAFALGAR OPS",
		"[i]\"Laurentian, this is Trafalgar Ops. Escort MV Port Royal from Point Echo to the sea buoy. Over.\"[/i]\n\nHow do you answer?",
		["\"Trafalgar Ops, Laurentian. Escort Port Royal from Point Echo to the sea buoy. Wilco. Out.\"",
		"\"Roger wilco, over and out.\"",
		"\"Copy that, we'll take care of it.\""],
		_on_ops_ack)


func _on_ops_ack(i: int) -> void:
	match i:
		0:
			score("discipline", 6, "Correct read-back and radio procedure")
		1:
			score("discipline", 1, "\"Over and out\" contradicts itself: over expects a reply, out ends the call")
		2:
			score("discipline", -3, "No read-back and informal radio language")
	log_line("You", ["Trafalgar Ops, Laurentian. Escort Port Royal from Point Echo to the sea buoy. Wilco. Out.", "Roger wilco, over and out.", "Copy that, we'll take care of it."][i])
	stage = 4
	port_royal.hold = false
	port_royal.follow = player
	port_royal.follow_gap = 280.0
	objective = "Phase 4 · Escort Port Royal south to the sea buoy. Keep her close."
	log_line("MV Port Royal", "Laurentian, Port Royal. Following in your wake. Out.")


func _escort_gap(delta: float) -> void:
	if port_royal == null:
		return
	if player.position.distance_to(port_royal.position) > 1100.0:
		gap_t += delta
		if gap_t > 5.0 and gap_penalty < 12:
			gap_t = 0.0
			gap_penalty += 3
			score("execution", -3, "Port Royal left far behind; slow down for your charge")
	else:
		gap_t = 0.0


func _break_choice() -> void:
	show_modal("THE BREAK · MAYDAY",
		"Fishing vessel [i]Lady Hannah[/i] is taking water, four people aboard, about two miles to the west. You are escorting [i]Port Royal[/i]. The Captain is on the bridge, looking at you.\n\n[color=#9fb4bf]Remember the intent.[/color]",
		["Keep escorting. The mayday is not our tasking.",
		"Turn toward Lady Hannah right now. Tell the Captain later.",
		"\"Captain, %s: mayday, Lady Hannah, two miles west. Recommend we divert and launch the RHIB; Port Royal holds here.\"" % _hale_title(),
		"Call Trafalgar Ops and wait for instructions."],
		_on_break)


func _on_break(i: int) -> void:
	break_choice = i
	match i:
		0:
			score("initiative", -15, "Ignored a mayday inside the Captain's intent")
			score("team", -8, "Left mariners in danger")
			log_line("Capt(N) Hale", "No. Every mariner answers a mayday, and my intent was clear. I have the ship.", "#ff8a7a")
			_start_rescue(true)
		1:
			score("initiative", 8, "Acted at once on the mayday")
			score("discipline", -8, "Changed the ship's tasking without telling the Captain")
			score("execution", -4, "Port Royal left without orders")
			log_line("Capt(N) Hale", "Right call, wrong way. Next time you tell me first. Carry on.")
			_start_rescue(false)
		2:
			score("initiative", 12, "Proposed a plan inside the Captain's intent")
			score("discipline", 6, "Reported up before acting")
			score("team", 5, "Kept Port Royal informed and safe")
			log_line("Capt(N) Hale", "Approved. Make it so.")
			log_line("You", "Port Royal, Laurentian. Hold this position, we are answering a mayday. Over.")
			log_line("MV Port Royal", "Laurentian, Port Royal. Holding. Good luck. Out.")
			_start_rescue(false)
		3:
			score("initiative", -6, "Waited for permission while lives were at risk")
			log_line("Trafalgar Ops", "Laurentian, Ops. Stand by...")
			log_line("Capt(N) Hale", "A mayday doesn't wait for a phone call. We're going. Your plan next time, %s." % player_short)
			_start_rescue(false)


func _start_rescue(captain_takes_over: bool) -> void:
	port_royal.follow = null
	port_royal.hold = true
	stage = 5
	objective = "Rescue · Close Lady Hannah (west), slow to 5 knots or less, launch the RHIB"
	if captain_takes_over:
		log_line("Capt(N) Hale", "Starboard thirty, half ahead. Officer of the Watch, you will launch the RHIB when we're close.")


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
				log_line("Coxswain", "Alongside Lady Hannah. Taking off the crew... one, two, three, four. All aboard.")
		"recover":
			rhib_timer -= delta
			if rhib_timer <= 0.0:
				rhib_state = "back"
				rhib.hold = false
				rhib.follow = player
				rhib.follow_gap = 20.0
				lady_hannah.distress = false
		"back":
			if rhib.position.distance_to(player.position) < 34.0:
				rhib_state = "done"
				rhib.queue_free()
				vessels.erase(rhib)
				rhib = null
				score("execution", 10, "Four fishermen recovered alive")
				score("team", 6, "RHIB crew brought home safely")
				log_line("Medic", "Four survivors aboard, cold but fine.")
				log_line("Capt(N) Hale", "Well done, everyone. Now get us back to Port Royal.")
				stage = 6
				objective = "Rejoin Port Royal (marked) and resume the escort"


func _mission_complete() -> void:
	phase = "done"
	paused = true
	log_line("Capt(N) Hale", "Sea buoy abeam. Port Royal is clear. Fall out from harbour stations.")
	if not (unlit == null or unlit.reported):
		score("awareness", -5, "Never reported the unlit craft")
	_debrief()


# ======================================================================
# Debrief
# ======================================================================

func _debrief() -> void:
	var total := 0
	for k in scores:
		total += scores[k]
	var avg := int(round(total / 5.0))
	var grade := "Mentioned in Dispatches" if avg >= 85 else ("Well done" if avg >= 72 else ("Satisfactory" if avg >= 58 else "Needs improvement"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	for k in ["awareness", "discipline", "initiative", "team", "execution"]:
		var l := Label.new()
		l.text = k.capitalize()
		l.custom_minimum_size = Vector2(140, 0)
		grid.add_child(l)
		var pb := ProgressBar.new()
		pb.max_value = 100
		pb.value = scores[k]
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(440, 22)
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
	var body := "[b]Command Rating: %d · %s[/b]\n\n" % [avg, grade]
	body += "[color=#f2c46d]PLANNED[/color]  Escort Port Royal to sea; nobody left without help.\n"
	body += "[color=#f2c46d]SUSTAIN[/color]\n%s\n" % ("\n".join(good) if good.size() else "• (nothing yet)")
	body += "[color=#f2c46d]IMPROVE[/color]\n%s\n\n" % ("\n".join(bad) if bad.size() else "• Nothing. Clean watch.")
	body += "[color=#9fb4bf]Promotion points earned: %d. History: in 1942 these same waters held the convoys of the Battle of the Atlantic, guarded by an anti-submarine net and gate off Point Pleasant. Play the Echo to sail them.[/color]" % (avg * 10)
	show_modal("AFTER ACTION REVIEW", body, ["Play Echo: Halifax, 1942", "Sail this mission again"], _on_debrief, grid)


func _on_debrief(i: int) -> void:
	if i == 0:
		_echo_intro()
	else:
		_setup_modern()
		_brief(0)


# ======================================================================
# Echo 1942: you are the helmsman. Follow the Officer of the Watch's orders exactly.
# ======================================================================

func _echo_intro() -> void:
	era = "1942"
	_setup_echo()
	show_modal("ECHO · HALIFAX, NOVEMBER 1942",
		"Bedford Basin is full of merchant ships forming convoy for the crossing to Britain. U-boats wait offshore. The city is blacked out.\n\n" +
		"You are [b]Leading Seaman Tom MacLeod[/b], helmsman of the corvette HMCS [i]Rosedale[/i]. Tonight you do not give orders. You [b]follow[/b] them, exactly and at once.\n\n" +
		"The Officer of the Watch will call rudder and engine orders. Repeat them by setting the wheel and telegraph. An anti-submarine net guards the harbour mouth; the gate opens only for ships that answer the challenge.\n\n" +
		"[color=#9fb4bf]Ashore at the signal station, Wren Rose Tremblay is on watch.[/color]",
		["Take the wheel"], func(_i): _echo_start())


func _echo_start() -> void:
	phase = "sail"
	paused = false
	objective = "Echo 1942 · Follow every helm and engine order. Leave harbour through the net gate."
	log_line("OOW", "Darken ship. Slow ahead.", "#e0c27a")
	_echo_issue("tele", 1)


func _echo_issue(kind: String, value: int) -> void:
	echo_last_order_t = mission_time
	var text: String
	if kind == "tele":
		echo_tele_order = value
		text = VesselScript.TELE_NAME[value]
	else:
		echo_rudder_order = value
		text = VesselScript.RUDDER_NAME[value]
	echo_orders.append({"kind": kind, "value": value, "at": mission_time, "obeyed": -1.0})
	order_label.text = "ORDER: " + text.to_upper()
	log_line("OOW", text + ".", "#e0c27a")
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
	# engine orders
	var gate_y := 2725.0
	var want_tele := 2
	if p.y < 500.0:
		want_tele = 1
	if p.y > gate_y - 700.0 and p.y < gate_y + 80.0:
		want_tele = 1 if world.gate_open else (0 if p.y > gate_y - 260.0 else 1)
	if want_tele != echo_tele_order and mission_time - echo_last_order_t > 2.5:
		_echo_issue("tele", want_tele)
	# gate challenge
	if not world.gate_open and p.y > gate_y - 750.0 and gate_t < 0.0:
		gate_t = mission_time
		log_line("Signalman", "Challenge flashed to the gate vessel by lamp... reply correct. Gate opening.", "#e0c27a")
	if gate_t >= 0.0 and not world.gate_open and mission_time - gate_t > 7.0:
		world.gate_open = true
		world.queue_redraw()
		log_line("OOW", "Gate's open. Steady as she goes through the middle.", "#e0c27a")
	# rudder orders from the route
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
	var body := "[b]Orders carried out within five seconds: %d of %d · average response %.1f s[/b]\n\n" % [ok, n, avg_t]
	body += "[i]Dear Tom,\nThe Basin is quiet tonight now your convoy has gone. I watched your lamp answer the challenge at the gate, and I knew it was you on the wheel. Come home to me in one piece, and come home a better sailor than you left.\nYours, Rose[/i]\n\n"
	body += "[color=#9fb4bf]History: Canada began the Second World War with only a handful of warships and ended it with one of the largest navies in the world, much of it corvettes like this one, escorting convoys out of Halifax. HMCS [i]Sackville[/i], the last Flower-class corvette, is preserved in Halifax today. About 6,700 women served in the Women's Royal Canadian Naval Service, many as signallers.[/color]\n\n"
	body += "Everything you did as Officer of the Watch depends on sailors who do this well. That is why leaders learn to follow first."
	show_modal("ECHO COMPLETE", body, ["Back to the title screen"], func(_i): _show_title())


# ======================================================================
# Drawing: overlay + radar + HUD
# ======================================================================

func _current_target() -> Variant:
	if era == "1942":
		return WorldScript.ROUTE[mini(echo_wp, WorldScript.ROUTE.size() - 1)]
	match stage:
		0:
			return Vector2(290, 740)
		1:
			return WorldScript.NARROWS_B
		2:
			return POINT_ECHO
		4:
			return SEA_BUOY
		5:
			return lady_hannah.position if lady_hannah else null
		6:
			return port_royal.position if port_royal else null
		7:
			return SEA_BUOY
	return null


func _draw_overlay() -> void:
	if player == null or phase == "title":
		return
	var tgt = _current_target()
	var col := Color(0.85, 0.15, 0.12, 0.9) if era == "modern" else Color(0.9, 0.75, 0.4, 0.8)
	if tgt != null:
		overlay.draw_arc(tgt, 60.0, 0, TAU, 40, col, 4.0)
		overlay.draw_arc(tgt, 20.0, 0, TAU, 20, col, 3.0)
		var a: Vector2 = player.position
		var b: Vector2 = tgt
		var d := a.distance_to(b)
		var n := int(d / 40.0)
		for i in range(1, n, 2):
			overlay.draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), Color(col, 0.5), 3.0)
	if era == "modern":
		overlay.draw_string(ThemeDB.fallback_font, POINT_ECHO + Vector2(70, 10), "POINT ECHO", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.6, 0.1, 0.1))
		overlay.draw_string(ThemeDB.fallback_font, SEA_BUOY + Vector2(70, 10), "SEA BUOY", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.6, 0.1, 0.1))
	# ship labels near player
	for v in vessels:
		if not is_instance_valid(v) or v == player or v.vname == "":
			continue
		var near: bool = v.position.distance_to(player.position) < VISUAL_RANGE
		if (near and v.kind != "merchant") or v == port_royal:
			overlay.draw_string(ThemeDB.fallback_font, v.position + Vector2(24, -18), v.vname, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.1, 0.1, 0.1) if era == "modern" else Color(0.85, 0.8, 0.6))


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
	# coarse coastline: sample land points
	var scale := rad / RADAR_RANGE
	var step := 110.0
	var y := -RADAR_RANGE
	while y <= RADAR_RANGE:
		var x := -RADAR_RANGE
		while x <= RADAR_RANGE:
			var off := Vector2(x, y)
			if off.length() < RADAR_RANGE and not world.is_water(player.position + off):
				r.draw_rect(Rect2(c + off * scale - Vector2(2, 2), Vector2(4, 4)), Color(0.3, 0.75, 0.45, 0.35))
			x += step
		y += step
	for v in vessels:
		if not is_instance_valid(v) or v == player:
			continue
		var off: Vector2 = v.position - player.position
		if off.length() > RADAR_RANGE:
			continue
		var col := Color(0.6, 1.0, 0.7)
		if v.needs_report and not v.reported:
			col = Color(1.0, 0.85, 0.3)
		if v.distress:
			col = Color(1.0, 0.35, 0.3)
		r.draw_circle(c + off * scale, 3.5, col)
	r.draw_circle(c, 3.0, Color(1, 1, 1))
	r.draw_string(ThemeDB.fallback_font, Vector2(8, 16), "RADAR 3.5 nm", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.9, 0.6))


func _update_hud() -> void:
	if player == null:
		return
	top_obj.text = objective
	top_nav.text = "%s  ·  %04.1f kn  ·  HDG %03d°  ·  %s" % [VesselScript.TELE_NAME[player.telegraph], absf(player.speed), int(round(player.heading)) % 360, VesselScript.RUDDER_NAME[player.rudder]]
	for k in tele_buttons:
		tele_buttons[k].modulate = Color(1.0, 0.8, 0.4) if player.telegraph == k else Color(1, 1, 1)
	for k in rudder_buttons:
		rudder_buttons[k].modulate = Color(1.0, 0.8, 0.4) if player.rudder == k else Color(1, 1, 1)
	# rebuild radio buttons only when the set changes
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
			l.text = "Nothing to report."
			l.add_theme_color_override("font_color", Color(0.6, 0.68, 0.72))
			radio_box.add_child(l)
		for a in acts:
			var b := Button.new()
			b.text = a[1]
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(0, 44)
			b.pressed.connect(_do_action.bind(a[0]))
			radio_box.add_child(b)
