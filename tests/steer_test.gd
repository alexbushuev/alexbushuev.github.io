extends Node
# Measures the two things that matter for steering, compared with the 2D game's formulas:
# how long one lane change takes, and how far a bend carries you if you don't steer.

func _ready() -> void:
	D.load_all()
	print("LANE CHANGE, hold one arrow until the bike has moved one lane (3.6 m)")
	for e in [[0, "strek"], [2, "kobra"], [4, "sapsan"], [5, "grom"]]:
		for frac in [0.5, 1.0]:
			_lane(e[0], e[1], frac)
	print("BEND, gas only, no steering: where the bike ends up after the first real bend")
	for e in [[0, "strek"], [1, "buivol"], [2, "kobra"], [3, "volk"], [4, "sapsan"], [5, "grom"]]:
		_bend(e[0], e[1])
	get_tree().quit()

func _sim(ti: int, b: String) -> Sim:
	var cat: int = D.tracks[ti].cat
	var sim := Sim.new()
	sim.setup(ti, b, {}, [2, 4, 4][cat], [2, 2, 3][cat], 0, 0, 1)
	sim.cars.clear()
	sim.foes.clear()
	sim.cops.clear()
	sim.phase = "race"
	return sim

func _lane(ti: int, b: String, frac: float) -> void:
	var sim := _sim(ti, b)
	var dt := 1.0 / 60.0
	sim.me.v = sim.me.top * frac
	sim.me.d = 1.8
	sim.me.s = 80.0
	sim.inp.gas = true
	sim.inp.steer = 1.0
	var t := 0.0
	while sim.me.d < 5.4 and t < 5.0:
		sim.step(dt)
		t += dt
	var k: float = sim.me.st.steer
	var pct: float = frac
	var auth2d: float = 2.5 * k * (0.4 + 0.6 * min(1.0, pct * 1.4)) * (1.0 - 0.25 * pct)
	print("  %-7s %3.0f km/h on the dial: %.2f s | 2D %.2f s" % [b, sim.me.st.kmh * frac, t, 0.5 / auth2d])

func _bend(ti: int, b: String) -> void:
	var sim := _sim(ti, b)
	var dt := 1.0 / 60.0
	sim.inp.gas = true
	sim.inp.steer = 0.0
	sim.me.d = 1.8
	var off_at := -1.0
	var first_k := 0.0
	while sim.phase == "race" and sim.t < 60.0:
		sim.step(dt)
		if abs(sim.road.kappa_at(sim.me.s)) > 0.002 and first_k == 0.0:
			first_k = sim.t
		if abs(sim.me.d) > Road.EDGE and off_at < 0.0:
			off_at = sim.t
			break
	var after: String = "%.1f s after bend starts" % (off_at - first_k) if off_at > 0.0 else "stayed on the road for 60 s"
	print("  %-7s on %-6s: bend at %.0f s, off the road: %s at %.0f km/h" % [b, sim.tr.id, first_k, after, sim.dial(sim.me, sim.me.v)])
