class_name Incident extends Node3D
# A little scene by the road, played out with a vehicle and people on foot, purely to look at:
#   "arrest": a police car pulls up behind, the officer cuffs the rider and takes him away;
#   "medic":  an ambulance pulls up, two paramedics carry the rider off on a stretcher;
#   "joy":    you after the line in the top three: off the bike, arms up, champagne;
#   "rage":   you out of the top three or with a wrecked bike: kick the bike over, throw the helmet.
# Everything is laid out in road space (s along, d across) and turned into the world each frame.

signal finished

var kind := ""
var sim: Sim
var r: Sim.Rider
var road: Road
var t := 0.0
var movie := false       # your own end of the race: a little quicker to start, and a camera to go with it
var done := false
var side := 1.0          # which edge the vehicle pulls over to

# vehicle
var car: Node3D
var car_s := 0.0
var car_d := 0.0
var car_v := 0.0
var lights: Array = []
var cs := 0.0            # where it stops
var cd := 0.0
var s_from := 0.0
var lane_in := 0.0       # the lane it comes up in
var s2 := 1.0            # from the rider towards the vehicle, across the road
var t_arrive := 4.0
var t_leave := -1.0
# people
var crew: Array[ActorView] = []
var vict: ActorView
var vs := 0.0            # the victim where he lies
var vd := 0.0
var stretcher: MeshInstance3D
var plan: Array = []     # [name, start, end] phases
var helmet_prop: MeshInstance3D
var helm_p := Vector3.ZERO
var helm_v := Vector3.ZERO
var foam: CPUParticles3D
var cam_target := Vector3.ZERO
var cam_dir := Vector3.BACK   # from what the camera looks at towards the camera
var cam_r := 4.2
var cam_h := 1.3
var face_yaw := 0.0       # your scenes: you face the road, the camera stands on it

static var _car_meshes := {}
static var _stretch_mesh: BoxMesh

func setup(k: String, s: Sim, who: Sim.Rider, as_movie := false) -> void:
	kind = k
	sim = s
	r = who
	road = s.rd(r)
	movie = as_movie
	if kind == "arrest" or kind == "medic":
		vs = r.fly_s
		vd = r.fly_d
		side = 1.0 if vd >= -0.5 else -1.0
		var lim: float = road.edge + 0.8
		if kind == "arrest":
			# the police car stops right behind him, in his lane
			cd = clamp(vd, -lim, lim)
			cs = vs - 7.0
			# not on top of his bike if it lies behind him
			if abs(r.d - cd) < 2.4 and r.s < vs + 2.0:
				cs = min(cs, r.s - 4.6)
		else:
			# the ambulance pulls up alongside, one lane over, its back doors level with him
			s2 = -1.0 if vd >= 0.0 else 1.0
			cd = clamp(vd + 3.4 * s2, -lim, lim)
			if abs(cd - vd) < 2.6:
				s2 = -s2
				cd = clamp(vd + 3.4 * s2, -lim, lim)
			cs = vs + 1.4
			if abs(r.d - cd) < 2.4 and abs(r.s - cs) < 4.2:
				cs = r.s + 4.4
		lane_in = cd
		s_from = cs - (45.0 if movie else 85.0)
		t_arrive = 3.2 if movie else 4.5
		_make_car("police" if kind == "arrest" else "ambulance")
		vict = _actor(ActorView.racer(r.look), int(r.look.helmet))
		if kind == "arrest":
			crew.append(_actor(ActorView.uniform(ActorView.COP), 0, true))
		else:
			crew.append(_actor(ActorView.uniform(ActorView.MEDIC), 0))
			crew.append(_actor(ActorView.uniform(ActorView.MEDIC), 0))
			if _stretch_mesh == null:
				_stretch_mesh = BoxMesh.new()
				_stretch_mesh.size = Vector3(0.62, 0.1, 1.95)
				var m := StandardMaterial3D.new()
				m.albedo_color = Color("#e8e6df")
				_stretch_mesh.material = m
			stretcher = MeshInstance3D.new()
			stretcher.mesh = _stretch_mesh
			add_child(stretcher)
		for a in crew:
			a.visible = false
		var f := road.fwd_at(vs)
		var rg := Vector3(f.x, 0.0, f.z).normalized().cross(Vector3.UP)
		# from the side away from the ambulance, so it does not stand in the way; for the police, from the middle of the road
		var cside: float = -s2 if kind == "medic" else (-1.0 if vd > 0.0 else 1.0)
		cam_dir = (rg * cside * 0.62 + Vector3(f.x, 0.0, f.z).normalized() * 0.78).normalized()
		cam_r = 8.5
		cam_h = 2.6
	else:
		# your own scene after the race: the bike stands on its side stand on the verge, you beside it
		vs = r.s
		if r.state == Sim.DOWN:
			# the bike is a wreck already, lying where it ended up
			vd = r.d
		else:
			vd = road.edge + 1.0
			r.d = vd
			r.v = 0.0
			r.psi = 0.3
			r.lean = -0.16
		vict = _actor(ActorView.racer(r.look), int(r.look.helmet))
		var f2 := road.fwd_at(vs)
		var fh := Vector3(f2.x, 0.0, f2.z).normalized()
		var facing := (-fh.cross(Vector3.UP) * 0.78 + fh * 0.62).normalized()
		face_yaw = atan2(-facing.x, -facing.z)
		cam_dir = facing
		cam_r = 4.3
		cam_h = 1.25

func _actor(cols: Array, helmet: int, with_cap := false) -> ActorView:
	var a := ActorView.new()
	add_child(a)
	a.sim_ref = sim
	a.road = road
	a.build_actor(cols, helmet, with_cap)
	return a

func _make_car(model: String) -> void:
	if _car_meshes.is_empty():
		var inst: Node = (load("res://models/cars.glb") as PackedScene).instantiate()
		for c in inst.get_children():
			if c is MeshInstance3D:
				_car_meshes[str(c.name)] = c.mesh
		inst.free()
	car = Node3D.new()
	add_child(car)
	var mi := MeshInstance3D.new()
	mi.mesh = _car_meshes.get(model)
	mi.material_override = World.shared_material([Color.WHITE])
	car.add_child(mi)
	# flashing lights on the bar, and the word on the sides
	var police := model == "police"
	var bar := Vector3(0, 1.52, 0.25) if police else Vector3(0, 2.3, -1.7)
	for i in 2:
		var b := BoxMesh.new()
		b.size = Vector3(0.34, 0.12, 0.2)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.disable_fog = true
		b.material = m
		var l := MeshInstance3D.new()
		l.mesh = b
		l.position = bar + Vector3(-0.32 if i == 0 else 0.32, 0, 0)
		car.add_child(l)
		lights.append(m)
	for sd in [-1.0, 1.0]:
		var lb := Label3D.new()
		lb.text = "ПОЛИЦИЯ" if police else "СКОРАЯ  03"
		if UiKit.big != null:
			lb.font = UiKit.big
		lb.font_size = 72
		lb.outline_size = 0
		lb.shaded = false
		lb.double_sided = false
		lb.modulate = Color("#1f4fb8") if police else Color("#d9232e")
		lb.pixel_size = 0.0042 if police else 0.0048
		lb.position = Vector3(sd * (0.915 if police else 1.015), 0.86 if police else 1.42, 0.0)
		lb.rotation = Vector3(0, sd * PI * 0.5, 0)
		car.add_child(lb)
	car_s = s_from
	car_d = lane_in

# ---------- helpers ----------
func W(s: float, d: float, y := 0.0) -> Vector3:
	return road.world(s, d, y)

# a heading in the world for a step from (s0, d0) to (s1, d1)
func yaw_to(s0: float, d0: float, s1: float, d1: float) -> float:
	var v := W(s1, d1) - W(s0, d0)
	if Vector2(v.x, v.z).length() < 0.01:
		return yaw_along(s0)
	return atan2(-v.x, -v.z)

func yaw_along(s: float, back := false) -> float:
	var f := road.fwd_at(s)
	if back:
		f = -f
	return atan2(-f.x, -f.z)

func lerp_sd(a: Vector2, b: Vector2, k: float) -> Vector2:
	return a.lerp(b, clamp(k, 0.0, 1.0))

func walk_time(a: Vector2, b: Vector2, v: float) -> float:
	return max(0.3, (W(b.x, b.y) - W(a.x, a.y)).length() / v)

func _place_car() -> void:
	var p := W(car_s, car_d)
	var f := road.fwd_at(car_s)
	car.global_transform = Transform3D(Basis.looking_at(f, Vector3.UP), p)
	var blink: bool = int(t * 6.0) % 2 == 0
	if lights.size() == 2:
		var police: bool = kind == "arrest"
		lights[0].albedo_color = (Color(0.15, 0.35, 1.0) if blink else Color(0.05, 0.08, 0.2)) if not police else (Color(0.15, 0.35, 1.0) if blink else Color(1.0, 0.1, 0.1))
		lights[1].albedo_color = (Color(0.05, 0.08, 0.2) if blink else Color(0.15, 0.35, 1.0)) if not police else (Color(1.0, 0.1, 0.1) if blink else Color(0.15, 0.35, 1.0))

# the vehicle comes up from behind, slows and pulls over; later pulls out and drives off
func _drive(delta: float) -> void:
	if t_leave < 0.0:
		var k: float = clamp(t / t_arrive, 0.0, 1.0)
		var e: float = 1.0 - pow(1.0 - k, 2.4)
		car_s = lerp(s_from, cs, e)
		car_d = cd
	else:
		var tl: float = t - t_leave
		car_v = min(car_v + 4.0 * delta, 22.0)
		car_s += car_v * delta
		var lane2: float = 5.4 if road.edge > 7.0 else 0.0
		car_d = lerp(cd, lane2, smoothstep(0.0, 2.0, tl))
		if tl > (3.5 if movie else 7.0):
			_end()
	_place_car()

func _end() -> void:
	if done:
		return
	done = true
	finished.emit()

# ---------- the scenes ----------
func step(delta: float) -> void:
	if done:
		return
	t += delta
	match kind:
		"arrest":
			_arrest(delta)
		"medic":
			_medic(delta)
		"joy":
			_joy(delta)
		"rage":
			_rage(delta)

func _arrest(delta: float) -> void:
	_drive(delta)
	var cop: ActorView = crew[0]
	var door := Vector2(cs + 0.6, cd - 1.25)
	var rear := Vector2(cs - 0.6, cd - 1.25)
	var stand := Vector2(vs, vd)
	var behind := Vector2(vs - 0.75, vd)
	var t0: float = t_arrive + 0.4
	var t1: float = t0 + walk_time(door, behind, 1.9)
	var t2: float = t1 + 1.7
	var t3: float = t2 + walk_time(stand, rear, 1.15)
	var face: float = yaw_along(vs)
	cam_target = W(vs, vd, 1.0).lerp(W(cs, cd, 1.0), 0.35)
	# the rider: lies, gets up when the car stops, hands up, then cuffed and led to the car
	if t < t_arrive:
		vict.place_lying(W(vs, vd), face)
		vict.pose("lie")
	elif t < t_arrive + 0.9:
		var k: float = (t - t_arrive) / 0.9
		vict.place(W(vs, vd), face)
		vict.pose("getup", 0.0, k)
	elif t < t1:
		vict.place(W(vs, vd), face)
		vict.pose("hands_up")
	elif t < t2:
		vict.place(W(vs, vd), face)
		vict.pose("cuffed")
	elif t < t3:
		var k2: float = (t - t2) / (t3 - t2)
		var p := lerp_sd(stand, rear, k2)
		vict.place(W(p.x, p.y), yaw_to(stand.x, stand.y, rear.x, rear.y))
		vict.pose("cuffed_walk", t - t2)
	else:
		vict.visible = false
	# the officer: out of the door, round behind the rider, cuffs, walks him to the car
	if t < t0 - 0.3:
		cop.visible = false
	elif t < t1:
		cop.visible = true
		var k3: float = clamp((t - t0) / (t1 - t0), 0.0, 1.0)
		var p2 := lerp_sd(door, behind, k3)
		cop.place(W(p2.x, p2.y), yaw_to(door.x, door.y, behind.x, behind.y) if k3 < 1.0 else face)
		cop.pose("walk" if k3 < 1.0 else "stand", t - t0)
	elif t < t2:
		cop.place(W(behind.x, behind.y), face)
		cop.pose("cuff")
	elif t < t3 + 0.3:
		var k4: float = clamp((t - t2 - 0.3) / (t3 - t2), 0.0, 1.0)
		var p3 := lerp_sd(Vector2(behind.x, behind.y), rear + Vector2(-0.9, 0.0), k4)
		cop.place(W(p3.x, p3.y), yaw_to(behind.x, behind.y, rear.x - 0.9, rear.y))
		cop.pose("escort", t - t2)
	else:
		cop.visible = false
	if t > t3 + 0.6 and t_leave < 0.0:
		t_leave = t
		sim.clear_body(r, side)

func _medic(delta: float) -> void:
	_drive(delta)
	var back := Vector2(cs - 3.2, cd)
	var at := Vector2(vs, vd + s2 * 0.95)
	var t0: float = t_arrive + 0.5
	var t1: float = t0 + walk_time(back, at, 1.5)
	var t2: float = t1 + 0.6     # down
	var t3: float = t2 + 0.9     # onto the stretcher
	var t4: float = t3 + 0.6     # up
	var t5: float = t4 + walk_time(at, back, 1.35)
	var t6: float = t5 + 0.7     # into the back of the van
	cam_target = W(vs, vd, 1.0).lerp(W(cs, cd, 1.0), 0.35)
	# where the stretcher is and which way it points
	var sp: Vector2
	var yaw: float
	var h := 0.8
	if t < t1:
		var k: float = clamp((t - t0) / (t1 - t0), 0.0, 1.0)
		sp = lerp_sd(back, at, k)
		yaw = yaw_to(back.x, back.y, at.x, at.y)
	elif t < t4:
		sp = at
		yaw = yaw_to(back.x, back.y, at.x, at.y)
		if t < t2:
			h = lerp(0.8, 0.3, (t - t1) / 0.6)
		elif t < t3:
			h = 0.3
		else:
			h = lerp(0.3, 0.8, (t - t3) / 0.6)
	elif t < t5:
		var k2: float = (t - t4) / (t5 - t4)
		sp = lerp_sd(at, back, k2)
		yaw = yaw_to(at.x, at.y, back.x, back.y)
	else:
		# slides into the back of the van
		var k3: float = clamp((t - t5) / 0.7, 0.0, 1.0)
		sp = back + Vector2(2.2 * k3, 0.0)
		yaw = yaw_along(back.x, true)
		h = 0.8 + 0.2 * k3
	var center := W(sp.x, sp.y, 0.0)
	var dir := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	stretcher.global_transform = Transform3D(Basis(Vector3.UP, yaw), center + Vector3.UP * h)
	stretcher.visible = t >= t0 - 0.2 and t < t6
	# the two paramedics, one at each end
	var bend := 0.0
	if t >= t1 and t < t4:
		bend = smoothstep(0.0, 1.0, clamp((t - t1) / 0.5, 0.0, 1.0)) * (1.0 - smoothstep(0.0, 1.0, clamp((t - t3) / 0.6, 0.0, 1.0)))
	for i in 2:
		var m: ActorView = crew[i]
		m.visible = t >= t0 - 0.2 and t < t5 + 0.2
		if not m.visible:
			continue
		var end_off: float = 1.25 if i == 0 else -1.25
		var p := center + dir * end_off
		m.place(p, yaw if i == 0 else yaw)
		var walking: bool = (t < t1 and t > t0) or (t > t4 and t < t5)
		if bend > 0.01:
			m.pose("bend", 0.0, bend)
		else:
			m.pose("carry_walk" if walking else "carry", t + (0.5 if i == 1 else 0.0))
	# the rider: lies until they lift him, then rides on the stretcher
	var face: float = yaw_along(vs)
	if t < t2:
		vict.place_lying(W(vs, vd), face)
	elif t < t3:
		var k4: float = smoothstep(0.0, 1.0, (t - t2) / 0.9)
		var from := W(vs, vd)
		var to := center - dir * 0.9
		vict.place_lying(from.lerp(to, k4), lerp_angle(face, yaw + PI, k4), lerp(0.12, 0.38, k4))
	elif t < t6:
		vict.place_lying(center - dir * 0.9, yaw + PI, h + 0.08)
	else:
		vict.visible = false
	vict.pose("lie")
	if t > t6 and t_leave < 0.0:
		t_leave = t
		stretcher.visible = false
		sim.clear_body(r, side)

# your own finish in the top three: off the bike, arms up, a bottle of champagne
func _joy(delta: float) -> void:
	var base := Vector2(vs + 0.4, vd - 1.1)
	var p := W(base.x, base.y)
	var face: float = face_yaw
	cam_target = p + Vector3.UP * 1.1
	vict.visible = true
	if t < 2.6:
		vict.place(p, face, 0.22 * max(0.0, sin(t * 7.0)))
		vict.pose("cheer", t)
	elif t < 3.0:
		vict.show_bottle(true)
		vict.place(p, face)
		vict.pose("shake", t)
	elif t < 4.2:
		vict.place(p, face)
		vict.pose("shake", t)
	else:
		vict.place(p, face)
		vict.pose("spray", t)
		if foam == null:
			foam = _foam()
		var fw := Basis(Vector3.UP, face) * Vector3(0, 0, -1)
		foam.global_transform = Transform3D(Basis.looking_at((Vector3.UP + fw * 0.35 + fw.cross(Vector3.UP) * 0.3).normalized(), fw), vict.bottle_tip())
		foam.emitting = true
	if t > 8.5:
		_end()

func _foam() -> CPUParticles3D:
	var f := CPUParticles3D.new()
	f.amount = 90
	f.lifetime = 1.1
	f.direction = Vector3(0, 0, -1)
	f.spread = 14.0
	f.initial_velocity_min = 3.5
	f.initial_velocity_max = 6.0
	f.gravity = Vector3(0, -7.0, 0)
	f.scale_amount_min = 0.03
	f.scale_amount_max = 0.07
	var q := SphereMesh.new()
	q.radius = 0.5
	q.height = 1.0
	q.radial_segments = 6
	q.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.97, 0.82)
	q.material = m
	f.mesh = q
	add_child(f)
	return f

# your own bad end: stomps, kicks the bike over, pulls the helmet off and throws it
func _rage(delta: float) -> void:
	var base := Vector2(vs + 0.2, vd - 1.0)
	var p := W(base.x, base.y)
	var to_bike: float = yaw_to(base.x, base.y, vs, vd)
	var away: float = face_yaw
	cam_target = p + Vector3.UP * 1.0
	vict.visible = true
	if t < 1.4:
		vict.place(p, away)
		vict.pose("stomp", t)
	elif t < 2.2:
		var k: float = (t - 1.4) / 0.8
		vict.place(p, to_bike)
		vict.pose("kick", 0.0, k)
		if k > 0.45 and r.state == Sim.RIDE:
			# the bike goes over
			r.lean = lerp(-0.16, 1.45, smoothstep(0.0, 1.0, (k - 0.45) / 0.55))
	elif t < 2.8:
		if r.state == Sim.RIDE:
			r.lean = 1.45
		vict.place(p, away)
		vict.pose("helmet_off", 0.0, (t - 2.2) / 0.6)
	elif t < 3.5:
		var k2: float = (t - 2.8) / 0.7
		if vict.has_helmet() and k2 > 0.0:
			vict.take_off_helmet()
			helmet_prop = _helmet()
		vict.place(p, away)
		vict.pose("throw", 0.0, k2)
		if helmet_prop != null:
			if k2 < 0.75:
				helm_p = vict.hand_world(true)
				# across the picture and away from the camera, not into it
				var fwd := Basis(Vector3.UP, away) * Vector3(0, 0, -1)
				helm_v = fwd.cross(Vector3.UP) * 5.5 - fwd * 2.0 + Vector3.UP * 4.5
			else:
				_fly_helmet(delta)
	else:
		vict.place(p, away)
		vict.pose("despair" if t > 4.6 else "stomp", t)
		_fly_helmet(delta)
	if t > 8.0:
		_end()

func _helmet() -> MeshInstance3D:
	if helmet_prop != null:
		return helmet_prop
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.3
	var m := StandardMaterial3D.new()
	m.albedo_color = vict.helmet_col
	sm.material = m
	mi.mesh = sm
	add_child(mi)
	return mi

func _fly_helmet(delta: float) -> void:
	if helmet_prop == null:
		return
	helm_v.y -= 9.81 * delta
	helm_p += helm_v * delta
	var ground: float = road.world(vs, vd).y + 0.15
	if helm_p.y < ground:
		helm_p.y = ground
		helm_v.y = abs(helm_v.y) * 0.35
		helm_v.x *= 0.6
		helm_v.z *= 0.6
	helmet_prop.global_position = helm_p
	helmet_prop.rotate_x(delta * 9.0)
