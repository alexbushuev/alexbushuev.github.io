extends Node
# Traffic against a bike, scene by scene, with numbers. Nothing here looks at the screen.

var fails := 0

func _ready() -> void:
	D.load_all()
	print("name                              | result")
	_slow("A slow scooter, car from behind", 0, "strek", 2.8, 60.0, 40.0, 1.8, false)
	_slow("B stopped dead in the lane", 0, "strek", 0.0, 60.0, 40.0, 1.8, false)
	_slow("C just pulling away, car 12 m back", 0, "strek", 0.0, 12.0, 40.0, 1.8, true)
	_slow("D same on the highway, 90 km/h", 4, "sapsan", 0.0, 80.0, 90.0, 5.4, true)
	_queue()
	_side()
	_fallen()
	_cut_in(40.0, "E2 cut in 40 m ahead of a car")
	_cut_in(6.0, "E1 cut in 6 m ahead of a car")
	_tail()
	_head()
	_oncoming_stop()
	_limits()
	_speed()
	print("FAILS: %d" % fails)
	get_tree().quit()

func _sim(ti: int, b: String) -> Sim:
	var cat: int = D.tracks[ti].cat
	var sim := Sim.new()
	sim.setup(ti, b, {}, [2, 4, 4][cat], [2, 2, 3][cat], 0, 0, 1)
	sim.cars.clear()
	sim.foes.clear()
	sim.cops.clear()
	sim.riders.clear()
	sim.riders.append(sim.me)
	sim.phase = "race"
	sim.me.s = 200.0
	return sim

func _car(sim: Sim, ds: float, lane: float, kmh: float, kind := "sedan") -> Sim.Car:
	var c := Sim.Car.new()
	c.kind = kind
	c.hw = Sim.CAR_DEF[kind][0]
	c.len = Sim.CAR_DEF[kind][1]
	c.d = lane
	c.dir = 1 if lane > 0.0 else -1
	c.v0 = kmh / 3.6
	c.v = c.dir * c.v0
	c.s = sim.me.s + ds
	sim.cars.append(c)
	return c

func _gap(sim: Sim, c: Sim.Car) -> float:
	return abs(sim.me.s - c.s) - c.len * 0.5 - 1.0

func _report(name_s: String, ok: bool, txt: String) -> void:
	if not ok:
		fails += 1
	print("%-34s| %s %s" % [name_s, "ok  " if ok else "FAIL", txt])

func _slow(name_s: String, ti: int, b: String, hold_v: float, behind: float, kmh: float, lane: float, gas: bool) -> void:
	var sim := _sim(ti, b)
	sim.me.d = lane
	sim.me.v = hold_v
	var c := _car(sim, -behind, lane, kmh)
	sim.link_cars()
	var min_gap := 1e9
	var hit := []
	var inside := 0
	var dt := 1.0 / 60.0
	var v_end := 0.0
	var tt := 0.0
	var max_brake_seen := false
	while tt < 25.0:
		if gas:
			sim.inp.gas = true
		else:
			sim.me.v = hold_v
		sim.me.d = lane
		sim.step(dt)
		tt += dt
		for e in sim.events:
			if e[0] == "crash" or e[0] == "bump" or e[0] == "scrape":
				hit.append(e[0])
		sim.events.clear()
		var g := _gap(sim, c)
		min_gap = min(min_gap, g)
		if g < 0.0 and abs(c.d - sim.me.d) < c.hw + 0.4:
			inside += 1
		max_brake_seen = max_brake_seen or c.braking
		v_end = abs(c.v) * 3.6
	_report(name_s, hit.is_empty() and inside == 0, "closest %.1f m, contacts %d, inside %d frames, car ends at %.0f km/h, braked %s" % [min_gap, hit.size(), inside, v_end, max_brake_seen])

func _queue() -> void:
	var sim := _sim(0, "strek")
	sim.me.d = 1.8
	var a := _car(sim, -40.0, 1.8, 40.0)
	var b := _car(sim, -55.0, 1.8, 40.0, "van")
	var c := _car(sim, -75.0, 1.8, 40.0, "truck")
	sim.link_cars()
	var overlap := 0
	for i in 1200:
		sim.me.v = 0.0
		sim.step(1.0 / 60.0)
		sim.events.clear()
		if a.s - b.s < (a.len + b.len) * 0.5 or b.s - c.s < (b.len + c.len) * 0.5:
			overlap += 1
	_report("F queue of three behind a stop", overlap == 0 and abs(c.v) < 0.1, "gaps %.1f / %.1f / %.1f m, overlap %d frames, last car %.1f km/h" % [_gap(sim, a), a.s - b.s - (a.len + b.len) * 0.5, b.s - c.s - (b.len + c.len) * 0.5, overlap, abs(c.v) * 3.6])

func _side() -> void:
	var sim := _sim(0, "strek")
	sim.me.d = 5.4
	sim.me.v = 11.0
	var c := _car(sim, 0.0, 1.8, 40.0)
	sim.link_cars()
	var crashes := 0
	var scrapes := 0
	var deep := 0.0
	for i in 240:
		sim.inp.steer = -1.0
		sim.me.v = abs(c.v)
		sim.step(1.0 / 60.0)
		for e in sim.events:
			if e[0] == "crash":
				crashes += 1
			if e[0] == "scrape":
				scrapes += 1
		sim.events.clear()
		if abs(c.s - sim.me.s) < c.len * 0.5 + 1.0:
			deep = max(deep, c.hw + 0.4 - abs(c.d - sim.me.d))
	_report("G steer into a car alongside", crashes == 0 and scrapes > 0 and deep < 0.25, "crashes %d, scrapes %d, deepest %.2f m, bike %.0f" % [crashes, scrapes, deep, sim.me.bike_hp])

func _fallen() -> void:
	var sim := _sim(0, "strek")
	sim.me.d = 1.8
	sim.me.v = 20.0
	sim.me.hp = 100.0
	var c := _car(sim, -45.0, 1.8, 40.0)
	sim.link_cars()
	sim.crash("car", 20.0)
	var min_bike := 1e9
	var min_rider := 1e9
	for i in 125:
		sim.step(1.0 / 60.0)
		sim.events.clear()
		if sim.me.state == Sim.DOWN:
			min_bike = min(min_bike, sim.me.s - c.s - c.len * 0.5)
			if abs(sim.me.fly_d - c.d) < c.hw + 0.6:
				min_rider = min(min_rider, sim.me.fly_s - c.s - c.len * 0.5)
	_report("H fallen rider in the lane", min_bike > 0.0 and min_rider > 0.0, "car stayed %.1f m from the bike, %.1f m from the rider" % [min_bike, min_rider])

func _cut_in(ahead: float, name_s: String) -> void:
	var sim := _sim(4, "sapsan")
	sim.me.d = 5.4
	sim.me.v = 8.0
	var c := _car(sim, -ahead, 1.8, 90.0)
	sim.link_cars()
	var why := []
	var inside := 0
	for i in 360:
		sim.inp.steer = clamp((1.8 - sim.me.d) * 0.8, -1.0, 1.0)
		if sim.me.state == Sim.RIDE:
			sim.me.v = 8.0
		sim.step(1.0 / 60.0)
		for e in sim.events:
			if e[0] == "crash":
				why.append(e[1])
			elif e[0] == "bump":
				why.append("bump")
		sim.events.clear()
		if sim.me.state == Sim.RIDE and sim.me.inv <= 0.0 and _gap(sim, c) < -0.3 and abs(c.d - sim.me.d) < c.hw + 0.2:
			inside += 1
	_report(name_s, inside == 0, "outcome %s, inside %d frames, hp %.0f" % [str(why) if why.size() > 0 else "stopped in time", inside, sim.me.hp])

func _tail() -> void:
	var sim := _sim(4, "sapsan")
	sim.me.d = 1.8
	sim.me.v = 40.0
	var c := _car(sim, 60.0, 1.8, 90.0)
	c.v0 = 16.0
	sim.link_cars()
	var why := []
	for i in 400:
		sim.me.v = 36.0 if sim.me.state == Sim.RIDE else sim.me.v
		sim.me.d = 1.8 if sim.me.state == Sim.RIDE else sim.me.d
		sim.step(1.0 / 60.0)
		for e in sim.events:
			if e[0] == "crash":
				why.append(e[1])
		sim.events.clear()
		if why.size() > 0:
			break
	_report("I ride square into a car's tail", why == ["car"], "outcome %s" % str(why))

func _head() -> void:
	var sim := _sim(4, "sapsan")
	sim.me.d = -1.8
	sim.me.v = 30.0
	var c := _car(sim, 150.0, -1.8, 90.0)
	sim.link_cars()
	var why := []
	var slowed := false
	for i in 400:
		sim.me.v = 30.0 if sim.me.state == Sim.RIDE else sim.me.v
		sim.step(1.0 / 60.0)
		slowed = slowed or (c.braking and sim.me.state == Sim.RIDE)
		for e in sim.events:
			if e[0] == "crash":
				why.append(e[1])
		sim.events.clear()
		if why.size() > 0:
			break
	_report("J head-on stays deadly", why == ["head"] and not slowed, "outcome %s, oncoming braked %s" % [str(why), slowed])

func _oncoming_stop() -> void:
	var sim := _sim(0, "strek")
	sim.me.d = -1.8
	sim.me.v = 0.0
	var c := _car(sim, 80.0, -1.8, 40.0)
	sim.link_cars()
	for i in 900:
		sim.me.v = 0.0
		sim.step(1.0 / 60.0)
		sim.events.clear()
	_report("K stopped in the oncoming lane", abs(c.v) < 0.1 and c.s > sim.me.s, "car stopped %.1f m from you" % (c.s - sim.me.s - c.len * 0.5 - 1.0))

func _limits() -> void:
	var line := ""
	var ok := true
	for ti in D.tracks.size():
		var sim := Sim.new()
		sim.setup(ti, D.bikes[0].id if ti < 2 else (D.bikes[5].id if ti < 4 else D.bikes[10].id), {}, 2, 2, 0, 0, 1)
		var top := {}
		for c in sim.cars:
			top[c.kind] = max(float(top.get(c.kind, 0.0)), c.v0 * 3.6)
			if c.v0 > D.world_speed(float(D.rules.traffic.max_kmh[c.kind])) + 0.01:
				ok = false
		line += "\n    %-7s %s" % [sim.tr.id, str(top)]
	_report("L top speed by track and type", ok, line)

func _speed() -> void:
	# cost of one simulation step on the busiest track, with every car and rival running
	var sim := Sim.new()
	sim.setup(5, "grom", {}, 4, 3, 0, 0, 1)
	sim.bot = true
	sim.phase = "race"
	var t0 := Time.get_ticks_usec()
	for i in 3000:
		sim.step(1.0 / 60.0)
		sim.events.clear()
	var us: float = float(Time.get_ticks_usec() - t0) / 3000.0
	print("%-34s| %d cars, %.0f microseconds per step = %.1f%% of a 60 fps frame" % ["M step cost", sim.cars.size(), us, us / 16667.0 * 100.0])
