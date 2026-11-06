extends Node
# Hills, crests you fly off, and what gravity does to each bike.
# godot --headless --path . res://tests/hill_test.tscn

var fails := 0
const BIKE := ["strek", "gekkon", "shershen", "volk", "sapsan", "grom"]

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

# where the player's speed settles on a steady grade, km/h on the dial
func settle(sim: Sim, grade: float) -> float:
	var m := sim.me
	var gs: float = Sim.G * grade / sqrt(1.0 + grade * grade)
	var v: float = m.top * 0.5
	for i in 6000:
		var p: float = v / m.top
		var was := v
		v += (sim.thrust(m, p) - sim.drag(m, p) - gs) / 60.0
		if was <= m.top and v > m.top and gs > -0.15:
			v = m.top
		v = clamp(v, 0.0, m.top * 1.35)
	return sim.dial(m, v)

func _ready() -> void:
	D.load_all()
	for ti in D.tracks.size():
		var tr: Dictionary = D.tracks[ti]
		var sim := Sim.new()
		sim.setup(ti, BIKE[ti], {}, 2, 2, 0, 0, 1)
		var road: Road = sim.road
		var lo := 1e9
		var hi := -1e9
		var gmax := 0.0
		for i in road.n:
			lo = min(lo, road.pos[i].y)
			hi = max(hi, road.pos[i].y)
			gmax = max(gmax, abs(road.grade[i]))
		var flat := settle(sim, 0.0)
		var up := settle(sim, 0.08)
		var down := settle(sim, -0.08)
		print("%-7s %5.0f m  height %.0f..%.0f m  steepest %.1f%%  steep stretches %d  crossings %d  | %s: flat %.0f, up 8%% %.0f, down 8%% %.0f km/h" % [tr.id, road.finish_s, lo, hi, gmax * 100.0, road.slopes.size(), road.crossings.size(), BIKE[ti], flat, up, down])
		check(abs(flat - float(sim.me.st.kmh)) < 1.0, "%s flat top speed is the bike's" % tr.id)
		check(up < flat - 4.0 and down > flat + 2.0, "%s hills change the top speed" % tr.id)
		check(road.kickers.size() >= 2, "%s has crests to fly off" % tr.id)
		var lift_lo: float = 1e9
		for kk in road.kickers:
			var v_top: float = sim.v_top
			var j := road.simulate_jump(float(kk.s) - 20.0, v_top)
			var v_lift := 70.0
			for v in range(8, 70):
				if road.simulate_jump(float(kk.s) - 20.0, float(v))[0]:
					v_lift = v
					break
			lift_lo = min(lift_lo, v_lift)
			print("   crest at %5.0f m: +%.1f%% / -%.1f%%  leaves the ground from %d km/h, lands safe up to %d km/h; flat out: %s" % [float(kk.s), float(kk.g1) * 100.0, float(kk.g2) * 100.0,
				int(sim.dial(sim.me, float(v_lift))), int(sim.dial(sim.me, float(kk.v_safe))),
				("%.0f m, %.1f m high, lands at %.1f m/s" % [float(j[1]) - float(kk.s), float(j[3]), float(j[2])]) if j[0] else "stays on the road"])
			check(float(j[3]) < 7.0, "%s crest at %.0f flies too high" % [tr.id, float(kk.s)])
		# ordinary hilltops must not throw anyone in the air below league speed
		var hops := 0
		var s := road.start_s
		while s < road.finish_s:
			var near_k := false
			for kk in road.kickers:
				if abs(s - float(kk.s)) < 30.0:
					near_k = true
			if not near_k and road.takeoff_between(s, s + 2.0, sim.v_top * 0.9) >= 0.0:
				hops += 1
				print("   hop at %.0f m, grade %.3f -> %.3f" % [s, road.grade_at(s), road.grade_at(s + 2.0)])
			s += 2.0
		check(hops == 0, "%s: %d plain hilltops throw you at 90%% league speed" % [tr.id, hops])
	print("FAILS: %d" % fails)
	get_tree().quit()
