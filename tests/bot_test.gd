extends Node
# Runs whole races with no screen. godot --headless --path . res://tests/bot_test.tscn -- [track] [bike] [peace]

var human := false

func _ready() -> void:
	var d: Node = D
	d.load_all()
	var args := OS.get_cmdline_user_args()
	var list: Array = []
	if args.size() >= 2:
		list = [[int(args[0]), args[1]]] if args[0] != "all" else [[0, "strek"], [0, "buivol"], [1, "buivol"], [2, "shershen"], [3, "volk"], [3, "karavan"], [4, "sapsan"], [4, "osa"], [5, "grom"], [5, "tsunami"]]
	else:
		list = [[0, "strek"], [0, "buivol"], [1, "buivol"], [2, "shershen"], [3, "volk"], [3, "karavan"], [4, "sapsan"], [4, "osa"], [5, "grom"], [5, "tsunami"]]
	var peace := args.size() >= 3 and "peace" in args[2]
	human = args.size() >= 3 and "human" in args[2]
	for e in list:
		for seed_v in [1, 2]:
			_race(d, e[0], e[1], seed_v, peace)
	get_tree().quit()

func _race(d: Node, ti: int, bid: String, seed_v: int, peace: bool) -> void:
	var cat: int = d.tracks[ti].cat
	var ts: int = [2, 4, 4][cat]
	var th: int = [2, 2, 3][cat]
	var sim := Sim.new()
	sim.setup(ti, bid, {}, ts, th, 0, 0, seed_v)
	sim.bot = true
	sim.bot_peace = peace
	sim.bot_human = human
	var dt := 1.0 / 60.0
	var maxv := 0.0
	var sum_v := 0.0
	var n := 0
	var slides := 0
	var edge := 0.0
	var min_k_v := 1e9
	var why: Dictionary = {}
	while sim.phase != "over" and sim.t < 400.0:
		sim.step(dt)
		for e in sim.events:
			if e[0] == "crash":
				why[e[1]] = why.get(e[1], 0) + 1
		sim.events.clear()
		if sim.phase == "race":
			maxv = max(maxv, sim.me.v)
			sum_v += sim.me.v
			n += 1
			if sim.me.slide:
				slides += 1
			edge = max(edge, abs(sim.me.d))
			if abs(sim.road.kappa_at(sim.me.s)) > 0.002:
				min_k_v = min(min_k_v, sim.me.v)
	var place := sim.final_place
	var ko_foes := 0
	for f in sim.foes:
		if f.state == Sim.DOWN:
			ko_foes += 1
	print("%-7s %-9s seed%d | %-6s place %d/%d t=%3.0fs len=%4.0fm | top %3.0f avg %3.0f slow-bend %3.0f km/h (bike %3.0f) | falls %d %s hp%3.0f bk%3.0f | KO %d slide %.0f%% edge %.1f shifts %d" % [
		d.tracks[ti].id, bid, seed_v, sim.end_kind, place, 8, sim.t, sim.road.finish_s, maxv * 3.6, sum_v / max(1, n) * 3.6,
		min_k_v * 3.6, sim.me.top * 3.6, sim.me.falls, str(why), sim.me.hp, sim.me.bike_hp, sim.stats.ko, 100.0 * slides / max(1, n), edge, sim.stats.shifts])
