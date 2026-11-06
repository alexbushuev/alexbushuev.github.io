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
	env.fog_density = 3.6 / draw_dist
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
	var placed := _place_decor()
	for i in count:
		var ch := Node3D.new()
		ch.visible = false
		add_child(ch)
		chunks.append(ch)
		var s0 := i * CHUNK
		var s1: float = min(road.length, s0 + CHUNK)
		var mi := MeshInstance3D.new()
		mi.mesh = _road_mesh(s0, s1, road_mat, ground_mat)
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
	_add_gantry("start", road.start_s + 22.0)
	_add_gantry("finish", road.finish_s)

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

func _rule_add(placed: Dictionary, kind: String, s: float, d: float, flip: bool, rng: RandomNumberGenerator, keep_lane := false) -> void:
	if s < 8.0 or s > road.length - 8.0:
		return
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
	var sc := 1.0
	if kind in ["birch", "pine", "palm", "bamboo", "bush"]:
		sc = rng.randf_range(0.8, 1.25)
	placed[i][kind].append(_decor_transform(s, d, yaw, sc))
	var solid: float = D.decor_solid.get(kind, 0.0)
	if solid > 0.0 and abs(d) < 16.0:
		var long_thing: bool = kind in ["fence", "rail", "conc", "wallb"]
		road.add_solid(s, d, solid, 2.2 if long_thing else solid)

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
						_rule_add(placed, k, s2, dv2, side2 < 0, rng)
				s2 += every + rng.randf() * jit
	# warning arrows on sharp bends
	var s3 := 100.0
	while s3 < road.finish_s:
		var kap := road.kappa_at(s3)
		if abs(kap) > 0.012:
			_rule_add(placed, "chev", s3, (-1.0 if kap > 0.0 else 1.0) * (Road.EDGE + 1.5), false, rng)
		s3 += 18.0
	return placed

func _road_mesh(s0: float, s1: float, road_mat: Material, ground_mat: Material) -> ArrayMesh:
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
	for i in steps:
		var a := i * 2
		idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var nrm := PackedVector3Array()
	nrm.resize(v.size())
	nrm.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = nrm
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, road_mat)
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
			for j in offs.size():
				var w: float = side * (Road.EDGE + offs[j])
				var wob: float = sin(s * 0.013 + side * 1.7 + j) * (0.0 if j < 2 else 2.2 * j)
				gv.append(road.world(s, w, drop[j] + wob - 0.02))
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
	mesh.surface_set_material(1, ground_mat)
	return mesh

func update_visibility(s: float, draw_dist: float) -> void:
	var a := int((s - 60.0) / CHUNK)
	var b := int((s + draw_dist) / CHUNK)
	for i in chunks.size():
		var vis: bool = i >= a and i <= b
		if chunks[i].visible != vis:
			chunks[i].visible = vis
