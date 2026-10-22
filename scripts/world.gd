extends Node2D
## Simplified chart of Halifax Harbour. North is up (-y), the sea is south (+y).
## Water is a union of capsules (channel segments) minus islands, plus open sea below OPEN_SEA_Y.

const OPEN_SEA_Y := 3700.0

# [start, end, radius]
const CHANNEL := [
	[Vector2(0, 0), Vector2(0, 0), 900.0],            # Bedford Basin
	[Vector2(0, 0), Vector2(250, 650), 300.0],        # basin mouth
	[Vector2(250, 650), Vector2(700, 1600), 170.0],   # The Narrows
	[Vector2(700, 1600), Vector2(900, 2400), 380.0],  # inner harbour
	[Vector2(900, 2400), Vector2(1000, 3400), 520.0], # outer harbour
	[Vector2(1000, 3400), Vector2(1000, 3800), 760.0], # approaches
]

# [centre, radius, name]
const ISLANDS := [
	[Vector2(1000, 2060), 70.0, "George's Island"],
	[Vector2(1560, 2980), 300.0, "McNabs Island"],
]

const NARROWS_A := Vector2(250, 650)
const NARROWS_B := Vector2(700, 1600)

# Centre-line route used for guidance and the 1942 helm orders.
const ROUTE := [
	Vector2(120, 330), Vector2(290, 740), Vector2(480, 1150), Vector2(700, 1600),
	Vector2(850, 2250), Vector2(930, 2750), Vector2(980, 3300), Vector2(1000, 3900), Vector2(1000, 5200),
]

var era := "modern"  # "modern" or "1942"
var gate_open := false

var c_land := Color("d9cfae")
var c_land_edge := Color("8a7f5c")
var c_water := Color("9cc3d0")
var c_deep := Color("7fb0c2")
var c_label := Color("3d3a2c")
var c_grid := Color(0.2, 0.3, 0.35, 0.12)


func set_era(e: String) -> void:
	era = e
	if era == "1942":
		c_land = Color("2b2a24")
		c_land_edge = Color("5a5440")
		c_water = Color("10212b")
		c_deep = Color("0c1a22")
		c_label = Color("b9a87a")
		c_grid = Color(0.7, 0.6, 0.4, 0.06)
	else:
		c_land = Color("d9cfae")
		c_land_edge = Color("8a7f5c")
		c_water = Color("9cc3d0")
		c_deep = Color("7fb0c2")
		c_label = Color("3d3a2c")
		c_grid = Color(0.2, 0.3, 0.35, 0.12)
	queue_redraw()


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func is_water(p: Vector2, margin := 0.0) -> bool:
	for isl in ISLANDS:
		if p.distance_to(isl[0]) < isl[1] + margin:
			return false
	if p.y > OPEN_SEA_Y + margin:
		return true
	for seg in CHANNEL:
		if _dist_to_segment(p, seg[0], seg[1]) < seg[2] - margin:
			return true
	return false


func in_narrows(p: Vector2) -> bool:
	var ab := NARROWS_B - NARROWS_A
	var t := (p - NARROWS_A).dot(ab) / ab.length_squared()
	return t > 0.05 and t < 0.95 and _dist_to_segment(p, NARROWS_A, NARROWS_B) < 260.0


func gate_points() -> Array:
	# 1942 anti-submarine net from the Halifax shore toward McNabs Island, with a gate in the channel.
	return [Vector2(560, 2700), Vector2(880, 2720), Vector2(1060, 2730), Vector2(1300, 2760)]


func gate_blocks(p: Vector2) -> bool:
	if era != "1942":
		return false
	var g := gate_points()
	var y_line := 2725.0
	if absf(p.y - y_line) > 18.0:
		return false
	if p.x > g[1].x and p.x < g[2].x:
		return not gate_open
	return p.x > g[0].x and p.x < g[3].x


func _capsule(a: Vector2, b: Vector2, r: float, c: Color) -> void:
	draw_circle(a, r, c)
	draw_circle(b, r, c)
	if a.distance_to(b) > 0.1:
		var n := (b - a).normalized().orthogonal() * r
		draw_colored_polygon(PackedVector2Array([a + n, b + n, b - n, a - n]), c)


func _draw() -> void:
	var big := Rect2(-3000, -2500, 8000, 9000)
	draw_rect(big, c_land)
	# water with a shoreline band
	for seg in CHANNEL:
		_capsule(seg[0], seg[1], seg[2] + 14.0, c_land_edge)
	draw_rect(Rect2(-3000, OPEN_SEA_Y - 14.0, 8000, 6000), c_land_edge)
	for seg in CHANNEL:
		_capsule(seg[0], seg[1], seg[2], c_water)
	draw_rect(Rect2(-3000, OPEN_SEA_Y, 8000, 6000), c_water)
	# deeper water contour
	for seg in CHANNEL:
		_capsule(seg[0], seg[1], seg[2] * 0.55, c_deep)
	draw_rect(Rect2(-3000, OPEN_SEA_Y + 250.0, 8000, 6000), c_deep)
	for isl in ISLANDS:
		draw_circle(isl[0], isl[1] + 14.0, c_land_edge)
		draw_circle(isl[0], isl[1], c_land)
	# chart grid (one square = 1 nautical mile at this scale, approx.)
	for x in range(-3000, 5000, 370):
		draw_line(Vector2(x, -2500), Vector2(x, 6500), c_grid, 1.0)
	for y in range(-2500, 6500, 370):
		draw_line(Vector2(-3000, y), Vector2(5000, y), c_grid, 1.0)
	# bridges across the Narrows (modern only)
	if era == "modern":
		_bridge(0.32, "A. Murray MacKay Bridge")
		_bridge(0.62, "Angus L. Macdonald Bridge")
	else:
		_draw_net()
	# place names
	var f := ThemeDB.fallback_font
	var names := [
		[Vector2(-260, -40), "BEDFORD BASIN"], [Vector2(560, 1040), "THE NARROWS"],
		[Vector2(-250, 1900), "HALIFAX"], [Vector2(1250, 1500), "DARTMOUTH"],
		[Vector2(1440, 2990), "McNABS ISLAND"], [Vector2(930, 2160), "George's Is."],
		[Vector2(330, 2640), "Point Pleasant"], [Vector2(80, 3560), "Chebucto Head"],
		[Vector2(820, 4300), "ATLANTIC OCEAN"],
	]
	for n in names:
		draw_string(f, n[0], n[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, c_label)


func _bridge(t: float, label: String) -> void:
	var p := NARROWS_A.lerp(NARROWS_B, t)
	var n := (NARROWS_B - NARROWS_A).normalized().orthogonal() * 230.0
	var c := Color("5d6066")
	draw_line(p - n, p + n, c, 10.0)
	draw_line(p - n, p + n, Color("b8bcc2"), 3.0)
	draw_string(ThemeDB.fallback_font, p + n + Vector2(12, 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, c_label)


func _draw_net() -> void:
	var g := gate_points()
	var net := Color("c9a65a")
	draw_line(g[0], g[1], net, 4.0)
	draw_line(g[2], g[3], net, 4.0)
	for i in range(0, 12):
		draw_circle(g[0].lerp(g[1], i / 11.0), 6.0, net)
		draw_circle(g[2].lerp(g[3], i / 11.0), 6.0, net)
	if not gate_open:
		draw_line(g[1], g[2], Color("e0b84f"), 3.0)
	draw_string(ThemeDB.fallback_font, g[1] + Vector2(0, -24), "A/S GATE", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, net)
