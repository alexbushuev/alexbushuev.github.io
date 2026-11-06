extends Node
# Rivals as players of the records table: after your race they ride on to the line on their own;
# their times are real and no faster than their bikes allow. godot --headless --path . res://tests/bots_test.tscn

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _ready() -> void:
	D.load_all()
	for e in [[0, "buivol"], [2, "shershen"], [4, "sapsan"], [5, "grom"]]:
		var sim := Sim.new()
		sim.setup(e[0], e[1], {}, 4, 3, 0, 0, 7)
		sim.bot = true
		sim.bot_phone = true
		var over_top := 0.0
		while sim.phase != "over" and sim.t < 500.0:
			sim.step(1.0 / 60.0)
			sim.events.clear()
			for f in sim.foes:
				if not f.is_cop and f.state == Sim.RIDE:
					over_top = max(over_top, f.v / f.top)
		var t_me: float = sim.stats.t_finish
		var kind: String = sim.end_kind
		var t0 := Time.get_ticks_msec()
		sim.start_solo()
		var steps := 0
		while not sim.solo_done():
			sim.step_rivals(1.0 / 20.0)
			steps += 1
			for f in sim.foes:
				if not f.is_cop and f.state == Sim.RIDE:
					over_top = max(over_top, f.v / f.top)
		var ms := Time.get_ticks_msec() - t0
		var stats := sim.bot_stats()
		var line := "%-7s you %s %5.1f s | ridden on %4.0f s of race in %d ms |" % [sim.tr.id, kind, t_me, steps / 20.0, ms]
		var done := 0
		for b in stats:
			var rb: Dictionary = D.bike_by_id[b.bike.split(" ")[0].to_lower()] if D.bike_by_id.has(b.bike.split(" ")[0].to_lower()) else {}
			if b.finished:
				done += 1
				# no faster than the whole track flat out on that bike
				var fastest: float = sim.road.finish_s * 0.55 / D.world_speed(float(_kmh(b.bike)))
				check(float(b.time_ms) / 1000.0 > fastest, "%s %s %.1f s is faster than his bike could" % [sim.tr.id, b.name, float(b.time_ms) / 1000.0])
			line += " %s %s%s" % [b.name, Hud.race_time(float(b.time_ms) / 1000.0) if b.finished else "—", (" ko%d" % b.ko) if b.ko > 0 else ""]
		print(line)
		check(stats.size() == 7, "seven rivals reported")
		check(done >= 2, "%s rivals reach the line (%d)" % [sim.tr.id, done])
		check(over_top <= 1.001, "%s a rival went faster than his bike: %.3f" % [sim.tr.id, over_top])
		check(ms < 4000, "riding the rest is quick: %d ms" % ms)
	print("FAILS: ", fails)
	get_tree().quit()

func _kmh(bike_txt: String) -> float:
	var nm := bike_txt.split(" ")[0]
	for b in D.bikes:
		if b.name == nm:
			return float(b.kmh)
	return 300.0
