class_name Road extends RefCounted
# The road as data: a centreline sampled every DS metres. Everything on it lives in road space (s along, d across, +d = right).
# Two lanes each way: ours at d = +1.8 and +5.4, oncoming at -1.8 and -5.4.

const DS := 2.0
const LANE_W := 3.6
const HALF := 7.2
const EDGE := 8.0
const A_REF := 11.0  # m/s2 of grip the bends are designed around

var pos := PackedVector3Array()
var fwd := PackedVector3Array()
var right := PackedVector3Array()
var kappa := PackedFloat32Array()
var grade := PackedFloat32Array()
var n := 0
var length := 0.0
var finish_s := 0.0
var start_s := 60.0
var solids: Array = []   # [s, d, r, half_len], sorted by s
var solid_index := {}    # bucket (30 m) -> [solids]

func curve_radius(c: float, tr: Dictionary) -> float:
	# Same difficulty curve as the 2D game: what fraction of the league's top speed this bend allows.
	var ck: float = tr.ck
	var frac := sqrt(1.14 * 0.78 * 0.92 / (c * ck * 0.9))
	var v: float = tr.kmh / 3.6 * frac
	return max(26.0, v * v / A_REF)

var _rng: RandomNumberGenerator
var _plan: Array = []  # [length, kappa_target, grade_target]
var _heading := 0.0
var _done := 0.0
var _elev := 0.0
var _gmax := 0.05
var _hills := 0.3

func _hill(p: float) -> float:
	if _rng.randf() >= _hills * p:
		return 0.0
	var g: float = (_rng.randf() * 2.0 - 1.0) * _gmax
	if _elev > 40.0 and g > 0.0:
		g = -g
	if _elev < -40.0 and g < 0.0:
		g = -g
	return g

func _straight(l: float, g: float) -> void:
	_plan.append([l, 0.0, g])
	_done += l
	_elev += g * l

func _curve(c: float, dir: int, ang: float, g: float, tr: Dictionary) -> int:
	if abs(_heading + dir * ang) > deg_to_rad(82.0):
		dir = -dir
	var r: float = curve_radius(c, tr)
	var k: float = dir / r
	var ease_len: float = clamp(ang * r * 0.25, 18.0, 90.0)
	var hold: float = max(6.0, ang * r - ease_len)
	_plan.append([ease_len, k, g])
	_plan.append([hold, k, g])
	_plan.append([ease_len, 0.0, g])
	_heading += dir * (hold + ease_len) / r
	var l: float = hold + ease_len * 2.0
	_done += l
	_elev += g * l
	return dir

func build(tr: Dictionary) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = int(tr.seed) * 7919
	var v_top: float = tr.kmh / 3.6
	var total: float = v_top * tr.sec
	var c_max: float = tr.curve
	_gmax = clamp(tr.hillH / 30.0 * 0.085, 0.02, 0.09)
	_hills = tr.hills
	_straight(start_s + 120.0, 0.0)
	while _done < total:
		var r := _rng.randf()
		var dir := -1 if _rng.randf() < 0.5 else 1
		var c: float = 1.6 + _rng.randf() * (c_max - 1.6)
		var ang: float = deg_to_rad(lerp(32.0, 95.0, _rng.randf()))
		if r < 0.25:
			_straight(v_top * lerp(2.0, 5.0, _rng.randf()), _hill(1.0))
		elif r < 0.62:
			_curve(c, dir, ang, _hill(1.0), tr)
		elif r < 0.85:
			var g: float = _hill(0.6)
			var d2: int = _curve(c, dir, ang * 0.7, g, tr)
			_curve(c, -d2, ang * 0.7, g, tr)
		else:
			_straight(v_top * lerp(2.5, 5.0, _rng.randf()), _hill(1.6))
	finish_s = _done
	_straight(700.0, 0.0)

	# Integrate the plan into positions
	var p := Vector3.ZERO
	var h := 0.0
	var k_now := 0.0
	var g_now := 0.0
	for piece in _plan:
		var steps := int(ceil(piece[0] / DS))
		var k0 := k_now
		for i in steps:
			# curvature eases linearly over the piece, grade eases over 40 m
			var t := float(i + 1) / steps
			k_now = lerp(k0, float(piece[1]), t) if piece[0] < 100.0 or abs(piece[1] - k0) > 1e-5 else float(piece[1])
			g_now += (float(piece[2]) - g_now) * min(1.0, DS / 40.0)
			h += k_now * DS
			var f := Vector3(sin(h), 0.0, -cos(h))
			pos.append(p)
			fwd.append(Vector3(f.x, g_now, f.z).normalized())
			right.append(Vector3(cos(h), 0.0, sin(h)))
			kappa.append(k_now)
			grade.append(g_now)
			p += f * DS
			p.y += g_now * DS
	n = pos.size()
	length = (n - 1) * DS

func _i(s: float) -> int:
	return clampi(int(s / DS), 0, n - 2)

func kappa_at(s: float) -> float:
	return kappa[_i(s)]

func grade_at(s: float) -> float:
	return grade[_i(s)]

func world(s: float, d: float, y := 0.0) -> Vector3:
	var i := _i(s)
	var t: float = clamp((s - i * DS) / DS, 0.0, 1.0)
	var p: Vector3 = pos[i].lerp(pos[i + 1], t)
	var r: Vector3 = right[i].lerp(right[i + 1], t)
	return p + r * d + Vector3.UP * y

func fwd_at(s: float) -> Vector3:
	var i := _i(s)
	var t: float = clamp((s - i * DS) / DS, 0.0, 1.0)
	return fwd[i].lerp(fwd[i + 1], t).normalized()

func add_solid(s: float, d: float, r: float, half_len: float) -> void:
	var e := [s, d, r, half_len]
	solids.append(e)
	var a := int((s - half_len) / 30.0)
	var b := int((s + half_len) / 30.0)
	for k in range(a, b + 1):
		if not solid_index.has(k):
			solid_index[k] = []
		solid_index[k].append(e)

func solid_hit(s: float, d: float, pad := 0.35) -> bool:
	var list: Variant = solid_index.get(int(s / 30.0))
	if list == null:
		return false
	for e in list:
		if abs(s - e[0]) < e[3] + 0.8 and abs(d - e[1]) < e[2] + pad:
			return true
	return false
