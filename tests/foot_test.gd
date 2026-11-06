extends Node
# People on foot and the difficulty setting.
# godot --headless --path . res://tests/foot_test.tscn

var fails := 0

func check(ok: bool, what: String, info := "") -> void:
	print("%-52s %s %s" % [what, "ok" if ok else "FAIL", info])
	if not ok:
		fails += 1

func race(ti: int, bike: String, diff := 1) -> Sim:
	var sim := Sim.new()
	sim.setup(ti, bike, {}, 4, 3, 0, 0, 3, {"diff": diff})
	sim.phase = "race"
	sim.t = 5.0
	sim.cars.clear()
	for c in sim.cops:
		c.s = 1e6
	return sim

# a straight piece of main road away from everything, to stage things on
func straight(sim: Sim) -> float:
	var s := 600.0
	while s < sim.road.finish_s - 400.0:
		var ok := true
		var x := -40.0
		while x < 140.0:
			if abs(sim.road.kappa_at(s + x)) > 0.002 or sim.road.in_branch_zone(s + x, 50.0):
				ok = false
				break
			x += 4.0
		if ok:
			return s
		s += 20.0
	return 600.0

func _ready() -> void:
	D.load_all()
	# ---- pedestrians turn up and get crossed ----
	var sim := Sim.new()
	sim.setup(5, "grom", {}, 4, 3, 0, 0, 5)
	sim.bot = true
	sim.bot_phone = true
	var seen := 0
	var on_road_when_passed := 0
	var met := {}
	var hit_light := 0
	var hit_heavy := 0
	while sim.phase != "over" and sim.t < 400.0:
		sim.step(1.0 / 60.0)
		for e in sim.events:
			if e[0] == "ped":
				if e[1]:
					hit_heavy += 1
				else:
					hit_light += 1
		sim.events.clear()
		for p in sim.peds:
			if not met.has(p):
				met[p] = false
				seen += 1
			if not met[p] and sim.me.s > p.s:
				met[p] = true
				if abs(p.d) < Road.EDGE:
					on_road_when_passed += 1
	check(seen >= 4, "people turn up at the crossings", "%d on %d crossings" % [seen, sim.road.crossings.size()])
	# at the line: the first three are happy, the rest sulk or rage by character
	var sm := race(2, "shershen")
	var moods := {}
	for i in sm.foes.size():
		var f: Sim.Rider = sm.foes[i]
		if f.is_cop:
			continue
		f.s = sm.road.finish_s - 30.0 - i * 6.0
		f.d = 1.8 if i % 2 == 0 else 5.4
		f.v = f.top * 0.8
	for k in 600:
		sm.step(1.0 / 60.0)
		for f in sm.foes:
			if f.finished and f.emote != "" and not moods.has(f.name):
				moods[f.name] = "%d %s" % [f.place, f.emote]
	var ok_m := moods.size() >= 5
	for f in sm.foes:
		if f.finished and f.place >= 1 and f.place <= 3 and moods.get(f.name, "").find("joy") < 0:
			ok_m = false
	check(ok_m, "rivals at the line show how they feel", str(moods))
	check(on_road_when_passed >= 1, "some are on the road when you get there", "%d" % on_road_when_passed)
	print("   bot hit %d light, %d heavy; finished: %s" % [hit_light, hit_heavy, sim.end_kind])
	# ---- a light one: half the speed gone ----
	sim = race(5, "grom")
	var s0 := straight(sim)
	sim.me.s = s0
	sim.me.d = 1.8
	sim.me.v = 30.0
	var p := Sim.Ped.new()
	p.s = s0 + 6.0
	p.d = 1.8
	p.v = 0.0
	sim.peds.append(p)
	sim._cross_i = 999
	sim.inp = {"steer": 0.0, "gas": false, "brake": false, "hand": false, "kick": false}
	for i in 30:
		sim.step(1.0 / 60.0)
	check(p.state == 1 and sim.me.state == Sim.RIDE and sim.me.v < 17.0 and sim.me.v > 12.0, "light pedestrian: flies off, you lose half the speed", "v %.1f" % sim.me.v)
	# ---- a heavy one: you fall ----
	sim = race(5, "grom")
	sim.me.s = s0
	sim.me.d = 1.8
	sim.me.v = 30.0
	var hp0: float = sim.me.hp
	var p2 := Sim.Ped.new()
	p2.s = s0 + 6.0
	p2.d = 1.8
	p2.v = 0.0
	p2.heavy = true
	sim.peds.append(p2)
	sim._cross_i = 999
	sim.inp = {"steer": 0.0, "gas": false, "brake": false, "hand": false, "kick": false}
	for i in 30:
		sim.step(1.0 / 60.0)
	check(sim.me.state == Sim.DOWN and p2.state == 4 and sim.me.hp < hp0, "heavy pedestrian: he stands, you go down", "hp %.0f" % sim.me.hp)
	# ---- run over a rival on his feet ----
	sim = race(5, "grom")
	sim.me.s = s0
	sim.me.d = 1.8
	sim.me.v = 25.0
	var f: Sim.Rider = sim.foes[0]
	f.state = Sim.DOWN
	f.run_phase = 2
	f.s = s0 + 30.0
	f.d = 5.4
	f.fly_s = s0 + 5.0
	f.fly_d = 1.8
	var life0: float = f.life
	sim.inp = {"steer": 0.0, "gas": false, "brake": false, "hand": false, "kick": false}
	for i in 20:
		sim.step(1.0 / 60.0)
	check(int(sim.stats.ko) == 1 and f.run_phase == 0 and f.life < life0, "you knock down a rival running to his bike", "life %.0f → %.0f" % [life0, f.life])
	# ---- a rival rides over you on foot ----
	sim = race(5, "grom")
	sim.me.state = Sim.DOWN
	sim.me.run_phase = 2
	sim.me.s = s0 + 40.0
	sim.me.fly_s = s0 + 8.0
	sim.me.fly_d = 1.8
	sim.me.d = 5.4
	var r: Sim.Rider = sim.foes[1]
	for o in sim.foes:
		if o != r and not o.is_cop:
			o.s = s0 + 600.0
	r.style = "maniac"
	r.s = s0 - 15.0
	r.d = 1.8
	r.lane = 1.8
	r.v = 25.0
	hp0 = sim.me.hp
	var got := false
	for i in 120:
		sim.step(1.0 / 60.0)
		if sim.me.run_phase == 0:
			got = true
			break
		sim.me.run_phase = 2     # keep him standing where he is
		sim.me.run_t = 0.0
		sim.me.fly_s = s0 + 8.0
		sim.me.fly_d = 1.8
	check(got and sim.me.hp < hp0 and r.ko_me == 1, "a maniac rides you down while you run to the bike", "hp %.0f → %.0f" % [hp0, sim.me.hp])
	# ---- a car does too ----
	sim = race(5, "grom")
	sim.me.state = Sim.DOWN
	sim.me.run_phase = 2
	sim.me.s = s0 + 40.0
	sim.me.fly_s = s0 + 3.0
	sim.me.fly_d = 1.8
	var c := Sim.Car.new()
	c.s = s0
	c.d = 1.8
	c.v = 16.0
	c.v0 = 16.0
	sim.cars.append(c)
	hp0 = sim.me.hp
	for i in 30:
		sim.step(1.0 / 60.0)
		if sim.me.run_phase == 0:
			break
		sim.me.run_t = 0.0
		sim.me.fly_s = s0 + 3.0
	check(sim.me.hp < hp0, "traffic knocks you down on foot", "hp %.0f → %.0f" % [hp0, sim.me.hp])
	# ---- difficulty: damage ----
	var dmg := []
	for dif in 3:
		sim = race(5, "grom", dif)
		sim.me.hp = 100.0
		sim.hurt_me(20.0, 1)
		dmg.append(100.0 - sim.me.hp)
	check(dmg[0] < dmg[1] and dmg[1] < dmg[2] and abs(dmg[0] / dmg[1] - 0.7) < 0.08 and abs(dmg[2] / dmg[1] - 1.3) < 0.08, "damage 70 / 100 / 130 %", str(dmg))
	# ---- difficulty: rivals ----
	var ahead := []
	var behind := []
	for dif in 3:
		sim = race(5, "grom", dif)
		sim.me.s = s0
		sim.me.d = 1.8
		sim.me.v = 0.0
		var a: Sim.Rider = sim.foes[2]
		var b: Sim.Rider = sim.foes[3]
		for o in sim.foes:
			if o != a and o != b:
				o.s = s0 + 2000.0
		a.s = s0 + 60.0
		a.v = a.top * 0.9
		a.skill = 1.0
		b.s = s0 - 60.0
		b.v = b.top * 0.9
		b.skill = 1.0
		sim.inp = {"steer": 0.0, "gas": false, "brake": false, "hand": false, "kick": false}
		for i in 240:
			sim.me.v = b.top
			sim.me.d = 1.8
			sim.step(1.0 / 60.0)
		ahead.append(a.v / a.top)
		behind.append(b.v / b.top)
	check(ahead[0] < ahead[1] - 0.05, "easy: a rival ahead of you eases off", "%.2f vs %.2f" % [ahead[0], ahead[1]])
	check(behind[2] > behind[1] + 0.03 and behind[2] > 1.0, "hard: a rival behind you pushes past his bike", "%.2f vs %.2f" % [behind[2], behind[1]])
	print("FAILS: %d" % fails)
	get_tree().quit()
