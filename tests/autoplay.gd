extends SceneTree
## Headless smoke test: plays Mission 1, the 1942 Echo and Mission 2 with a simple autopilot.
## Run: godot --headless -s tests/autoplay.gd            (English)
##      godot --headless -s tests/autoplay.gd -- fr      (French)

var main
var t := 0.0
var last_stage := -99
var last_era := ""
var debriefs := 0
var done := false
var lang := "en"


func _initialize() -> void:
	if "fr" in OS.get_cmdline_user_args():
		lang = "fr"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Engine.time_scale = 4.0


func _pick() -> void:
	var title: String = main.modal_title.text
	var idx := 0
	var first_btn: String = main.modal_buttons.get_child(0).text if main.modal_buttons.get_child_count() > 0 else ""
	if first_btn == "English":
		idx = 1 if lang == "fr" else 0
	elif title.begins_with("TRUE NORTH") or title.begins_with("COMMANDEMENT"):
		idx = 1 if lang == "fr" else 0   # officer: Élise or Liam
	elif title.begins_with("READ-BACK") or title.begins_with("COLLATIONNEMENT"):
		idx = 1
	elif title.begins_with("THE BREAK") or title.begins_with("LE POINT DE RUPTURE"):
		idx = 2
	elif title.begins_with("AFTER ACTION") or title.begins_with("RETOUR D'EXP"):
		debriefs += 1
		print("DEBRIEF mission=", main.mission, " scores=", main.scores)
		for e in main.aar:
			print("  AAR ", e)
		if main.mission == 2:
			print("ALL MISSIONS COMPLETE lang=", lang, " break=", main.break_choice)
			done = true
			return
		idx = 0
	elif title.begins_with("ECHO COMPLETE") or title.begins_with("ÉCHO TERMINÉ"):
		print("ECHO COMPLETE orders=", main.echo_orders.size())
		idx = 0
	print("MODAL: ", title.replace("\n", " "), " -> ", idx)
	main._modal_pick(idx)


func _process(delta: float) -> bool:
	t += delta
	if done or t > 2500.0:
		print("END t=", t, " done=", done)
		return true
	if main.modal_root.visible:
		_pick()
		return false
	if main.player == null or main.phase != "sail":
		return false
	if main.stage != last_stage or main.era != last_era:
		last_stage = main.stage
		last_era = main.era
		print("t=%.1f era=%s stage=%d pos=%s" % [main.mission_time, main.era, main.stage, main.player.position])
	if main.era == "1942":
		main._set_telegraph(main.echo_tele_order)
		main._set_rudder(main.echo_rudder_order)
		return false
	var p: Vector2 = main.player.position
	if int(main.mission_time / 20.0) != int((main.mission_time - delta) / 20.0):
		print("  .. t=%.0f stage=%d pos=%s hdg=%.0f kn=%.1f helo=%s obj=%s" % [main.mission_time, main.stage, p, main.player.heading, main.player.speed, main.helo_state, main.objective])
	for a in main._radio_actions():
		if a[0] == "board" and main.player.speed > 5.0:
			continue
		main._do_action(a[0])
	var tgt = main._current_target()
	if tgt == null:
		return false
	if main.era == "sable" and _blocked(p, tgt):
		# steer round the nearest end of Sable Island instead of driving over it
		var best := Vector2.ZERO
		var bd := INF
		for e in [Vector2(1050, -880), Vector2(4150, -880)]:
			var d: float = p.distance_to(e) + e.distance_to(tgt)
			if d < bd:
				bd = d
				best = e
		tgt = best
	var to: Vector2 = tgt - p
	var want := rad_to_deg(atan2(to.x, -to.y))
	var err := wrapf(want - main.player.heading, -180.0, 180.0)
	var r := 0
	if absf(err) > 30: r = 2 if err > 0 else -2
	elif absf(err) > 6: r = 1 if err > 0 else -1
	main._set_rudder(r)
	var tele := 2
	if main.mission == 1 and main.stage == 5 and main.lady_hannah and p.distance_to(main.lady_hannah.position) < 600:
		tele = 1 if p.distance_to(main.lady_hannah.position) > 180 else 0
	elif main.mission == 2 and main.stage == 3 and main.trawler:
		var d: float = p.distance_to(main.trawler.position)
		tele = 2 if d > 450 else (1 if d > 240 else 0)
	main._set_telegraph(tele)
	return false


func _blocked(a: Vector2, b: Vector2) -> bool:
	var n := int(a.distance_to(b) / 40.0)
	for i in n:
		if not main.world.is_water(a.lerp(b, float(i) / maxf(n, 1)), 70.0):
			return true
	return false
