class_name ActorView extends BikeView
# A person on foot for the little scenes around the race: a rider getting up, a police officer, a paramedic.
# The same body as the riders, posed by hand: stand, walk, lie, get up, hands behind the back, carry a stretcher,
# cheer, shake a bottle, stomp, kick, take off the helmet, throw it.
# Coordinates of a pose are the body's own: x right, y up, forward is -z, feet at the origin.

var body: Node3D
var body_k := Vector3.ONE
var helm_meshes: Array = []
var cap: MeshInstance3D
var bottle: MeshInstance3D
var helmet_col := Color.WHITE

const COP := ["#2b3a5c", "#c9a227", "#1e2a44", "#121216", "#e0b48c", "#2b3a5c"]
const MEDIC := ["#f1efe8", "#d9232e", "#2a3a66", "#1e1b1b", "#d6a77e", "#f1efe8"]

static var _cap_mesh: CylinderMesh
static var _bottle_mesh: CylinderMesh

# jacket, stripe, pants, boots, skin, sleeve: a uniform
static func uniform(o: Array) -> Array:
	var skin := Color(o[4])
	return [Color(o[0]), Color(o[1]), Color(o[2]), Color(o[3]), skin, skin, skin, skin, Color(o[5])]

# a racer's own outfit, as on the bike: gloves and helmet included
static func racer(look: Dictionary) -> Array:
	var o: Dictionary = look.outfit
	return [Color(o.jacket), Color(o.stripe), Color(o.pants), Color(o.boots), Color(o.glove), Color(o.skin), Color(o.helmet), Color(o.hs), Color(o.sleeve)]

func build_actor(cols: Array, helmet: int, with_cap := false) -> void:
	body = Node3D.new()
	add_child(body)
	rider_root = Node3D.new()
	body.add_child(rider_root)
	var rig: Node3D = (load("res://models/rider.glb") as PackedScene).instantiate()
	rider_root.add_child(rig)
	for n in rig.find_children("*", "Skeleton3D", true, false):
		skel = n
	pal_mat = _paint_material(cols)
	if cols.size() > 6:
		helmet_col = cols[6]
	for n in rig.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.material_override = pal_mat
		if mi.name == "helm_full":
			mi.visible = helmet >= 2
			helm_meshes.append(mi)
		elif mi.name == "helm_open":
			mi.visible = helmet == 1
			helm_meshes.append(mi)
	for bn in D.models.rider.joints:
		J[bn] = to_g(D.models.rider.joints[bn])
		bones[bn] = skel.find_bone(bn)
	if with_cap:
		if _cap_mesh == null:
			_cap_mesh = CylinderMesh.new()
			_cap_mesh.top_radius = 0.12
			_cap_mesh.bottom_radius = 0.13
			_cap_mesh.height = 0.09
			var m := StandardMaterial3D.new()
			m.albedo_color = Color("#1e2a44")
			_cap_mesh.material = m
		var att := BoneAttachment3D.new()
		skel.add_child(att)
		att.bone_name = "head"
		cap = MeshInstance3D.new()
		cap.mesh = _cap_mesh
		cap.position = Vector3(0, 0.2, 0)
		att.add_child(cap)
	blob = MeshInstance3D.new()
	blob.mesh = blob_mesh()
	add_child(blob)

func has_helmet() -> bool:
	for m in helm_meshes:
		if m.visible:
			return true
	return false

func take_off_helmet() -> void:
	for m in helm_meshes:
		m.visible = false

# the champagne: a green bottle held between the hands
func show_bottle(on: bool) -> void:
	if bottle == null:
		if _bottle_mesh == null:
			_bottle_mesh = CylinderMesh.new()
			_bottle_mesh.top_radius = 0.022
			_bottle_mesh.bottom_radius = 0.045
			_bottle_mesh.height = 0.34
			var m := StandardMaterial3D.new()
			m.albedo_color = Color("#1f5a2a")
			m.metallic_specular = 0.8
			m.roughness = 0.2
			_bottle_mesh.material = m
		bottle = MeshInstance3D.new()
		bottle.mesh = _bottle_mesh
		rider_root.add_child(bottle)
	bottle.visible = on

# where the neck of the bottle is, in the world: the foam comes out there
func bottle_tip() -> Vector3:
	if bottle == null:
		return global_position
	return bottle.global_transform * Vector3(0, 0.19, 0)

func hand_world(right: bool) -> Vector3:
	return skel.global_transform * skel.get_bone_global_pose(bones["arm_l." + ("R" if right else "L")]) * Vector3(0, -0.29, 0)

# Standing or walking: feet on the ground at p, facing yaw (0 = towards -z in the world)
func place(p: Vector3, yaw: float, lift := 0.0) -> void:
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(body_k), p + Vector3.UP * lift)
	blob.global_transform = Transform3D(Basis.from_scale(Vector3(0.5, 1.0, 0.3)), p + Vector3.UP * 0.03)
	blob.visible = true

# Lying on his back, feet at p, head towards yaw + 180 degrees; at height h (on a stretcher, say)
func place_lying(p: Vector3, yaw: float, h := 0.12) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)
	body.global_transform = Transform3D(b * Basis.from_scale(body_k), p + Vector3.UP * h + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.05))
	blob.visible = h < 0.3

# legs and swinging arms of an ordinary walk: [hips, left foot, right foot, left hand, right hand]
func _walk(t: float, speed: float, stride: float) -> Array:
	var ph: float = t * TAU * speed
	return [Vector3(0, 0.94 + 0.025 * abs(sin(ph)), 0),
		Vector3(-0.11, 0.08 + 0.12 * max(0.0, sin(ph)), -stride * cos(ph)),
		Vector3(0.11, 0.08 + 0.12 * max(0.0, -sin(ph)), stride * cos(ph)),
		Vector3(-0.24, 0.62, 0.16 * cos(ph)),
		Vector3(0.24, 0.62, -0.16 * cos(ph))]

# ---------- poses. t runs in seconds for the ones that move, k from 0 to 1 for the ones that go somewhere ----------
func pose(name_p: String, t := 0.0, k := 1.0) -> void:
	var hips := Vector3(0, 0.95, 0)
	var q_h := Quaternion.IDENTITY
	var q_s := Quaternion.IDENTITY
	var q_hd := Quaternion.IDENTITY
	var hl := Vector3(-0.24, 0.62, 0.02)
	var hr := Vector3(0.24, 0.62, 0.02)
	var fl := Vector3(-0.12, 0.08, 0.0)
	var fr := Vector3(0.12, 0.08, 0.0)
	match name_p:
		"stand":
			pass
		"walk":
			var wk := _walk(t, 1.0, 0.27)
			hips = wk[0]
			fl = wk[1]
			fr = wk[2]
			hl = wk[3]
			hr = wk[4]
		"lie":
			hl = Vector3(-0.42, 0.95, 0.05)
			hr = Vector3(0.42, 0.95, 0.05)
			fl = Vector3(-0.16, 0.08, 0.02)
			fr = Vector3(0.16, 0.08, 0.02)
		"getup":
			# from sitting on the ground to standing, k over the move
			var c: float = (1.0 - k) * 0.5
			hips = Vector3(0, 0.95 - c, -c * 0.4)
			q_s = Quaternion(Vector3.RIGHT, -0.8 * (1.0 - k))
			hl = Vector3(-0.3, 0.62 - c * 0.6, -0.25 * (1.0 - k))
			hr = Vector3(0.3, 0.62 - c * 0.6, -0.25 * (1.0 - k))
			fl = Vector3(-0.14, 0.08, -0.25 * (1.0 - k))
			fr = Vector3(0.14, 0.08, -0.25 * (1.0 - k))
		"hands_up":
			hl = Vector3(-0.32, 1.86, -0.05)
			hr = Vector3(0.32, 1.86, -0.05)
		"cuffed", "cuffed_walk":
			if name_p == "cuffed_walk":
				var wk := _walk(t, 0.8, 0.2)
				hips = wk[0]
				fl = wk[1]
				fr = wk[2]
				hl = wk[3]
				hr = wk[4]
			hl = Vector3(-0.08, 0.9, 0.2)
			hr = Vector3(0.08, 0.9, 0.2)
			q_hd = Quaternion(Vector3.RIGHT, -0.35)
			q_s = Quaternion(Vector3.RIGHT, -0.12)
		"cuff":
			hl = Vector3(-0.12, 1.0, -0.42)
			hr = Vector3(0.12, 1.0, -0.42)
			q_s = Quaternion(Vector3.RIGHT, -0.25)
			q_hd = Quaternion(Vector3.RIGHT, -0.3)
		"escort":
			var wk := _walk(t, 0.8, 0.22)
			hips = wk[0]
			fl = wk[1]
			fr = wk[2]
			hl = wk[3]
			hr = wk[4]
			hr = Vector3(0.14, 1.0, -0.4)
		"carry", "carry_walk":
			if name_p == "carry_walk":
				var wk := _walk(t, 0.9, 0.22)
				hips = wk[0]
				fl = wk[1]
				fr = wk[2]
				hl = wk[3]
				hr = wk[4]
			hl = Vector3(-0.26, 0.82, -0.28)
			hr = Vector3(0.26, 0.82, -0.28)
		"bend":
			# bending down to the ground and up again with the load, k = how far down
			hips = Vector3(0, 0.95 - 0.28 * k, 0.12 * k)
			q_s = Quaternion(Vector3.RIGHT, -1.0 * k)
			q_hd = Quaternion(Vector3.RIGHT, -0.5 * k)
			hl = Vector3(-0.26, lerp(0.82, 0.35, k), lerp(-0.28, -0.5, k))
			hr = Vector3(0.26, lerp(0.82, 0.35, k), lerp(-0.28, -0.5, k))
			fl = Vector3(-0.15, 0.08, 0.02)
			fr = Vector3(0.15, 0.08, 0.02)
		"cheer":
			var hop: float = max(0.0, sin(t * 7.0))
			hl = Vector3(-0.36, 1.92 + 0.06 * sin(t * 14.0), -0.1)
			hr = Vector3(0.36, 1.92 - 0.06 * sin(t * 14.0), -0.1)
			fl = Vector3(-0.13, 0.08 + 0.1 * hop, 0.05 * hop)
			fr = Vector3(0.13, 0.08 + 0.1 * hop, 0.05 * hop)
			q_hd = Quaternion(Vector3.RIGHT, 0.35)
			q_s = Quaternion(Vector3.RIGHT, 0.1)
		"shake":
			var sh: float = 0.12 * sin(t * 22.0)
			hl = Vector3(-0.05, 1.18 + sh, -0.3)
			hr = Vector3(0.05, 1.1 + sh, -0.3)
		"spray":
			hl = Vector3(-0.05, 1.5 + 0.03 * sin(t * 9.0), -0.42)
			hr = Vector3(0.05, 1.4 + 0.03 * sin(t * 9.0), -0.4)
			q_s = Quaternion(Vector3.RIGHT, 0.2)
			q_hd = Quaternion(Vector3.RIGHT, 0.3)
		"stomp":
			var a: float = sin(t * 8.0)
			hl = Vector3(-0.34, 1.12 + 0.1 * sin(t * 15.0), -0.22)
			hr = Vector3(0.34, 1.12 - 0.1 * sin(t * 15.0), -0.22)
			fl = Vector3(-0.13, 0.08 + 0.2 * max(0.0, a), -0.05 * max(0.0, a))
			fr = Vector3(0.13, 0.08 + 0.2 * max(0.0, -a), -0.05 * max(0.0, -a))
			q_hd = Quaternion(Vector3.UP, 0.4 * sin(t * 6.0))
			q_s = Quaternion(Vector3.RIGHT, -0.15)
		"kick":
			var w: float = sin(PI * clamp(k, 0.0, 1.0))
			fr = Vector3(0.05, 0.08 + 0.55 * w, -0.65 * w)
			hips = Vector3(0, 0.95, 0.08 * w)
			q_s = Quaternion(Vector3.RIGHT, 0.25 * w)
			hl = Vector3(-0.45, 1.1, 0.0)
			hr = Vector3(0.45, 1.1, 0.0)
		"helmet_off":
			hl = Vector3(-0.17, lerp(1.5, 1.95, k), -0.05)
			hr = Vector3(0.17, lerp(1.5, 1.95, k), -0.05)
		"throw":
			# right arm from behind the head over and forward
			var w2: float = clamp(k, 0.0, 1.0)
			hr = Vector3(0.22, 1.75, 0.35).lerp(Vector3(0.3, 1.45, -0.75), smoothstep(0.0, 1.0, w2))
			hl = Vector3(-0.35, 1.2, -0.3)
			q_s = Quaternion(Vector3.RIGHT, lerp(0.3, -0.35, w2)) * Quaternion(Vector3.UP, lerp(-0.5, 0.3, w2))
			fr = Vector3(0.14, 0.08, 0.15)
			fl = Vector3(-0.14, 0.08, -0.22)
		"despair":
			hl = Vector3(-0.15, 1.72, -0.02)
			hr = Vector3(0.15, 1.72, -0.02)
			q_hd = Quaternion(Vector3.UP, 0.35 * sin(t * 3.0)) * Quaternion(Vector3.RIGHT, -0.5)
			q_s = Quaternion(Vector3.RIGHT, -0.2)
	_pose(hips, q_h, q_s, q_hd, hl, hr, fl, fr)
	if bottle != null and bottle.visible:
		var mid: Vector3 = (hl + hr) * 0.5
		var up := Vector3(0, 1, 0)
		if name_p == "spray":
			up = Vector3(0, 0.55, -0.85).normalized()
		bottle.transform = Transform3D(Basis(Quaternion(Vector3.UP, up)), mid + up * 0.06)
