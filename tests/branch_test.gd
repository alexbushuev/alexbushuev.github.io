extends Node
# Side roads: geometry, getting on and off, and whether the shortcut really is quicker.
# godot --headless --path . res://tests/branch_test.tscn

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _ready() -> void:
	D.load_all()
	for ti in D.tracks.size():
		var tr: Dictionary = D.tracks[ti]
		var road := Road.new()
		road.build(tr)
		var kinds: Array = []
		for f in road.features:
			kinds.append(f.kind)
		var line := "%-8s %5.0f m |" % [tr.id, road.finish_s]
		for b in road.branches:
			var main_len: float = b.s1 - b.s0
			var min_gap := 1e9
			for i in range(45 if b.kind == "cut" else 25, b.n - (45 if b.kind == "cut" else 25), 3):
				min_gap = min(min_gap, road.dist_to_road(b.pos[i], b.s0 - 60.0, b.s1 + 60.0))
			var kmax := 0.0
			for k in b.kappa:
				kmax = max(kmax, abs(k))
			line += " %s %s %.0f/%.0f m (%.0f%%) gap %.0f r_min %.0f |" % [b.kind, "R" if b.side > 0 else "L", b.length, main_len, b.length / main_len * 100.0, min_gap, 1.0 / max(kmax, 1e-4)]
			check(b.length < main_len * (0.8 if b.kind == "cut" else 0.97), "%s %s not shorter" % [tr.id, b.kind])
			check(min_gap > (Road.EDGE + b.half + 2.0 if b.kind == "fork" else 4.0), "%s %s runs into the main road (%.1f m)" % [tr.id, b.kind, min_gap])
			# ends meet the main road
			var p0 := road.world(b.s0, b.side * 5.4)
			var p1 := road.world(b.s1, b.side * 5.4)
			check(p0.distance_to(b.world(0.0, 0.0)) < 0.3 and p1.distance_to(b.world(b.length, 0.0)) < 2.5, "%s %s ends do not meet: %.2f %.2f" % [tr.id, b.kind, p0.distance_to(b.world(0.0, 0.0)), p1.distance_to(b.world(b.length, 0.0))])
		line += " %s" % ",".join(kinds.filter(func(k: String) -> bool: return k in ["tunnel", "bridge"]))
		print(line)
		check(road.branches.size() == 2, tr.id + " has two side roads")
	# timing: the same bot on the same track, main road against side roads
	print("track    bike      main      side     gain   on side  falls")
	for e in [[0, "strek"], [1, "buivol"], [2, "shershen"], [3, "volk"], [4, "sapsan"], [5, "grom"]]:
		var res := {}
		for mode in ["", "take"]:
			var sim := Sim.new()
			sim.setup(e[0], e[1], {}, 4, 3, 0, 0, 3)
			sim.bot = true
			sim.bot_peace = true
			sim.bot_branch = mode
			for c in sim.cars:
				c.s = -5000.0
			for c in sim.cops:
				c.s = 1e7
			for f in sim.foes:
				if not f.is_cop:
					f.s = -1e5
					f.out = true
					f.state = Sim.DOWN
			var why := {}
			var on_side := 0.0
			var t_side := {}
			while sim.phase != "over" and sim.t < 500.0:
				var was: int = sim.me.path
				sim.step(1.0 / 60.0)
				if sim.me.path != 0:
					on_side += 1.0 / 60.0
				for ev in sim.events:
					if ev[0] == "crash":
						why[ev[1] + "@" + str(sim.me.path) + ":" + str(int(sim.me.s))] = 1
				sim.events.clear()
			res[mode] = [sim.stats.t_finish if sim.end_kind == "finish" else -1.0, on_side, sim.me.falls, why.keys(), sim.end_kind]
		var gain: float = res[""][0] - res["take"][0]
		print("%-8s %-8s %6.1f s  %6.1f s  %+5.1f s  %5.1f s  %d/%d %s %s %s %s" % [D.tracks[e[0]].id, e[1], res[""][0], res["take"][0], gain, res["take"][1], res[""][2], res["take"][2], res[""][3], res["take"][3], res[""][4], res["take"][4]])
		check(res["take"][1] > 5.0, "%s bot never got onto the side roads" % D.tracks[e[0]].id)
		check(res[""][1] == 0.0, "%s bot told to stay still took a side road" % D.tracks[e[0]].id)
		check(res["take"][0] > 0.0, "%s bot on side roads did not finish" % D.tracks[e[0]].id)
	print("FAILS: ", fails)
	get_tree().quit()
