class_name Showroom extends Node3D
# The 3D picture behind garage, shop, bar and start screen: a real bike with a real rider on a slowly turning stand.

var cam: Camera3D
var stand: Node3D
var rig: BikeView
var key := ""
var mode := ""
var scene_root: Node3D
var fraction := 0.46   # how much of the screen, from the left, is free for the picture
const VFOV := 30.0
const DIST := 6.2

func build(kind: String) -> void:
	mode = kind
	scene_root = Node3D.new()
	add_child(scene_root)
	var colors: Array = {
		"garage": ["#191820", "#3a3843", "#55504a", "#ffb347"],
		"shop": ["#dfe3e6", "#f4f5f4", "#b9bfc4", "#ffc81f"],
		"bar": ["#140c10", "#2b1a1e", "#3a2318", "#ff4f7b"],
	}[kind]
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(colors[0])
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	scene_root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 30, 0)
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_energy = 0.75
	scene_root.add_child(sun)
	# floor and back wall
	_box(Vector3(40, 0.1, 30), Vector3(0, -0.05, -3), Color(colors[1]))
	_box(Vector3(40, 12, 0.2), Vector3(0, 6, -7), Color(colors[0]).lightened(0.05))
	var disc := CylinderMesh.new()
	disc.top_radius = 1.75
	disc.bottom_radius = 1.75
	disc.height = 0.06
	disc.radial_segments = 40
	var dm := MeshInstance3D.new()
	dm.mesh = disc
	dm.material_override = _flat(Color(colors[2]))
	dm.position = Vector3(0, 0.0, 0)
	scene_root.add_child(dm)
	var ring := TorusMesh.new()
	ring.inner_radius = 1.72
	ring.outer_radius = 1.8
	ring.rings = 40
	var rm := MeshInstance3D.new()
	rm.mesh = ring
	rm.material_override = _flat(Color(colors[3]))
	rm.scale = Vector3(1, 0.3, 1)
	rm.position = Vector3(0, 0.03, 0)
	scene_root.add_child(rm)
	match kind:
		"garage":
			_garage_props()
		"shop":
			_shop_props()
		"bar":
			_bar_props()
	stand = Node3D.new()
	stand.position = Vector3(0, 0.03, 0)
	stand.rotation.y = 0.7
	add_child(stand)
	cam = Camera3D.new()
	cam.fov = VFOV
	cam.far = 60.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.45, DIST), Vector3(0, 0.82, 0), Vector3.UP)
	cam.current = true
	layout()

func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m

func _box(size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = _flat(c)
	mi.position = pos
	scene_root.add_child(mi)
	return mi

func _neon(txt: String, pos: Vector3, c: Color, px := 180) -> void:
	var l := Label3D.new()
	l.text = txt
	l.font = UiKit.big
	l.font_size = px
	l.pixel_size = 0.008
	l.modulate = c
	l.outline_modulate = c.darkened(0.55)
	l.outline_size = 14
	l.shaded = false
	l.position = pos
	scene_root.add_child(l)

func _garage_props() -> void:
	# roller shutter, tool board, tyre stack, work lamp
	for i in 16:
		_box(Vector3(9, 0.26, 0.05), Vector3(-1.5, 0.4 + i * 0.32, -6.85), Color("#2c2b33") if i % 2 else Color("#34333c"))
	_box(Vector3(3.2, 1.7, 0.08), Vector3(-5.8, 2.6, -6.8), Color("#4a3d2c"))
	for i in 6:
		_box(Vector3(0.07, 0.6 + (i % 3) * 0.2, 0.05), Vector3(-7.0 + i * 0.5, 2.6, -6.74), Color("#b8bcc4"))
	for i in 4:
		var t := TorusMesh.new()
		t.inner_radius = 0.2
		t.outer_radius = 0.42
		var mi := MeshInstance3D.new()
		mi.mesh = t
		mi.material_override = _flat(Color("#101013"))
		mi.position = Vector3(-4.1, 0.14 + i * 0.26, -3.6)
		scene_root.add_child(mi)
	_box(Vector3(4.0, 0.08, 0.3), Vector3(0, 5.6, -3), Color("#fff1c4"))

func _shop_props() -> void:
	_neon("МОТОСАЛОН", Vector3(-1.6, 5.3, -6.7), Color("#d9232e"), 150)
	for i in 5:
		_box(Vector3(2.2, 3.4, 0.05), Vector3(-6.4 + i * 2.8, 2.4, -6.85), Color("#bfd7e6"))
	_box(Vector3(30, 0.2, 0.3), Vector3(0, 4.4, -6.7), Color("#c9ced2"))
	_box(Vector3(5.0, 0.08, 0.5), Vector3(0, 6.2, -2.5), Color("#ffffff"))

func _bar_props() -> void:
	_neon("БАЙКЕРЫ", Vector3(-1.5, 5.2, -6.7), Color("#ff4f7b"), 170)
	_neon("Бар «Цепь»", Vector3(-1.5, 4.1, -6.7), Color("#7ff5ff"), 80)
	# counter and shelves with bottles
	_box(Vector3(12, 1.1, 0.8), Vector3(-1.5, 0.55, -5.2), Color("#4a2a18"))
	_box(Vector3(12.2, 0.1, 1.0), Vector3(-1.5, 1.12, -5.2), Color("#6b3f22"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for row in 2:
		_box(Vector3(10, 0.06, 0.3), Vector3(-1.5, 1.9 + row * 0.8, -6.6), Color("#3a2318"))
		for i in 26:
			var h: float = rng.randf_range(0.28, 0.5)
			var c := Color.from_hsv(rng.randf(), 0.65, 0.75)
			_box(Vector3(0.13, h, 0.13), Vector3(-6.2 + i * 0.37, 1.93 + row * 0.8 + h * 0.5, -6.55), c)
	for i in 3:
		var stool := CylinderMesh.new()
		stool.top_radius = 0.2
		stool.bottom_radius = 0.1
		stool.height = 0.8
		var mi := MeshInstance3D.new()
		mi.mesh = stool
		mi.material_override = _flat(Color("#1d1b20"))
		mi.position = Vector3(-5.2 + i * 1.3, 0.4, -4.3)
		scene_root.add_child(mi)

func layout() -> void:
	if cam == null:
		return
	var vp := get_viewport()
	var sz: Vector2 = Vector2(vp.size) if vp != null else Vector2(844, 390)
	var aspect: float = sz.x / max(1.0, sz.y)
	var half_h: float = DIST * tan(deg_to_rad(VFOV * 0.5))
	var half_w: float = half_h * aspect
	# put the bike in the middle of the free part of the screen
	cam.h_offset = (1.0 - fraction) * half_w
	cam.v_offset = -0.12

func show_rig(bike: Dictionary, paint_i: int, outfit: Variant, helmet: int, weapon: String, rider_on: bool, dark := false, is_cop := false) -> void:
	var new_key := "%s/%d/%s/%d/%s/%s/%s" % [bike.art, paint_i, str(outfit), helmet, weapon, rider_on, dark]
	if new_key == key:
		return
	key = new_key
	if rig != null:
		stand.remove_child(rig)
		rig.queue_free()
	var r := Sim.Rider.new()
	r.bike = bike
	r.is_cop = is_cop
	r.weapon = weapon
	r.top = 1.0
	var o: Dictionary = outfit if outfit != null else D.outfit(0, 0, 5)
	r.look = {"outfit": o, "helmet": helmet, "paint": paint_i}
	rig = BikeView.new()
	stand.add_child(rig)
	rig.setup(r, null)
	rig._pose_riding(0.0, true)
	rig.rider_root.visible = rider_on
	rig.blob.visible = false
	if dark:
		var pal := PackedVector3Array()
		pal.resize(16)
		pal.fill(Vector3(0.05, 0.05, 0.06))
		rig.bike_mat.set_shader_parameter("pal", pal)

func _process(delta: float) -> void:
	if stand != null:
		stand.rotation.y += delta * 0.45
