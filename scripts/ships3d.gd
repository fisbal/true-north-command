extends RefCounted
## Low-poly 3D models built in code: ships, boats, the helicopter, buoys.
## Every model faces -Z (bow forward) with the waterline at y = 0.
## Scale: one world unit is about 1.6 m (the frigate is 84 units, 134 m).

static var _vc_mat: StandardMaterial3D


static func vc_mat() -> StandardMaterial3D:
	if _vc_mat == null:
		_vc_mat = StandardMaterial3D.new()
		_vc_mat.vertex_color_use_as_albedo = true
		_vc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_vc_mat.roughness = 0.75
	return _vc_mat


static func glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.disable_fog = true
	return m


# ---------------------------------------------------------------- primitives

static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	tri(st, a, b, c, col)
	tri(st, a, c, d, col)


static func obox(st: SurfaceTool, center: Vector3, size: Vector3, col: Color, basis := Basis()) -> void:
	var h := size / 2.0
	var p: Array[Vector3] = []
	for i in 8:
		var o := Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
		p.append(center + basis * o)
	var top := col.lightened(0.08)
	quad(st, p[0], p[2], p[6], p[4], col)
	quad(st, p[1], p[5], p[7], p[3], col)
	quad(st, p[0], p[4], p[5], p[1], col.darkened(0.2))
	quad(st, p[2], p[3], p[7], p[6], top)
	quad(st, p[0], p[1], p[3], p[2], col)
	quad(st, p[4], p[6], p[7], p[5], col)


static func box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color, yaw := 0.0) -> void:
	obox(st, center, size, col, Basis(Vector3.UP, yaw))


static func beam(st: SurfaceTool, a: Vector3, b: Vector3, t: float, col: Color) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	var up := Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT
	var bs := Basis.looking_at(d, up)
	obox(st, (a + b) / 2.0, Vector3(t, t, d.length()), col, bs)


static func cyl(st: SurfaceTool, center: Vector3, r: float, h: float, col: Color, seg := 10) -> void:
	var y0 := center.y - h / 2.0
	var y1 := center.y + h / 2.0
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(center.x + cos(a0) * r, 0, center.z + sin(a0) * r)
		var p1 := Vector3(center.x + cos(a1) * r, 0, center.z + sin(a1) * r)
		quad(st, Vector3(p0.x, y0, p0.z), Vector3(p1.x, y0, p1.z), Vector3(p1.x, y1, p1.z), Vector3(p0.x, y1, p0.z), col)
		tri(st, Vector3(center.x, y1, center.z), Vector3(p0.x, y1, p0.z), Vector3(p1.x, y1, p1.z), col.lightened(0.08))


static func hull(st: SurfaceTool, l: float, b: float, fb: float, dr: float, bow_frac: float, sheer: float,
		stern_ratio: float, ctop: Color, cbottom: Color, cdeck: Color) -> void:
	# Stations from the transom (u = 0) to the stem (u = 1); each station is a U-shaped section.
	var n := 16
	var rings: Array = []
	var boot := Color(0.08, 0.08, 0.09)
	for s in n:
		var u := float(s) / (n - 1)
		var z := l * 0.5 - u * l
		var w := b * 0.5
		var a := 0.0
		if u > 1.0 - bow_frac:
			a = (u - (1.0 - bow_frac)) / bow_frac
			w *= pow(maxf(cos(a * PI * 0.5), 0.0), 0.75)
		elif u < 0.12:
			w *= lerpf(stern_ratio, 1.0, u / 0.12)
		var deck := fb + sheer * a * a
		var keel := -dr * (1.0 - 0.75 * a * a)
		var rake := a * a * l * 0.05
		var pts: Array[Vector3] = [
			Vector3(0, keel, z), Vector3(w * 0.6, keel * 0.8, z), Vector3(w * 0.95, keel * 0.25, z),
			Vector3(w, 0.7, z - rake * 0.2), Vector3(w * 1.03, deck, z - rake)]
		rings.append(pts)
	var cols := [cbottom, cbottom, boot, ctop]
	for s in n - 1:
		var r0: Array = rings[s]
		var r1: Array = rings[s + 1]
		for k in 4:
			var a0: Vector3 = r0[k]
			var a1: Vector3 = r0[k + 1]
			var b0: Vector3 = r1[k]
			var b1: Vector3 = r1[k + 1]
			quad(st, a0, b0, b1, a1, cols[k])
			quad(st, _mx(a0), _mx(a1), _mx(b1), _mx(b0), cols[k])
		var d0: Vector3 = r0[4]
		var d1: Vector3 = r1[4]
		quad(st, _mx(d0), d0, d1, _mx(d1), cdeck)
	var t: Array = rings[0]
	for k in 4:
		quad(st, t[k], t[k + 1], _mx(t[k + 1]), _mx(t[k]), ctop.darkened(0.1) if k == 3 else cbottom)


static func _mx(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


static func _finish(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()


static func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


# ---------------------------------------------------------------- models

const GREY := Color(0.56, 0.6, 0.62)
const LIGHT_GREY := Color(0.68, 0.71, 0.73)
const DARK := Color(0.16, 0.17, 0.19)
const GLASS := Color(0.07, 0.1, 0.13)
const ANTIFOUL := Color(0.45, 0.14, 0.11)
const WHITE := Color(0.9, 0.9, 0.87)


## Builds a model. Returns a Node3D; animated parts are stored as metadata:
## "radar" (spins), "rotor" and "tail_rotor" (helicopter), "lights" (navigation lights), "deck_h".
static func build(kind: String, seed_val: int, era := "modern") -> Node3D:
	var root := Node3D.new()
	var st := _new_st()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var l := 30.0
	var bw := 8.0
	var fb := 3.0
	var mast_h := 12.0
	match kind:
		"frigate":
			l = 84.0; bw = 12.0; fb = 6.0; mast_h = 35.0
			_frigate(st, root)
		"corvette":
			l = 60.0; bw = 10.0; fb = 5.0; mast_h = 25.0
			_corvette(st)
		"merchant":
			l = 104.0; bw = 17.0; fb = 8.0; mast_h = 30.0
			_merchant(st, rng, era)
		"ferry":
			l = 34.0; bw = 12.0; fb = 3.5; mast_h = 12.0
			_ferry(st)
		"fishing":
			l = 28.0; bw = 8.0; fb = 3.0; mast_h = 15.0
			_fishing(st, rng)
		"unlit":
			l = 18.0; bw = 5.0; fb = 1.6; mast_h = 3.0
			_skiff(st)
		"trawler":
			l = 38.0; bw = 9.5; fb = 4.0; mast_h = 21.0
			_trawler(st)
		"rhib":
			l = 11.0; bw = 3.8; fb = 1.3; mast_h = 3.5
			_rhib(st)
		"helo":
			_helo(st, root)
	var mi := MeshInstance3D.new()
	mi.mesh = _finish(st)
	mi.material_override = vc_mat()
	root.add_child(mi)
	root.set_meta("deck_h", fb)
	if kind != "helo":
		root.set_meta("lights", _nav_lights(root, l, bw, fb, mast_h))
	return root


static func _nav_lights(root: Node3D, l: float, bw: float, fb: float, mast_h: float) -> Node3D:
	var lights := Node3D.new()
	root.add_child(lights)
	var r := 0.35 + l * 0.006
	for spec in [[Vector3(-bw * 0.55, fb + 2.0, -l * 0.12), Color(1, 0.15, 0.1)],
			[Vector3(bw * 0.55, fb + 2.0, -l * 0.12), Color(0.2, 1, 0.35)],
			[Vector3(0, mast_h + 0.5, -l * 0.08), Color(1, 1, 0.92)],
			[Vector3(0, fb + 1.2, l * 0.5), Color(1, 1, 0.92)]]:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 8
		sm.rings = 4
		m.mesh = sm
		m.material_override = glow_mat(spec[1])
		m.position = spec[0]
		lights.add_child(m)
	return lights


static func _radar(root: Node3D, at: Vector3, w: float) -> void:
	var st := _new_st()
	box(st, Vector3.ZERO, Vector3(w, 0.6, 0.8), DARK)
	box(st, Vector3(0, -0.6, 0), Vector3(0.6, 0.8, 0.6), DARK)
	var mi := MeshInstance3D.new()
	mi.mesh = _finish(st)
	mi.material_override = vc_mat()
	mi.position = at
	root.add_child(mi)
	root.set_meta("radar", mi)


static func _frigate(st: SurfaceTool, root: Node3D) -> void:
	# Halifax-class patrol frigate (fictional HMCS Laurentian)
	hull(st, 84, 12, 6, 4.5, 0.3, 2.0, 0.85, GREY, ANTIFOUL, Color(0.34, 0.36, 0.37))
	box(st, Vector3(0, 9, -4), Vector3(9.5, 6, 22), LIGHT_GREY)          # forward superstructure
	box(st, Vector3(0, 14.2, -11), Vector3(8.5, 4.4, 7), LIGHT_GREY)     # bridge
	box(st, Vector3(0, 14.6, -14.55), Vector3(8.3, 1.3, 0.2), GLASS)     # bridge windows
	box(st, Vector3(0, 13.0, -12), Vector3(13, 0.6, 2.6), LIGHT_GREY)    # bridge wings
	beam(st, Vector3(0, 16, -6), Vector3(0, 35, -6), 1.3, LIGHT_GREY)    # mast
	box(st, Vector3(0, 29, -6), Vector3(8, 0.4, 0.4), LIGHT_GREY)        # yard
	box(st, Vector3(0, 24, -6), Vector3(2.6, 1.4, 2.6), LIGHT_GREY)      # platform
	box(st, Vector3(0, 16, 5), Vector3(5, 8, 6), GREY)                    # funnel
	box(st, Vector3(0, 20.3, 5), Vector3(5.2, 0.6, 6.2), DARK)
	box(st, Vector3(0, 9.2, 14), Vector3(9.5, 6.4, 13), LIGHT_GREY)      # hangar
	box(st, Vector3(0, 9.2, 20.55), Vector3(8, 5.4, 0.15), Color(0.45, 0.48, 0.5))  # hangar door
	box(st, Vector3(0, 6.06, 31), Vector3(0.5, 0.06, 18), WHITE)          # flight deck markings
	box(st, Vector3(0, 6.06, 31), Vector3(9, 0.06, 0.5), WHITE)
	box(st, Vector3(0, 7.3, -25), Vector3(3.6, 2.6, 4.2), LIGHT_GREY)    # 57 mm gun
	beam(st, Vector3(0, 7.8, -27), Vector3(0, 8.3, -32.5), 0.5, DARK)
	box(st, Vector3(0, 6.5, -19), Vector3(5, 1, 3), DARK)                 # missile cells
	for sx in [-1.0, 1.0]:
		box(st, Vector3(sx * 5.3, 8, 3), Vector3(1.8, 1.6, 6), DARK)      # boats in davits
		box(st, Vector3(sx * 3.2, 7.6, 22.5), Vector3(1.5, 1.6, 4), GREY) # torpedo / harpoon
	_radar(root, Vector3(0, 35.8, -6), 7.0)
	for side in [-1.0, 1.0]:
		var lb := Label3D.new()
		lb.text = "344"
		lb.font_size = 72
		lb.pixel_size = 0.045
		lb.outline_size = 0
		lb.modulate = Color(0.95, 0.95, 0.95)
		lb.position = Vector3(side * 6.25, 3.8, -27)
		lb.rotation.y = side * PI / 2.0
		lb.double_sided = false
		root.add_child(lb)


static func _corvette(st: SurfaceTool) -> void:
	# Flower-class corvette, 1942, in Western Approaches camouflage
	var pale := Color(0.8, 0.84, 0.85)
	hull(st, 60, 10, 5, 4, 0.32, 2.8, 0.8, pale, ANTIFOUL, Color(0.4, 0.38, 0.34))
	for p in [[-12.0, 7.0, Color(0.38, 0.55, 0.62)], [8.0, 9.0, Color(0.5, 0.66, 0.6)], [-1.0, 4.0, Color(0.3, 0.45, 0.55)]]:
		for sx in [-1.0, 1.0]:
			box(st, Vector3(sx * 5.06, 2.6, p[0]), Vector3(0.12, 3.4, p[1]), p[2])
	box(st, Vector3(0, 8, -7), Vector3(7, 6, 8), pale)                     # bridge
	box(st, Vector3(0, 9.6, -11.05), Vector3(6.6, 1.1, 0.2), GLASS)
	box(st, Vector3(0, 11.3, -7), Vector3(7.6, 0.6, 8.6), Color(0.6, 0.62, 0.6))
	beam(st, Vector3(0, 11, -10), Vector3(0, 25, -11.5), 0.8, pale)       # mast
	box(st, Vector3(0, 19, -11), Vector3(1.8, 1.6, 1.8), pale)            # crow's nest
	cyl(st, Vector3(0, 10, 3), 1.9, 10, Color(0.62, 0.68, 0.7))           # funnel
	cyl(st, Vector3(0, 15.2, 3), 1.95, 0.6, DARK)
	box(st, Vector3(0, 7.4, -21), Vector3(2.6, 2.2, 2.4), Color(0.6, 0.64, 0.66))  # 4-inch gun
	beam(st, Vector3(0, 7.6, -22), Vector3(0, 7.9, -26), 0.45, DARK)
	box(st, Vector3(0, 7, 15), Vector3(2.4, 1.6, 2.4), Color(0.6, 0.64, 0.66))     # pom-pom
	for sx in [-1.0, 1.0]:
		beam(st, Vector3(sx * 2, 5.6, 23), Vector3(sx * 2, 5.3, 29.5), 0.5, DARK)  # depth-charge rails
		for z in [24.0, 26.0, 28.0]:
			cyl(st, Vector3(sx * 2, 6.2, z), 0.6, 1.0, DARK, 8)
		box(st, Vector3(sx * 4.2, 7, 7), Vector3(1.4, 1.2, 5), Color(0.55, 0.5, 0.42))  # whaler


static func _merchant(st: SurfaceTool, rng: RandomNumberGenerator, era: String) -> void:
	var hulls := [Color(0.13, 0.2, 0.32), Color(0.45, 0.13, 0.11), Color(0.12, 0.28, 0.2), Color(0.2, 0.2, 0.22)]
	var hc: Color = hulls[rng.randi() % hulls.size()]
	if era == "1942":
		hc = Color(0.28, 0.3, 0.31)
	hull(st, 104, 17, 8, 6, 0.22, 1.5, 0.9, hc, ANTIFOUL, Color(0.36, 0.27, 0.22))
	if era == "1942":
		# wartime cargo ship: hatches, derricks, midships bridge, tall funnel
		for z in [-36.0, -22.0, 18.0, 32.0]:
			box(st, Vector3(0, 9, z), Vector3(9, 2, 9), Color(0.3, 0.28, 0.24))
			beam(st, Vector3(0, 8, z + 6), Vector3(0, 26, z + 6), 0.8, Color(0.4, 0.38, 0.34))
			beam(st, Vector3(0, 12, z + 6), Vector3(0, 20, z - 2), 0.4, Color(0.4, 0.38, 0.34))
		box(st, Vector3(0, 13, -4), Vector3(14, 10, 14), Color(0.5, 0.5, 0.48))
		box(st, Vector3(0, 16, -11.1), Vector3(13, 1.2, 0.2), GLASS)
		cyl(st, Vector3(0, 22, 4), 2.2, 10, Color(0.15, 0.15, 0.15))
		return
	var cc := [Color(0.18, 0.45, 0.72), Color(0.7, 0.2, 0.15), Color(0.86, 0.5, 0.14), Color(0.2, 0.5, 0.3),
		Color(0.6, 0.6, 0.6), Color(0.85, 0.85, 0.8), Color(0.55, 0.15, 0.4)]
	var z := -38.0
	while z < 20.0:
		var tiers := rng.randi_range(1, 3)
		for x in [-5.6, 0.0, 5.6]:
			for t in tiers:
				box(st, Vector3(x, 9.4 + t * 2.8, z), Vector3(5.2, 2.7, 6.1), cc[rng.randi() % cc.size()])
		z += 6.5
	box(st, Vector3(0, 16, 33), Vector3(15, 16, 9), WHITE)                  # accommodation
	for y in [12.0, 16.0, 20.0]:
		box(st, Vector3(0, y, 28.45), Vector3(14, 0.9, 0.15), GLASS)
	box(st, Vector3(0, 23.6, 29.5), Vector3(19, 0.6, 3), WHITE)            # bridge wings
	box(st, Vector3(0, 27, 39), Vector3(5, 7, 5), hc)                       # funnel
	box(st, Vector3(0, 28, 39), Vector3(5.1, 1.2, 5.1), WHITE)
	beam(st, Vector3(0, 8, -46), Vector3(0, 20, -46), 0.6, WHITE)


static func _ferry(st: SurfaceTool) -> void:
	hull(st, 34, 12, 3.5, 2.5, 0.2, 0.5, 0.95, WHITE, Color(0.1, 0.25, 0.45), Color(0.4, 0.42, 0.44))
	box(st, Vector3(0, 6, 0), Vector3(11, 5, 26), WHITE)
	box(st, Vector3(0, 6.4, 0), Vector3(11.1, 1.5, 24), GLASS)
	box(st, Vector3(0, 9.7, -4), Vector3(6, 2.4, 4), Color(0.12, 0.3, 0.55))
	for sx in [-1.0, 1.0]:
		box(st, Vector3(sx * 6.05, 2.4, 0), Vector3(0.1, 1.0, 28), Color(0.12, 0.3, 0.55))


static func _fishing(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var hulls := [Color(0.7, 0.15, 0.12), Color(0.15, 0.3, 0.6), Color(0.13, 0.45, 0.3), Color(0.85, 0.7, 0.2)]
	var hc: Color = hulls[rng.randi() % hulls.size()]
	hull(st, 28, 8, 3, 2.5, 0.3, 1.6, 0.8, hc, ANTIFOUL, Color(0.5, 0.45, 0.38))
	box(st, Vector3(0, 5.6, -5), Vector3(5.5, 5.2, 6), WHITE)              # wheelhouse
	box(st, Vector3(0, 6.8, -8.05), Vector3(5.0, 1.3, 0.12), GLASS)
	beam(st, Vector3(0, 8, -6), Vector3(0, 15, -6), 0.4, WHITE)            # mast
	beam(st, Vector3(0, 11, -5), Vector3(0, 5, 9), 0.35, WHITE)            # boom
	for sx in [-1.0, 1.0]:
		beam(st, Vector3(sx * 3, 3, 11.5), Vector3(sx * 3, 9, 11.5), 0.5, Color(0.3, 0.3, 0.3))
	beam(st, Vector3(-3, 9, 11.5), Vector3(3, 9, 11.5), 0.5, Color(0.3, 0.3, 0.3))
	for i in 4:
		box(st, Vector3(rng.randf_range(-2.5, 2.5), 3.5, rng.randf_range(2, 9)), Vector3(1.4, 1, 1.4), Color(0.2, 0.45, 0.7))


static func _skiff(st: SurfaceTool) -> void:
	hull(st, 18, 5, 1.6, 1.0, 0.35, 0.6, 0.85, Color(0.2, 0.22, 0.24), Color(0.15, 0.15, 0.15), Color(0.28, 0.28, 0.27))
	box(st, Vector3(0, 2.3, 1), Vector3(1.6, 1.4, 1.2), DARK)
	box(st, Vector3(0, 1.8, 9.4), Vector3(1, 2.2, 1), Color(0.05, 0.05, 0.05))
	for p in [Vector3(-1, 2.3, 3), Vector3(1, 2.3, 4.5), Vector3(0, 2.3, -3)]:
		cyl(st, p, 0.45, 1.7, Color(0.1, 0.1, 0.12), 6)


static func _trawler(st: SurfaceTool) -> void:
	var rust := Color(0.3, 0.2, 0.16)
	hull(st, 38, 9.5, 4, 3, 0.28, 1.8, 0.85, rust, Color(0.2, 0.12, 0.1), Color(0.35, 0.3, 0.25))
	box(st, Vector3(0, 7, 9), Vector3(6.5, 6, 7), Color(0.68, 0.65, 0.57))   # wheelhouse
	box(st, Vector3(0, 8.4, 5.45), Vector3(6, 1.3, 0.12), GLASS)
	box(st, Vector3(0, 5.4, -6), Vector3(7, 2.8, 14), Color(0.24, 0.31, 0.21))  # tarp over cargo
	beam(st, Vector3(0, 10, 9), Vector3(0, 21, 9), 0.5, Color(0.5, 0.5, 0.5))
	cyl(st, Vector3(0, 18, 9), 1.0, 1.2, Color(0.85, 0.85, 0.85), 8)          # satellite dome
	for sx in [-1.0, 1.0]:
		beam(st, Vector3(sx * 3.6, 4, 17), Vector3(sx * 3.6, 12, 17), 0.6, Color(0.25, 0.2, 0.18))
	beam(st, Vector3(-3.6, 12, 17), Vector3(3.6, 12, 17), 0.6, Color(0.25, 0.2, 0.18))


static func _rhib(st: SurfaceTool) -> void:
	hull(st, 11, 3.8, 1.3, 0.6, 0.35, 0.4, 0.9, Color(0.22, 0.23, 0.24), Color(0.12, 0.12, 0.12), Color(0.3, 0.3, 0.3))
	for sx in [-1.0, 1.0]:
		beam(st, Vector3(sx * 1.8, 1.1, 5), Vector3(sx * 1.4, 1.3, -4), 0.9, Color(0.12, 0.13, 0.14))
	box(st, Vector3(0, 1.9, 0.5), Vector3(1.2, 1.2, 1), DARK)
	for p in [Vector3(-0.8, 2.1, 2), Vector3(0.8, 2.1, 2), Vector3(0, 2.1, 3.5), Vector3(-0.7, 2.1, -1.5)]:
		cyl(st, p, 0.4, 1.6, Color(0.95, 0.45, 0.1), 6)


static func _helo(st: SurfaceTool, root: Node3D) -> void:
	# CH-148 Cyclone maritime helicopter
	var hc := Color(0.45, 0.5, 0.53)
	box(st, Vector3(0, 0, 0), Vector3(4, 4.2, 13), hc)
	box(st, Vector3(0, -0.4, -7.6), Vector3(3.4, 3, 2.5), hc)
	box(st, Vector3(0, 0.8, -7.4), Vector3(3.5, 1.2, 2.2), GLASS)
	beam(st, Vector3(0, 1, 6), Vector3(0, 1.8, 17), 1.5, hc)
	box(st, Vector3(0, 3.6, 17), Vector3(0.4, 4, 2.5), hc)
	box(st, Vector3(0, 2.6, 0), Vector3(2.5, 1.2, 4), hc)
	for sx in [-1.0, 1.0]:
		box(st, Vector3(sx * 2.6, -1.4, 1), Vector3(1.4, 1.4, 5), hc)
	var rotor := _rotor(9.5, 4, 0.8)
	rotor.position = Vector3(0, 3.4, 0)
	root.add_child(rotor)
	root.set_meta("rotor", rotor)
	var tail := _rotor(1.8, 4, 0.3)
	tail.rotation = Vector3(0, 0, PI / 2.0)
	tail.position = Vector3(0.4, 3.8, 17.5)
	var holder := Node3D.new()
	holder.add_child(tail)
	root.add_child(holder)
	root.set_meta("tail_rotor", tail)


static func _rotor(r: float, blades: int, w: float) -> MeshInstance3D:
	var st := _new_st()
	for i in blades:
		var a := TAU * i / blades
		box(st, Vector3(sin(a), 0, cos(a)) * r * 0.5, Vector3(w, 0.15, r), DARK, a)
	var mi := MeshInstance3D.new()
	mi.mesh = _finish(st)
	mi.material_override = vc_mat()
	return mi


static func buoy(color_a: Color, color_b: Color, light: Color) -> Node3D:
	var root := Node3D.new()
	var st := _new_st()
	cyl(st, Vector3(0, 0.5, 0), 2.4, 2.5, color_a, 10)
	for i in 4:
		cyl(st, Vector3(0, 2.5 + i * 1.5, 0), 1.2 - i * 0.12, 1.5, color_a if i % 2 == 0 else color_b, 8)
	var mi := MeshInstance3D.new()
	mi.mesh = _finish(st)
	mi.material_override = vc_mat()
	root.add_child(mi)
	var lm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.8
	sm.height = 1.6
	lm.mesh = sm
	lm.material_override = glow_mat(light)
	lm.position = Vector3(0, 9, 0)
	root.add_child(lm)
	root.set_meta("light", lm)
	return root
