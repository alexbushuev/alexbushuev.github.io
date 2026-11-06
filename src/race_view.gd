class_name RaceView extends Node3D
# Everything visible during a race: world, bikes, traffic, camera, effects. Reads the Sim; never changes it.

var sim: Sim
var world: World
var cam: Camera3D
var views: Array[BikeView] = []
var me_view: BikeView
var car_nodes: Array[MeshInstance3D] = []
var sparks: CPUParticles3D
var smoke: CPUParticles3D
var dust: CPUParticles3D
var impact: CPUParticles3D
var shake := 0.0
var draw_dist := 480.0
var cam_d := 1.8
var cam_dist := 4.2
var cam_h := 1.75
var cam_look_h := 1.0
var fov_now := 62.0
var cam_roll := 0.0
var debug_close := false

func _particles(col: Color, size: float, life: float, amount: int, spread: float, vel: Vector2, grav: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = col
	m.vertex_color_use_as_albedo = false
	q.material = m
	p.mesh = q
	p.lifetime = life
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.spread = spread
	p.direction = Vector3.UP
	p.initial_velocity_min = vel.x
	p.initial_velocity_max = vel.y
	p.gravity = Vector3(0, grav, 0)
	p.local_coords = false
	add_child(p)
	return p

func build(s: Sim) -> void:
	sim = s
	var tr: Dictionary = s.tr
	var theme: Dictionary = D.themes[int(tr.theme)]
	draw_dist = clamp(tr.kmh * 2.4 + 300.0, 420.0, 900.0)
	world = World.new()
	add_child(world)
	world.build(s.road, theme, draw_dist)
	await get_tree().process_frame
	cam = Camera3D.new()
	cam.far = draw_dist + 400.0
	cam.near = 0.25
	cam.fov = fov_now
	add_child(cam)
	cam.current = true
	me_view = _add_bike(s.me)
	for f in s.foes:
		_add_bike(f)
	await get_tree().process_frame
	_build_cars(theme)
	sparks = _particles(Color(1.0, 0.75, 0.25), 0.1, 0.45, 26, 70.0, Vector2(3, 11), -9.0)
	impact = _particles(Color(1.0, 0.9, 0.5), 0.14, 0.28, 14, 90.0, Vector2(2, 7), -3.0)
	smoke = _particles(Color(0.8, 0.8, 0.85, 1.0), 0.5, 0.5, 6, 40.0, Vector2(0.5, 2), 1.0)
	dust = _particles(Color(theme.grass[0]).lightened(0.2), 0.32, 0.4, 7, 60.0, Vector2(1, 4), -6.0)
	world.update_visibility(s.me.s, draw_dist)

func _add_bike(r: Sim.Rider) -> BikeView:
	var v := BikeView.new()
	add_child(v)
	v.setup(r, sim.road)
	views.append(v)
	return v

func _build_cars(theme: Dictionary) -> void:
	var scene: PackedScene = load("res://models/cars.glb")
	var inst: Node = scene.instantiate()
	var meshes := {}
	for c in inst.get_children():
		if c is MeshInstance3D:
			meshes[str(c.name)] = c.mesh
	inst.free()
	var by_col := {}
	for c in sim.cars:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[c.kind]
		var key: String = c.color.to_html()
		if not by_col.has(key):
			var m := World.shared_material([c.color])
			m.set_shader_parameter("ambient", Vector3.ONE * 0.62)
			by_col[key] = m
		mi.material_override = by_col[key]
		mi.visible = false
		add_child(mi)
		car_nodes.append(mi)

func _fx(p: CPUParticles3D, at: Vector3) -> void:
	p.global_position = at
	p.restart()
	p.emitting = true

func handle_event(e: Array) -> void:
	match e[0]:
		"hit":
			var f: Sim.Rider = e[1]
			_fx(impact, sim.road.world(f.s, f.d, 1.25))
			shake = max(shake, 0.05)
		"ko":
			var f2: Sim.Rider = e[1]
			_fx(sparks, sim.road.world(f2.s, f2.d, 0.5))
		"crash":
			_fx(sparks, sim.road.world(sim.me.s, sim.me.d, 0.4))
			shake = 0.42
		"hurt":
			shake = max(shake, 0.16)
		"dust":
			if Engine.get_process_frames() % 6 == 0:
				_fx(dust, sim.road.world(sim.me.s, sim.me.d, 0.1))

func _process(delta: float) -> void:
	if sim == null or cam == null or car_nodes.size() != sim.cars.size() or impact == null:
		return
	var me := sim.me
	world.update_visibility(me.s, draw_dist)
	for v in views:
		v.refresh(delta, me.s)
	for i in sim.cars.size():
		var c: Sim.Car = sim.cars[i]
		var node: MeshInstance3D = car_nodes[i]
		var dist: float = abs(c.s - me.s)
		var vis: bool = dist < draw_dist * 0.85 and c.s > 2.0 and c.s < sim.road.length - 2.0
		node.visible = vis
		if vis:
			var p := sim.road.world(c.s, c.d)
			var f := sim.road.fwd_at(c.s)
			if c.v < 0.0:
				f = -f
			node.global_transform = Transform3D(Basis.looking_at(f, Vector3.UP), p)
	# slide smoke
	if me.state == Sim.RIDE and me.slide and Engine.get_process_frames() % 5 == 0:
		_fx(smoke, sim.road.world(me.s - 0.6, me.d, 0.1))
	_update_camera(delta)

func _update_camera(delta: float) -> void:
	var me := sim.me
	var pct: float = me.v / max(1.0, me.top)
	var falling := me.state == Sim.DOWN
	var focus_s: float = me.fly_s if falling else me.s
	var focus_d: float = me.fly_d if falling else me.d
	cam_d += (focus_d * 0.82 - cam_d) * min(1.0, delta * 6.0)
	var want_dist: float = lerp(3.9, 5.0, pct) + (1.8 if falling else 0.0)
	cam_dist += (want_dist - cam_dist) * min(1.0, delta * 2.5)
	var back: float = focus_s - cam_dist
	var cp := sim.road.world(max(1.0, back), cam_d, cam_h + (0.6 if falling else 0.0))
	var look_ahead: float = lerp(7.0, 12.0, pct)
	var lp := sim.road.world(focus_s + look_ahead, lerp(cam_d, focus_d, 0.6) + me.psi * 2.0, cam_look_h)
	if shake > 0.0:
		shake = max(0.0, shake - delta * 1.1)
		var sx := randf_range(-shake, shake)
		var sy := randf_range(-shake, shake)
		cp += Vector3(sx, sy, 0.0)
	var want_roll: float = -me.lean * 0.16
	cam_roll += (want_roll - cam_roll) * min(1.0, delta * 5.0)
	if debug_close:
		var c0: Vector3 = sim.road.world(focus_s + 2.4, focus_d - 2.6, 1.5)
		cam.look_at_from_position(c0, sim.road.world(focus_s, focus_d, 0.8), Vector3.UP)
		cam.fov = 45.0
		return
	cam.look_at_from_position(cp, lp, Vector3.UP)
	cam.rotate_object_local(Vector3.BACK, cam_roll)
	var want_fov: float = lerp(60.0, 80.0, pct * pct)
	fov_now += (want_fov - fov_now) * min(1.0, delta * 3.0)
	cam.fov = fov_now
