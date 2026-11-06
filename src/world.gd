class_name World extends Node3D
# Turns a Road plus a theme into geometry: asphalt, ground, sky, roadside. Split into chunks so only what's near gets drawn.

const CHUNK := 160.0
const SEG_M := 3.0   # one 2D road segment of decor spacing, in metres

var road: Road
var theme: Dictionary
var chunks: Array[Node3D] = []
var paint_shader: Shader
var decor_mat: ShaderMaterial
var decor_meshes := {}
var labels := {}          # chunk -> [[transform, text, kind]]
var _grid := {}           # where the roads run, for keeping houses and trees off them: cell -> [[x, z, edge]]
const CELL := 12.0
var _rng_f := RandomNumberGenerator.new()

static func shared_material(pal: Array) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://src/paint.gdshader")
	var arr := PackedVector3Array()
	arr.resize(16)
	for i in pal.size():
		var c: Color = pal[i]
		arr[i] = Vector3(c.r, c.g, c.b)
	m.set_shader_parameter("pal", arr)
	return m

func _tone_palette(t: Dictionary) -> Array:
	var keys := ["leaf", "leaf2", "trunk", "dark", "wall", "wall2", "roof", "win", "metal", "wood", "plate"]
	var out: Array = []
	for k in keys:
		out.append(Color(t.tone[k]))
	return out

func _road_texture(t: Dictionary) -> ImageTexture:
	var w := 256
	var h := 256
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var base: Color = Color(t.road[0])
	var base2: Color = Color(t.road[1])
	var line: Color = Color(t.lane)
	var r1: Color = Color(t.rumble[0])
	var r2: Color = Color(t.rumble[1])
	var yellow := Color("#e8b91c")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var half := Road.EDGE            # the texture spans -EDGE .. +EDGE, 8 m long
	for y in h:
		for x in w:
			var d: float = (float(x) / (w - 1) * 2.0 - 1.0) * half
			var c: Color = base.lerp(base2, rng.randf() * 0.7)
			var band := int(y / 64) % 2
			if abs(d) > Road.HALF + 0.14:
				c = r1 if band == 0 else r2
			elif abs(abs(d) - Road.HALF) < 0.09:
				c = line
			elif abs(abs(d) - 0.14) < 0.05:
				c = yellow
			elif abs(abs(d) - Road.LANE_W) < 0.075 and y < h * 0.45:
				c = line
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _sky_material(t: Dictionary) -> PanoramaSkyMaterial:
	var w := 512
	var h := 256
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var stops: Array = t.sky
	var fog := Color(t.fog)
	for y in h:
		var v := 1.0 - float(y) / (h * 0.5)  # 1 at zenith, 0 at horizon
		var c: Color
		if y >= h * 0.5:
			c = fog
		else:
			var q: float = 1.0 - v
			c = Color(stops[0][0])
			for i in stops.size() - 1:
				var a: Array = stops[i]
				var b: Array = stops[i + 1]
				if q >= a[1] and q <= b[1]:
					c = Color(a[0]).lerp(Color(b[0]), (q - a[1]) / max(0.001, b[1] - a[1]))
					break
		for x in w:
			img.set_pixel(x, y, c)
	var sun: Variant = t.get("sun")
	if sun != null:
		var cx: float = sun.x * w
		var cy: float = sun.y * h * 0.5
		var rad: float = sun.r * h * 0.35
		var sc := Color(sun.c)
		for y in range(int(cy - rad - 2), int(cy + rad + 3)):
			for x in range(int(cx - rad - 2), int(cx + rad + 3)):
				if y >= 0 and y < h and Vector2(x - cx, y - cy).length() < rad:
					img.set_pixel(posmod(x, w), y, sc)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var stars: float = t.get("stars", 0.0)
	if stars > 0.0:
		for i in int(stars * 2600):
			img.set_pixel(rng.randi() % w, rng.randi() % int(h * 0.3), Color(1, 1, 1))
	var tex := ImageTexture.create_from_image(img)
	var m := PanoramaSkyMaterial.new()
	m.panorama = tex
	m.filter = true
	return m

func _make_environment(t: Dictionary, draw_dist: float) -> WorldEnvironment:
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = _sky_material(t)
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(t.fog)
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = draw_dist * 0.5
	env.fog_depth_end = draw_dist
	env.fog_depth_curve = 1.0
	env.fog_density = 1.0
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	return we

func _load_decor() -> void:
	var scene: PackedScene = load("res://models/decor.glb")
	var inst: Node = scene.instantiate()
	for c in inst.get_children():
		if c is MeshInstance3D:
			decor_meshes[c.name] = c.mesh
	inst.free()

func _grid_build() -> void:
	var s := 0.0
	while s <= road.length:
		_grid_put(road.world(s, 0.0), Road.EDGE)
		s += 4.0
	for b in road.branches:
		var s2 := 0.0
		while s2 <= b.length:
			_grid_put(b.world(s2, 0.0), b.edge + 0.6)
			s2 += 4.0

func _grid_put(p: Vector3, e: float) -> void:
	var k := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	if not _grid.has(k):
		_grid[k] = []
	_grid[k].append([p.x, p.z, e])

# nothing of this size stands on any road here, nor on the road elsewhere when it bends back past
func _clear(p: Vector3, radius: float) -> bool:
	var reach: float = radius + Road.EDGE + 1.0
	var c0 := Vector2i(floori((p.x - reach) / CELL), floori((p.z - reach) / CELL))
	var c1 := Vector2i(floori((p.x + reach) / CELL), floori((p.z + reach) / CELL))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var list: Variant = _grid.get(Vector2i(cx, cz))
			if list == null:
				continue
			for q in list:
				var dx: float = p.x - float(q[0])
				var dz: float = p.z - float(q[1])
				var lim: float = float(q[2]) + max(radius, 0.1)
				if dx * dx + dz * dz < lim * lim:
					return false
	return true

# side roads sit in flat ground; a tunnel goes through a hill
func _zone_flat(s: float) -> float:
	var k := 0.0
	for b in road.branches:
		var a: float = b.s0 - 140.0
		var e: float = b.s1 + 140.0
		if s > a and s < e:
			k = max(k, clamp(min(s - a, e - s) / 60.0, 0.0, 1.0))
	return k

func _zone_hill(s: float) -> float:
	var k := 0.0
	for f in road.features:
		if f.kind == "tunnel":
			var a: float = float(f.s_a) - 80.0
			var e: float = float(f.s_b) + 80.0
			if s > a and s < e:
				k = max(k, smoothstep(0.0, 1.0, clamp(min(s - a, e - s) / 80.0, 0.0, 1.0)))
	return k

func _in_tunnel(s: float) -> bool:
	return road.feature_at(s, "tunnel") != null

func build(r: Road, t: Dictionary, draw_dist: float) -> void:
	road = r
	theme = t
	add_child(_make_environment(t, draw_dist))
	var dim: float = t.get("dim", 0.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 25, 0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 0.62 * (1.0 - dim)
	sun.shadow_enabled = false
	add_child(sun)
	_load_decor()
	decor_mat = shared_material(_tone_palette(t))
	decor_mat.set_shader_parameter("ambient", Vector3(0.82, 0.82, 0.82) * (1.0 - dim * 0.4))
	var road_mat := StandardMaterial3D.new()
	road_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	road_mat.albedo_texture = _road_texture(t)
	road_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var ground_mat := StandardMaterial3D.new()
	ground_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground_mat.vertex_color_use_as_albedo = true

	var count := int(ceil(road.length / CHUNK))
	_grid_build()
	var road_dark := road_mat.duplicate() as StandardMaterial3D
	road_dark.albedo_color = Color(0.42, 0.42, 0.46)
	var placed := _place_decor()
	_place_features(placed)
	for i in count:
		var ch := Node3D.new()
		ch.visible = false
		add_child(ch)
		chunks.append(ch)
		var s0 := i * CHUNK
		var s1: float = min(road.length, s0 + CHUNK)
		var mi := MeshInstance3D.new()
		mi.mesh = _road_mesh(s0, s1, road_mat, ground_mat, road_dark)
		ch.add_child(mi)
		var by_kind: Dictionary = placed.get(i, {})
		for kind in by_kind:
			var mesh: Mesh = decor_meshes.get(kind)
			if mesh == null:
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			var list: Array = by_kind[kind]
			mm.instance_count = list.size()
			for j in list.size():
				mm.set_instance_transform(j, list[j])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = decor_mat
			ch.add_child(mmi)
		for lb in labels.get(i, []):
			ch.add_child(_label3d(lb[0], lb[1], lb[2]))
	_add_gantry("start", road.start_s + 22.0)
	_add_gantry("finish", road.finish_s)
	_build_tunnels(ground_mat)
	for bi in road.branches.size():
		_build_branch(bi, ground_mat)

func _add_gantry(kind: String, s: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = decor_meshes.get(kind)
	mi.material_override = decor_mat
	mi.transform = _decor_transform(s, 0.0, 0.0)
	var i := int(s / CHUNK)
	if i < chunks.size():
		chunks[i].add_child(mi)

func _decor_transform(s: float, d: float, yaw_extra: float, scale_v := 1.0) -> Transform3D:
	var p := road.world(s, d, 0.0)
	var f := road.fwd_at(s)
	var h := atan2(f.x, -f.z)  # 0 means facing -Z
	var b := Basis(Vector3.UP, -h + yaw_extra).scaled(Vector3.ONE * scale_v)
	return Transform3D(b, p)

func _rule_add(placed: Dictionary, kind: String, s: float, d: float, flip: bool, rng: RandomNumberGenerator, keep_lane := false, text := "") -> bool:
	if s < 8.0 or s > road.length - 8.0:
		return false
	# nothing inside a hill, under an overpass, or on top of a road that bends back past here
	var foot: float = max(float(D.decor_solid.get(kind, 0.0)), 0.6 if kind in ["fence", "rail", "conc", "wallb"] else 0.3)
	if kind != "chev":
		for f in road.features:
			if f.kind == "tunnel" and s > float(f.s_a) - 70.0 and s < float(f.s_b) + 70.0 and abs(d) < 26.0 + foot:
				return false
			if f.kind == "bridge" and abs(s - float(f.s)) < 9.0 + foot and abs(d) < 36.0:
				return false
	var p := road.world(s, d)
	if not _clear(p, foot):
		return false
	var i := int(s / CHUNK)
	if not placed.has(i):
		placed[i] = {}
	if not placed[i].has(kind):
		placed[i][kind] = []
	# things with a front face the road: -Y in the model faces out of the building, so turn it towards the road
	var yaw: float = -PI * 0.5 if d > 0.0 else PI * 0.5
	if kind in ["birch", "pine", "palm", "bamboo", "bush", "buffalo"]:
		yaw = rng.randf() * TAU
	if kind in ["fence", "rail", "conc", "wallb"]:
		yaw = 0.0
	# signs face the traffic coming towards them, turned a little to the road
	if kind in ["sign", "slimit", "bigsign", "tsign", "chev", "gore"]:
		yaw = (0.18 if d > 0.0 else -0.18)
	if kind in ["hay", "shed", "cont1", "cont2", "cont3", "rock"]:
		yaw += rng.randf_range(-0.5, 0.5)
	var sc := 1.0
	if kind in ["birch", "pine", "palm", "bamboo", "bush"]:
		sc = rng.randf_range(0.8, 1.25)
	var xf := _decor_transform(s, d, yaw, sc)
	placed[i][kind].append(xf)
	if text != "":
		if not labels.has(i):
			labels[i] = []
		labels[i].append([xf, text, kind])
	var solid: float = D.decor_solid.get(kind, 0.0)
	if solid > 0.0 and abs(d) < 16.0:
		var long_thing: bool = kind in ["fence", "rail", "conc", "wallb"]
		road.add_solid(s, d, solid, 2.2 if long_thing else solid)
	return true

func _place_decor() -> Dictionary:
	var placed := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(theme.get("seed", 1)) * 101
	var length := road.length - 10.0
	for r in theme.decor:
		var k: String = r.k
		if k == "sign" or k == "fence" or k == "post":
			pass
		var xr: Array = r.x
		var both: bool = r.get("both", 0) == 1
		if r.has("run"):
			var s := 90.0
			while s < length:
				var run_m: float = rng.randf_range(r.run[0], r.run[1]) * SEG_M
				var side := -1 if rng.randf() < 0.5 else 1
				var e := s
				while e < s + run_m:
					var dv: float = side * max(Road.EDGE + 1.5, lerp(float(xr[0]), float(xr[1]), rng.randf()) * Road.HALF)
					_rule_add(placed, k, e, dv, false, rng)
					if both:
						_rule_add(placed, k, e, -dv, false, rng)
					e += 4.2
				s += run_m + rng.randf_range(r.gap[0], r.gap[1]) * SEG_M
		else:
			var every: float = float(r.every) * SEG_M
			var jit: float = float(r.get("jit", 0)) * SEG_M
			var s2: float = 90.0 + rng.randf() * every
			while s2 < length:
				if rng.randf() < r.get("p", 1.0):
					var one_side: int = int(r.get("side", 0))
					for side2 in ([1, -1] if both else [one_side if one_side != 0 else (-1 if rng.randf() < 0.5 else 1)]):
						var base: float = lerp(float(xr[0]), float(xr[1]), rng.randf()) * Road.HALF
						var dv2: float = side2 * max(Road.EDGE + 1.3, base)
						var txt := ""
						if k == "slimit":
							txt = str(int(r.get("limit", 60)))
						elif k == "sign" and r.get("text", 0) == 1:
							txt = _sign_text(s2, rng)
						_rule_add(placed, k, s2, dv2, side2 < 0, rng, false, txt)
				s2 += every + rng.randf() * jit
	# warning arrows on sharp bends
	var s3 := 100.0
	while s3 < road.finish_s:
		var kap := road.kappa_at(s3)
		if abs(kap) > 0.012:
			_rule_add(placed, "chev", s3, (-1.0 if kap > 0.0 else 1.0) * (Road.EDGE + 1.5), false, rng)
		s3 += 18.0
	return placed

func _road_mesh(s0: float, s1: float, road_mat: Material, ground_mat: Material, road_dark: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var steps := int(ceil((s1 - s0) / 6.0))
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	# asphalt, 2 x steps quads
	for i in steps + 1:
		var s: float = lerp(s0, s1, float(i) / steps)
		v.append(road.world(s, -Road.EDGE))
		v.append(road.world(s, Road.EDGE))
		var tv: float = s / 8.0
		uv.append(Vector2(0.0, tv))
		uv.append(Vector2(1.0, tv))
	var idx_dark := PackedInt32Array()
	for i in steps:
		var a := i * 2
		var sm: float = lerp(s0, s1, (float(i) + 0.5) / steps)
		if _in_tunnel(sm):
			idx_dark.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
		else:
			idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var nrm := PackedVector3Array()
	nrm.resize(v.size())
	nrm.fill(Vector3.UP)
	for pair in [[idx, road_mat], [idx_dark, road_dark]]:
		if (pair[0] as PackedInt32Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_INDEX] = pair[0]
		arr[Mesh.ARRAY_NORMAL] = nrm
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
	# ground ribbons either side
	var g1 := Color(theme.grass[0])
	var g2 := Color(theme.grass[1])
	var gv := PackedVector3Array()
	var gc := PackedColorArray()
	var gi := PackedInt32Array()
	var offs := [0.0, 5.0, 22.0, 70.0, 180.0]
	var drop := [0.0, -0.25, 0.25, 1.2, 4.0]
	var coarse := int(ceil((s1 - s0) / 16.0))
	var base := 0
	for side in [-1, 1]:
		for i in coarse + 1:
			var s: float = lerp(s0, s1, float(i) / coarse)
			var band := int(s / 24.0) % 2
			var flat := _zone_flat(s)
			var hill := _zone_hill(s)
			for j in offs.size():
				var w: float = side * (Road.EDGE + offs[j])
				var wob: float = sin(s * 0.013 + side * 1.7 + j) * (0.0 if j < 2 else 2.2 * j)
				var y: float = drop[j] + wob
				if j >= 1:
					y = lerp(y, -0.15, flat) + hill * [0.0, 11.0, 12.0, 7.0, 4.0][j]
				gv.append(road.world(s, w, y - 0.02))
				gc.append(g1 if (band + j) % 2 == 0 else g2)
		for i in coarse:
			for j in offs.size() - 1:
				var a: int = base + i * offs.size() + j
				var b: int = a + offs.size()
				if side > 0:
					gi.append_array([a, b, a + 1, a + 1, b, b + 1])
				else:
					gi.append_array([a, a + 1, b, a + 1, b + 1, b])
		base = gv.size()
	var arr2 := []
	arr2.resize(Mesh.ARRAY_MAX)
	arr2[Mesh.ARRAY_VERTEX] = gv
	arr2[Mesh.ARRAY_COLOR] = gc
	arr2[Mesh.ARRAY_INDEX] = gi
	var nrm2 := PackedVector3Array()
	nrm2.resize(gv.size())
	nrm2.fill(Vector3.UP)
	arr2[Mesh.ARRAY_NORMAL] = nrm2
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
	mesh.surface_set_material(mesh.get_surface_count() - 1, ground_mat)
	return mesh

func update_visibility(s: float, draw_dist: float) -> void:
	# a little behind too: the mirrors look back
	var a := int((s - (150.0 if S.data.get("mirrors", true) else 60.0)) / CHUNK)
	var b := int((s + draw_dist) / CHUNK)
	for i in chunks.size():
		var vis: bool = i >= a and i <= b
		if chunks[i].visible != vis:
			chunks[i].visible = vis


# ---------- build 8: signs, overpasses, tunnels, side roads ----------
const SIGN_TEXT := [
	["СНТ «Рассвет»", "СНТ «Ромашка»", "Озеро 5 км", "Дачи 3 км"],
	["МКР Северный", "ул. Ленина", "Центр 4 км", "Рынок"],
	["ТЭЦ-2", "Склады", "Завод 1 км", "Депо"],
	["М5", "Москва 900", "Кафе 2 км", "Заправка 5"],
	["Кольцо", "Центр", "Аэропорт 12", "Порт"],
	["Рисовые поля", "Ферма 2 км", "Деревня", "Рынок 4 км"],
]
const TREE := ["birch", "birch", "bush", "pine", "bush", "palm"]

func _theme_i() -> int:
	for i in D.themes.size():
		if D.themes[i] == theme:
			return i
	return 0

func _sign_text(s: float, rng: RandomNumberGenerator) -> String:
	var list: Array = SIGN_TEXT[_theme_i()]
	return list[rng.randi() % list.size()]

func _label3d(xf: Transform3D, text: String, kind: String) -> Label3D:
	var l := Label3D.new()
	l.text = text
	if UiKit.mid != null:
		l.font = UiKit.mid
	l.font_size = 96
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var off := Vector3(0, 2.5, 0.07)
	var px := 0.0034
	match kind:
		"slimit":
			off = Vector3(0, 2.5, 0.065)
			px = 0.0034
			l.modulate = Color("#16151b")
		"tsign":
			off = Vector3(0, 2.35, 0.065)
			px = 0.0028
			l.modulate = Color("#16151b")
		"bigsign":
			off = Vector3(0, 3.4, 0.1)
			px = 0.0046
			l.modulate = Color("#f3eedf")
		_:
			off = Vector3(0, 2.5, 0.065)
			px = 0.0024
			l.modulate = Color("#16151b")
	l.pixel_size = px
	l.transform = xf * Transform3D(Basis(), off)
	return l

func _put(placed: Dictionary, kind: String, xf: Transform3D, chunk: int, text := "") -> void:
	if not placed.has(chunk):
		placed[chunk] = {}
	if not placed[chunk].has(kind):
		placed[chunk][kind] = []
	placed[chunk][kind].append(xf)
	if text != "":
		if not labels.has(chunk):
			labels[chunk] = []
		labels[chunk].append([xf, text, kind])

func _xf(on: Road, s: float, d: float, yaw: float) -> Transform3D:
	var p := on.world(s, d, 0.0)
	var f := on.fwd_at(s)
	var h := atan2(f.x, -f.z)
	return Transform3D(Basis(Vector3.UP, -h + yaw), p)

func _place_features(placed: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(theme.get("seed", 1)) * 37 + int(road.length)
	var sgn := func(kind: String, s: float, d: float, text: String) -> void:
		_rule_add(placed, kind, s, d, false, rng, false, text)
	sgn.call("tsign", road.start_s + 70.0, Road.EDGE + 1.6, SIGN_TEXT[_theme_i()][0])
	for m in [1000.0, 500.0]:
		if road.finish_s - m > road.start_s + 300.0:
			sgn.call("bigsign", road.finish_s - m, Road.EDGE + 3.4, "ФИНИШ %s" % ("1 км" if m >= 1000.0 else "500 м"))
	for f in road.features:
		match f.kind:
			"tunnel":
				sgn.call("bigsign", float(f.s_a) - 170.0, Road.EDGE + 3.4, "ТОННЕЛЬ %d м" % int(round((float(f.s_b) - float(f.s_a)) / 10.0) * 10))
			"bridge":
				var bs: float = f.s
				var ci := int(bs / CHUNK)
				_put(placed, "deck", _xf(road, bs, 0.0, 0.0), ci)
				for d in [0.0, -(Road.EDGE + 1.4), Road.EDGE + 1.4]:
					_put(placed, "pillar", _xf(road, bs, d, 0.0), ci)
	for b in road.branches:
		var word := "СРЕЗКА" if b.kind == "cut" else "ОБЪЕЗД"
		var txt: String = (word + " →") if b.side > 0 else ("← " + word)
		for back in [230.0, 100.0]:
			sgn.call("bigsign", b.s0 - back, b.side * (Road.EDGE + 3.4), txt)

func _tex(w: int, h: int, fn: Callable) -> ImageTexture:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, fn.call(float(x) / (w - 1), float(y) / (h - 1)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _branch_material(kind: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	if kind == "cut":
		var g1 := Color("#8c7a58")
		var g2 := Color("#6e5f44")
		m.albedo_texture = _tex(64, 128, func(u: float, v: float) -> Color:
			var c := g1.lerp(g2, rng.randf())
			# two worn tyre tracks
			if abs(u - 0.32) < 0.07 or abs(u - 0.68) < 0.07:
				c = c.darkened(0.18)
			if u < 0.05 or u > 0.95:
				c = c.lerp(Color(theme.grass[0]), 0.6)
			return c)
	else:
		var base := Color(theme.road[0])
		var base2 := Color(theme.road[1])
		var line := Color(theme.lane)
		m.albedo_texture = _tex(64, 128, func(u: float, v: float) -> Color:
			var c := base.lerp(base2, rng.randf() * 0.7)
			if abs(u - 0.5) < 0.012 and v < 0.45:
				c = line
			if abs(u - 0.06) < 0.012 or abs(u - 0.94) < 0.012:
				c = line
			return c)
	return m

func _tunnel_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

# A strip of quads following a road between two s, cut into pieces by chunk. pts(s) returns the points across.
func _strip(on: Road, sa: float, sb: float, step: float, across: Array, cols: Array, chunk_of: Callable, mat: Material, uv_mode := false) -> void:
	var pieces := {}
	var s := sa
	while s < sb - 0.01:
		var e: float = min(sb, s + step)
		var ci: int = chunk_of.call((s + e) * 0.5)
		if not pieces.has(ci):
			pieces[ci] = [[], [], []]
		var pc: Array = pieces[ci]
		for j in across.size() - 1:
			var a0: Array = across[j]
			var a1: Array = across[j + 1]
			var q := [on.world(s, a0[0], a0[1]), on.world(s, a1[0], a1[1]), on.world(e, a0[0], a0[1]), on.world(e, a1[0], a1[1])]
			var colr: Color = cols[j] if typeof(cols[j]) == TYPE_COLOR else (cols[j] as Callable).call(s)
			for k in [0, 2, 1, 1, 2, 3]:
				pc[0].append(q[k])
				pc[1].append(colr)
				if uv_mode:
					var uu: float = 0.0 if k in [0, 2] else 1.0
					var vv: float = (s if k in [0, 1] else e) / 8.0
					pc[2].append(Vector2(uu, vv))
		s = e
	for ci in pieces:
		if ci < 0 or ci >= chunks.size():
			continue
		var pc2: Array = pieces[ci]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array(pc2[0])
		arr[Mesh.ARRAY_COLOR] = PackedColorArray(pc2[1])
		if uv_mode:
			arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array(pc2[2])
		var nrm := PackedVector3Array()
		nrm.resize((pc2[0] as Array).size())
		nrm.fill(Vector3.UP)
		arr[Mesh.ARRAY_NORMAL] = nrm
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		chunks[ci].add_child(mi)

func _build_tunnels(_ground_mat: Material) -> void:
	var mat := _tunnel_material()
	var by_chunk := func(s: float) -> int: return int(s / CHUNK)
	var w := Road.EDGE + 0.2
	var h := 6.6
	var wall := Color("#77736b")
	var wall_lo := Color("#4f4c47")
	var ceil_c := Color("#3d3b38")
	var grass := Color(theme.grass[0]).darkened(0.08)
	for f in road.features:
		if f.kind != "tunnel":
			continue
		var sa: float = f.s_a
		var sb: float = f.s_b
		# inside: walls, a dark band low down, the ceiling
		_strip(road, sa, sb, 6.0, [[-w, 0.0], [-w, 1.0], [-w, h], [-w * 0.5, h], [w * 0.5, h], [w, h], [w, 1.0], [w, 0.0]],
			[wall_lo, wall, ceil_c, ceil_c, ceil_c, wall, wall_lo], by_chunk, mat)
		# lamps along the ceiling, every 12 m
		var s := sa + 6.0
		while s < sb - 4.0:
			_strip(road, s, s + 3.0, 3.0, [[-3.4, h - 0.02], [-2.8, h - 0.02]], [Color("#fff0b8")], by_chunk, mat)
			_strip(road, s, s + 3.0, 3.0, [[2.8, h - 0.02], [3.4, h - 0.02]], [Color("#fff0b8")], by_chunk, mat)
			s += 12.0
		# the top of the hill over the road
		_strip(road, sa - 1.0, sb + 1.0, 8.0, [[-(Road.EDGE + 5.5), 11.0], [Road.EDGE + 5.5, 11.0]], [grass], by_chunk, mat)
		# portals: a concrete face round the opening at each end
		for pe in [sa, sb]:
			var ci: int = int(pe / CHUNK)
			if ci >= chunks.size():
				continue
			var fv := PackedVector3Array()
			var fc := PackedColorArray()
			var conc := Color("#8e8a80")
			var rim := Color("#5d5a54")
			var rects := [[-(Road.EDGE + 16.0), -w, 0.0, 12.5, conc], [w, Road.EDGE + 16.0, 0.0, 12.5, conc], [-w, w, h, 12.5, conc],
				[-w - 0.6, -w, 0.0, h + 0.6, rim], [w, w + 0.6, 0.0, h + 0.6, rim], [-w - 0.6, w + 0.6, h, h + 0.6, rim]]
			var out_dir: float = -1.0 if pe == sa else 1.0
			for rc in rects:
				var lift: float = 0.05 if rc[4] == rim else 0.0
				var a := road.world(pe - out_dir * lift, rc[0], rc[2])
				var b := road.world(pe - out_dir * lift, rc[1], rc[2])
				var c := road.world(pe - out_dir * lift, rc[0], rc[3])
				var d2 := road.world(pe - out_dir * lift, rc[1], rc[3])
				for q in [a, b, c, c, b, d2]:
					fv.append(q)
					fc.append(rc[4])
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = fv
			arr[Mesh.ARRAY_COLOR] = fc
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			chunks[ci].add_child(mi)

func _build_branch(bi: int, ground_mat: Material) -> void:
	var b: Road = road.branches[bi]
	var by_chunk := func(s: float) -> int: return int(road.branch_prog(bi, s) / CHUNK)
	# the side road shows from where it leaves the main road's edge to where it meets it again
	var sa := 0.0
	while sa < b.length * 0.4 and road.dist_to_road(b.world(sa, 0.0), b.s0 - 30.0, b.s0 + 120.0) < Road.EDGE - b.half * 0.4:
		sa += 2.0
	var sb := b.length
	while sb > b.length * 0.6 and road.dist_to_road(b.world(sb, 0.0), b.s1 - 120.0, b.s1 + 30.0) < Road.EDGE - b.half * 0.4:
		sb -= 2.0
	var mat := _branch_material(b.kind)
	var white := Color.WHITE
	_strip(b, sa, sb, 4.0, [[-b.edge, 0.0], [b.edge, 0.0]], [white], by_chunk, _with_vertex_white(mat), true)
	var g1 := Color(theme.grass[0])
	var g2 := Color(theme.grass[1])
	var gcol := func(s: float) -> Color: return g1 if int(s / 24.0) % 2 == 0 else g2
	_strip(b, sa, sb, 8.0, [[-b.edge - 6.0, -0.06], [-b.edge, -0.03]], [gcol], by_chunk, ground_mat)
	_strip(b, sa, sb, 8.0, [[b.edge, -0.03], [b.edge + 6.0, -0.06]], [gcol], by_chunk, ground_mat)
	# what stands along it, kept off both roads
	var rng := RandomNumberGenerator.new()
	rng.seed = 501 + bi * 17
	var placed := {}
	var add := func(kind: String, s: float, d: float, yaw: float, solid: float, half: float) -> void:
		var p := b.world(s, d)
		if solid >= 0.0 and road.dist_to_road(p, b.s0 - 80.0, b.s1 + 80.0) < Road.EDGE + max(solid, 0.4) + 0.5:
			return
		var ci: int = by_chunk.call(s)
		if not placed.has(ci):
			placed[ci] = {}
		if not placed[ci].has(kind):
			placed[ci][kind] = []
		placed[ci][kind].append(_xf(b, s, d, yaw))
		if solid > 0.0:
			b.add_solid(s, d, solid, half)
	var tree: String = TREE[_theme_i()]
	var s := sa + 6.0
	while s < sb - 6.0:
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.75:
				var dv: float = side * (b.edge + rng.randf_range(1.2, 6.0))
				add.call(tree, s + rng.randf_range(-3.0, 3.0), dv, rng.randf() * TAU, float(D.decor_solid.get(tree, 0.3)), float(D.decor_solid.get(tree, 0.3)))
		s += rng.randf_range(7.0, 12.0)
	if b.kind == "cut":
		for bp in b.bumps:
			add.call("hole", float(bp[0]), float(bp[1]), rng.randf() * TAU, -1.0, 0.0)
		var n_rock := 3 if b.length > 220.0 else 2
		for k in n_rock:
			var rs: float = lerp(sa + 50.0, sb - 50.0, (k + rng.randf_range(0.2, 0.8)) / n_rock)
			add.call("rock", rs, rng.randf_range(-b.half + 0.6, b.half - 0.6), rng.randf() * TAU, 0.8, 0.7)
		var s3 := sa + 10.0
		while s3 < sb - 10.0:
			add.call("barrel", s3, (b.edge + 0.4) * (1.0 if rng.randf() < 0.5 else -1.0), 0.0, 0.0, 0.0)
			s3 += rng.randf_range(30.0, 60.0)
	else:
		var s4 := sa + 16.0
		while s4 < sb - 10.0:
			add.call("lamp", s4, -b.side * (b.edge + 1.0), -PI * 0.5 * -b.side, 0.25, 0.25)
			s4 += 32.0
		for k in 2:
			var ws: float = lerp(sa, sb, 0.32 + k * 0.3 + rng.randf_range(-0.05, 0.05))
			add.call("wreck", ws, (1.9 if rng.randf() < 0.5 else -1.9), rng.randf_range(-0.12, 0.12), 1.0, 2.2)
	# a chevron board where it splits off
	add.call("gore", sa + 4.0, -b.side * (b.edge + 0.9), 0.0, -1.0, 0.0)
	for ci in placed:
		if ci < 0 or ci >= chunks.size():
			continue
		for kind in placed[ci]:
			var mesh: Mesh = decor_meshes.get(kind)
			if mesh == null:
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			var list: Array = placed[ci][kind]
			mm.instance_count = list.size()
			for j in list.size():
				mm.set_instance_transform(j, list[j])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = decor_mat
			chunks[ci].add_child(mmi)

func _with_vertex_white(m: StandardMaterial3D) -> StandardMaterial3D:
	m.vertex_color_use_as_albedo = true
	return m
