extends Node2D
## Any ship, boat or aircraft on the chart. The player's ship uses telegraph/rudder;
## AI vessels either cruise on a fixed course, hold, or follow a target.
## Drawn top-down in local space with the bow pointing up (-y).

const KN := 4.5  # world units per second per knot (time is compressed)
const TELE_KN := {-1: -5.0, 0: 0.0, 1: 5.0, 2: 10.0, 3: 18.0, 4: 26.0}

var kind := "frigate"   # frigate, corvette, ferry, fishing, merchant, unlit, trawler, rhib, helo
var vname := ""
var hull_no := ""
var heading := 160.0    # degrees true, 0 = north
var speed := 0.0        # knots
var telegraph := 0
var rudder := 0
var max_kn := 26.0
var lit := true
var darkened := false
var is_player := false
var follow: Node2D = null
var follow_gap := 260.0
var max_follow_kn := 16.0
var hold := false
var cruise_kn := 0.0
var distress := false
var t := 0.0
var needs_report := false
var detected_at := -1.0
var reported := false
var contact_desc := "contact"
var identified := false
var ais := true
var trail: Array = []       # recent stern positions (world space), drawn by the trail layer
var _trail_t := 0.0

# palette
const C_OUT := Color(0.08, 0.1, 0.12, 0.85)
const C_SHADOW := Color(0, 0, 0, 0.22)
const C_FOAM := Color(1, 1, 1, 0.75)


func dir() -> Vector2:
	var r := deg_to_rad(heading)
	return Vector2(sin(r), -cos(r))


func length() -> float:
	return {"frigate": 84.0, "corvette": 60.0, "merchant": 104.0, "ferry": 34.0, "fishing": 28.0,
		"unlit": 18.0, "trawler": 38.0, "rhib": 11.0, "helo": 22.0}.get(kind, 30.0)


func step(delta: float) -> void:
	t += delta
	if is_player:
		var tgt: float = clampf(TELE_KN[telegraph], -max_kn, max_kn)
		speed = move_toward(speed, tgt, 2.2 * delta)
		var steer := clampf(absf(speed) / 8.0, 0.0, 1.2)
		heading = fposmod(heading + rudder * 7.5 * steer * signf(speed + 0.0001) * delta, 360.0)
	elif follow and is_instance_valid(follow) and not hold:
		var to := follow.position - position
		var want := rad_to_deg(atan2(to.x, -to.y))
		var diff := wrapf(want - heading, -180.0, 180.0)
		var turn := 25.0 if kind != "helo" else 120.0
		heading = fposmod(heading + clampf(diff, -turn * delta, turn * delta), 360.0)
		var d := to.length()
		var tgt_kn := 0.0 if d < follow_gap else clampf((d - follow_gap) / 40.0, 3.0, max_follow_kn)
		speed = move_toward(speed, tgt_kn, (2.0 if kind != "helo" else 12.0) * delta)
	elif hold:
		speed = move_toward(speed, 0.0, 2.0 * delta)
	else:
		speed = move_toward(speed, cruise_kn, 2.0 * delta)
	position += dir() * speed * KN * delta
	rotation = deg_to_rad(heading)
	# wake trail (ships and boats only)
	_trail_t += delta
	if kind != "helo" and _trail_t > 0.2:
		_trail_t = 0.0
		if absf(speed) > 1.0:
			trail.append([position - dir() * length() * 0.5, t])
		while trail.size() > 0 and t - trail[0][1] > 7.0:
			trail.pop_front()
	queue_redraw()


# ---------------------------------------------------------------- drawing helpers

func _hull(l: float, b: float, stern_w: float, bow_sharp := 0.32) -> PackedVector2Array:
	# smooth pointed bow, parallel midbody, transom stern
	var pts := PackedVector2Array()
	var hl := l / 2.0
	var bow_len := l * bow_sharp
	for i in 7:
		var a := float(i) / 6.0
		var y := -hl + bow_len * a
		var x := (b / 2.0) * sin(a * PI / 2.0)
		pts.append(Vector2(x, y))
	pts.append(Vector2(b / 2.0, hl - 6.0))
	pts.append(Vector2(stern_w / 2.0, hl))
	pts.append(Vector2(-stern_w / 2.0, hl))
	pts.append(Vector2(-b / 2.0, hl - 6.0))
	for i in range(6, -1, -1):
		var a := float(i) / 6.0
		pts.append(Vector2(-(b / 2.0) * sin(a * PI / 2.0), -hl + bow_len * a))
	return pts


func _shape(pts: PackedVector2Array, fill: Color, outline := true) -> void:
	draw_colored_polygon(pts, fill)
	if outline:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, C_OUT, 1.2, true)


func _shadow(pts: PackedVector2Array) -> void:
	var s := PackedVector2Array()
	for p in pts:
		s.append(p + Vector2(4, 5).rotated(-rotation))
	draw_colored_polygon(s, C_SHADOW)


func _box(r: Rect2, c: Color) -> void:
	draw_rect(r, c)
	draw_rect(r, C_OUT, false, 1.0)


func _gun(at: Vector2, r: float, barrel: float, c: Color) -> void:
	draw_circle(at, r, c)
	draw_arc(at, r, 0, TAU, 16, C_OUT, 1.0)
	draw_line(at, at + Vector2(0, -barrel), C_OUT, 2.0)


func _bow_wave(l: float, b: float) -> void:
	var s := clampf(absf(speed) / 18.0, 0.0, 1.0)
	if s < 0.08:
		return
	var y := -l / 2.0
	var c := Color(1, 1, 1, 0.55 * s)
	draw_polyline(PackedVector2Array([Vector2(-b * 0.9 - 6 * s, y + l * 0.35), Vector2(-b * 0.25, y + 4), Vector2(0, y - 2)]), c, 2.0, true)
	draw_polyline(PackedVector2Array([Vector2(b * 0.9 + 6 * s, y + l * 0.35), Vector2(b * 0.25, y + 4), Vector2(0, y - 2)]), c, 2.0, true)
	draw_circle(Vector2(0, l / 2.0 + 3), b * 0.35 * s + 1.0, Color(1, 1, 1, 0.5 * s))


func _nav_lights(l: float, b: float) -> void:
	if not lit or darkened:
		return
	draw_circle(Vector2(-b / 2.0 - 1, -l * 0.08), 2.4, Color("ff3b30"))  # port, red
	draw_circle(Vector2(b / 2.0 + 1, -l * 0.08), 2.4, Color("34c759"))   # starboard, green
	draw_circle(Vector2(0, l / 2.0 - 2), 1.8, Color("fffbe6"))             # stern light


# ---------------------------------------------------------------- vessel art

func _draw() -> void:
	match kind:
		"frigate":
			_draw_frigate()
		"corvette":
			_draw_corvette()
		"merchant":
			_draw_merchant()
		"ferry":
			_draw_ferry()
		"fishing":
			_draw_fishing()
		"unlit":
			_draw_skiff()
		"trawler":
			_draw_trawler()
		"rhib":
			_draw_rhib()
		"helo":
			_draw_helo()
	if distress and int(t * 2.0) % 2 == 0:
		draw_arc(Vector2.ZERO, length() * 0.9, 0, TAU, 32, Color("ff3b30"), 2.5)


func _draw_frigate() -> void:
	# Halifax-class style patrol frigate
	var l := 84.0
	var b := 15.0
	var hull := _hull(l, b, 12.0, 0.34)
	_shadow(hull)
	_bow_wave(l, b)
	_shape(hull, Color("6e7a83"))
	_shape(_hull(l - 6, b - 4, 9.0, 0.34), Color("8b959c"), false)       # deck
	# hull number on the foredeck
	draw_string(ThemeDB.fallback_font, Vector2(-7, -24), hull_no, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("f2f2f2"))
	_gun(Vector2(0, -22), 3.6, 9.0, Color("9aa4ab"))                       # 57 mm gun
	_box(Rect2(-3.5, -16, 7, 4), Color("5d676f"))                          # missile cells
	_box(Rect2(-5.5, -11, 11, 16), Color("b4bdc3"))                        # bridge + superstructure
	draw_rect(Rect2(-4.5, -10, 9, 2.2), Color("1d2a33"))                   # bridge windows
	_box(Rect2(-2.5, -2, 5, 5), Color("596169"))                           # mast base
	var ang := t * 3.0
	draw_line(Vector2(0, 0.5) - Vector2(cos(ang), sin(ang)) * 6.0, Vector2(0, 0.5) + Vector2(cos(ang), sin(ang)) * 6.0, Color("e6e9eb"), 1.6)
	_box(Rect2(-4.5, 6, 9, 7), Color("9da6ad"))                            # funnel block
	draw_rect(Rect2(-3, 7.5, 6, 3), Color("2a2f33"))
	_box(Rect2(-6, 14, 12, 9), Color("aab3b9"))                            # hangar
	draw_rect(Rect2(-6.5, 23, 13, 16), Color("4f585f"))                    # flight deck
	draw_arc(Vector2(0, 31), 5.0, 0, TAU, 20, Color("f5f5f5"), 1.2)
	draw_line(Vector2(0, 23.5), Vector2(0, 38.5), Color("f2d24b"), 1.0)
	_nav_lights(l, b)


func _draw_corvette() -> void:
	# Flower-class corvette, 1942, with dazzle camouflage
	var l := 60.0
	var b := 12.0
	var hull := _hull(l, b, 7.0, 0.3)
	_shadow(hull)
	_bow_wave(l, b)
	_shape(hull, Color("6f8a8c"))
	var dazzle := [
		[Vector2(-6, -20), Vector2(6, -14), Vector2(6, -8), Vector2(-6, -14)],
		[Vector2(-6, 2), Vector2(6, -4), Vector2(6, 4), Vector2(-6, 10)],
		[Vector2(-6, 16), Vector2(6, 20), Vector2(5, 26), Vector2(-5, 22)],
	]
	for poly in dazzle:
		draw_colored_polygon(PackedVector2Array(poly), Color("3e5560"))
	_shape(_hull(l - 6, b - 4, 5.0, 0.3), Color(0.72, 0.78, 0.76, 0.35), false)
	_gun(Vector2(0, -17), 3.0, 7.0, Color("7d8b8e"))                       # 4-inch gun
	_box(Rect2(-4.5, -11, 9, 9), Color("c9d1cf"))                          # bridge
	draw_rect(Rect2(-3.5, -10.2, 7, 1.8), Color("1d2a33"))
	draw_circle(Vector2(0, 0), 1.6, Color("3a3a3a"))                       # mast
	_box(Rect2(-3, 3, 6, 7), Color("4a4f52"))                              # funnel
	draw_rect(Rect2(-2, 4, 4, 2), Color("1c1c1c"))
	_gun(Vector2(0, 16), 2.2, 4.0, Color("7d8b8e"))                        # pom-pom aft
	for i in 3:
		draw_rect(Rect2(-5, 21 + i * 2.6, 3, 1.6), Color("2b2b2b"))         # depth-charge rails
		draw_rect(Rect2(2, 21 + i * 2.6, 3, 1.6), Color("2b2b2b"))
	_nav_lights(l, b)


func _draw_merchant() -> void:
	var l := 104.0
	var b := 18.0
	var hull := _hull(l, b, 16.0, 0.22)
	_shadow(hull)
	_bow_wave(l, b)
	_shape(hull, Color("7d2a26"))
	_shape(_hull(l - 5, b - 3, 13.0, 0.22), Color("8f8f86"), false)
	var cols := [Color("2f6db5"), Color("d38c2b"), Color("3a8a4c"), Color("c9c9c9"), Color("b43a3a"), Color("5b4f8f"), Color("2f6db5")]
	for i in 7:
		var y := -33.0 + i * 9.0
		for j in 3:
			_box(Rect2(-7.5 + j * 5.0, y, 4.6, 8), cols[(i + j * 2) % cols.size()])
	_box(Rect2(-8, 31, 16, 10), Color("f2f2ee"))                           # accommodation
	draw_rect(Rect2(-7, 31.5, 14, 2), Color("1d2a33"))
	_box(Rect2(-3, 42, 6, 4), Color("222222"))                             # funnel
	_nav_lights(l, b)


func _draw_ferry() -> void:
	var l := 34.0
	var b := 14.0
	var r := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		r.append(Vector2(cos(a) * b / 2.0, sin(a) * l / 2.0))
	_shadow(r)
	_bow_wave(l, b)
	_shape(r, Color("f3f3f0"))
	_box(Rect2(-5, -10, 10, 20), Color("2f6a9a"))
	draw_rect(Rect2(-4, -9, 8, 3), Color("bfe0f0"))
	draw_rect(Rect2(-4, 6, 8, 3), Color("bfe0f0"))
	_nav_lights(l, b)


func _draw_fishing() -> void:
	var l := 28.0
	var b := 9.0
	var hull := _hull(l, b, 7.0, 0.38)
	_shadow(hull)
	_bow_wave(l, b)
	_shape(hull, Color("2e5f9a") if not distress else Color("d4533b"))
	_shape(_hull(l - 4, b - 3, 5.0, 0.38), Color("d9d2bf"), false)
	_box(Rect2(-3.2, -6, 6.4, 6), Color("f4f1e6"))                         # wheelhouse
	draw_rect(Rect2(-2.6, -5.6, 5.2, 1.6), Color("1d2a33"))
	draw_circle(Vector2(0, 6), 2.6, Color("6b6b5f"))                       # net drum
	draw_line(Vector2(0, 2), Vector2(-11, 10), Color("5a4a36"), 1.2)       # outriggers
	draw_line(Vector2(0, 2), Vector2(11, 10), Color("5a4a36"), 1.2)
	_nav_lights(l, b)


func _draw_skiff() -> void:
	var hull := _hull(18, 6, 5, 0.4)
	_shadow(hull)
	_bow_wave(18, 6)
	_shape(hull, Color("2a2f33"))
	draw_rect(Rect2(-2, 1, 4, 4), Color("3e454b"))
	draw_rect(Rect2(-1.5, 7.5, 3, 2), Color("111111"))                      # outboard


func _draw_trawler() -> void:
	var l := 38.0
	var b := 11.0
	var hull := _hull(l, b, 9.0, 0.32)
	_shadow(hull)
	_bow_wave(l, b)
	_shape(hull, Color("2c3135"))
	_shape(_hull(l - 4, b - 3, 7.0, 0.32), Color("4a4e4a"), false)
	_box(Rect2(-3.5, -12, 7, 7), Color("6d6f68"))                          # wheelhouse
	draw_rect(Rect2(-3, -11.5, 6, 1.6), Color("111111"))
	var tarp := Rect2(-4.5, -2, 9, 14)                                     # tarp-covered deck cargo
	_box(tarp, Color("6b5a3a"))
	for i in 5:
		draw_line(Vector2(-4.5, -2 + i * 3.5), Vector2(4.5, 1.5 + i * 3.5), Color("4d3f27"), 1.0)
	draw_line(Vector2(0, 12), Vector2(0, 17), Color("222222"), 2.0)       # gantry
	draw_line(Vector2(-4, 16), Vector2(4, 16), Color("222222"), 2.0)
	_nav_lights(l, b)


func _draw_rhib() -> void:
	var l := 11.0
	var b := 4.6
	var hull := _hull(l, b, 4.0, 0.45)
	_shadow(hull)
	_bow_wave(l, b)
	_shape(hull, Color("ff7a1a"))
	draw_colored_polygon(_hull(l - 3, b - 2, 2.2, 0.45), Color("3b4247"))
	draw_rect(Rect2(-1, -1, 2, 2), Color("dde3e6"))
	for p in [Vector2(-0.8, 2.5), Vector2(0.8, 2.5), Vector2(0, -3)]:
		draw_circle(p, 0.8, Color("1a1a1a"))


func _draw_helo() -> void:
	# CH-148 Cyclone style
	var body := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		body.append(Vector2(cos(a) * 3.6, sin(a) * 7.5 - 2.0))
	var shadow_off := Vector2(14, 18).rotated(-rotation)
	var sh := PackedVector2Array()
	for p in body:
		sh.append(p + shadow_off)
	draw_colored_polygon(sh, Color(0, 0, 0, 0.18))
	draw_line(Vector2(0, 4), Vector2(0, 14), Color("5f6a72"), 2.2)       # tail boom
	draw_line(Vector2(-3, 13.5), Vector2(3, 13.5), Color("5f6a72"), 1.6)
	_shape(body, Color("727e86"))
	draw_colored_polygon(PackedVector2Array([Vector2(-2.6, -7), Vector2(2.6, -7), Vector2(2, -4), Vector2(-2, -4)]), Color("1d2a33"))
	var a0 := t * 18.0
	for k in 4:
		var a := a0 + k * PI / 2.0
		draw_line(Vector2(0, -1), Vector2(0, -1) + Vector2(cos(a), sin(a)) * 11.0, Color(0.15, 0.17, 0.18, 0.8), 1.4)
	draw_arc(Vector2(0, -1), 11.0, 0, TAU, 28, Color(0.9, 0.9, 0.9, 0.25), 1.0)
	draw_circle(Vector2(0, 14), 2.0, Color(0.2, 0.2, 0.2, 0.4))
