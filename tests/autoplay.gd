extends SceneTree
## Headless smoke test: plays the whole mission and the 1942 Echo with a simple autopilot.
## Run: godot --headless -s tests/autoplay.gd

var main
var t := 0.0
var last_stage := -99
var debriefs := 0
var done := false


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Engine.time_scale = 4.0


func _pick() -> void:
	var title: String = main.modal_title.text
	var idx := 0
	if title.begins_with("READ-BACK"):
		idx = 1
	elif title.begins_with("THE BREAK"):
		idx = 2
	elif title.begins_with("AFTER ACTION"):
		debriefs += 1
		print("DEBRIEF scores=", main.scores)
		for e in main.aar:
			print("  AAR ", e)
		idx = 0
	elif title.begins_with("ECHO COMPLETE"):
		print("ECHO COMPLETE orders=", main.echo_orders.size())
		print(main.modal_body.get_parsed_text().substr(0, 120))
		done = true
	print("MODAL: ", title.replace("\n", " "), " -> ", idx)
	main._modal_pick(idx)


func _process(delta: float) -> bool:
	t += delta
	if done or t > 900.0:
		print("END t=", t, " done=", done)
		return true
	if main.modal_root.visible:
		_pick()
		return false
	if main.player == null or main.phase != "sail":
		return false
	if main.stage != last_stage:
		last_stage = main.stage
		print("t=%.1f era=%s stage=%d pos=%s" % [main.mission_time, main.era, main.stage, main.player.position])
	if main.era == "1942":
		main._set_telegraph(main.echo_tele_order)
		main._set_rudder(main.echo_rudder_order)
		return false
	for a in main._radio_actions():
		main._do_action(a[0])
	var tgt = main._current_target()
	if tgt == null:
		return false
	var p: Vector2 = main.player.position
	var to: Vector2 = tgt - p
	var want := rad_to_deg(atan2(to.x, -to.y))
	var err := wrapf(want - main.player.heading, -180.0, 180.0)
	var r := 0
	if absf(err) > 30: r = 2 if err > 0 else -2
	elif absf(err) > 6: r = 1 if err > 0 else -1
	main._set_rudder(r)
	var tele := 2
	if main.stage == 5 and main.lady_hannah and p.distance_to(main.lady_hannah.position) < 600:
		tele = 1 if p.distance_to(main.lady_hannah.position) > 180 else 0
	elif main.stage == 2 or main.stage == 4 or main.stage == 7:
		tele = 2
	main._set_telegraph(tele)
	return false
