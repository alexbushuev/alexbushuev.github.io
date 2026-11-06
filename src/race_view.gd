class_name RaceView extends Node3D
# Everything visible during a race: world, bikes, traffic, camera, effects. Reads the Sim; never changes it.

var sim: Sim
var world: World
var cam: Camera3D
var views: Array[BikeView] = []
var ped_views: Array[PedView] = []
var view_of := {}           # Sim.Rider -> BikeView
var incidents: Array[Incident] = []
var inc_seen := {}
var movie: Incident = null  # your own end-of-race scene, with its own camera
var ped_of := {}          # Sim.Ped -> PedView
var me_view: BikeView
var car_nodes: Array[MeshInstance3D] = []
var brake_nodes: Array[Node3D] = []
var brake_box: BoxMesh
var sparks: CPUParticles3D
var smoke: CPUParticles3D
var dust: CPUParticles3D
var impact: CPUParticles3D
var shake := 0.0
var draw_dist := 480.0
var cam_d := 1.8
var cam_dist := 5.0
var cam_h := 2.7
var cam_look_h := -0.2
var fov_now := 56.0
var cam_roll := 0.0
var cam_air := 0.0
var debug_close := false
var last_path := 0

func _particles(col: Color, size: float, life: float, amount: int, spread: float, vel: Vector2, grav: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = col
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
	draw_dist = clamp(s.v_top * 15.0, 450.0, 720.0)
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
	for k in 8:
		var pv := PedView.new()
		add_child(pv)
		pv.build_ped(s)
		ped_views.append(pv)
	await get_tree().process_frame
	_build_cars(theme)
	sparks = _particles(Color(1.0, 0.75, 0.25), 0.06, 0.45, 26, 70.0, Vector2(3, 11), -9.0)
	impact = _particles(Color(1.0, 0.9, 0.5), 0.09, 0.28, 14, 90.0, Vector2(2, 7), -3.0)
	smoke = _particles(Color(0.85, 0.85, 0.88, 0.16), 0.45, 0.4, 5, 40.0, Vector2(0.5, 2), 1.0)
	dust = _particles(Color(theme.grass[0]).lightened(0.2), 0.32, 0.4, 7, 60.0, Vector2(1, 4), -6.0)
	world.update_visibility(s.me.s, draw_dist)

# people crossing: each one the sim has gets a body from the pool, and gives it back when he is gone
func _sync_peds(delta: float, cam_s: float) -> void:
	for pv in ped_views:
		if pv.p != null and not (pv.p in sim.peds):
			ped_of.erase(pv.p)
			pv.p = null
			pv.visible = false
	for p in sim.peds:
		if not ped_of.has(p):
			for pv in ped_views:
				if pv.p == null:
					pv.assign(p)
					ped_of[p] = pv
					break
	for pv in ped_views:
		if pv.p != null:
			pv.refresh_ped(delta, cam_s)

func _add_bike(r: Sim.Rider) -> BikeView:
	var v := BikeView.new()
	add_child(v)
	v.setup(r, sim)
	views.append(v)
	view_of[r] = v
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
		# brake lights: drawn only while the driver is braking
		var lights := Node3D.new()
		lights.visible = false
		var p: Array = {"sedan": [0.55, 0.72, 2.23], "van": [0.84, 1.02, 2.63], "truck": [1.0, 0.85, 3.96]}[c.kind]
		for side in [-1.0, 1.0]:
			var q := MeshInstance3D.new()
			q.mesh = _brake_mesh()
			q.position = Vector3(side * p[0], p[1], p[2])
			lights.add_child(q)
		mi.add_child(lights)
		brake_nodes.append(lights)

func _brake_mesh() -> BoxMesh:
	if brake_box == null:
		brake_box = BoxMesh.new()
		brake_box.size = Vector3(0.42, 0.2, 0.04)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.08, 0.05)
		brake_box.material = m
	return brake_box

func _fx(p: CPUParticles3D, at: Vector3) -> void:
	p.global_position = at
	p.restart()
	p.emitting = true

func handle_event(e: Array) -> void:
	match e[0]:
		"hit":
			var f: Sim.Rider = e[1]
			_fx(impact, sim.rd(f).world(f.s, f.d, 1.25))
			shake = max(shake, 0.05)
		"ko":
			var f2: Sim.Rider = e[1]
			_fx(sparks, sim.rd(f2).world(f2.s, f2.d, 0.5))
		"crash":
			_fx(sparks, sim.rd(sim.me).world(sim.me.s, sim.me.d, 0.4))
			shake = 0.42
		"hurt":
			shake = max(shake, 0.16)
		"scrape":
			_fx(sparks, sim.rd(sim.me).world(sim.me.s, sim.me.d, 0.5))
			shake = max(shake, 0.12)
		"bump":
			shake = max(shake, 0.1)
		"land":
			var hv: float = float(e[1]) if e[1] != null else 2.0
			shake = max(shake, clamp(hv * 0.035, 0.03, 0.3))
			if hv > 3.0:
				_fx(dust, sim.rd(sim.me).world(sim.me.s, sim.me.d, 0.1))
		"dust":
			if Engine.get_process_frames() % 6 == 0:
				_fx(dust, sim.rd(sim.me).world(sim.me.s, sim.me.d, 0.1))

func _process(delta: float) -> void:
	if sim == null or cam == null or car_nodes.size() != sim.cars.size() or impact == null:
		return
	var me := sim.me
	world.update_visibility(me.ps, draw_dist)
	for v in views:
		v.refresh(delta, me.ps)
	_sync_peds(delta, me.ps)
	_check_incidents(delta)
	if movie != null:
		movie.step(delta)
	for i in sim.cars.size():
		var c: Sim.Car = sim.cars[i]
		var node: MeshInstance3D = car_nodes[i]
		var dist: float = abs(c.s - me.ps)
		var vis: bool = dist < draw_dist * 0.85 and c.s > 2.0 and c.s < sim.road.length - 2.0
		node.visible = vis
		if vis:
			var p := sim.road.world(c.s, c.d)
			var f := sim.road.fwd_at(c.s)
			if c.dir < 0:
				f = -f
			node.global_transform = Transform3D(Basis.looking_at(f, Vector3.UP), p)
			brake_nodes[i].visible = c.braking
	# slide smoke
	if me.state == Sim.RIDE and me.slide and Engine.get_process_frames() % 5 == 0:
		_fx(smoke, sim.rd(me).world(me.s - 0.6, me.d, 0.1))
	_update_camera(delta)

# A rival or a cop lies out of the race near you: the police come for the arrested, the ambulance for the rest.
# Only near you, and no more than two at once: further off nobody would see it.
func _check_incidents(delta: float) -> void:
	for f in sim.foes:
		if inc_seen.has(f):
			continue
		var lying: bool = f.state == Sim.DOWN and (f.out or f.is_cop) and f.run_phase == 0 and f.lie_t > 0.6 and not f.gone
		if not lying:
			continue
		var ahead: float = f.ps - sim.me.ps
		if ahead < -100.0:
			inc_seen[f] = true
			continue
		if ahead > 300.0 or incidents.size() >= 2 or movie != null:
			continue
		inc_seen[f] = true
		var inc := Incident.new()
		add_child(inc)
		inc.setup("arrest" if f.arrested else "medic", sim, f)
		view_of[f].hide_rider = true
		incidents.append(inc)
	for i in range(incidents.size() - 1, -1, -1):
		var inc: Incident = incidents[i]
		inc.step(delta)
		if inc.done or inc.r.ps < sim.me.ps - 400.0:
			if not inc.done:
				sim.clear_body(inc.r, inc.side)
			incidents.remove_at(i)
			inc.queue_free()

# your end of the race as a little film: the scene plays, the camera circles it
func start_movie(kind: String) -> Incident:
	for inc in incidents:
		inc.visible = abs(inc.r.ps - sim.me.ps) < 60.0
	var m := Incident.new()
	add_child(m)
	m.setup(kind, sim, sim.me, true)
	me_view.hide_rider = true
	movie = m
	return m

func _movie_camera(delta: float) -> void:
	var m := movie
	var ang: float = atan2(m.cam_dir.x, m.cam_dir.z) + 0.35 - 0.07 * m.t
	var p: Vector3 = m.cam_target + Vector3(sin(ang), 0.0, cos(ang)) * m.cam_r + Vector3.UP * m.cam_h
	cam.look_at_from_position(p, m.cam_target, Vector3.UP)
	cam.fov = 50.0

func _update_camera(delta: float) -> void:
	if movie != null:
		_movie_camera(delta)
		return
	var me := sim.me
	var pct: float = me.v / max(1.0, me.top)
	var falling := me.state == Sim.DOWN
	var on: Road = sim.rd(me)
	# onto or off a side road: d is now measured from another centreline, keep the camera where it was
	if me.path != last_path:
		var b: Road = sim.road.branches[(me.path if me.path != 0 else last_path) - 1]
		cam_d += (-1.0 if me.path != 0 else 1.0) * b.side * 5.4
		last_path = me.path
	# down: keep both the rider and his bike in the picture while he runs back to it
	var focus_s: float = (me.fly_s + me.s) * 0.5 if falling else me.s
	var focus_d: float = (me.fly_d + me.d) * 0.5 if falling else me.d
	cam_d += (focus_d * 0.82 - cam_d) * min(1.0, delta * 8.0)
	var want_dist: float = lerp(4.8, 5.6, pct) + (2.2 + min(9.0, abs(me.fly_s - me.s) * 0.6) if falling else 0.0)
	cam_dist += (want_dist - cam_dist) * min(1.0, delta * 2.5)
	var back: float = focus_s - cam_dist
	# off a crest the camera goes up with the bike, a little behind it, and keeps the road in view
	var lift: float = (on.height_at(me.s) + me.air_h - on.height_at(back)) if me.air else 0.0
	# lags a little going up, so you see the bike leave the road
	cam_air += (lift - cam_air) * min(1.0, delta * (2.5 if me.air else 4.0))
	var cp := on.world(back if me.path != 0 else max(1.0, back), cam_d, cam_h + (0.6 if falling else 0.0) + max(0.0, cam_air))
	var look_ahead: float = lerp(14.0, 20.0, pct)
	var lp := on.world(focus_s + look_ahead, lerp(cam_d, focus_d, 0.6) + me.psi * 2.0, cam_look_h + max(0.0, cam_air) * 0.5)
	if shake > 0.0:
		shake = max(0.0, shake - delta * 1.1)
		var sx := randf_range(-shake, shake)
		var sy := randf_range(-shake, shake)
		cp += Vector3(sx, sy, 0.0)
	var want_roll: float = -me.lean * 0.08
	cam_roll += (want_roll - cam_roll) * min(1.0, delta * 5.0)
	if debug_close:
		var c0: Vector3 = on.world(focus_s + 2.4, focus_d - 2.6, 1.5 + me.air_h)
		cam.look_at_from_position(c0, on.world(focus_s, focus_d, 0.8 + me.air_h), Vector3.UP)
		cam.fov = 45.0
		return
	cam.look_at_from_position(cp, lp, Vector3.UP)
	cam.rotate_object_local(Vector3.BACK, cam_roll)
	var want_fov: float = lerp(54.0, 62.0, pct * pct)
	fov_now += (want_fov - fov_now) * min(1.0, delta * 3.0)
	cam.fov = fov_now
