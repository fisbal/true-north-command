extends SceneTree
## Renders screenshots of each era and camera: godot -s tests/shots.gd -- <outdir>

var main
var t := 0.0
var step := 0
var out := "user://"
var plan := [
	["title", 0, 1.0], ["m1", 0, 6.0], ["m1", 1, 1.0], ["m1", 2, 1.0],
	["echo", 0, 6.0], ["m2", 0, 6.0], ["m2", 1, 1.0], ["m2", 2, 1.0],
]
var shot_t := 0.0
var started := -1


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _go(what: String) -> void:
	main.modal_root.hide()
	main.view.cam_mode = 0
	match what:
		"m1":
			main._start_mission(1)
			main.modal_root.hide()
			main._start_sail("test", [])
			main._set_telegraph(2)
		"echo":
			main._echo_intro()
			main.modal_root.hide()
			main._echo_start()
			main.modal_root.hide()
		"m2":
			main._start_mission(2)
			main.modal_root.hide()
			main.stage = 0
			main._start_sail("test", [])
			main._set_telegraph(2)
			main._launch_helo()


func _process(delta: float) -> bool:
	t += delta
	shot_t += delta
	if step >= plan.size():
		return true
	var p: Array = plan[step]
	if started != step:
		started = step
		if step == 0 or plan[step - 1][0] != p[0]:
			if p[0] != "title":
				_go(p[0])
		main.view.cam_mode = p[1]
	if shot_t >= p[2]:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/%02d_%s_cam%d.png" % [out, step, p[0], p[1]])
		print("shot ", step)
		step += 1
		shot_t = 0.0
	return false
