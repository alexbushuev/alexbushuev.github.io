class_name Road extends RefCounted
# The road as data: a centreline sampled every DS metres. Everything on it lives in road space (s along, d across, +d = right).
# Two lanes each way: ours at d = +1.8 and +5.4, oncoming at -1.8 and -5.4.

const DS := 2.0
const LANE_W := 3.6
const HALF := 7.2
const EDGE := 8.0
const A_REF := 8.0   # the bends leave a margin: a rider has about 11 m/s2 of grip, so they can be taken a little faster

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
var edge := EDGE         # a branch is narrower
var half := HALF
var features: Array = [] # main road: tunnels, overpasses, bends a branch cuts across
var branches: Array = [] # main road: the side roads, each a Road of its own
var city := false
# a branch: where it leaves and rejoins the main road, on which side, and what it is
var kind := ""
var side := 1
var s0 := 0.0
var s1 := 0.0
var bumps: Array = []    # potholes on a shortcut, [s, d]

func curve_radius(c: float, tr: Dictionary) -> float:
	# Same difficulty curve as the 2D game: what fraction of the league's top speed this bend allows.
	var ck: float = tr.ck
	var frac := sqrt(1.14 * 0.78 * 0.92 / (c * ck * 0.9))
	var v: float = D.world_speed(tr.kmh) * frac
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
	var ease_len: float = clamp(ang * r * 0.4, 30.0, 120.0)
	var hold: float = max(6.0, ang * r - ease_len)
	_plan.append([ease_len, k, g])
	_plan.append([hold, k, g])
	_plan.append([ease_len, 0.0, g])
	_heading += dir * (hold + ease_len) / r
	var l: float = hold + ease_len * 2.0
	_done += l
	_elev += g * l
	return dir

# a bend with a given radius and no turning back on itself
func _bend(dir: int, ang: float, r: float) -> void:
	var k: float = dir / r
	var ease_len: float = clamp(ang * r * 0.4, 30.0, 120.0)
	var hold: float = max(6.0, ang * r - ease_len)
	_plan.append([ease_len, k, 0.0])
	_plan.append([hold, k, 0.0])
	_plan.append([ease_len, 0.0, 0.0])
	_heading += dir * (hold + ease_len) / r
	var l: float = hold + ease_len * 2.0
	_done += l

# A detour: a long flat bend of 160 degrees with a smoother, a little shorter side road across its inside.
# A shortcut: the main road runs out sideways round a hairpin and comes back; a straight gravel track closes the loop.
func _branch_bend(kind: String, v_top: float) -> void:
	if kind == "cut":
		if abs(_heading) > deg_to_rad(4.0):
			_bend(-1 if _heading > 0.0 else 1, abs(_heading), max(60.0, pow(v_top * 0.85, 2.0) / A_REF))
		_straight(50.0, 0.0)
		var lobe := 1 if _rng.randf() < 0.5 else -1
		var r1: float = max(40.0, pow(v_top * 0.72, 2.0) / A_REF)
		var rh: float = max(30.0, pow(v_top * 0.5, 2.0) / A_REF)
		var leg: float = clamp(v_top * 0.5, 12.0, 30.0)
		var a0 := _done
		_bend(lobe, deg_to_rad(90.0), r1)
		_straight(leg, 0.0)
		_bend(-lobe, deg_to_rad(180.0), rh)
		_straight(leg, 0.0)
		_bend(lobe, deg_to_rad(90.0), r1)
		features.append({"kind": kind, "s_a": a0, "s_b": _done, "dir": -lobe, "r": r1})
		_straight(140.0, 0.0)
		return
	var dir := 1 if _heading < -0.05 else (-1 if _heading > 0.05 else (1 if _rng.randf() < 0.5 else -1))
	var pre: float = -dir * deg_to_rad(80.0) - _heading
	if abs(pre) > deg_to_rad(4.0):
		_bend(1 if pre > 0.0 else -1, abs(pre), max(60.0, pow(v_top * 0.85, 2.0) / A_REF))
	_straight(60.0, 0.0)
	var r: float = max(60.0, pow(v_top * 0.78, 2.0) / A_REF)
	var a := _done
	_bend(dir, deg_to_rad(160.0), r)
	features.append({"kind": kind, "s_a": a, "s_b": _done, "dir": dir, "r": r})
	_straight(140.0, 0.0)

func build(tr: Dictionary) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = int(tr.seed) * 7919
	var v_top: float = D.world_speed(tr.kmh)
	var total: float = v_top * tr.sec * float(D.rules.get("track_k", 1.0))
	var c_max: float = tr.curve
	_gmax = clamp(tr.hillH / 30.0 * 0.085, 0.02, 0.09)
	_hills = tr.hills
	city = int(tr.theme) in [1, 2, 4]
	var plan_b: Array = [["fork", 0.28], ["cut", 0.62]]
	_straight(start_s + 120.0, 0.0)
	while _done < total:
		if not plan_b.is_empty() and _done >= total * float(plan_b[0][1]):
			_branch_bend(plan_b[0][0], v_top)
			plan_b.pop_front()
			continue
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
	for f in features:
		_make_branch(f)
	_pick_tunnels_and_bridges()

# ---------- side roads ----------
# Builds a branch from sampled points: same arrays as the main road, so everything that drives on a Road drives on it
func from_points(pts: Array) -> void:
	n = pts.size()
	for i in n:
		var a: Vector3 = pts[max(0, i - 1)]
		var b: Vector3 = pts[min(n - 1, i + 1)]
		var f: Vector3 = (b - a)
		var fh := Vector3(f.x, 0.0, f.z).normalized()
		pos.append(pts[i])
		fwd.append(f.normalized())
		right.append(Vector3(-fh.z, 0.0, fh.x))
		grade.append(f.y / max(0.01, Vector2(f.x, f.z).length()))
	for i in n:
		var h0: float = atan2(fwd[max(0, i - 1)].x, -fwd[max(0, i - 1)].z)
		var h1: float = atan2(fwd[min(n - 1, i + 1)].x, -fwd[min(n - 1, i + 1)].z)
		kappa.append(wrapf(h1 - h0, -PI, PI) / (DS * float(min(n - 1, i + 1) - max(0, i - 1))))
	length = (n - 1) * DS
	finish_s = length
	start_s = 0.0

func heading_at(s: float) -> float:
	var f := fwd_at(s)
	return atan2(f.x, -f.z)

func _hermite(p0: Vector3, m0: Vector3, p1: Vector3, m1: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return p0 * (2.0 * t3 - 3.0 * t2 + 1.0) + m0 * (t3 - 2.0 * t2 + t) + p1 * (-2.0 * t3 + 3.0 * t2) + m1 * (t3 - t2)

# shortest distance in the ground plane from a point to the main road's centreline between two s
func dist_to_road(p: Vector3, sa: float, sb: float) -> float:
	var best := 1e9
	var s := sa
	while s <= sb:
		var q := pos[_i(s)]
		best = min(best, Vector2(p.x - q.x, p.z - q.z).length())
		s += 4.0
	return best

func _make_branch(f: Dictionary) -> void:
	var b := Road.new()
	b.kind = f.kind
	b.side = int(f.dir)
	var cut: bool = f.kind == "cut"
	b.half = 2.8 if cut else 4.0
	b.edge = b.half + 0.6
	b.s0 = float(f.s_a) + (4.0 if cut else 12.0)
	b.s1 = float(f.s_b) - (4.0 if cut else 12.0)
	var lane := b.side * 5.4
	var p0 := world(b.s0, lane)
	var p1 := world(b.s1, lane)
	var h0 := fwd_at(b.s0)
	var h1 := fwd_at(b.s1)
	h0 = Vector3(h0.x, 0.0, h0.z).normalized()
	h1 = Vector3(h1.x, 0.0, h1.z).normalized()
	var chord: float = Vector2(p1.x - p0.x, p1.z - p0.z).length()
	# the shortcut leaves and rejoins with tight corners and runs straight between; the detour is smoother and longer
	var k_m: float = 1.0 if cut else 1.25
	var pts: Array = []
	for attempt in 6:
		var raw: Array = []
		for i in 401:
			var t := float(i) / 400.0
			raw.append(_hermite(p0, h0 * chord * k_m, p1, h1 * chord * k_m, t))
		# even spacing
		pts = [raw[0]]
		var acc := 0.0
		for i in range(1, raw.size()):
			var seg: float = (raw[i] - raw[i - 1]).length()
			acc += seg
			while acc >= DS:
				acc -= DS
				var q: float = 1.0 - acc / max(0.0001, seg)
				pts.append(raw[i - 1].lerp(raw[i], q))
		pts.append(p1)
		# keep clear of the main road everywhere but where it leaves and rejoins
		var ok := true
		var lim: float = EDGE + b.half + 3.0
		var skip: int = 45 if cut else 25
		for i in range(skip, pts.size() - skip, 3):
			if dist_to_road(pts[i], b.s0 - 60.0, b.s1 + 60.0) < lim:
				ok = false
				break
		if ok:
			break
		k_m *= 0.8
	# flat bend, a hair above the main road's ground
	for i in pts.size():
		var q2: Vector3 = pts[i]
		var t2: float = float(i) / max(1, pts.size() - 1)
		q2.y = lerp(p0.y, p1.y, t2) + 0.05 * sin(PI * t2)
		pts[i] = q2
	b.from_points(pts)
	branches.append(b)
	f["branch"] = branches.size() - 1
	# potholes on the shortcut
	if cut:
		var s := 50.0
		while s < b.length - 50.0:
			s += _rng.randf_range(35.0, 70.0)
			b.bumps.append([s, _rng.randf_range(-b.half + 0.7, b.half - 0.7)])

# main-road progress for a point on branch i
func branch_prog(bi: int, s: float) -> float:
	var b: Road = branches[bi]
	return b.s0 + clamp(s / max(1.0, b.length), 0.0, 1.0) * (b.s1 - b.s0)

func in_branch_zone(s: float, pad: float) -> bool:
	for b in branches:
		if s > b.s0 - pad and s < b.s1 + pad:
			return true
	return false

# ---------- tunnels and overpasses ----------
func _quiet(sa: float, sb: float) -> bool:
	var s := sa
	while s < sb:
		if abs(kappa_at(s)) > 1.0 / 160.0:
			return false
		s += 8.0
	return true

func _pick_tunnels_and_bridges() -> void:
	var taken: Array = []
	var free := func(a: float, b: float) -> bool:
		if a < start_s + 300.0 or b > finish_s - 220.0 or in_branch_zone(a, 160.0) or in_branch_zone(b, 160.0):
			return false
		for x in taken:
			if b > x[0] - 200.0 and a < x[1] + 200.0:
				return false
		return true
	if not city:
		var want := 1 if finish_s < 3200.0 else 2
		var tries := 0
		while want > 0 and tries < 400:
			tries += 1
			var l: float = _rng.randf_range(160.0, 280.0)
			var a: float = _rng.randf_range(start_s + 300.0, finish_s - 300.0 - l)
			if free.call(a, a + l) and _quiet(a, a + l):
				taken.append([a, a + l])
				features.append({"kind": "tunnel", "s_a": a, "s_b": a + l})
				want -= 1
		# a tunnel is a hill: its walls stop you
		for f in features:
			if f.kind == "tunnel":
				var s: float = f.s_a
				while s < f.s_b:
					add_solid(s, -(EDGE + 0.9), 0.5, 2.1)
					add_solid(s, EDGE + 0.9, 0.5, 2.1)
					s += 4.0
	else:
		var want2 := 3 if finish_s < 3200.0 else 4
		var tries2 := 0
		while want2 > 0 and tries2 < 600:
			tries2 += 1
			var s2: float = _rng.randf_range(start_s + 300.0, finish_s - 260.0)
			if free.call(s2 - 30.0, s2 + 30.0) and _quiet(s2 - 40.0, s2 + 40.0):
				taken.append([s2 - 30.0, s2 + 30.0])
				# pillars in the median: whoever rides the double line meets them
				var wide := _rng.randf() < 0.5
				features.append({"kind": "bridge", "s": s2, "wide": wide})
				add_solid(s2, 0.0, 0.42, 0.55)
				for sd in [-1.0, 1.0]:
					add_solid(s2, sd * (EDGE + 1.4), 0.6, 0.6)
				want2 -= 1
	features.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.get("s_a", x.get("s", 0.0))) < float(y.get("s_a", y.get("s", 0.0))))

func feature_at(s: float, kind_v: String) -> Variant:
	for f in features:
		if f.kind == kind_v and s >= float(f.get("s_a", f.get("s", 0.0))) and s <= float(f.get("s_b", f.get("s", 0.0))):
			return f
	return null

# the nearest solid or pothole ahead that sits on the road near d: riders steer round it. [s, d, r]
func solid_ahead(s: float, d: float, look: float) -> Variant:
	var best: Variant = null
	var bs := 1e9
	for bp in bumps:
		var dsb: float = float(bp[0]) - s
		if dsb > 0.0 and dsb < look and abs(d - float(bp[1])) < 1.9 and dsb < bs:
			bs = dsb
			best = [bp[0], bp[1], 0.6]
	var k0 := int(s / 30.0)
	var k1 := int((s + look) / 30.0)
	for k in range(k0, k1 + 1):
		var list: Variant = solid_index.get(k)
		if list == null:
			continue
		for e in list:
			var ds: float = float(e[0]) - s
			if ds > -1.0 and ds < look and abs(float(e[1])) < edge and abs(d - float(e[1])) < float(e[2]) + 1.3 and ds < bs:
				bs = ds
				best = e
	return best

func _i(s: float) -> int:
	return clampi(int(s / DS), 0, n - 2)

func kappa_at(s: float) -> float:
	return kappa[_i(s)]

func grade_at(s: float) -> float:
	return grade[_i(s)]

func world(s: float, d: float, y := 0.0) -> Vector3:
	var i := _i(s)
	var t: float = (s - i * DS) / DS
	var p: Vector3
	if t < 0.0 or t > 1.0:
		# off either end: carry on straight, so a branch blends into the main road it joins
		var e: int = 0 if t < 0.0 else n - 1
		var fh := Vector3(fwd[e].x, 0.0, fwd[e].z).normalized()
		p = pos[e] + fh * (s - e * DS)
		return p + right[e] * d + Vector3.UP * y
	p = pos[i].lerp(pos[i + 1], t)
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
