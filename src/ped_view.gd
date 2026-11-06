class_name PedView extends BikeView
# Someone crossing the road: the rider's body without a bike or a helmet, in everyday clothes.
# A light one walks; a heavy one is a big man carrying a crate. Knocked over, he tumbles, lies, gets up and hurries off.

var p: Sim.Ped
var walk_clock := 0.0
var body: Node3D
var crate: MeshInstance3D
var yaw_now := 0.0
var body_k := Vector3.ONE
var blob_k := Vector3.ONE

# jacket, stripe, pants, boots, (gloves = skin), skin, -, -, sleeve
const LOOKS := [
	["#c8442e", "#f3eedf", "#2d3550", "#3a2a22", "#e0b48c", "#c8442e"],
	["#3f7a55", "#d9d2c0", "#39393f", "#1e1b1b", "#c9976d", "#3f7a55"],
	["#e9c13a", "#2b2b2b", "#4a5d7a", "#4a3628", "#f0c8a0", "#e9c13a"],
	["#6a4aa8", "#e9e6dc", "#222228", "#151517", "#b07f5a", "#6a4aa8"],
	["#d9d6cc", "#c0392b", "#55606e", "#2e2a26", "#e8bd94", "#d9d6cc"],
	["#2f6fb0", "#f3eedf", "#6b5a44", "#2a2320", "#d6a77e", "#2f6fb0"],
]
const HEAVY := ["#e07a1f", "#f3eedf", "#2a3346", "#1a1714", "#d39c72", "#e07a1f"]

static var _crate_mesh: BoxMesh

# built once and kept: a race reuses a handful of these for everyone who crosses
func build_ped(sim: Sim) -> void:
	sim_ref = sim
	road = sim.road
	visible = false
	body = Node3D.new()
	add_child(body)
	rider_root = Node3D.new()
	body.add_child(rider_root)
	var rig: Node3D = (load("res://models/rider.glb") as PackedScene).instantiate()
	rider_root.add_child(rig)
	for n in rig.find_children("*", "Skeleton3D", true, false):
		skel = n
	pal_mat = _paint_material(_cols(LOOKS[0]))
	for n in rig.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.material_override = pal_mat
		if mi.name == "helm_full" or mi.name == "helm_open":
			mi.visible = false
	for bn in D.models.rider.joints:
		J[bn] = to_g(D.models.rider.joints[bn])
		bones[bn] = skel.find_bone(bn)
	if _crate_mesh == null:
			_crate_mesh = BoxMesh.new()
			_crate_mesh.size = Vector3(0.5, 0.38, 0.36)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color("#9a6b3c")
			m.roughness = 1.0
			_crate_mesh.material = m
	crate = MeshInstance3D.new()
	crate.mesh = _crate_mesh
	crate.position = Vector3(0, 1.02, -0.34)
	rider_root.add_child(crate)
	blob = MeshInstance3D.new()
	blob.mesh = blob_mesh()
	add_child(blob)

static func _cols(o: Array) -> Array:
	var skin := Color(o[4])
	return [Color(o[0]), Color(o[1]), Color(o[2]), Color(o[3]), skin, skin, skin, skin, Color(o[5])]

# dressed for whoever is crossing now; a heavy one is a big man, broad and tall, with a crate in front of him
func assign(ped: Sim.Ped) -> void:
	p = ped
	var arr := PackedVector3Array()
	arr.resize(16)
	var cols: Array = _cols(HEAVY if p.heavy else LOOKS[p.look % LOOKS.size()])
	for i in cols.size():
		arr[i] = Vector3(cols[i].r, cols[i].g, cols[i].b)
	pal_mat.set_shader_parameter("pal", arr)
	body_k = Vector3(1.32, 1.12, 1.32) if p.heavy else Vector3.ONE
	blob_k = Vector3(0.55, 1.0, 0.32) * (1.25 if p.heavy else 1.0)
	crate.visible = p.heavy
	spin_a = 0.0
	flail_t = 0.0
	yaw_now = atan2(-(road.fwd_at(p.s).cross(Vector3.UP).normalized() * p.dir).x, -(road.fwd_at(p.s).cross(Vector3.UP).normalized() * p.dir).z)

func refresh_ped(delta: float, cam_s: float) -> void:
	visible = p != null and p.state != 3 and abs(p.s - cam_s) < 320.0
	if not visible:
		return
	var on_s: float = p.fly_s if p.state == 1 else p.s
	var on_d: float = p.fly_d if p.state == 1 else p.d
	var f := road.fwd_at(on_s)
	var fh := Vector3(f.x, 0.0, f.z).normalized()
	var rgt := fh.cross(Vector3.UP).normalized()
	var ground := road.world(on_s, on_d, 0.0)
	blob.global_position = ground + Vector3.UP * 0.03
	blob.global_basis = Basis(Vector3.UP, atan2(-fh.x, -fh.z)) * Basis.from_scale(blob_k)
	# faces the way he walks: across the road
	var face: Vector3 = rgt * p.dir
	var want_yaw: float = atan2(-face.x, -face.z)
	yaw_now = lerp_angle(yaw_now, want_yaw, min(1.0, delta * 8.0))
	var b := Basis(Vector3.UP, yaw_now)
	match p.state:
		0:
			body.global_transform = Transform3D(b * Basis.from_scale(body_k), ground)
			rider_root.transform = Transform3D.IDENTITY
			if p.wait > 0.0:
				_stand(0.0)
			else:
				walk_clock += delta * TAU * (0.75 if p.heavy else 0.95) * (p.v / (0.9 if p.heavy else 1.4))
				_walk(walk_clock)
		1:
			# tumbling
			spin_a += p.spin * delta
			var fp := road.world(p.fly_s, p.fly_d, p.fly_y)
			var settled: bool = p.fly_y <= 0.16 and abs(p.fly_v) < 0.5
			var bb := Basis.looking_at(fh, Vector3.UP) * Basis(Vector3.RIGHT, spin_a)
			if settled:
				bb = Basis.looking_at(fh, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
			body.global_transform = Transform3D(bb * Basis.from_scale(body_k), fp - bb * Vector3(0, 0.9, 0))
			_flail(delta if not settled else delta * 0.1)
		2:
			var w: float = smoothstep(0.0, 1.0, clamp(p.t / 0.7, 0.0, 1.0))
			body.global_transform = Transform3D((b * Basis(Vector3.RIGHT, -PI * 0.5 * (1.0 - w))) * Basis.from_scale(body_k), ground + Vector3.UP * 0.15 * (1.0 - w))
			_stand(sin(w * PI) * 0.3)
		4:
			# staggers back from the hit, arms out, and keeps his feet
			var k: float = sin(clamp(p.t / 1.3, 0.0, 1.0) * PI)
			body.global_transform = Transform3D((b * Basis(Vector3.RIGHT, 0.25 * k)) * Basis.from_scale(body_k), ground)
			_stand(0.0, k)

func _stand(crouch: float, arms_out := 0.0) -> void:
	var hips := Vector3(0, 0.95 - crouch, 0.0)
	var hl := Vector3(-0.27, 1.0, -0.34) if p.heavy else Vector3(-0.24, 0.62 - crouch, 0.02)
	var hr := Vector3(0.27, 1.0, -0.34) if p.heavy else Vector3(0.24, 0.62 - crouch, 0.02)
	if arms_out > 0.0:
		hl = hl.lerp(Vector3(-0.6, 1.25, -0.1), arms_out)
		hr = hr.lerp(Vector3(0.6, 1.25, -0.1), arms_out)
	_pose(hips, Quaternion.IDENTITY, Quaternion(Vector3.RIGHT, -0.3 * crouch), Quaternion.IDENTITY,
		hl, hr, Vector3(-0.12, 0.08, 0.0), Vector3(0.12, 0.08, 0.0))

func _walk(ph: float) -> void:
	var stride: float = 0.2 if p.heavy else 0.27
	var hips := Vector3(0, 0.94 + 0.025 * abs(sin(ph)), 0)
	var fl := Vector3(-0.11, 0.08 + 0.12 * max(0.0, sin(ph)), -stride * cos(ph))
	var fr := Vector3(0.11, 0.08 + 0.12 * max(0.0, -sin(ph)), stride * cos(ph))
	var hl: Vector3
	var hr: Vector3
	if p.heavy:
		hl = Vector3(-0.27, 1.0, -0.34)
		hr = Vector3(0.27, 1.0, -0.34)
	else:
		hl = Vector3(-0.24, 0.62, 0.16 * cos(ph))
		hr = Vector3(0.24, 0.62, -0.16 * cos(ph))
	_pose(hips, Quaternion.IDENTITY, Quaternion(Vector3.UP, 0.08 * sin(ph)), Quaternion.IDENTITY, hl, hr, fl, fr)

func _flail(delta: float) -> void:
	flail_t += delta
	var a := flail_t * 9.0
	var hips := Vector3(0, 0.95, 0)
	_pose(hips, Quaternion.IDENTITY, Quaternion(Vector3.RIGHT, sin(a * 0.7) * 0.35), Quaternion.IDENTITY,
		hips + Vector3(-0.5, 0.25 + sin(a) * 0.4, cos(a) * 0.3), hips + Vector3(0.5, 0.25 + sin(a + 2.0) * 0.4, cos(a + 1.0) * 0.3),
		hips + Vector3(-0.25, -0.72, sin(a + 1.0) * 0.3), hips + Vector3(0.25, -0.72, sin(a + 3.0) * 0.3))
