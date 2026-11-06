class_name Sim extends RefCounted
# The race itself: no graphics, no sound, no engine objects. It can run with no screen, which is how the bot tests it.
# Rules come from the 2D game (data/*.json); distances are real metres, speeds m/s.

const RIDE := 0
const DOWN := 1
const WAIT := 2

const X2M := 7.2          # 2D game's road half-width in metres
const REACH_M := 4.7      # 2D reach numbers to metres
const Z_REACH := 3.0
const BUST_M := 50.0
const G := 9.81
const STEER_F := 0.5      # steering and bend pull, relative to the 2D game. Only their ratio sets how fast a bend can be taken
const LANES := [-5.4, -1.8, 1.8, 5.4]
const MY_LANES := [1.8, 5.4]

class Rider:
	var name := ""
	var is_me := false
	var is_cop := false
	var s := 0.0
	var d := 0.0
	var v := 0.0
	var vx := 0.0
	var psi := 0.0        # heading against the road, radians
	var lat := 0.0        # sideways speed right now, m/s
	var lean := 0.0       # radians, + right
	var a_lat := 0.0
	var sv := 0.0         # steering smoothed
	var push := 0.0
	var state := 0
	var hp := 100.0
	var max_hp := 100.0
	var bike_hp := 100.0
	var weapon := "none"
	var attack: Variant = null  # {type, t, side, w, done}
	var inv := 0.0
	var flash := 0.0
	var stun := 0.0
	var top := 20.0
	var acc := 0.2
	var a_grip := 11.0
	var a_brake := 12.0
	var hand := 70.0
	var dur := 100.0
	var prot := 0.0
	var no_hand := false
	var hit_mul := 1.0
	var reach_k := 1.0
	var skill := 1.0
	var aggr := 0.5
	var ch: Variant = null      # rival character
	var style := ""
	var bike: Dictionary = {}
	var look: Dictionary = {}
	var cd := 2.0
	var hit_t := -99.0
	var angry := 0.0
	var lane := 1.8
	var lane_t := 3.0
	var look_t := 0.0
	var lim := 1e9
	var finished := false
	var said := false
	var out := false
	var down_t := 0.0
	var down_dur := 2.0
	# rider's own flight while the bike slides
	var fly_s := 0.0
	var fly_d := 0.0
	var fly_y := 0.0
	var fly_vy := 0.0
	var fly_v := 0.0
	var fly_vd := 0.0
	var spin := 0.0
	var bike_rot := 0.0
	# gears
	var gear := 0
	var gears := 3
	var shift_t := 0.0
	var shift_len := 0.1
	var rpm := 0.1
	var gas_on := false
	var slide := false
	# player only
	var st: Dictionary = {}
	var off_t := 0.0
	var falls := 0
	var dead := false
	var bustable := false
	var last_hit := -99.0
	var scrape_t := -99.0
	var start_w := "none"
	var start_gone := false
	var target: Rider = null     # cop: who he is after
	var retarget_t := 0.0
	var last_side := 1
	var fall_kmh := 0.0
	var bot_lane := 1.8
	var bot_block := 0.0

class Car:
	var s := 0.0
	var d := 0.0
	var v := 0.0        # signed: + travels with us, - oncoming
	var dir := 1
	var v0 := 10.0      # the speed this driver wants, never above the limit for its type
	var hw := 0.95
	var len := 4.4
	var kind := "sedan"
	var color := Color.WHITE
	var lead: Variant = null
	var braking := false

const CAR_DEF := {"sedan": [0.95, 4.4], "van": [1.05, 5.2], "truck": [1.3, 8.0]}
# how drivers keep their distance (Intelligent Driver Model, a standard traffic formula)
const CAR_A := 2.4         # gentle acceleration, m/s2
const CAR_B := 4.0         # comfortable braking, m/s2
const CAR_BRAKE_MAX := 11.0
const CAR_T := 0.9         # seconds of headway
const CAR_S0 := 3.0        # metres left to whatever it stopped behind
const CAR_LOOK := 170.0
const CAR_AB2 := 6.197     # 2 * sqrt(A * B)
const CAR_COLS := ["#c0392b", "#2f6fb0", "#d8d8d8", "#3a3a42", "#b08a2e", "#3f7a55", "#6f4aa8"]

var road: Road
var tr: Dictionary
var track_i := 0
var v_top := 20.0
var me: Rider
var foes: Array[Rider] = []
var cops: Array[Rider] = []
var cars: Array[Car] = []
var riders: Array[Rider] = []
var phase := "count"
var t := 0.0
var count := 3.0
var inp := {"steer": 0.0, "gas": false, "brake": false, "hand": false, "kick": false}
var bot := false
var bot_peace := false
var bot_human := false   # bot presses buttons like a thumb: full left, full right or nothing, with a reaction delay
var _hum_t := 0.0
var _hum_steer := 0.0
var demo := false
var order: Array[Rider] = []
var final_place := 0
var end_kind := ""
var end_t := 0.0
var next_atk := 0.0
var say_at := 0.0
var stats := {"ko": 0, "cop_ko": 0, "shifts": 0, "t_finish": 0.0}
var events: Array = []    # for sound and effects, drained by the view each frame
var banner := ""
var banner_bad := false
var say_txt := ""
var rng := RandomNumberGenerator.new()

func ev(kind: String, a: Variant = null, b: Variant = null) -> void:
	events.append([kind, a, b])

# what the speedometer shows for a rider going at world speed v
func dial(r: Rider, v: float) -> float:
	var top_kmh: float = r.st.kmh if r.is_me else float(r.bike.kmh)
	return v / max(1.0, r.top) * top_kmh

func show_banner(txt: String, bad := false) -> void:
	banner = txt
	banner_bad = bad
	ev("banner", txt, bad)

func setup(track_index: int, bike_id: String, upgrades := {}, ts := 2, th := 2, cs := 0, ch := 0, seed_v := 1, extra := {}) -> void:
	track_i = track_index
	tr = D.tracks[track_index]
	rng.seed = seed_v
	v_top = D.world_speed(tr.kmh)
	road = Road.new()
	road.build(tr)
	var b: Dictionary = D.bike_by_id[bike_id]
	var glove: int = extra.get("glove", 0)
	var boot: int = extra.get("boot", 0)
	var st := D.rider_stats(b, upgrades, ts, th, glove, boot, extra.get("weapon", "none"))
	me = Rider.new()
	me.is_me = true
	me.name = "Ты"
	me.st = st
	me.bike = b
	me.s = road.start_s
	me.d = 1.8
	me.top = st.top
	me.acc = st.accel
	me.a_grip = st.a_grip
	me.a_brake = st.a_brake
	me.prot = st.prot
	me.no_hand = st.no_hand
	me.bike_hp = st.dur
	me.dur = st.dur
	me.gears = st.gears
	me.shift_len = st.shift
	me.reach_k = st.reach_k
	me.weapon = st.weapon
	me.start_w = st.weapon
	me.look = {"outfit": D.outfit(ts, cs, ch, glove, boot), "helmet": th, "paint": int(extra.get("paint", b.paint))}
	var roster: Array = tr.roster
	for k in roster.size():
		var e: Array = roster[k]
		var c: Dictionary = D.rivals[e[0]]
		var rb: Dictionary = D.bike_by_id[e[1]]
		var fx := D.gear_fx(int(c.suit), int(c.helmet))
		var row := int(k / 2)
		var f := Rider.new()
		f.name = c.name
		f.ch = c
		f.style = c.style
		f.skill = c.skill
		f.aggr = c.aggr
		f.weapon = e[2] if e.size() > 2 else c.get("weapon", "none")
		f.s = me.s + (3 - row) * 6.0
		f.d = 5.4 if (k == 6 or k % 2 == 0) else 1.8
		f.lane = f.d
		f.max_hp = tr.foeHp * c.hp
		f.hp = f.max_hp
		f.bike = rb
		f.top = D.world_speed(rb.kmh * (1.0 - D.aero_loss(fx.aero, rb.kmh)))
		f.acc = rb.acc * (1.0 - D.weight_loss(fx.kg, rb.hp))
		f.a_grip = D.a_grip(rb.grip, rb.hand)
		f.a_brake = D.a_brake(rb.grip, f.top)
		f.hand = rb.hand
		f.dur = rb.dur
		f.prot = fx.prot
		f.no_hand = fx.no_hand
		f.hit_mul = fx.kick if fx.no_hand else fx.hit
		f.reach_k = fx.reach_k
		if fx.no_hand:
			f.weapon = "none"
		f.cd = rng.randf_range(1.2, 2.6)
		f.lane_t = rng.randf_range(2.0, 5.0)
		var lg: Dictionary = D.leagues[int(rb.cat)]
		f.gears = int(lg.gears)
		f.look = {"outfit": D.outfit(int(c.suit), int(c.c), int(c.h)), "helmet": int(c.helmet), "paint": int(c.paint)}
		foes.append(f)
	var cop_i := 0
	for fr in tr.cops:
		var c2 := Rider.new()
		c2.name = "Инспектор" + ("" if cop_i == 0 else " %d" % (cop_i + 1))
		c2.is_cop = true
		c2.state = WAIT
		c2.s = road.finish_s * fr
		c2.d = 9.2
		c2.max_hp = tr.copHp
		c2.hp = c2.max_hp
		c2.top = v_top
		c2.acc = 0.3
		c2.a_grip = 13.0
		c2.a_brake = D.a_brake(70.0, v_top)
		c2.weapon = "baton"
		c2.cd = 1.0
		c2.dur = 999.0
		var art: String = D.leagues[int(tr.cat)].cop
		c2.bike = {"art": art, "kmh": tr.kmh, "name": "Полиция", "cat": tr.cat, "cc": 0}
		c2.look = {"outfit": {"jacket": "#1f3f8a", "stripe": "#f3eedf", "pants": "#1a2a55", "boots": "#0e0e12", "glove": "#16151b", "skin": "#e0b48c", "helmet": "#e9e6dc", "hs": "#1f3f8a", "sleeve": "#1f3f8a"}, "helmet": 2, "paint": -1}
		foes.append(c2)
		cops.append(c2)
		cop_i += 1
	riders.append(me)
	for f2 in foes:
		riders.append(f2)
	_make_cars()

func _make_cars() -> void:
	var r2 := RandomNumberGenerator.new()
	r2.seed = int(tr.seed) + 1
	var types := ["sedan", "sedan", "van", "sedan", "truck"]
	var zspan := road.finish_s - road.start_s
	var limits: Dictionary = D.rules.traffic.max_kmh
	var add := func(ln: int, share: float, e: float) -> void:
		var c := Car.new()
		c.kind = types[r2.randi() % types.size()]
		c.hw = CAR_DEF[c.kind][0]
		c.len = CAR_DEF[c.kind][1]
		c.color = Color(CAR_COLS[r2.randi() % CAR_COLS.size()])
		c.d = LANES[ln]
		c.dir = 1 if ln >= 2 else -1
		c.v0 = min(share * v_top, D.world_speed(float(limits[c.kind])))
		c.v = c.dir * c.v0
		# spread so that a rider at league speed meets them evenly through the race
		c.s = road.start_s + zspan * e * (1.0 - c.dir * c.v0 / (v_top * 0.9))
		cars.append(c)
	var prev := -1
	var total: int = int(round(float(tr.cars) * float(D.rules.traffic.density)))
	for k in total:
		var ln := 2 if r2.randf() < 0.5 else 3
		if ln == prev and r2.randf() < 0.6:
			ln = 5 - ln
		prev = ln
		var e: float = lerp(0.07, 0.96, float(k) / total) + r2.randf() * 0.015
		add.call(ln, 0.5 if ln == 2 else 0.38, e)
	var on := int(round(total * 0.8))
	for k in on:
		var ln := 1 if r2.randf() < 0.55 else 0
		var e: float = lerp(0.05, 0.98, float(k) / on) + r2.randf() * 0.02
		add.call(ln, 0.5 if ln == 1 else 0.42, e)
	link_cars()

# each car follows the next one ahead in its lane; they start spaced out and never swap order
func link_cars() -> void:
	for lane in LANES:
		var list: Array[Car] = []
		for c in cars:
			if is_equal_approx(c.d, lane):
				list.append(c)
		list.sort_custom(func(a: Car, b: Car) -> bool: return a.dir * a.s > b.dir * b.s)
		for i in list.size():
			var c: Car = list[i]
			c.lead = null
			if i > 0:
				var l: Car = list[i - 1]
				c.lead = l
				var room: float = (l.len + c.len) * 0.5 + 12.0
				if c.dir * (l.s - c.s) < room:
					c.s = l.s - c.dir * room

func _update_car(c: Car, dt: float) -> void:
	if c.dir > 0 and c.s >= road.length - 30.0:
		c.v = 0.0
		c.braking = false
		return
	if c.dir < 0 and c.s < -100.0:
		return
	var speed: float = abs(c.v)
	var gap := 1e9
	var obs_v := 0.0
	if c.lead != null:
		var l: Car = c.lead
		gap = c.dir * (l.s - c.s) - (l.len + c.len) * 0.5
		obs_v = abs(l.v)
	var reach: float = c.hw + 1.0
	for r in riders:
		if r.state == WAIT:
			continue
		var fallen: bool = r.state == DOWN
		var rv: float = r.v
		if c.dir < 0:
			# oncoming drivers only stop for someone lying or standing in their lane; riding at them stays deadly
			if not fallen and r.v > 4.0:
				continue
			rv = 0.0
		if abs(r.d - c.d) < reach or abs(r.d + r.lat * 0.35 - c.d) < reach:
			var g: float = c.dir * (r.s - c.s) - c.len * 0.5 - 1.0
			if g > -1.5 and g < CAR_LOOK and g < gap:
				gap = g
				obs_v = rv
		if fallen and abs(r.fly_d - c.d) < reach:
			var g2: float = c.dir * (r.fly_s - c.s) - c.len * 0.5 - 0.6
			if g2 > -1.5 and g2 < CAR_LOOK and g2 < gap:
				gap = g2
				obs_v = max(0.0, r.fly_v) if c.dir > 0 else 0.0
	var ratio: float = speed / c.v0
	var free: float = ratio * ratio * ratio * ratio
	var a: float
	if gap < 1e8:
		var s_star: float = max(CAR_S0, CAR_S0 + speed * CAR_T + speed * (speed - obs_v) / CAR_AB2)
		var q: float = s_star / max(gap, 0.1)
		a = CAR_A * (1.0 - free - q * q)
	else:
		a = CAR_A * (1.0 - free)
	a = max(a, -CAR_BRAKE_MAX)
	speed = max(0.0, speed + a * dt)
	c.braking = a < -1.2
	c.v = c.dir * speed
	c.s += c.v * dt
	if c.lead != null:
		var l2: Car = c.lead
		var touch: float = (l2.len + c.len) * 0.5 + 0.5
		if c.dir * (l2.s - c.s) < touch:
			c.s = l2.s - c.dir * touch
			c.v = c.dir * min(speed, abs(l2.v))

# Getting back on the bike: never inside a car, whichever lane has room
func _safe_spawn(r: Rider) -> void:
	for lane in [r.d, 1.8, 5.4]:
		var clear := true
		for c in cars:
			if c.dir > 0 and abs(c.s - r.s) < c.len * 0.5 + 4.0 and abs(c.d - lane) < c.hw + 0.6:
				clear = false
				break
		if clear:
			r.d = lane
			return
	var ahead: float = r.s
	for c in cars:
		if c.dir > 0 and abs(c.s - r.s) < c.len * 0.5 + 4.0:
			ahead = max(ahead, c.s + c.len * 0.5 + 4.0)
	r.s = ahead

# Touching traffic. Told apart by where the contact happened, and nobody ever stays inside a car.
# Only a square hit is a crash; clipping a corner or rubbing a side throws you off with a scratch.
func _car_contact(dt: float) -> void:
	var m := me
	for c in cars:
		var halfs: float = c.len * 0.5 + 1.0
		var dd: float = c.s - m.s
		if abs(dd) >= halfs:
			continue
		var halfw: float = c.hw + 0.3
		var dw: float = c.d - m.d
		if abs(dw) >= halfw:
			continue
		var kmh: float = dial(m, m.v)
		var rel: float = m.v - c.v
		var depth: float = halfw - abs(dw)
		var glancing: bool = depth < 0.35
		var from_end: bool = halfs - abs(dd) <= abs(rel) * dt * 1.6 + 0.08
		if c.dir < 0:
			if glancing:
				_scrape(c, dw, rel)
				continue
			m.s = min(m.s, c.s - halfs)
			m.v = 0.0
			crash("head", kmh + min(60.0, abs(c.v) * 3.6))
			return
		if from_end and dd > 0.0 and rel > 0.0 and not glancing:
			# rode square into its tail
			m.s = c.s - halfs
			m.v = max(0.0, c.v) * 0.4
			crash("car", kmh)
			return
		if from_end and dd <= 0.0 and rel <= 0.0:
			# cut in so close it could not stop: it shoves you, and hard if it was going much faster
			c.s = m.s - halfs
			c.v = m.v
			if -rel > 8.0:
				crash("rear", dial(m, -rel))
				return
			m.v = min(m.top, m.v - rel * 0.5)
			ev("bump")
			continue
		if abs(rel) > 22.0 and not glancing:
			if dd <= 0.0 and rel < 0.0:
				c.s = m.s - halfs
				c.v = m.v
				crash("rear", dial(m, -rel))
				return
			m.v = max(0.0, c.v) * 0.4
			crash("car", kmh)
			return
		_scrape(c, dw, rel)

func _scrape(c: Car, dw: float, rel: float) -> void:
	var m := me
	var side: float = -1.0 if dw > 0.0 else 1.0
	m.d = c.d + side * (c.hw + 0.3)
	m.push = side * 3.0
	m.sv = 0.0
	if rel > 0.0:
		m.v = max(m.v * 0.85, c.v if c.dir > 0 else 0.0)
	if t - m.scrape_t > 0.5:
		m.scrape_t = t
		m.bike_hp = max(1.0, m.bike_hp - 2.0 - abs(rel) * 0.15)
		m.hp = max(1.0, m.hp - abs(rel) * 0.25)
		m.last_hit = t
		m.flash = 0.08
		ev("scrape")

# ---------- combat ----------
func weapon_def(w: String) -> Dictionary:
	return D.gear.weapons[w]

func nearest_foe() -> Rider:
	var best: Rider = null
	var bs := 1e9
	for f in foes:
		if f.state != RIDE and f.state != WAIT:
			continue
		var dz: float = f.s - me.s
		if abs(dz) > Z_REACH:
			continue
		var sc: float = abs(f.d - me.d) + abs(dz) * 0.3
		if sc < bs:
			bs = sc
			best = f
	return best

func try_attack(kind: String) -> void:
	if phase != "race" or me.state != RIDE or me.attack != null:
		return
	if kind == "hand" and me.no_hand:
		ev("denied")
		show_banner("Комбез не даёт ударить", true)
		return
	var base: Dictionary = D.gear.kick if kind == "kick" else weapon_def(me.weapon)
	var tg := nearest_foe()
	var cdk: float = me.st.cd_k
	var w := {"reach": base.reach * REACH_M * me.reach_k, "cd": base.cd * cdk, "hit_at": base.hitAt * cdk, "dmg": base.dmg}
	var side := 1
	if tg != null:
		side = 1 if tg.d >= me.d else -1
	elif me.sv > 0.1:
		side = 1
	elif me.sv < -0.1:
		side = -1
	else:
		side = me.last_side
	me.last_side = side
	me.attack = {"type": kind, "t": 0.0, "side": side, "w": w, "done": false, "weapon": "none" if kind == "kick" else me.weapon}
	if tg != null and abs(tg.d - me.d) < w.reach + 0.5:
		me.push += side * 2.5

func _resolve_hit(a: Dictionary) -> void:
	var list: Array[Rider] = []
	for f in foes:
		if f.state != RIDE and f.state != WAIT:
			continue
		var dz: float = f.s - me.s
		var dx: float = f.d - me.d
		if abs(dz) > Z_REACH or abs(dx) > a.w.reach or dx * a.side < -0.8:
			continue
		list.append(f)
	list.sort_custom(func(p: Rider, q: Rider) -> bool: return abs(p.d - me.d) < abs(q.d - me.d))
	if list.is_empty():
		ev("whiff")
		return
	var n := 3 if (a.type == "hand" and me.weapon == "chain") else 1
	for i in min(n, list.size()):
		_hit_foe(list[i], a)

func _hit_foe(f: Rider, a: Dictionary) -> void:
	if f.inv > 0.0:
		return
	var st := me.st
	var kick: bool = a.type == "kick"
	var dmg: float
	if kick:
		dmg = st.kick
	elif me.weapon == "none":
		dmg = st.fist
	else:
		dmg = max(1.0, round(a.w.dmg * st.hit_k))
	if f.state == WAIT:
		_start_chase(f)
	f.hit_t = t
	f.angry = 6.0
	f.hp -= dmg * (1.0 - 0.5 * f.prot)
	f.stun = 0.45
	f.flash = 0.12
	f.push += a.side * (2.6 if kick else 0.6) * X2M * 0.8 * (st.push if kick else 1.0)
	ev("hit", f, "kick" if kick else me.weapon)
	_say(f, 0.3)
	if f.hp <= 0.0:
		ko_foe(f, a.side, true, "")

func ko_foe(f: Rider, side: int, by_me: bool, why: String) -> void:
	var kmh := dial(f, f.v)
	var knock := why == ""
	var inj: float = kmh * D.rules.fall_k * (1.0 - f.prot) * (0.6 if knock else 1.0)
	var health: float = 50.0 if knock else clamp(f.hp / f.max_hp * 100.0, 15.0, 100.0)
	if why != "":
		f.dur -= 30.0 if why == "car" else 25.0
	f.out = not f.is_cop and (inj >= health * 1.5 or f.dur <= 0.0)
	f.state = DOWN
	f.down_t = 0.0
	f.down_dur = 1e9 if (f.is_cop or f.out) else 2.5 + inj / 18.0
	f.attack = null
	f.bike_rot = 0.0
	f.push = side * 1.3 * X2M * 0.5
	_launch(f, side)
	if abs(f.s - me.s) < 120.0:
		ev("ko", f, why)
	if f.is_cop:
		var any_left := false
		for c in cops:
			if c.state == RIDE:
				any_left = true
		if not any_left:
			ev("siren", false)
	var mine := by_me or (t - f.hit_t < 2.5)
	if mine and not f.is_cop:
		stats.ko += 1
	if f.is_cop:
		if mine:
			stats.cop_ko += 1
		show_banner("Коп вырублен" if mine else "Коп разбился")
	elif f.out and mine:
		show_banner("Выбывает: " + f.name)
	elif why == "pole" and mine:
		show_banner("В столб!")
	elif by_me:
		show_banner("Нокаут")
	if by_me and not me.no_hand and f.weapon != "none" and weapon_def(f.weapon).rank > weapon_def(me.weapon).rank:
		var w := f.weapon
		lose_weapon()
		me.weapon = w
		if not f.is_cop:
			f.weapon = "none"
		show_banner(weapon_def(w).win)
		ev("weapon")

func _launch(r: Rider, side: int) -> void:
	r.fly_s = r.s
	r.fly_d = r.d
	r.fly_y = 0.9
	r.fly_vy = rng.randf_range(2.8, 4.2)
	r.fly_v = r.v * 0.92
	r.fly_vd = side * rng.randf_range(0.6, 2.2)
	r.spin = rng.randf_range(4.0, 9.0) * (1.0 if rng.randf() < 0.5 else -1.0)

func _update_flight(r: Rider, dt: float) -> void:
	r.fly_vy -= G * dt
	r.fly_y += r.fly_vy * dt
	var on_ground := r.fly_y <= 0.18
	if on_ground:
		r.fly_y = 0.18
		r.fly_vy = abs(r.fly_vy) * 0.34
		if r.fly_vy < 0.5:
			r.fly_vy = 0.0
		r.fly_v = max(0.0, r.fly_v - 9.0 * dt * 4.0)
		r.fly_vd *= exp(-3.0 * dt)
		r.spin *= exp(-2.6 * dt)
	r.fly_s += r.fly_v * dt
	r.fly_d = clamp(r.fly_d + r.fly_vd * dt, -13.0, 13.0)

func hurt_me(dmg: float, side: int) -> void:
	if me.inv > 0.0 or me.state != RIDE or phase != "race":
		return
	dmg = round(dmg * (1.0 - 0.5 * me.prot))
	me.hp -= dmg
	me.last_hit = t
	me.flash = 0.12
	me.push += side * 0.9 * X2M * 0.6
	ev("hurt", dmg)
	if me.hp <= 0.0:
		me.hp = 0.0
		crash("knock")

func lose_weapon() -> String:
	var w := me.weapon
	if w == "none":
		return ""
	if me.start_w == w and not me.start_gone:
		me.start_gone = true
		ev("stock", w)
	me.weapon = "none"
	ev("weapon")
	return w

func crash(why: String, kmh_at := -1.0) -> void:
	if me.state != RIDE or me.inv > 0.0 or phase != "race":
		return
	var kmh: float = dial(me, me.v) if kmh_at < 0.0 else kmh_at
	me.bustable = false
	for c in cops:
		if c.state == RIDE and abs(c.s - me.s) < BUST_M:
			me.bustable = true
	me.state = DOWN
	me.down_t = 0.0
	me.attack = null
	me.falls += 1
	me.bike_rot = 0.0
	var loss := {"head": 45.0, "car": 30.0, "pole": 25.0, "rear": 20.0, "off": 18.0}.get(why, 12.0) as float
	me.bike_hp = max(0.0, me.bike_hp - loss)
	var inj: float = kmh * D.rules.fall_k * (1.0 - me.prot)
	if why == "knock":
		me.hp = max(me.hp, 50.0)
		inj *= 0.6
	me.hp = max(0.0, me.hp - inj)
	me.fall_kmh = round(kmh)
	me.dead = me.hp <= 0.0
	_launch(me, 1 if me.lean >= 0.0 else -1)
	var lost := lose_weapon()
	if me.dead:
		show_banner("Скорая уже едет", true)
	elif lost != "":
		show_banner("Потерял " + str(weapon_def(lost).acc), true)
	elif why == "off":
		show_banner("Вылетел с дороги", true)
	elif why == "head":
		show_banner("Лоб в лоб", true)
	elif why == "rear":
		show_banner("Въехали сзади", true)
	elif why != "knock":
		show_banner("Авария", true)
	else:
		show_banner("Тебя вырубили", true)
	ev("crash", why)

func _start_chase(c: Rider, who: Rider = null) -> void:
	c.state = RIDE
	c.target = who if who != null else me
	c.v = max(c.v, c.target.v * 0.35)
	c.lane = 5.4
	if abs(c.s - me.s) < 150.0:
		show_banner("Сирена!", true)
	ev("siren", true)

# Cops go for whichever racer is closest. Whoever just hit one gets his full attention.
func _nearest_racer(f: Rider) -> Rider:
	var best: Rider = null
	var bd := 1e9
	for r in riders:
		if r.is_cop or r.state != RIDE or r.finished:
			continue
		if r.is_me and phase != "race":
			continue
		var dist: float = abs(r.s - f.s) + abs(r.d - f.d) * 0.5
		if dist < bd:
			bd = dist
			best = r
	return best

func _pick_target(f: Rider) -> void:
	if f.angry > 0.0 and me.state == RIDE and phase == "race":
		f.target = me
		return
	var near := _nearest_racer(f)
	if near == null:
		f.target = null
		return
	var cur := f.target
	var keep: bool = cur != null and cur.state == RIDE and not cur.finished and (not cur.is_me or phase == "race")
	if keep:
		var cur_d: float = abs(cur.s - f.s) + abs(cur.d - f.d) * 0.5
		var near_d: float = abs(near.s - f.s) + abs(near.d - f.d) * 0.5
		if cur_d < near_d + 5.0:
			return
	f.target = near

func _cop_hit(f: Rider, tg: Rider, w: Dictionary, side: int) -> void:
	if tg.inv > 0.0 or tg.state != RIDE:
		return
	var near_me: bool = abs(tg.s - me.s) < 120.0
	tg.hp -= w.foe * tr.foeDmg * 1.2 * (1.0 - 0.5 * tg.prot)
	tg.stun = 0.45
	tg.flash = 0.12
	tg.push += side * 2.5
	if near_me:
		ev("hit", tg, f.weapon)
	if tg.hp <= 0.0:
		ko_foe(tg, side, false, "")
		# a rival the police knock off the bike stays with the police
		tg.out = true
		tg.down_dur = 1e9
		if near_me:
			show_banner("Коп взял: " + tg.name)

func _say(f: Rider, chance: float) -> void:
	if f.ch == null or rng.randf() > chance or t < say_at:
		return
	say_at = t + 3.5
	var l: Array = f.ch.say
	say_txt = f.name + ": " + str(l[rng.randi() % l.size()])
	ev("say", say_txt)

func live_place() -> int:
	var p := 1
	for f in foes:
		if not f.is_cop and f.s > me.s:
			p += 1
	return p

# ---------- bends: how fast a rider can be here and still make everything he can see ----------
func corner_limit(s: float, v: float, a_grip: float, a_brake: float, margin := 0.92) -> float:
	var lim := 1e9
	var look: float = max(50.0, v * v / (2.0 * a_brake) + v * 0.8)
	var ds := 8.0
	var x := 0.0
	while x < look:
		var k: float = abs(road.kappa_at(s + x))
		if k > 0.0005:
			var vk := sqrt(a_grip * margin / k)
			var allowed := sqrt(vk * vk + 2.0 * a_brake * 0.9 * max(0.0, x - v * 0.25))
			lim = min(lim, allowed)
		x += ds
	return lim

# ---------- player ----------
# Same steering model as the 2D game, in metres per second across the road:
# the bars give a sideways speed, a bend pulls you to its outside with the square of your speed.
func steer_auth(m: Rider) -> float:
	var pct: float = m.v / m.top
	var auth: float = 2.5 * m.st.steer * (0.4 + 0.6 * min(1.0, pct * 1.4)) * (1.0 - 0.25 * pct) * X2M * STEER_F
	return min(auth, m.v * 0.75)

func bend_pull(m: Rider, s: float) -> float:
	return road.kappa_at(s) * m.v * m.v * 1.487 * m.st.grip_f * STEER_F

func gear_span(k: int) -> float:
	return pow(float(k + 1) / me.gears, 0.72) * (1.06 if k == me.gears - 1 else 1.0)

func _update_gear(dt: float, pulling: bool) -> void:
	var p: float = me.v / me.top
	if me.shift_t > 0.0:
		me.shift_t -= dt
	if me.state == RIDE and me.shift_t <= 0.0:
		if pulling and me.gear < me.gears - 1 and p / gear_span(me.gear) >= 0.97:
			me.gear += 1
			me.shift_t = me.shift_len
			stats.shifts += 1
			ev("shift", true)
		elif me.gear > 0 and p < gear_span(me.gear - 1) * 0.6:
			me.gear -= 1
			me.shift_t = me.shift_len * 0.5
			ev("shift", false)
	var target: float = clamp(p / gear_span(me.gear), 0.28 if me.v > me.top * 0.02 else 0.1, 1.0)
	me.rpm += (target - me.rpm) * min(1.0, dt * (30.0 if me.shift_t > 0.0 else 14.0))

func _lane_clear(lane: float, within_extra: float) -> bool:
	for o in cars:
		var e: float = o.s - me.s
		var closing: float = me.v - o.v
		if e > -8.0 and e < max(30.0, closing * 2.4) + within_extra and abs(o.d - lane) < o.hw + 1.1:
			return false
	return true

# nothing alongside between here and that lane
func _path_clear(lane: float) -> bool:
	var lo: float = min(me.d, lane)
	var hi: float = max(me.d, lane)
	for o in cars:
		var e: float = o.s - me.s
		if e > -o.len and e < 7.0 + max(0.0, me.v - o.v) * 0.7 and o.d + o.hw + 0.5 > lo and o.d - o.hw - 0.5 < hi and abs(o.d - me.d) > 0.3:
			return false
	return true

func _bot_input() -> void:
	var lim := corner_limit(me.s, me.v, me.a_grip, me.a_brake, 0.9)
	var tx := me.bot_lane
	me.bot_block = 0.0
	if not _lane_clear(tx, 0.0):
		var free: Array = []
		for v2 in [1.8, 5.4, -1.8, -5.4]:
			if _lane_clear(v2, 8.0) and _path_clear(v2):
				free.append(v2)
		if free.size() > 0:
			free.sort_custom(func(a: float, b: float) -> bool: return abs(a - me.d) + (6.0 if a < 0.0 else 0.0) < abs(b - me.d) + (6.0 if b < 0.0 else 0.0))
			tx = free[0]
		else:
			for c in cars:
				var e: float = c.s - me.s
				var closing: float = max(0.0, me.v - c.v)
				if c.dir > 0 and e > 0.0 and e < closing * closing / 18.0 + 18.0 and abs(c.d - me.d) < 2.2:
					me.bot_block = max(0.05, c.v * 0.95)
					break
	elif tx < 0.0 and _lane_clear(1.8, 15.0):
		tx = 1.8
	me.bot_lane = tx
	inp.steer = clamp((tx - me.d) * 0.55 + bend_pull(me, me.s) / max(1.0, steer_auth(me)), -1.0, 1.0)
	if bot_human:
		_hum_t -= 1.0 / 60.0
		if _hum_t <= 0.0:
			_hum_t = 0.1
			_hum_steer = 0.0 if abs(inp.steer) < 0.3 else sign(inp.steer)
		inp.steer = _hum_steer
	if me.bot_block > 0.0 and me.v > me.bot_block:
		inp.gas = false
		inp.brake = true
	else:
		inp.gas = me.v < lim * 0.97
		inp.brake = me.v > lim * 1.02
	inp.hand = false
	inp.kick = false
	if not bot_peace:
		var tg := nearest_foe()
		if tg != null and abs(tg.d - me.d) < weapon_def(me.weapon).reach * REACH_M:
			if me.no_hand or rng.randf() < 0.25:
				inp.kick = true
			else:
				inp.hand = true

func _update_me(dt: float) -> void:
	var m := me
	var top := m.top
	var pct: float = m.v / top
	var k_road := road.kappa_at(m.s)
	m.inv = max(0.0, m.inv - dt)
	m.flash = max(0.0, m.flash - dt)
	var stopping := phase == "finish" or phase == "over"
	var auto := phase != "race" or bot
	if m.state == RIDE:
		if auto and not stopping:
			_bot_input()
		var steer: float = inp.steer
		var brk: bool = inp.brake and not stopping
		var gas: bool = inp.gas and not brk and not stopping
		var pull: float = bend_pull(m, m.s)
		var auth: float = steer_auth(m)
		if stopping:
			steer = clamp((clamp(m.d, 1.8, 5.4) - m.d) * 0.55 + pull / max(1.0, auth), -1.0, 1.0)
		m.sv += (steer - m.sv) * min(1.0, dt * 7.0)
		var off: bool = abs(m.d) > Road.EDGE
		var over: bool = abs(pull) > auth * 1.15
		m.slide = abs(pull) > auth * 0.82 and m.v > top * 0.3
		var bars: float = m.sv * auth * (0.68 if over else (0.88 if m.slide else 1.0))
		var lateral: float = bars - pull
		m.lat = lateral + m.push
		m.d += m.lat * dt
		m.push *= exp(-5.0 * dt)
		# what you see: the bike points where it is really going and leans for the turn it is actually making
		var want_psi: float = atan2(lateral + m.push, max(4.0, m.v))
		m.psi += (want_psi - m.psi) * min(1.0, dt * 9.0)
		var v2: float = m.v * m.v
		var a_req: float = v2 * road.kappa_at(m.s)
		var q: float = bars / pull if abs(pull) > 0.5 else 0.0
		var a_eff: float = a_req * clamp(q, -0.2, 1.25)
		var want_lean: float = atan2(a_eff, G) * 0.8 + m.sv * 0.24 * (1.0 - min(1.0, abs(q)))
		want_lean = clamp(want_lean, -0.75, 0.75) * clamp(m.v / 8.0, 0.0, 1.0)
		m.lean += (want_lean - m.lean) * min(1.0, dt * 10.0)
		m.s += m.v * cos(m.psi) * dt
		# pedals
		m.gas_on = gas
		if stopping:
			m.v -= top * 0.3 * dt
		elif brk:
			m.v -= m.a_brake * dt
		elif gas:
			if m.shift_t <= 0.0:
				m.v += top * m.acc * dt * max(0.04, 1.0 - 0.96 * pct)
		else:
			m.v -= top * (0.02 + 0.05 * pct) * dt
		m.v -= G * road.grade_at(m.s) * 0.55 * dt
		if off and m.v > top * 0.4:
			m.v -= top * 0.75 * m.st.off * dt
			ev("dust")
		m.v = clamp(m.v, 0.0, top)
		if phase == "race" and m.inv <= 0.0:
			_car_contact(dt)
			if m.state == RIDE:
				if off and pct > 0.62 and dial(m, m.v) > 110.0:
					m.off_t += dt
				else:
					m.off_t = max(0.0, m.off_t - dt * 2.0)
				if m.off_t > 0.3:
					m.off_t = 0.0
					crash("off")
			if m.state == RIDE and abs(m.d) > Road.EDGE and road.solid_hit(m.s, m.d):
				crash("pole")
		m.d = clamp(m.d, -12.4, 12.4)
		if m.state == RIDE:
			if m.attack != null:
				var a: Dictionary = m.attack
				a.t += dt
				if not a.done and a.t >= a.w.hit_at:
					a.done = true
					_resolve_hit(a)
				if m.attack != null and a.t >= a.w.cd:
					m.attack = null
			elif phase == "race":
				if inp.hand:
					try_attack("hand")
				elif inp.kick:
					try_attack("kick")
			if m.hp < 100.0 and t - m.last_hit > 4.0 and phase == "race":
				m.hp = min(100.0, m.hp + 1.5 * dt)
	else:
		m.down_t += dt
		m.gear = 0
		m.v = max(0.0, m.v - 14.0 * dt)
		m.s += m.v * dt
		m.d += m.push * dt
		m.push *= exp(-3.0 * dt)
		m.bike_rot = min(1.0, m.bike_rot + dt * 5.0)
		m.lean = m.lean
		_update_flight(m, dt)
		if phase == "race":
			if m.dead:
				if m.down_t > 1.6:
					end_race("dead")
			elif m.down_t > 0.8 and m.bustable:
				end_race("busted")
			if phase == "race" and not m.dead and m.down_t > 1.4 and m.bike_hp <= 0.0:
				end_race("wrecked")
			if phase == "race" and not m.dead and m.down_t > 2.2:
				m.state = RIDE
				m.d = clamp(m.fly_d, 1.8, 5.4) if abs(m.fly_d) > 0.0 else 1.8
				m.s = max(m.s, m.fly_s - 2.0)
				_safe_spawn(m)
				m.off_t = 0.0
				m.v = 0.0
				m.hp = max(m.hp, 15.0)
				m.inv = 1.8
				m.sv = 0.0
				m.push = 0.0
				m.lean = 0.0
				m.a_lat = 0.0
				m.psi = 0.0
				m.bike_rot = 0.0
				ev("up")
	_update_gear(dt, m.state == RIDE and not stopping and m.gas_on)
	if phase == "race" and m.s >= road.finish_s:
		final_place = live_place()
		stats.t_finish = t
		end_kind = "finish"
		end_t = 2.2
		phase = "finish"
		show_banner("Первый!" if final_place == 1 else "Финиш")
		ev("siren", false)
		if m.state == DOWN:
			m.state = RIDE
			m.inv = 9.0

func end_race(kind: String) -> void:
	end_kind = kind
	end_t = 1.0
	phase = "finish"
	final_place = 0
	ev("siren", false)

# ---------- rivals and cops ----------
func _update_foe(f: Rider, dt: float) -> void:
	var m := me
	f.flash = max(0.0, f.flash - dt)
	f.inv = max(0.0, f.inv - dt)
	f.stun = max(0.0, f.stun - dt)
	if f.state == WAIT:
		if phase == "race":
			var near := _nearest_racer(f)
			if near != null and near.s > f.s - 40.0 and near.s < f.s + 60.0:
				_start_chase(f, near)
		return
	if f.s >= road.length - 20.0:
		f.v = 0.0
		return
	if f.state == DOWN:
		f.down_t += dt
		f.v = max(0.0, f.v - 14.0 * dt)
		f.s += f.v * dt
		f.d = clamp(f.d + f.push * dt, -12.4, 12.4)
		f.push *= exp(-3.0 * dt)
		f.bike_rot = min(1.0, f.bike_rot + dt * 5.0)
		_update_flight(f, dt)
		if f.down_t > f.down_dur:
			f.state = RIDE
			f.hp = f.max_hp * 0.6
			f.v = 0.0
			f.d = clamp(f.fly_d, 1.5, 5.8)
			f.s = max(f.s, f.fly_s - 2.0)
			_safe_spawn(f)
			f.inv = 1.5
			f.push = 0.0
			f.vx = 0.0
			f.bike_rot = 0.0
		return
	var tg: Rider = m
	if f.is_cop:
		f.retarget_t -= dt
		if f.retarget_t <= 0.0 or f.target == null or f.target.state != RIDE:
			f.retarget_t = 0.4
			_pick_target(f)
		if f.target == null:
			f.v = max(0.0, f.v - v_top * 0.3 * dt)
			f.s += f.v * dt
			return
		tg = f.target
	var dz: float = f.s - tg.s
	var adz: float = abs(dz)
	var tgt: float
	f.look_t -= dt
	if f.look_t <= 0.0:
		f.look_t = 0.2
		f.lim = corner_limit(f.s, f.v, f.a_grip, f.a_brake, 0.9)
	if f.is_cop:
		# closes up until he is right alongside, then holds there and swings. There is no timer: only a knockout stops him
		tgt = max(0.0, tg.v + clamp(-dz * 0.8, -8.0, max(8.0, v_top * 0.35)))
		tgt = min(tgt, f.lim)
	else:
		tgt = f.top * f.skill
		tgt = min(tgt, f.lim)
		if f.style == "brawler" and adz < 12.0 and m.state == RIDE:
			# comes alongside and stays there to fight
			tgt = min(f.top * 1.07, max(m.v + clamp(-dz * 0.8, -5.0, 6.0), v_top * 0.2))
		if f.style == "coward" and f.angry > 0.0:
			tgt *= 1.06
		if m.state == RIDE and dz < -2.0 and dz > -45.0 and (f.style == "brawler" or (f.style == "thief" and m.weapon != "none")):
			tgt *= 1.07
		if dz > 30.0:
			tgt *= 1.0 - clamp((dz - 30.0) / 250.0, 0.0, 0.18)
		elif dz < -5.0 and f.lim > f.v:
			tgt = min(f.lim, tgt * (1.0 + clamp((-dz - 5.0) / 83.0, 0.0, 0.3)))
		if f.finished:
			tgt = v_top * 0.6
	if f.stun > 0.0:
		tgt *= 0.82
	if abs(f.d) > Road.EDGE:
		tgt *= 0.6
	var pull: float
	if f.is_cop:
		pull = 0.3 * v_top
	else:
		pull = f.acc * f.top * max(0.18 if dz < -10.0 else 0.06, 1.0 - 0.96 * f.v / f.top)
	f.v += clamp(tgt - f.v, -f.a_brake * dt, pull * dt)
	f.v = max(0.0, f.v)
	# steering
	f.lane_t -= dt
	if f.lane_t <= 0.0:
		f.lane = LANES[1] if (f.style == "maniac" and rng.randf() < 0.25) else MY_LANES[rng.randi() % 2]
		f.lane_t = rng.randf_range(2.5, 6.0)
	var tx: float = f.lane
	f.angry = max(0.0, f.angry - dt)
	var sty := "cop" if f.is_cop else f.style
	var live := phase == "race" and tg.state == RIDE and tg.inv <= 0.0
	var range_m: float = {"cop": 70.0, "brawler": 32.0, "thief": 32.0 if m.weapon != "none" else 12.0, "maniac": 15.0, "blocker": 13.0, "racer": 4.5, "calm": 4.5, "coward": 0.0}[sty]
	if f.angry > 0.0 and sty != "coward":
		range_m = max(range_m, 25.0)
	if live and adz < range_m:
		var hash_v := (f.name.length() * 7) % 3
		tx = clamp(tg.d + (-1.0 if f.d < tg.d else 1.0) * (1.25 + hash_v * 0.3), -6.6, 6.6)
	if live and sty == "blocker" and dz > 2.5 and dz < 28.0:
		tx = clamp(m.d, -6.6, 6.6)
	if live and sty == "coward" and f.angry > 0.0 and adz < 30.0:
		tx = 6.6 if f.d >= m.d else -6.6
	if live and not f.said and adz < 13.0 and not f.is_cop:
		f.said = true
		_say(f, 0.5)
	for c in cars:
		var dd: float = c.s - f.s
		if dd > 0.0 and dd < (16.0 + (f.v - c.v) * 0.9) * (0.5 if sty == "maniac" else 1.0) and abs(c.d - f.d) < 2.3:
			var nx: float = c.d + (-3.6 if f.d <= c.d else 3.6)
			if abs(nx) > 6.6 or (nx < 0.0 and c.dir > 0 and rng.randf() < 0.02):
				nx = c.d + (3.6 if f.d <= c.d else -3.6)
			tx = nx
			break
	if f.is_cop and abs(f.d) > 7.2:
		tx = sign(f.d) * 5.6
	var lat_max: float = max(1.5, f.v * 0.45)
	var want: float = clamp(clamp(tx - f.d, -7.2, 7.2) * 1.5 * (0.72 + 0.006 * f.hand), -lat_max, lat_max)
	f.vx += (want - f.vx) * min(1.0, dt * 5.0)
	f.lat = f.vx + f.push
	f.d = clamp(f.d + f.lat * dt, -12.4, 12.4)
	f.push *= exp(-3.0 * dt)
	f.s += f.v * dt
	var k: float = road.kappa_at(f.s)
	var a_lat: float = clamp(f.v * f.v * k, -f.a_grip, f.a_grip) + f.vx * 3.5
	f.lean += (clamp(atan2(a_lat, G) * 0.8, -0.75, 0.75) * clamp(f.v / 8.0, 0.0, 1.0) - f.lean) * min(1.0, dt * 8.0)
	f.psi = atan2(f.vx, max(4.0, f.v))
	f.rpm = clamp(f.v / max(1.0, f.top), 0.2, 1.0)
	# crashes
	var can_crash: bool = not f.is_cop or t - f.hit_t < 2.5
	if f.inv <= 0.0:
		for c in cars:
			var dd2: float = c.s - f.s
			if abs(dd2) < c.len * 0.5 + 1.0 and abs(c.d - f.d) < c.hw + 0.35:
				if c.dir > 0 and f.v <= c.v:
					# the car caught up: it waits behind, or the rival slides off its side
					if dd2 < 0.0:
						c.s = f.s - (c.len * 0.5 + 1.0)
						c.v = f.v
					else:
						f.d = c.d + (1.0 if f.d >= c.d else -1.0) * (c.hw + 0.35)
					continue
				if can_crash:
					ko_foe(f, 1 if f.d >= c.d else -1, false, "car")
					f.v = max(0.0, c.v) * 0.5
					return
				f.v = max(0.0, c.v)
				break
		if can_crash and abs(f.d) > Road.EDGE and road.solid_hit(f.s, f.d):
			ko_foe(f, 0, false, "pole")
			f.v *= 0.3
			return
	# shove with the player
	if tg.is_me and m.state == RIDE and adz < 2.2 and abs(f.d - m.d) < 1.0:
		var sd := 1 if f.d >= m.d else -1
		f.d += sd * 4.0 * dt
		m.d -= sd * 2.5 * dt
	# attack
	f.cd -= dt
	if f.attack != null:
		var a: Dictionary = f.attack
		a.t += dt
		if not a.done and a.t >= 0.28:
			a.done = true
			var w := weapon_def(f.weapon)
			if abs(f.s - tg.s) < Z_REACH and abs(f.d - tg.d) < w.reach * REACH_M * f.reach_k + 0.3:
				if not tg.is_me:
					_cop_hit(f, tg, w, 1 if tg.d >= f.d else -1)
				else:
					var had := m.weapon
					var could := m.inv <= 0.0 and m.state == RIDE and phase == "race"
					if could:
						ev("hit", m, f.weapon)
					hurt_me(w.foe * tr.foeDmg * (1.2 if f.is_cop else 1.0) * f.hit_mul, 1 if m.d >= f.d else -1)
					if could:
						_say(f, 0.35)
					var steal: float = 0.25 if f.is_cop else (0.36 if f.style == "thief" else 0.12)
					if could and m.state == RIDE and had != "none" and m.weapon == had and rng.randf() < steal:
						var got := lose_weapon()
						if not f.is_cop and not f.no_hand and weapon_def(got).rank >= weapon_def(f.weapon).rank:
							f.weapon = got
						show_banner("Отобрали " + str(weapon_def(got).acc), true)
		if a.t > 0.48:
			f.attack = null
	elif f.cd <= 0.0 and phase == "race" and tg.state == RIDE and tg.inv <= 0.0 and adz < 2.6 and f.stun <= 0.0 and (t >= next_atk or not tg.is_me):
		var calm_type: bool = sty == "racer" or sty == "calm" or sty == "coward"
		if not (calm_type and f.angry <= 0.0) and not (sty == "coward" and rng.randf() < 0.7):
			var w2 := weapon_def(f.weapon)
			if abs(f.d - tg.d) < w2.reach * REACH_M * f.reach_k:
				if tg.is_me:
					next_atk = t + 0.8
				f.attack = {"t": 0.0, "side": 1 if tg.d >= f.d else -1, "done": false, "weapon": f.weapon, "type": "hand"}
				f.cd = rng.randf_range(1.3, 2.6) * (1.6 - f.aggr * 0.6)
	if not f.is_cop and not f.finished and f.s >= road.finish_s:
		f.finished = true
		order.append(f)

func step(dt: float) -> void:
	t += dt
	if phase == "count":
		var b := ceili(count)
		count -= dt
		var n := ceili(count)
		if n != b and n > 0:
			ev("count", n)
		me.rpm += ((0.6 if inp.gas else 0.1) - me.rpm) * min(1.0, dt * 8.0)
		if count <= 0.0:
			phase = "race"
			t = 0.0
			show_banner("Газ!")
			ev("go")
		return
	_update_me(dt)
	for f in foes:
		_update_foe(f, dt)
	for c in cars:
		_update_car(c, dt)
	if phase == "finish":
		end_t -= dt
		if end_t <= 0.0:
			phase = "over"
			ev("over", end_kind)
