extends Node2D
## Any ship or boat on the chart. The player's ship uses telegraph/rudder;
## AI vessels either drift on a fixed course or follow a target.

const KN := 4.5  # world units per second per knot (time is compressed)
const TELE_KN := {-1: -5.0, 0: 0.0, 1: 5.0, 2: 10.0, 3: 18.0, 4: 26.0}
const TELE_NAME := {-1: "Slow astern", 0: "Stop engines", 1: "Slow ahead", 2: "Half ahead", 3: "Full ahead", 4: "Flank speed"}
const RUDDER_NAME := {-2: "Port thirty", -1: "Port fifteen", 0: "Midships", 1: "Starboard fifteen", 2: "Starboard thirty"}

var kind := "frigate"   # frigate, corvette, ferry, fishing, merchant, unlit, rhib
var vname := ""
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
var hold := false
var cruise_kn := 0.0
var distress := false
var t := 0.0
var needs_report := false
var detected_at := -1.0
var reported := false
var contact_desc := "contact"


func dir() -> Vector2:
	var r := deg_to_rad(heading)
	return Vector2(sin(r), -cos(r))


func step(delta: float) -> void:
	t += delta
	if is_player:
		var tgt: float = clampf(TELE_KN[telegraph], -max_kn, max_kn)
		speed = move_toward(speed, tgt, 2.2 * delta)
		var steer := clampf(absf(speed) / 8.0, 0.0, 1.2)
		heading = fposmod(heading + rudder * 7.5 * steer * signf(speed + 0.0001) * delta, 360.0)
	elif follow and not hold:
		var to := follow.position - position
		var want := rad_to_deg(atan2(to.x, -to.y))
		var diff := wrapf(want - heading, -180.0, 180.0)
		heading = fposmod(heading + clampf(diff, -25.0 * delta, 25.0 * delta), 360.0)
		var d := to.length()
		var tgt_kn := 0.0 if d < follow_gap else clampf((d - follow_gap) / 40.0, 3.0, 16.0)
		speed = move_toward(speed, tgt_kn, 2.0 * delta)
	elif hold:
		speed = move_toward(speed, 0.0, 2.0 * delta)
	else:
		speed = move_toward(speed, cruise_kn, 2.0 * delta)
	position += dir() * speed * KN * delta
	rotation = deg_to_rad(heading)
	queue_redraw()


func _hull(l: float, b: float, stern_w: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -l / 2), Vector2(b / 2, -l / 4), Vector2(b / 2, l / 2 - 4),
		Vector2(stern_w / 2, l / 2), Vector2(-stern_w / 2, l / 2), Vector2(-b / 2, l / 2 - 4), Vector2(-b / 2, -l / 4),
	])


func _draw() -> void:
	match kind:
		"frigate":
			_wake(70.0)
			draw_colored_polygon(_hull(70, 14, 11), Color("6f7a82"))
			draw_rect(Rect2(-5, -16, 10, 22), Color("aab3b9"))
			draw_rect(Rect2(-3, -26, 6, 6), Color("4a525a"))
			draw_rect(Rect2(-6, 18, 12, 14), Color("8a949b"))
			draw_circle(Vector2(0, 25), 4.0, Color("e8e8e8"))
			draw_line(Vector2(0, -35), Vector2(0, -30), Color("4a525a"), 2.0)
		"corvette":
			_wake(55.0)
			draw_colored_polygon(_hull(56, 11, 8), Color("596a72"))
			draw_rect(Rect2(-4, -12, 8, 14), Color("8b9aa0"))
			draw_rect(Rect2(-2.5, 3, 5, 6), Color("2a2a2a"))
			draw_circle(Vector2(0, -21), 2.5, Color("3a3a3a"))
		"merchant":
			_wake(80.0)
			draw_colored_polygon(_hull(84, 16, 14), Color("8e2f2a"))
			for i in range(5):
				draw_rect(Rect2(-6, -26 + i * 9, 12, 7), [Color("2f6db5"), Color("d38c2b"), Color("3a8a4c"), Color("c9c9c9"), Color("b43a3a")][i])
			draw_rect(Rect2(-7, 24, 14, 10), Color("f0f0f0"))
		"ferry":
			_wake(30.0)
			draw_rect(Rect2(-8, -16, 16, 32), Color("f1f1f1"))
			draw_rect(Rect2(-5, -9, 10, 18), Color("2f6a9a"))
		"fishing":
			_wake(20.0)
			draw_colored_polygon(_hull(22, 7, 5), Color("c2412e") if not distress else Color("e05a3a"))
			draw_rect(Rect2(-2.5, -2, 5, 6), Color("f0e6d0"))
		"unlit":
			draw_colored_polygon(_hull(16, 5, 4), Color("2a2f33"))
		"rhib":
			_wake(10.0)
			draw_colored_polygon(_hull(9, 3.5, 3), Color("ff7a1a"))
	if lit and not darkened and kind in ["frigate", "corvette", "merchant", "ferry", "fishing"]:
		var half := 6.0
		draw_circle(Vector2(-half, -4), 2.2, Color("ff3b30"))  # port light, red
		draw_circle(Vector2(half, -4), 2.2, Color("34c759"))   # starboard light, green
	if distress and int(t * 2.0) % 2 == 0:
		draw_arc(Vector2.ZERO, 26.0, 0, TAU, 24, Color("ff3b30"), 2.0)


func _wake(len_: float) -> void:
	var s := clampf(absf(speed) / 18.0, 0.0, 1.0)
	if s < 0.05:
		return
	var w := Color(1, 1, 1, 0.35 * s)
	draw_colored_polygon(PackedVector2Array([Vector2(-4, len_ / 2 - 6), Vector2(4, len_ / 2 - 6), Vector2(14 + 18 * s, len_ / 2 + 70 * s), Vector2(-14 - 18 * s, len_ / 2 + 70 * s)]), w)
