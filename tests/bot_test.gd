extends Node
# Runs whole races with no screen. godot --headless --path . res://tests/bot_test.tscn -- [track] [bike] [peace]

var human := false
var phone := false

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
	phone = args.size() >= 3 and "phone" in args[2]
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
	sim.bot_phone = phone
	var dt := 1.0 / 60.0
	var maxv := 0.0
	var sum_v := 0.0
	var n := 0
	var slides := 0
	var edge := 0.0
	var min_k_v := 1e9
	var why: Dictionary = {}
	var inside := 0
	var pile := 0
	var max_car := 0.0
	while sim.phase != "over" and sim.t < 400.0:
		sim.step(dt)
		if OS.get_cmdline_user_args().has("trace2") and sim.phase == "race" and sim.t > 16.0 and sim.t < 20.0 and int(sim.t * 60.0) % 12 == 0:
			var nc: Sim.Car = null
			for c in sim.cars:
				if c.s > sim.me.s and (nc == null or c.s < nc.s) and c.dir > 0:
					nc = c
			print("  t=%.1f s=%.0f d=%.2f lane=%.1f steer=%.2f sv=%.2f pull=%.1f auth=%.1f v=%.0f | next car ds=%.0f d=%.1f" % [sim.t, sim.me.s, sim.me.d, sim.me.bot_lane, sim.inp.steer, sim.me.sv, sim.bend_pull(sim.me, sim.me.s), sim.steer_auth(sim.me), sim.me.v * 3.6, nc.s - sim.me.s, nc.d])
		for e in sim.events:
			if e[0] == "crash":
				why[e[1]] = why.get(e[1], 0) + 1
				if OS.get_cmdline_user_args().has("trace"):
					var best: Sim.Car = null
					for c in sim.cars:
						if best == null or abs(c.s - sim.me.s) + abs(c.d - sim.me.d) * 3.0 < abs(best.s - sim.me.s) + abs(best.d - sim.me.d) * 3.0:
							best = c
					print("  crash t=%.1f %s me s=%.0f d=%.2f lane=%.1f v=%.0f block=%.0f k=%.4f | car ds=%.1f d=%.1f v=%.0f %s" % [sim.t, e[1], sim.me.s, sim.me.d, sim.me.bot_lane, sim.me.fall_kmh, sim.me.bot_block * 3.6, sim.road.kappa_at(sim.me.s), best.s - sim.me.s, best.d, best.v * 3.6, best.kind])
		sim.events.clear()
		if sim.phase == "race" and sim.me.state == Sim.RIDE and sim.me.inv <= 0.0:
			for c in sim.cars:
				if abs(c.s - sim.me.s) < c.len * 0.5 + 0.9 and abs(c.d - sim.me.d) < c.hw + 0.3:
					inside += 1
					break
		for c in sim.cars:
			max_car = max(max_car, abs(c.v))
			if c.lead != null and c.dir * (c.lead.s - c.s) < (c.lead.len + c.len) * 0.5 - 0.01:
				pile += 1
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
	print("%-7s %-9s seed%d | %-6s place %d/%d t=%3.0fs len=%4.0fm | top %3.0f avg %3.0f slow-bend %3.0f km/h (bike %3.0f) | falls %d %s hp%3.0f bk%3.0f | KO %d inside %d pile %d car %3.0f" % [
		d.tracks[ti].id, bid, seed_v, sim.end_kind, place, 8, sim.t, sim.road.finish_s, sim.dial(sim.me, maxv), sim.dial(sim.me, sum_v / max(1, n)),
		sim.dial(sim.me, min_k_v), sim.me.st.kmh, sim.me.falls, str(why), sim.me.hp, sim.me.bike_hp, sim.stats.ko, inside, pile, max_car * 3.6])
