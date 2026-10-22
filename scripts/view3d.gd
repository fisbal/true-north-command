extends Node3D
## The 3D view. main.gd runs the missions on a 2D chart (x, y); this node shows the same
## world in 3D at (x, height, y), so chart north (-y) is -Z. It reads main's state every
## frame and never changes it, so the mission logic and the scoring stay in one place.

const Ships := preload("res://scripts/ships3d.gd")
const WorldScript := preload("res://scripts/world.gd")

const WATER_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec3 deep : source_color = vec3(0.10, 0.22, 0.27);
uniform vec3 crest : source_color = vec3(0.32, 0.45, 0.48);
uniform float amp = 0.6;
varying vec3 wpos;
float wave(vec2 p, float t) {
	return sin(p.x * 0.045 + t * 1.1) * 0.6 + sin(p.y * 0.065 - t * 1.4) * 0.5 + sin((p.x + p.y) * 0.11 + t * 2.0) * 0.25;
}
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	VERTEX.y += wave(w.xz, t) * amp;
	float e = 1.0;
	float hx = wave(w.xz + vec2(e, 0.0), t) - wave(w.xz - vec2(e, 0.0), t);
	float hz = wave(w.xz + vec2(0.0, e), t) - wave(w.xz - vec2(0.0, e), t);
	NORMAL = normalize(vec3(-hx * amp * 0.5, 1.0, -hz * amp * 0.5));
	wpos = w;
}
void fragment() {
	float r = sin(wpos.x * 0.9 + TIME * 2.3) * sin(wpos.z * 0.7 - TIME * 1.9);
	float r2 = sin(wpos.x * 0.31 - wpos.z * 0.27 + TIME * 1.3);
	NORMAL = normalize(NORMAL + VIEW_MATRIX[0].xyz * r * 0.06 + VIEW_MATRIX[1].xyz * r2 * 0.05);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(deep, crest, clamp(fres * 1.5 + r2 * 0.06, 0.0, 1.0));
	ROUGHNESS = 0.12;
	SPECULAR = 0.55;
}
"""

var main
var era := ""
var built_lang := ""
var models := {}    # vessel -> Node3D
var labels := {}    # vessel -> Label3D
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var water: MeshInstance3D
var water_mat: ShaderMaterial
var scenery: Node3D
var wake_mesh: ImmediateMesh
var beacon: Node3D
var gate_closed: Node3D
var sea_buoy: Node3D
var echo_buoy: Node3D
var distress_light: MeshInstance3D
var noise := FastNoiseLite.new()

var cam_mode := 0   # 0 chase, 1 bridge, 2 tactical
var zoom := 0.8
var orbit := 0.0
var pitch := 0.0
var drag_t := 10.0
var title_t := 0.0
var t := 0.0


func _ready() -> void:
	noise.seed = 1749
	noise.frequency = 0.004
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.5
	cam.far = 30000.0
	add_child(cam)
	cam.make_current()

	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.set("fog_mode", 1)   # depth fog (Godot 4.3+)
	env.fog_density = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = false
	add_child(sun)

	water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000, 9000)
	pm.subdivide_width = 140
	pm.subdivide_depth = 140
	water.mesh = pm
	var sh := Shader.new()
	sh.code = WATER_SHADER
	water_mat = ShaderMaterial.new()
	water_mat.shader = sh
	water.material_override = water_mat
	add_child(water)

	var wake := MeshInstance3D.new()
	wake_mesh = ImmediateMesh.new()
	wake.mesh = wake_mesh
	var wm := StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.vertex_color_use_as_albedo = true
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	wm.no_depth_test = false
	wake.material_override = wm
	add_child(wake)

	beacon = _make_beacon()
	add_child(beacon)
	distress_light = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.5
	sm.height = 5.0
	distress_light.mesh = sm
	distress_light.material_override = Ships.glow_mat(Color(1, 0.25, 0.1))
	distress_light.visible = false
	add_child(distress_light)


func _make_beacon() -> Node3D:
	var b := Node3D.new()
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.0
	cm.bottom_radius = 2.0
	cm.height = 260.0
	col.mesh = cm
	col.position.y = 130.0
	var m := Ships.glow_mat(Color(0.95, 0.2, 0.15, 0.35))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	col.material_override = m
	b.add_child(col)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 26.0
	tm.outer_radius = 30.0
	ring.mesh = tm
	ring.position.y = 1.0
	ring.material_override = m
	b.add_child(ring)
	b.set_meta("mat", m)
	return b


# ======================================================================
# Scenery per era
# ======================================================================

func set_era(e: String) -> void:
	era = e
	for v in models.keys():
		_drop(v)
	if scenery:
		scenery.queue_free()
	scenery = Node3D.new()
	add_child(scenery)
	gate_closed = null
	sea_buoy = null
	echo_buoy = null
	match era:
		"1942":
			sky_mat.sky_top_color = Color(0.02, 0.03, 0.06)
			sky_mat.sky_horizon_color = Color(0.07, 0.09, 0.12)
			sky_mat.ground_horizon_color = Color(0.05, 0.07, 0.09)
			sky_mat.ground_bottom_color = Color(0.02, 0.03, 0.04)
			sky_mat.sun_angle_max = 3.0
			sun.light_color = Color(0.6, 0.7, 0.9)
			sun.light_energy = 0.35
			sun.rotation_degrees = Vector3(-35, 140, 0)
			env.ambient_light_energy = 0.35
			env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
			env.fog_light_color = Color(0.05, 0.07, 0.1)
			water_mat.set_shader_parameter("deep", Color(0.02, 0.05, 0.07))
			water_mat.set_shader_parameter("crest", Color(0.1, 0.15, 0.2))
			water_mat.set_shader_parameter("amp", 0.5)
			_build_halifax(true)
		"sable":
			sky_mat.sky_top_color = Color(0.32, 0.5, 0.72)
			sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.82)
			sky_mat.ground_horizon_color = Color(0.72, 0.78, 0.82)
			sky_mat.ground_bottom_color = Color(0.2, 0.3, 0.35)
			sun.light_color = Color(1, 0.96, 0.88)
			sun.light_energy = 1.1
			sun.rotation_degrees = Vector3(-38, -30, 0)
			env.ambient_light_energy = 0.9
			env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
			env.fog_light_color = Color(0.7, 0.76, 0.8)
			water_mat.set_shader_parameter("deep", Color(0.06, 0.2, 0.3))
			water_mat.set_shader_parameter("crest", Color(0.3, 0.48, 0.56))
			water_mat.set_shader_parameter("amp", 1.4)
			_build_sable()
		_:
			sky_mat.sky_top_color = Color(0.5, 0.57, 0.63)
			sky_mat.sky_horizon_color = Color(0.8, 0.82, 0.83)
			sky_mat.ground_horizon_color = Color(0.8, 0.82, 0.83)
			sky_mat.ground_bottom_color = Color(0.3, 0.35, 0.38)
			sun.light_color = Color(1, 0.95, 0.88)
			sun.light_energy = 0.75
			sun.rotation_degrees = Vector3(-30, -150, 0)
			env.ambient_light_energy = 0.9
			env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
			env.fog_light_color = Color(0.8, 0.82, 0.84)
			water_mat.set_shader_parameter("deep", Color(0.1, 0.22, 0.27))
			water_mat.set_shader_parameter("crest", Color(0.36, 0.47, 0.5))
			water_mat.set_shader_parameter("amp", 0.6)
			_build_halifax(false)


func _land_dist(p: Vector2) -> float:
	# Signed distance to the shoreline: positive on land, negative in the water.
	var d := INF
	for seg in WorldScript.CHANNEL:
		d = minf(d, WorldScript._dist_to_segment(p, seg[0], seg[1]) - seg[2])
	d = minf(d, WorldScript.OPEN_SEA_Y - p.y)
	for isl in WorldScript.ISLANDS:
		var di: float = p.distance_to(isl[0]) - isl[1]
		if di < 0.0:
			d = -di
		elif d < 0.0:
			d = maxf(d, -di)
	return d


func _halifax_h(p: Vector2) -> float:
	var d := _land_dist(p)
	if d < 0.0:
		return maxf(-4.0 + d * 0.05, -40.0)
	var n := noise.get_noise_2dv(p)
	return 0.8 + 42.0 * (1.0 - exp(-d / 320.0)) + n * 16.0 * clampf(d / 160.0, 0.0, 1.0)


func _sable_dist(p: Vector2) -> float:
	var pts: PackedVector2Array = main.world.sable_points()
	var d := INF
	for i in pts.size() - 1:
		d = minf(d, WorldScript._dist_to_segment(p, pts[i], pts[i + 1]))
	return WorldScript.SABLE_R - d


func _sable_h(p: Vector2) -> float:
	var d := _sable_dist(p)
	if d < 0.0:
		return maxf(-3.0 + d * 0.04, -30.0)
	var n := noise.get_noise_2d(p.x * 4.0, p.y * 4.0)
	return 0.6 + 9.0 * smoothstep(0.0, WorldScript.SABLE_R, d) * (0.65 + 0.45 * n)


func _terrain(x0: float, y0: float, x1: float, y1: float, step: float, hfn: Callable, colfn: Callable) -> MeshInstance3D:
	var nx := int((x1 - x0) / step) + 1
	var ny := int((y1 - y0) / step) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in ny:
		for i in nx:
			var p := Vector2(x0 + i * step, y0 + j * step)
			var h: float = hfn.call(p)
			st.set_color(colfn.call(p, h))
			st.add_vertex(Vector3(p.x, h, p.y))
	for j in ny - 1:
		for i in nx - 1:
			var a := j * nx + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + nx)
			st.add_index(a + 1)
			st.add_index(a + nx + 1)
			st.add_index(a + nx)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Ships.vc_mat()
	return mi


func _halifax_col(p: Vector2, h: float) -> Color:
	var n := noise.get_noise_2d(p.x * 3.0, p.y * 3.0)
	if h < 2.2:
		return Color(0.42, 0.4, 0.36)                      # rocky shore
	if h < 4.0:
		return Color(0.5, 0.5, 0.36)
	var forest := Color(0.17, 0.27, 0.16).lerp(Color(0.3, 0.37, 0.22), clampf(n * 0.5 + 0.5, 0.0, 1.0))
	if h > 50.0:
		return forest.lerp(Color(0.45, 0.45, 0.42), clampf((h - 50.0) / 12.0, 0.0, 1.0))
	return forest


func _sable_col(p: Vector2, h: float) -> Color:
	var n := noise.get_noise_2d(p.x * 6.0, p.y * 6.0)
	if h < 2.0:
		return Color(0.8, 0.75, 0.6)
	if h > 4.5 and n > -0.15:
		return Color(0.48, 0.56, 0.3).lerp(Color(0.62, 0.64, 0.38), clampf(n, 0.0, 1.0))  # marram grass
	return Color(0.86, 0.8, 0.63)


func _build_halifax(wartime: bool) -> void:
	scenery.add_child(_terrain(-2700, -1900, 4300, 4300, 50.0, _halifax_h, _halifax_col))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1917
	# Halifax downtown (west shore) and Dartmouth (east shore)
	for spec in [[Rect2(-700, 1300, 1200, 1300), 110, 14.0, 60.0], [Rect2(900, 900, 900, 1400), 70, 10.0, 34.0]]:
		var r: Rect2 = spec[0]
		var placed := 0
		var tries := 0
		while placed < spec[1] and tries < 3000:
			tries += 1
			var p := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
			var d := _land_dist(p)
			if d < 22.0 or d > 520.0:
				continue
			var tall: float = rng.randf_range(spec[2], spec[3]) * clampf(1.4 - d / 600.0, 0.4, 1.4)
			if wartime:
				tall = minf(tall, 18.0)
			var fw := rng.randf_range(12, 30)
			var g := _halifax_h(p)
			var c: Color = [Color(0.62, 0.6, 0.56), Color(0.5, 0.52, 0.55), Color(0.72, 0.68, 0.6), Color(0.38, 0.42, 0.46)][rng.randi() % 4]
			if wartime:
				c = c.darkened(0.3)
			Ships.box(st, Vector3(p.x, g + tall / 2.0 - 2.0, p.y), Vector3(fw, tall, rng.randf_range(12, 30)), c, rng.randf_range(-0.3, 0.3))
			placed += 1
	# houses all around the harbour
	var houses := 0
	var tries := 0
	while houses < 520 and tries < 9000:
		tries += 1
		var p := Vector2(rng.randf_range(-2200, 3200), rng.randf_range(-1500, 3650))
		var d := _land_dist(p)
		if d < 25.0 or d > 700.0:
			continue
		var g := _halifax_h(p)
		var c: Color = [Color(0.85, 0.84, 0.8), Color(0.55, 0.62, 0.7), Color(0.7, 0.35, 0.28), Color(0.85, 0.75, 0.5), Color(0.4, 0.5, 0.45)][rng.randi() % 5]
		var yaw := rng.randf_range(0, PI)
		Ships.box(st, Vector3(p.x, g + 2.5, p.y), Vector3(9, 7, 12), c, yaw)
		Ships.box(st, Vector3(p.x, g + 6.6, p.y), Vector3(9.4, 1.2, 12.4), Color(0.22, 0.22, 0.24), yaw)
		houses += 1
	# dockyard cranes north of downtown
	for p in [Vector2(320, 1180), Vector2(380, 1330), Vector2(450, 1470)]:
		if _land_dist(p) < 0.0:
			continue
		var g := _halifax_h(p)
		var c := Color(0.75, 0.18, 0.12) if not wartime else Color(0.3, 0.28, 0.25)
		for o in [Vector2(-6, -6), Vector2(6, -6), Vector2(-6, 6), Vector2(6, 6)]:
			Ships.beam(st, Vector3(p.x + o.x, g, p.y + o.y), Vector3(p.x + o.x * 0.5, g + 42, p.y + o.y * 0.5), 1.4, c)
		Ships.beam(st, Vector3(p.x - 30, g + 44, p.y), Vector3(p.x + 70, g + 44, p.y), 3.0, c)
	if not wartime:
		_bridge(st, 0.32)
		_bridge(st, 0.62)
	# Chebucto Head lighthouse
	var lp := Vector2(80, 3560)
	var lg := _halifax_h(lp)
	Ships.cyl(st, Vector3(lp.x, lg + 10, lp.y), 4.0, 20.0, Color(0.95, 0.95, 0.93))
	Ships.cyl(st, Vector3(lp.x, lg + 22, lp.y), 4.4, 4.0, Color(0.75, 0.12, 0.1))
	var mi := MeshInstance3D.new()
	mi.mesh = Ships._finish(st)
	mi.material_override = Ships.vc_mat()
	scenery.add_child(mi)
	var lamp := Ships.buoy(Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 0.95, 0.7))
	lamp.get_child(0).visible = false
	lamp.position = Vector3(lp.x, lg + 16, lp.y)
	scenery.add_child(lamp)

	if wartime:
		_build_net()
	else:
		sea_buoy = Ships.buoy(Color(0.8, 0.12, 0.1), Color(0.95, 0.95, 0.93), Color(1, 0.95, 0.8))
		sea_buoy.position = Vector3(main.SEA_BUOY.x, 0, main.SEA_BUOY.y)
		scenery.add_child(sea_buoy)
		echo_buoy = Ships.buoy(Color(0.95, 0.75, 0.1), Color(0.15, 0.15, 0.15), Color(1, 0.85, 0.3))
		echo_buoy.position = Vector3(main.POINT_ECHO.x + 40, 0, main.POINT_ECHO.y)
		scenery.add_child(echo_buoy)
	var names := [
		[Vector2(-200, -60), _t("BEDFORD BASIN", "BASSIN DE BEDFORD")], [Vector2(560, 1040), _t("THE NARROWS", "LE GOULET")],
		[Vector2(-150, 1900), "HALIFAX"], [Vector2(1300, 1500), "DARTMOUTH"],
		[Vector2(1560, 2980), _t("McNABS ISLAND", "ÎLE McNABS")], [Vector2(1000, 2060), _t("George's Island", "Île George")],
		[Vector2(330, 2640), "Point Pleasant"], [Vector2(80, 3500), _t("Chebucto Head", "Cap Chebucto")],
	]
	for n in names:
		_place_label(n[0], n[1], _halifax_h(n[0]) + 70.0)
	if not wartime:
		_place_label(main.POINT_ECHO + Vector2(40, 0), _t("POINT ECHO", "POINT ÉCHO"), 28.0, Color(1, 0.85, 0.4))
		_place_label(main.SEA_BUOY, _t("SEA BUOY", "BOUÉE DE MER"), 28.0, Color(1, 0.85, 0.4))


func _bridge(st: SurfaceTool, f: float) -> void:
	var a: Vector2 = WorldScript.NARROWS_A
	var b: Vector2 = WorldScript.NARROWS_B
	var p := a.lerp(b, f)
	var n := (b - a).normalized().orthogonal()
	var deck := 46.0
	var c := Color(0.42, 0.45, 0.48)
	var e0 := p - n * 330.0
	var e1 := p + n * 330.0
	var g0 := _halifax_h(e0)
	var g1 := _halifax_h(e1)
	Ships.beam(st, Vector3(e0.x, g0 + 4, e0.y), Vector3(p.x - n.x * 200, deck, p.y - n.y * 200), 14.0, c)
	Ships.beam(st, Vector3(p.x - n.x * 200, deck, p.y - n.y * 200), Vector3(p.x + n.x * 200, deck, p.y + n.y * 200), 14.0, c)
	Ships.beam(st, Vector3(p.x + n.x * 200, deck, p.y + n.y * 200), Vector3(e1.x, g1 + 4, e1.y), 14.0, c)
	for s in [-1.0, 1.0]:
		var tp: Vector2 = p + n * 120.0 * s
		var top := Vector3(tp.x, deck + 55, tp.y)
		for side in [-6.0, 6.0]:
			var off: Vector2 = (b - a).normalized() * side
			Ships.beam(st, Vector3(tp.x + off.x, -5, tp.y + off.y), Vector3(tp.x + off.x, deck + 55, tp.y + off.y), 3.5, Color(0.55, 0.58, 0.6))
		# main cables
		for k in 6:
			var q0: Vector2 = p + n * (120.0 * s + 40.0 * s * (k - 2.5) / 2.5 - 40.0 * s)
			Ships.beam(st, top, Vector3(q0.x, deck + 1, q0.y), 0.6, Color(0.7, 0.72, 0.74))
	Ships.beam(st, Vector3(p.x - n.x * 120, deck + 55, p.y - n.y * 120), Vector3(p.x + n.x * 120, deck + 55, p.y + n.y * 120), 0.8, Color(0.7, 0.72, 0.74))


func _build_net() -> void:
	var g: Array = main.world.gate_points()
	var floats := SurfaceTool.new()
	floats.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pair in [[g[0], g[1]], [g[2], g[3]]]:
		for i in 14:
			var q: Vector2 = pair[0].lerp(pair[1], i / 13.0)
			Ships.cyl(floats, Vector3(q.x, 0.6, q.y), 1.6, 2.0, Color(0.55, 0.45, 0.25), 8)
	var mi := MeshInstance3D.new()
	mi.mesh = Ships._finish(floats)
	mi.material_override = Ships.vc_mat()
	scenery.add_child(mi)
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 8:
		var q: Vector2 = g[1].lerp(g[2], i / 7.0)
		Ships.cyl(gst, Vector3(q.x, 0.6, q.y), 1.6, 2.0, Color(0.85, 0.7, 0.25), 8)
	gate_closed = MeshInstance3D.new()
	gate_closed.mesh = Ships._finish(gst)
	gate_closed.material_override = Ships.vc_mat()
	scenery.add_child(gate_closed)
	for p in [g[1], g[2]]:
		var gb := Ships.buoy(Color(0.3, 0.3, 0.3), Color(0.5, 0.45, 0.3), Color(0.4, 0.7, 1.0))
		gb.position = Vector3(p.x, 0, p.y)
		scenery.add_child(gb)
	_place_label(g[1] + Vector2(0, -40), _t("A/S GATE", "PORTE ANTI-SOUS-MARINE"), 30.0, Color(0.95, 0.8, 0.45))
	var names := [[Vector2(-200, -60), _t("BEDFORD BASIN", "BASSIN DE BEDFORD")], [Vector2(-150, 1900), "HALIFAX 1942"]]
	for n in names:
		_place_label(n[0], n[1], 80.0)


func _build_sable() -> void:
	var c: Vector2 = WorldScript.SABLE_CENTRE
	var half := WorldScript.SABLE_LEN * 0.5 + 150.0
	scenery.add_child(_terrain(c.x - half, c.y - 520, c.x + half, c.y + 180, 22.0, _sable_h, _sable_col))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Sable Island station
	var sp := c + Vector2(-80, -250)
	var g := _sable_h(sp)
	Ships.box(st, Vector3(sp.x, g + 3, sp.y), Vector3(16, 7, 10), Color(0.92, 0.92, 0.9))
	Ships.box(st, Vector3(sp.x, g + 7, sp.y), Vector3(16.5, 1.2, 10.5), Color(0.7, 0.15, 0.12))
	Ships.beam(st, Vector3(sp.x + 14, g, sp.y), Vector3(sp.x + 14, g + 30, sp.y), 0.8, Color(0.85, 0.85, 0.85))
	# wild horses
	var rng := RandomNumberGenerator.new()
	rng.seed = 1960
	var pts: PackedVector2Array = main.world.sable_points()
	for i in 14:
		var q := pts[rng.randi_range(5, pts.size() - 6)] + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
		var h := _sable_h(q)
		if h < 1.0:
			continue
		var yaw := rng.randf_range(0, TAU)
		var hc: Color = [Color(0.35, 0.22, 0.13), Color(0.2, 0.13, 0.08), Color(0.5, 0.36, 0.22)][rng.randi() % 3]
		var bs := Basis(Vector3.UP, yaw)
		Ships.obox(st, Vector3(q.x, h + 1.5, q.y), Vector3(0.9, 0.9, 2.2), hc, bs)
		Ships.obox(st, Vector3(q.x, h + 2.2, q.y) + bs * Vector3(0, 0, -1.3), Vector3(0.5, 1.2, 0.6), hc, bs)
		for o in [Vector3(-0.3, 0, -0.8), Vector3(0.3, 0, -0.8), Vector3(-0.3, 0, 0.8), Vector3(0.3, 0, 0.8)]:
			Ships.obox(st, Vector3(q.x, h + 0.55, q.y) + bs * o, Vector3(0.2, 1.1, 0.2), hc.darkened(0.3), bs)
	var mi := MeshInstance3D.new()
	mi.mesh = Ships._finish(st)
	mi.material_override = Ships.vc_mat()
	scenery.add_child(mi)
	_place_label(c + Vector2(-60, -420), _t("SABLE ISLAND", "ÎLE DE SABLE"), 70.0)
	_place_label(Vector2(4300, -1500), _t("THE GULLY (marine protected area)", "LE GULLY (zone de protection marine)"), 50.0)
	_place_label(main.M2_RENDEZVOUS, _t("RENDEZVOUS", "RENDEZ-VOUS"), 30.0, Color(1, 0.85, 0.4))


func _place_label(p: Vector2, text: String, h: float, col := Color(1, 1, 1)) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 64
	l.outline_size = 14
	l.pixel_size = 0.25
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.7)
	l.position = Vector3(p.x, h, p.y)
	scenery.add_child(l)


func _t(en: String, fr: String) -> String:
	return fr if main.lang == "fr" else en


# ======================================================================
# Per-frame sync
# ======================================================================

func _drop(v) -> void:
	if models.has(v):
		var m = models[v]
		if is_instance_valid(m):
			m.queue_free()
		models.erase(v)
	if labels.has(v):
		var l = labels[v]
		if is_instance_valid(l):
			l.queue_free()
		labels.erase(v)


func _model_for(v) -> Node3D:
	if models.has(v):
		return models[v]
	var m := Ships.build(v.kind, hash(v.vname) + models.size() * 31 + int(v.position.x), era)
	add_child(m)
	models[v] = m
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.no_depth_test = true
	l.font_size = 36
	l.outline_size = 10
	l.pixel_size = 0.0011
	l.outline_modulate = Color(0, 0, 0, 0.8)
	add_child(l)
	labels[v] = l
	return m


func _process(delta: float) -> void:
	if main == null:
		return
	t += delta
	if era != main.era or scenery == null or built_lang != main.lang:
		built_lang = main.lang
		set_era(main.era)
	for v in models.keys():
		if not is_instance_valid(v) or not main.vessels.has(v):
			_drop(v)
	var player = main.player if is_instance_valid(main.player) else null
	for v in main.vessels:
		if not is_instance_valid(v):
			continue
		var m := _model_for(v)
		var ph := float(hash(v.vname) % 100)
		var size_k: float = clampf(30.0 / v.length(), 0.25, 1.6)
		var amp: float = 1.4 if era == "sable" else 0.6
		var y := sin(t * 0.9 + ph) * 0.35 * amp * size_k
		var roll := sin(t * 0.7 + ph) * 0.035 * amp * size_k
		if v.kind == "helo":
			var d: float = v.position.distance_to(player.position) if player else 100.0
			y = clampf(d * 0.45, 8.5, 60.0)
			roll = 0.0
			var rotor = m.get_meta("rotor")
			rotor.rotation.y += delta * 25.0
			var tr = m.get_meta("tail_rotor")
			tr.rotation.x += delta * 40.0
		elif v == player:
			roll -= v.rudder * v.speed * 0.0016
		m.position = Vector3(v.position.x, y, v.position.y)
		m.rotation = Vector3(sin(t * 0.55 + ph) * 0.012 * amp * size_k, -deg_to_rad(v.heading), roll)
		if m.has_meta("radar"):
			var rd = m.get_meta("radar")
			rd.rotation.y += delta * 3.0
		if m.has_meta("lights"):
			var lt = m.get_meta("lights")
			lt.visible = v.lit and not v.darkened
		_update_label(v, m, player)
	_update_markers(player)
	_update_wake()
	_update_camera(delta, player)
	_update_fog(player)
	water.position = Vector3(snappedf(cam.global_position.x, 30.0), 0, snappedf(cam.global_position.z, 30.0))


func _update_label(v, m: Node3D, player) -> void:
	var l: Label3D = labels[v]
	var show := false
	var txt: String = v.vname
	if player and v != player and v.vname != "":
		var near: bool = v.position.distance_to(player.position) < main.VISUAL_RANGE * (1.6 if era == "sable" else 1.0)
		show = near or v == main.port_royal or (era == "sable" and v.identified)
		if era == "sable" and v.has_meta("id_text") and not v.identified:
			txt = _t("unidentified", "non identifié")
	l.visible = show and main.phase == "sail"
	l.text = txt
	l.modulate = Color(1, 0.55, 0.45) if (v.needs_report and not v.reported) else Color(1, 1, 1)
	l.position = m.position + Vector3(0, v.length() * 0.35 + 14.0, 0)


func _update_markers(player) -> void:
	var tgt = main._current_target() if player and main.phase == "sail" else null
	beacon.visible = tgt != null
	if tgt != null:
		beacon.position = Vector3(tgt.x, 0, tgt.y)
		var c := Color(0.95, 0.2, 0.15, 0.35) if era != "1942" else Color(1, 0.8, 0.4, 0.35)
		var bm = beacon.get_meta("mat")
		bm.albedo_color = c
	if gate_closed:
		gate_closed.visible = not main.world.gate_open
	var flashing := false
	for v in main.vessels:
		if is_instance_valid(v) and v.distress:
			distress_light.position = Vector3(v.position.x, 18.0 + fmod(t * 6.0, 30.0), v.position.y)
			flashing = fmod(t, 2.5) < 1.6
	distress_light.visible = flashing
	for b in [sea_buoy, echo_buoy]:
		if b:
			var bl = b.get_meta("light")
			bl.visible = fmod(t, 4.0) < 1.0
			b.position.y = sin(t * 1.3) * 0.4


func _update_wake() -> void:
	if DisplayServer.get_name() == "headless":
		return
	wake_mesh.clear_surfaces()
	var any := false
	for v in main.vessels:
		if is_instance_valid(v) and (v.trail.size() > 1 or absf(v.speed) > 3.0) and v.kind != "helo":
			any = true
			break
	if not any:
		return
	wake_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in main.vessels:
		if not is_instance_valid(v) or v.kind == "helo":
			continue
		var w: float = v.length() * 0.05
		var pts: Array = v.trail.duplicate()
		pts.append([v.position - v.dir() * v.length() * 0.5, v.t])
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1][0]
			var b: Vector2 = pts[i][0]
			if a.distance_to(b) < 0.5:
				continue
			var n := (b - a).normalized().orthogonal()
			var age_a: float = v.t - pts[i - 1][1]
			var age_b: float = v.t - pts[i][1]
			var wa := w * (1.0 + age_a * 0.6)
			var wb := w * (1.0 + age_b * 0.6)
			var ca := Color(1, 1, 1, clampf(1.0 - age_a / 7.0, 0.0, 1.0) * 0.22)
			var cb := Color(1, 1, 1, clampf(1.0 - age_b / 7.0, 0.0, 1.0) * 0.22)
			_wv(a - n * wa, ca); _wv(a + n * wa, ca); _wv(b + n * wb, cb)
			_wv(a - n * wa, ca); _wv(b + n * wb, cb); _wv(b - n * wb, cb)
		# bow wave
		var s: float = clampf(absf(v.speed) / 18.0, 0.0, 1.0)
		if s > 0.1:
			var f: Vector2 = v.dir()
			var r := f.orthogonal()
			var bow: Vector2 = v.position + f * v.length() * 0.5
			var c := Color(1, 1, 1, 0.6 * s)
			var c0 := Color(1, 1, 1, 0.0)
			for side in [-1.0, 1.0]:
				var tip: Vector2 = bow - f * v.length() * 0.4 + r * side * (v.length() * 0.09 + 7.0 * s)
				var inner: Vector2 = bow - f * v.length() * 0.3 + r * side * v.length() * 0.06
				_wv(bow, c); _wv(tip, c0); _wv(inner, c)
	wake_mesh.surface_end()


func _wv(p: Vector2, c: Color) -> void:
	wake_mesh.surface_set_color(c)
	wake_mesh.surface_add_vertex(Vector3(p.x, 0.9, p.y))


# ======================================================================
# Camera
# ======================================================================

static func fwd3(heading_deg: float) -> Vector3:
	var r := deg_to_rad(heading_deg)
	return Vector3(sin(r), 0, -cos(r))


func cycle_view() -> void:
	cam_mode = (cam_mode + 1) % 3
	orbit = 0.0
	pitch = 0.0


func view_name() -> String:
	return [_t("Chase", "Poursuite"), _t("Bridge", "Passerelle"), _t("Tactical", "Tactique")][cam_mode]


func _unhandled_input(event: InputEvent) -> void:
	var rel := Vector2.ZERO
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT or event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		rel = event.relative
	elif event is InputEventScreenDrag:
		rel = event.relative
	if rel != Vector2.ZERO:
		orbit = wrapf(orbit + rel.x * 0.35, -180.0, 180.0)
		pitch = clampf(pitch - rel.y * 0.25, -25.0, 40.0)
		drag_t = 0.0
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		cycle_view()


func _update_camera(delta: float, player) -> void:
	drag_t += delta
	if player == null:
		# title screen: slow flight around the harbour or the island
		title_t += delta
		var centre := Vector3(500, 0, 2300) if era != "sable" else Vector3(WorldScript.SABLE_CENTRE.x, 0, WorldScript.SABLE_CENTRE.y)
		var a := title_t * 0.05
		cam.position = centre + Vector3(sin(a) * 650.0, 140.0, cos(a) * 650.0)
		cam.look_at(centre + Vector3(0, 10, 0), Vector3.UP)
		return
	if cam_mode == 0 and drag_t > 3.0:
		orbit = lerpf(orbit, 0.0, 1.0 - exp(-1.5 * delta))
		pitch = lerpf(pitch, 0.0, 1.0 - exp(-1.5 * delta))
	var p := Vector3(player.position.x, 0, player.position.y)
	var hdg: float = player.heading
	var f := fwd3(hdg)
	var m: Node3D = models.get(player)
	var deck: float = m.get_meta("deck_h") if m else 6.0
	match cam_mode:
		1:
			var eye: Vector3 = p + f * (player.length() * 0.185) + Vector3.UP * (deck + 9.0)
			cam.position = eye
			var look := fwd3(hdg + orbit)
			cam.look_at(eye + look * 100.0 + Vector3.UP * (pitch - 3.0), Vector3.UP)
		2:
			var h := 650.0 / zoom
			var want := p + Vector3(0, h, h * 0.35)
			cam.position = cam.position.lerp(want, 1.0 - exp(-5.0 * delta))
			cam.look_at(p, Vector3.UP)
		_:
			var dist := clampf(135.0 / zoom, 45.0, 1100.0)
			var back := -fwd3(hdg + orbit)
			var want := p + back * dist + Vector3.UP * (dist * 0.24 + 10.0 + pitch * dist / 60.0)
			cam.position = cam.position.lerp(want, 1.0 - exp(-4.0 * delta))
			if cam.position.distance_to(want) > dist * 3.0:
				cam.position = want
			cam.look_at(p + f * 25.0 + Vector3.UP * 8.0, Vector3.UP)


func _update_fog(player) -> void:
	var begin := 150.0
	var end := 900.0
	match era:
		"1942":
			begin = 80.0
			end = 750.0
		"sable":
			begin = 500.0
			end = 4500.0
		_:
			if player:
				var at_sea: float = clampf((player.position.y - 3400.0) / 800.0, 0.0, 1.0)
				begin = lerpf(120.0, 250.0, at_sea)
				end = lerpf(850.0, 1500.0, at_sea)
	if player == null:
		begin *= 2.0
		end *= 2.5
	if cam_mode == 2 and player:
		begin += 650.0 / zoom
		end += 650.0 / zoom
	env.set("fog_depth_begin", begin)
	env.set("fog_depth_end", end)
	env.set("fog_depth_curve", 1.2)
