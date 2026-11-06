class_name BikeView extends Node3D
# One motorcycle with its rider on screen. Reads a Sim.Rider, draws it. The rider is posed with simple two-bone IK,
# so the same skeleton sits correctly on a moped and on a hyperbike and can punch and kick to any side.

var r: Sim.Rider
var road: Road
var sim_ref: Sim
var lean_node: Node3D
var bike_scene: Node3D
var front: Node3D
var wheel_f: Node3D
var wheel_r: Node3D
var rider_root: Node3D
var skel: Skeleton3D
var meta: Dictionary
var J := {}        # joint rest positions, Godot axes
var bones := {}
var pal_mat: ShaderMaterial
var bike_mat: ShaderMaterial
var weapon_nodes := {}
var blob: MeshInstance3D
var spin_a := 0.0
var tuck := 0.0
var hit_flash := 0.0
var flail_t := 0.0
var cop_lights: MeshInstance3D
var _detached := false
var body_yaw := 0.0
var run_clock := 0.0

static var _wheel_mat: ShaderMaterial
static var _blob_mesh: QuadMesh
static var _weapons: Dictionary = {}

const D2G := Vector3(1, 1, 1)

static func to_g(v: Array) -> Vector3:
	return Vector3(v[0], v[2], -v[1])

func _paint_material(pal: Array, ambient := 0.62) -> ShaderMaterial:
	var m := World.shared_material(pal)
	m.set_shader_parameter("ambient", Vector3.ONE * ambient)
	return m

func setup(rider: Sim.Rider, sim: Sim) -> void:
	r = rider
	sim_ref = sim
	road = sim.road if sim != null else null
	var art: String = r.bike.art
	meta = D.models.bikes[art]
	lean_node = Node3D.new()
	add_child(lean_node)
	var bs: PackedScene = load("res://models/bike_%s.glb" % art)
	bike_scene = bs.instantiate()
	lean_node.add_child(bike_scene)
	# bike paint
	var paint_i: int = r.look.paint
	var c1: Color
	var c2: Color
	if paint_i < 0:
		c1 = Color("#e9e6dc")
		c2 = Color("#1f3f8a")
	else:
		var p: Dictionary = D.gear.paints[paint_i]
		c1 = Color(p.c)
		c2 = Color(p.d)
	bike_mat = _paint_material([c1, c2])
	if _wheel_mat == null:
		_wheel_mat = _paint_material([Color.WHITE])
	front = bike_scene.find_child("front", true, false)
	wheel_f = bike_scene.find_child("wheel_f", true, false)
	wheel_r = bike_scene.find_child("wheel_r", true, false)
	(bike_scene.find_child("chassis", true, false) as MeshInstance3D).material_override = bike_mat
	(front as MeshInstance3D).material_override = bike_mat
	(wheel_f as MeshInstance3D).material_override = _wheel_mat
	(wheel_r as MeshInstance3D).material_override = _wheel_mat
	# rider
	rider_root = Node3D.new()
	lean_node.add_child(rider_root)
	var rs: PackedScene = load("res://models/rider.glb")
	var rig: Node3D = rs.instantiate()
	rider_root.add_child(rig)
	skel = rig.find_child("*", true, false) as Skeleton3D
	if skel == null:
		for n in rig.find_children("*", "Skeleton3D", true, false):
			skel = n
	var o: Dictionary = r.look.outfit
	var cols := [Color(o.jacket), Color(o.stripe), Color(o.pants), Color(o.boots), Color(o.glove), Color(o.skin), Color(o.helmet), Color(o.hs), Color(o.sleeve)]
	pal_mat = _paint_material(cols)
	var helm: int = r.look.helmet
	for n in rig.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.material_override = pal_mat
		if mi.name == "helm_full":
			mi.visible = helm >= 2
		elif mi.name == "helm_open":
			mi.visible = helm == 1
	for bn in D.models.rider.joints:
		J[bn] = to_g(D.models.rider.joints[bn])
		bones[bn] = skel.find_bone(bn)
	_make_weapons()
	blob = MeshInstance3D.new()
	blob.mesh = blob_mesh()
	add_child(blob)
	blob.position = Vector3(0, 0.03, 0)
	if r.is_cop:
		_make_cop_lights()
	_set_pose_static()

# a soft dark patch instead of real shadows, cheap on phones
static func blob_mesh() -> QuadMesh:
	if _blob_mesh == null:
		_blob_mesh = QuadMesh.new()
		_blob_mesh.size = Vector2(1.6, 2.6)
		_blob_mesh.orientation = PlaneMesh.FACE_Y
		var img := Image.create_empty(32, 32, false, Image.FORMAT_LA8)
		for y in 32:
			for x in 32:
				var q: float = Vector2((x - 15.5) / 16.0, (y - 15.5) / 16.0).length()
				img.set_pixel(x, y, Color(0, 0, 0, clamp(1.0 - q, 0.0, 1.0) * 0.55))
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.disable_fog = true
		_blob_mesh.material = m
	return _blob_mesh

func _make_cop_lights() -> void:
	var b := BoxMesh.new()
	b.size = Vector3(0.34, 0.07, 0.1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.2, 0.4, 1.0)
	m.disable_fog = true
	b.material = m
	cop_lights = MeshInstance3D.new()
	cop_lights.mesh = b
	var sy: Array = meta.seat
	cop_lights.position = Vector3(0, sy[1] + 0.34, -(sy[0] - 0.42))
	lean_node.add_child(cop_lights)

func _make_weapons() -> void:
	if _weapons.is_empty():
		var ws: PackedScene = load("res://models/weapons.glb")
		var inst: Node = ws.instantiate()
		for c in inst.get_children():
			if c is MeshInstance3D:
				_weapons[str(c.name)] = c.mesh
		inst.free()
	for w in ["baton", "chain"]:
		for side in ["L", "R"]:
			var att := BoneAttachment3D.new()
			skel.add_child(att)
			att.bone_name = "arm_l." + side
			var mi := MeshInstance3D.new()
			mi.mesh = _weapons[w]
			mi.material_override = _wheel_mat
			att.add_child(mi)
			# at the fist; forearm rest points down, so the weapon carries on in that direction when punching
			mi.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, -0.28, 0.01))
			mi.visible = false
			weapon_nodes[w + side] = mi

func _set_pose_static() -> void:
	tuck = deg_to_rad(float(meta.tuck))

# ---------- IK ----------
func _aim(from_dir: Vector3, to_dir: Vector3) -> Quaternion:
	return Quaternion(from_dir.normalized(), to_dir.normalized())

func _two_bone(a: Vector3, target: Vector3, la: float, lb: float, pole: Vector3) -> Array:
	var d: Vector3 = target - a
	var l: float = clamp(d.length(), 0.05, (la + lb) * 0.999)
	var dir: Vector3 = d.normalized()
	var cos_a: float = clamp((la * la + l * l - lb * lb) / (2.0 * la * l), -1.0, 1.0)
	var sin_a: float = sqrt(1.0 - cos_a * cos_a)
	var perp: Vector3 = (pole - dir * pole.dot(dir)).normalized()
	var e: Vector3 = a + dir * la * cos_a + perp * la * sin_a
	var t2: Vector3 = a + dir * l
	return [e, t2]

const DOWN_V := Vector3(0, -1, 0)

func _pose(hips: Vector3, q_hips: Quaternion, q_spine: Quaternion, q_head: Quaternion,
		hand_l: Vector3, hand_r: Vector3, foot_l: Vector3, foot_r: Vector3) -> void:
	skel.set_bone_pose_position(bones["hips"], hips)
	skel.set_bone_pose_rotation(bones["hips"], q_hips)
	var spine_p: Vector3 = hips + q_hips * (J["spine"] - J["hips"])
	skel.set_bone_pose_rotation(bones["spine"], q_hips.inverse() * q_spine)
	skel.set_bone_pose_rotation(bones["head"], q_spine.inverse() * q_head)
	# arms
	for side in [["L", hand_l, -1.0], ["R", hand_r, 1.0]]:
		var sn: String = side[0]
		var sh: Vector3 = spine_p + q_spine * (J["arm_u." + sn] - J["spine"])
		var res := _two_bone(sh, side[1], 0.29, 0.28, Vector3(side[2] * 0.7, -0.5, 0.6))
		var qu := _aim(DOWN_V, res[0] - sh)
		var ql := _aim(DOWN_V, res[1] - res[0])
		skel.set_bone_pose_rotation(bones["arm_u." + sn], q_spine.inverse() * qu)
		skel.set_bone_pose_rotation(bones["arm_l." + sn], qu.inverse() * ql)
	# legs
	for side in [["L", foot_l, -1.0], ["R", foot_r, 1.0]]:
		var sn: String = side[0]
		var hp: Vector3 = hips + q_hips * (J["leg_u." + sn] - J["hips"])
		var res := _two_bone(hp, side[1], 0.42, 0.37, Vector3(side[2] * 0.35, 0.2, -1.0))
		var qu := _aim(DOWN_V, res[0] - hp)
		var ql := _aim(DOWN_V, res[1] - res[0])
		skel.set_bone_pose_rotation(bones["leg_u." + sn], q_hips.inverse() * qu)
		skel.set_bone_pose_rotation(bones["leg_l." + sn], qu.inverse() * ql)

func _pose_riding(delta: float, near: bool) -> void:
	var sy: Array = meta.seat
	var by: Array = meta.bar
	var py: Array = meta.peg
	var bw: float = meta.bw
	var hang: float = clamp(r.lean * 0.55, -0.2, 0.2)
	var hips := Vector3(hang, float(sy[1]) + 0.13, -float(sy[0]))
	var t_extra: float = 0.0
	if r.is_me or near:
		t_extra = clamp(r.v / max(1.0, r.top), 0.0, 1.0) * deg_to_rad(10.0)
	var q_spine := Quaternion(Vector3.RIGHT, -(tuck + t_extra))
	q_spine = Quaternion(Vector3.BACK, -hang * 1.2) * q_spine
	var q_hips := Quaternion(Vector3.RIGHT, -(tuck + t_extra) * 0.35)
	var q_head := Quaternion(Vector3.RIGHT, -(tuck + t_extra) * 0.12)
	var steer: float = r.sv if r.is_me else clamp(r.vx * 0.2, -1.0, 1.0)
	var steer_a: float = steer * 0.28 / (1.0 + r.v * 0.09)
	var hand_y := float(by[1])
	var hand_z := -float(by[0])
	var hr := Vector3(bw - 0.05, hand_y, hand_z - steer_a * (bw - 0.05))
	var hl := Vector3(-(bw - 0.05), hand_y, hand_z + steer_a * (bw - 0.05))
	var fr := Vector3(0.17, float(py[1]) + 0.14, -float(py[0]))
	var fl := Vector3(-0.17, float(py[1]) + 0.14, -float(py[0]))
	# strike
	var showing := {"baton": "", "chain": ""}
	var at: Variant = r.attack
	if at != null:
		var dur: float = 0.48 if not r.is_me else float(at.w.cd)
		var hit_at: float = 0.28 if not r.is_me else float(at.w.hit_at)
		var tm: float = at.t
		var w: float
		if tm < hit_at:
			w = tm / hit_at
		else:
			w = 1.0 - clamp((tm - hit_at) / max(0.05, dur - hit_at), 0.0, 1.0)
		w = smoothstep(0.0, 1.0, w)
		var sd: int = at.side
		if at.get("type", "hand") == "kick":
			var hip := hips + Vector3(sd * 0.12, -0.02, 0)
			var tgt := hip + Vector3(sd * 0.72, -0.12, 0.05)
			if sd > 0:
				fr = fr.lerp(tgt, w)
			else:
				fl = fl.lerp(tgt, w)
			q_spine = Quaternion(Vector3.BACK, sd * 0.35 * w) * q_spine
		else:
			var sh_y: float = hand_y + 0.3
			var back := Vector3(sd * 0.22, sh_y + 0.18, hand_z + 0.45)
			var strike := Vector3(sd * 0.8, sh_y - 0.12, hand_z + 0.1)
			var tgt2: Vector3
			if tm < hit_at * 0.5:
				tgt2 = (hr if sd > 0 else hl).lerp(back, tm / (hit_at * 0.5))
			elif tm < hit_at:
				tgt2 = back.lerp(strike, (tm - hit_at * 0.5) / (hit_at * 0.5))
			else:
				tgt2 = strike.lerp(hr if sd > 0 else hl, clamp((tm - hit_at) / max(0.05, dur - hit_at), 0.0, 1.0))
			if sd > 0:
				hr = tgt2
			else:
				hl = tgt2
			q_spine = Quaternion(Vector3.BACK, -sd * 0.28 * w) * q_spine
	# which fist holds the weapon
	var weapon: String = r.weapon
	var side_w := "R"
	if at != null and at.side < 0 and at.get("type", "hand") != "kick":
		side_w = "L"
	for key in weapon_nodes:
		weapon_nodes[key].visible = weapon != "none" and key == weapon + side_w
	# in the air: the trick, blended in after take-off and out again before landing
	if r.air and r.trick != "" and r.trick != "flip" and r.trick != "whip":
		var u: float = clamp(r.trick_t / max(0.1, r.trick_len), 0.0, 1.0)
		var w: float = smoothstep(0.0, 0.22, u) * (1.0 - smoothstep(0.72, 1.0, u))
		var sx: float = -float(sy[0])
		var sh: float = float(sy[1])
		match r.trick:
			"nohands":
				hl = hl.lerp(Vector3(-0.62, hand_y + 0.72, hand_z + 0.4), w)
				hr = hr.lerp(Vector3(0.62, hand_y + 0.72, hand_z + 0.4), w)
				q_spine = q_spine.slerp(Quaternion(Vector3.RIGHT, 0.12), w)
				q_head = q_head.slerp(Quaternion(Vector3.RIGHT, 0.25), w)
			"nacnac":
				# the right leg swung over the back to the left side
				fr = fr.lerp(Vector3(-0.66, sh + 0.2, sx + 0.12), w)
				hips = hips.lerp(hips + Vector3(-0.12, 0.08, 0.04), w)
				q_spine = q_spine.slerp(Quaternion(Vector3.UP, 0.45) * Quaternion(Vector3.RIGHT, -0.2), w)
			"heel":
				fl = fl.lerp(Vector3(-0.66, sh + 0.05, sx - 0.15), w)
				fr = fr.lerp(Vector3(0.66, sh + 0.05, sx - 0.15), w)
				hips = hips.lerp(hips + Vector3(0, 0.1, 0), w)
			"superman":
				# off the pegs, stretched out flat behind the bike, hands still on the bars
				hips = hips.lerp(Vector3(0, sh + 0.5, sx + 0.32), w)
				fl = fl.lerp(Vector3(-0.12, sh + 0.66, sx + 1.12), w)
				fr = fr.lerp(Vector3(0.12, sh + 0.66, sx + 1.12), w)
				q_hips = q_hips.slerp(Quaternion(Vector3.RIGHT, -1.25), w)
				q_spine = q_spine.slerp(Quaternion(Vector3.RIGHT, -1.3), w)
				q_head = q_head.slerp(Quaternion(Vector3.RIGHT, -0.7), w)
			"seat":
				# up on his feet on the seat, arms out for balance
				hips = hips.lerp(Vector3(0, sh + 0.93, sx - 0.02), w)
				fl = fl.lerp(Vector3(-0.13, sh + 0.07, sx + 0.02), w)
				fr = fr.lerp(Vector3(0.13, sh + 0.07, sx + 0.02), w)
				hl = hl.lerp(Vector3(-0.66, sh + 1.62, sx), w)
				hr = hr.lerp(Vector3(0.66, sh + 1.62, sx), w)
				q_hips = q_hips.slerp(Quaternion.IDENTITY, w)
				q_spine = q_spine.slerp(Quaternion(Vector3.RIGHT, 0.08), w)
				q_head = q_head.slerp(Quaternion.IDENTITY, w)
	# past the line: joy, a sulk or a rage, as big as his character makes it
	if r.emote != "" and not r.air:
		var tt: float = r.emote_t
		var we: float = smoothstep(0.0, 0.4, tt) * (1.0 - smoothstep(5.2, 6.4, tt))
		var k: float = r.emote_k
		match r.emote:
			"joy":
				var pump: float = 0.12 * sin(tt * 10.0)
				hr = hr.lerp(Vector3(0.28, hand_y + 0.9 + pump, hand_z + 0.42), we)
				if k >= 0.95:
					hl = hl.lerp(Vector3(-0.28, hand_y + 0.9 - pump, hand_z + 0.42), we)
				hips = hips.lerp(hips + Vector3(0, 0.2 * k, 0.05), we)
				q_spine = q_spine.slerp(Quaternion(Vector3.RIGHT, 0.12), we)
				q_head = q_head.slerp(Quaternion(Vector3.RIGHT, 0.4), we)
			"sad":
				q_head = q_head.slerp(Quaternion(Vector3.UP, 0.35 * sin(tt * 2.5)) * Quaternion(Vector3.RIGHT, -0.75), we)
				q_spine = q_spine.slerp(Quaternion(Vector3.RIGHT, -0.75), we)
				hl = hl.lerp(Vector3(-0.32, hand_y - 0.38, hand_z + 0.5), we * k)
			"angry":
				var shake: float = sin(tt * 18.0) * 0.07 * k
				if k > 0.75 and int(tt * 1.5) % 2 == 1:
					# beats the tank with his fist
					hr = hr.lerp(Vector3(0.12, hand_y - 0.02 - 0.14 * max(0.0, sin(tt * 12.0)), hand_z + 0.36), we)
				else:
					hr = hr.lerp(Vector3(0.36 + shake, hand_y + 0.64 + shake, hand_z + 0.32), we)
				q_head = q_head.slerp(Quaternion(Vector3.UP, 0.45 * sin(tt * 7.0) * k), we)
				q_spine = q_spine.slerp(Quaternion(Vector3.BACK, -0.2 * k) * Quaternion(Vector3.RIGHT, -0.3), we)
	_pose(hips, q_hips, q_spine, q_head, hl, hr, fl, fr)
	if front != null:
		front.rotation = Vector3.ZERO
		var ax: Array = meta.steer_axis
		var axis := Vector3(0, ax[1], -ax[0]).normalized()
		front.basis = Basis(axis, -steer_a)

func _pose_flying(delta: float) -> void:
	flail_t += delta
	var s: float = clamp(abs(r.spin) * 0.25, 0.1, 1.0)
	var a := flail_t * 9.0
	var hips := Vector3(0, 0.95, 0)
	var q_spine := Quaternion(Vector3.RIGHT, sin(a * 0.7) * 0.4 * s)
	var q_h := Quaternion.IDENTITY
	var hl := hips + Vector3(-0.55, 0.25 + sin(a) * 0.45 * s, cos(a) * 0.3 * s)
	var hr := hips + Vector3(0.55, 0.25 + sin(a + 2.0) * 0.45 * s, cos(a + 1.0) * 0.3 * s)
	var fl := hips + Vector3(-0.3, -0.72, sin(a + 1.0) * 0.35 * s)
	var fr := hips + Vector3(0.3, -0.72, sin(a + 3.0) * 0.35 * s)
	_pose(hips, q_h, q_spine, q_h, hl, hr, fl, fr)

# On foot after a fall: getting up, running to the bike, lifting it by the handlebar
func _pose_on_foot(delta: float, f: Vector3) -> void:
	var ground := road.world(r.fly_s, r.fly_d, 0.0)
	var rgt := f.cross(Vector3.UP).normalized()
	var want_yaw := 0.0
	if r.run_phase == 2:
		var to := road.world(r.s + 0.35, r.d + r.run_side * 0.72) - ground
		to.y = 0.0
		if to.length() > 0.05:
			want_yaw = atan2(to.dot(rgt), to.dot(f))
	elif r.run_phase == 3:
		want_yaw = -r.run_side * PI * 0.5
	if r.run_phase == 1:
		body_yaw = 0.0
	else:
		body_yaw = lerp_angle(body_yaw, want_yaw, min(1.0, delta * 12.0))
	var face: Vector3 = f.rotated(Vector3.UP, -body_yaw)
	var basis := Basis.looking_at(Vector3(face.x, 0.0, face.z).normalized(), Vector3.UP)
	var up_q := Quaternion.IDENTITY
	match r.run_phase:
		1:
			var w: float = smoothstep(0.0, 1.0, clamp(r.run_t / 0.5, 0.0, 1.0))
			rider_root.global_transform = Transform3D(basis * Basis(Vector3.RIGHT, -PI * 0.5 * (1.0 - w)), ground + Vector3.UP * 0.18 * (1.0 - w))
			var crouch: float = sin(w * PI) * 0.35
			var hips := Vector3(0, 0.95 - crouch, 0.05)
			_pose(hips, Quaternion.IDENTITY, Quaternion(Vector3.RIGHT, -0.5 * (1.0 - w) - crouch), up_q,
				Vector3(-0.3, 0.7 - crouch, -0.25), Vector3(0.3, 0.7 - crouch, -0.25), Vector3(-0.13, 0.14, -0.05), Vector3(0.13, 0.14, -0.05))
		2:
			rider_root.global_transform = Transform3D(basis, ground)
			run_clock += delta * 2.0 * PI * 1.55
			var ph: float = run_clock
			var hips2 := Vector3(0, 0.9 + 0.05 * abs(sin(ph)), 0)
			var q_sp := Quaternion(Vector3.RIGHT, -0.32) * Quaternion(Vector3.UP, 0.18 * sin(ph))
			var fl := Vector3(-0.11, 0.14 + 0.26 * max(0.0, sin(ph)), -0.4 * cos(ph))
			var fr := Vector3(0.11, 0.14 + 0.26 * max(0.0, -sin(ph)), 0.4 * cos(ph))
			var hl := Vector3(-0.26, 0.98 + 0.08 * cos(ph), 0.28 * cos(ph))
			var hr := Vector3(0.26, 0.98 - 0.08 * cos(ph), -0.28 * cos(ph))
			_pose(hips2, Quaternion(Vector3.RIGHT, -0.1), q_sp, Quaternion(Vector3.RIGHT, 0.12), hl, hr, fl, fr)
		3:
			rider_root.global_transform = Transform3D(basis, ground)
			var w3: float = clamp(r.run_t / 0.7, 0.0, 1.0)
			var bend: float = lerp(1.05, 0.3, w3)
			var hips3 := Vector3(0, lerp(0.8, 0.93, w3), 0.12)
			# hands on the grips wherever the rising bike has them
			var inv := rider_root.global_transform.affine_inverse()
			var by: Array = meta.bar
			var bw: float = meta.bw
			var g1 := inv * (lean_node.global_transform * Vector3(-(bw - 0.05), float(by[1]), -float(by[0])))
			var g2 := inv * (lean_node.global_transform * Vector3(bw - 0.05, float(by[1]), -float(by[0])))
			var hl3: Vector3 = g1 if g1.x < g2.x else g2
			var hr3: Vector3 = g2 if g1.x < g2.x else g1
			_pose(hips3, Quaternion(Vector3.RIGHT, -0.2), Quaternion(Vector3.RIGHT, -bend), Quaternion(Vector3.RIGHT, 0.4),
				hl3, hr3, Vector3(-0.16, 0.14, 0.08), Vector3(0.16, 0.14, 0.08))

var air_pitch := 0.0
var _blob_air := false
var hide_rider := false    # an end-of-race scene has his body: only the bike is drawn here

# The bike's own frame under the rider: its lean, and in the air the flip or the whip, turned about its middle
func _trick_frame() -> Transform3D:
	var lb := Basis(Vector3.BACK, -r.lean)
	if not r.air or (r.trick != "flip" and r.trick != "whip"):
		return Transform3D(lb, Vector3.ZERO)
	var u: float = clamp(r.trick_t / max(0.1, r.trick_len), 0.0, 1.0)
	var rot: Basis
	if r.trick == "flip":
		# a back flip: nose up and right over, ending level again
		rot = Basis(Vector3.RIGHT, TAU * smoothstep(0.0, 1.0, u))
	else:
		# the whip: the bike swung sideways and laid flat, then straightened
		var k: float = sin(PI * smoothstep(0.0, 1.0, u))
		var side: float = 1.0 if (r.name.length() % 2) == 0 else -1.0
		rot = Basis(Vector3.UP, 0.75 * k * side) * Basis(Vector3.BACK, -1.05 * k * side)
	var c := Vector3(0, 0.75, 0)
	return Transform3D(rot * lb, c - rot * c)

func _place_on_road(s: float, d: float, yaw: float) -> void:
	var p := road.world(s, d)
	var f := road.fwd_at(s)
	if r.air:
		# in the air: up off the road, nose along where he is flying
		p.y += r.air_h
		var fh := Vector3(f.x, 0.0, f.z).normalized()
		f = (fh + Vector3.UP * air_pitch).normalized()
	var up := Vector3.UP
	var rgt := f.cross(up).normalized()
	var u2 := rgt.cross(f).normalized()
	var b := Basis(rgt, u2, -f)
	if yaw != 0.0:
		b = b * Basis(Vector3.UP, -yaw)
	global_transform = Transform3D(b, p)

func refresh(delta: float, cam_s: float) -> void:
	if sim_ref != null:
		road = sim_ref.rd(r)
	var dist: float = abs(r.ps - cam_s)
	var near := dist < 90.0
	visible = dist < 620.0
	if not visible:
		return
	if r.state == Sim.DOWN:
		_place_on_road(r.s, r.d, r.psi if r.is_me else 0.0)
		# bike lies down and scrapes along, and comes up again when he lifts it
		var side: float = r.bike_side
		lean_node.rotation = Vector3(0, 0, -side * lerp(abs(r.lean), 1.42, r.bike_rot))
		lean_node.position = Vector3.UP * lerp(0.0, 0.22, r.bike_rot)
		if not _detached:
			_detached = true
			rider_root.top_level = true
			flail_t = 0.0
			spin_a = 0.0
			for key in weapon_nodes:
				weapon_nodes[key].visible = false
		rider_root.visible = not hide_rider and not r.gone
		var f := road.fwd_at(r.fly_s)
		if r.run_phase == 0:
			spin_a += r.spin * delta
			var fp := road.world(r.fly_s, r.fly_d, r.fly_y)
			var b := Basis.looking_at(f, Vector3.UP) * Basis(Vector3.RIGHT, spin_a) * Basis(Vector3.BACK, spin_a * 0.35)
			var settled: bool = r.fly_y <= 0.19 and abs(r.fly_v) < 1.0
			if settled:
				b = Basis.looking_at(f, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
			rider_root.global_transform = Transform3D(b, fp - b * Vector3(0, 0.95, 0))
			_pose_flying(delta if not settled else delta * 0.1)
			body_yaw = 0.0
		else:
			_pose_on_foot(delta, f)
		blob.visible = false
	else:
		if _detached:
			_detached = false
			rider_root.top_level = false
			rider_root.transform = Transform3D.IDENTITY
			lean_node.position = Vector3.ZERO
		var want_pitch: float = (r.air_vy / max(4.0, r.v)) if r.air else road.grade_at(r.s)
		air_pitch += (want_pitch - air_pitch) * min(1.0, delta * 7.0)
		_place_on_road(r.s, r.d, r.psi)
		lean_node.transform = _trick_frame()
		rider_root.visible = not hide_rider
		blob.visible = dist < 180.0
		# the shadow stays on the road and gets smaller the higher he flies
		if r.air:
			_blob_air = true
			var k: float = 1.0 / (1.0 + r.air_h * 0.35)
			var gp := road.world(r.s, r.d, 0.04)
			var gf := road.fwd_at(r.s)
			var rg := gf.cross(Vector3.UP).normalized()
			blob.global_transform = Transform3D(Basis(rg * k, rg.cross(gf).normalized(), -gf * k), gp)
		elif _blob_air:
			_blob_air = false
			blob.transform = Transform3D(Basis(), Vector3(0, 0.03, 0))
		if near or r.air or int(Engine.get_process_frames() + r.name.length()) % 4 == 0:
			_pose_riding(delta, near)
	# wheels
	var rot: float = r.v * delta
	if wheel_f != null:
		wheel_f.rotate_object_local(Vector3.RIGHT, -rot / float(meta.rf))
		wheel_r.rotate_object_local(Vector3.RIGHT, -rot / float(meta.rr))
	# damage flash and blinking after getting up
	var blink: bool = r.inv > 0.0 and r.state == Sim.RIDE and int(r.inv * 10.0) % 2 == 0
	lean_node.visible = not blink
	if cop_lights != null:
		var on: bool = r.state == Sim.RIDE
		cop_lights.visible = on
		if on:
			var m: StandardMaterial3D = cop_lights.mesh.material
			m.albedo_color = Color(0.2, 0.4, 1.0) if int(Time.get_ticks_msec() / 160) % 2 == 0 else Color(1.0, 0.15, 0.15)
