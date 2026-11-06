extends Node
# Cops and money, scene by scene. Uses its own save file.

var fails := 0

func _ready() -> void:
	D.load_all()
	S.path = "user://rules_test_save.json"
	print("--- cops")
	_cop_never_gives_up()
	_cop_wakes_for_rival()
	_cop_nearest()
	_cop_hits_me()
	_cop_turns_on_attacker()
	_ko_cop()
	print("--- money and save")
	_buying()
	_save_reload()
	_ledger()
	_weapon_stock()
	_unlock()
	print("FAILS: %d" % fails)
	get_tree().quit()

func _ok(name_s: String, ok: bool, txt := "") -> void:
	if not ok:
		fails += 1
	print("%-40s %s %s" % [name_s, "ok  " if ok else "FAIL", txt])

func _sim(ti: int, b: String, keep_cop := true) -> Sim:
	var cat: int = D.tracks[ti].cat
	var sim := Sim.new()
	sim.setup(ti, b, {}, [2, 4, 4][cat], [2, 2, 3][cat], 0, 0, 1)
	sim.cars.clear()
	sim.phase = "race"
	return sim

func _only_cop(sim: Sim, cop_s: float) -> Sim.Rider:
	var cop: Sim.Rider = sim.cops[0]
	for c in sim.cops:
		if c != cop:
			sim.foes.erase(c)
			sim.riders.erase(c)
	sim.cops = [cop]
	var rivals: Array = []
	for f in sim.foes:
		if not f.is_cop:
			rivals.append(f)
	for f in rivals:
		sim.foes.erase(f)
		sim.riders.erase(f)
	cop.s = cop_s
	return cop

func _hold(sim: Sim) -> void:
	sim.me.hp = 100.0
	sim.me.bike_hp = 100.0

func _cop_never_gives_up() -> void:
	for e in [[0, "buivol"], [2, "volk"], [5, "tsunami"]]:
		var sim := _sim(e[0], e[1])
		sim.bot = true
		sim.bot_peace = true
		var cop := _only_cop(sim, 150.0)
		sim.me.s = 100.0
		sim.me.v = sim.me.top * 0.8
		var ride_t := 0.0
		var near_t := 0.0
		var tt := 0.0
		var hits := 0
		var far := 0.0
		var banner_gone := false
		while tt < 100.0 and sim.me.s < sim.road.finish_s - 80.0:
			_hold(sim)
			sim.step(1.0 / 60.0)
			tt += 1.0 / 60.0
			for ev in sim.events:
				if ev[0] == "hit" and ev[1] == sim.me:
					hits += 1
				if ev[0] == "banner" and "отстал" in str(ev[1]):
					banner_gone = true
			sim.events.clear()
			if sim.me.state == Sim.DOWN:
				sim.me.state = Sim.RIDE
				sim.me.dead = false
				sim.me.bustable = false
			if cop.state == Sim.RIDE:
				ride_t += 1.0 / 60.0
				var gap: float = abs(cop.s - sim.me.s)
				far = max(far, gap)
				if gap < 15.0:
					near_t += 1.0 / 60.0
		_ok("chase on %s, %s" % [sim.tr.id, e[1]], cop.state == Sim.RIDE and not banner_gone and near_t > ride_t * 0.7 and hits > 3,
			"%.0f s of chase, within 15 m %.0f%% of it, furthest %.0f m, baton hits %d" % [ride_t, 100.0 * near_t / max(1.0, ride_t), far, hits])

func _cop_wakes_for_rival() -> void:
	var sim := _sim(2, "kobra")
	var cop: Sim.Rider = sim.cops[0]
	# you are 500 m back; a rival rides past the cop
	var rival: Sim.Rider = null
	for f in sim.foes:
		if f.is_cop:
			continue
		if rival == null:
			rival = f
			continue
		f.s = 3000.0
	for c in sim.cops:
		if c != cop:
			c.s = 2500.0
	cop.s = 600.0
	rival.s = 500.0
	rival.v = rival.top * 0.8
	sim.me.s = 60.0
	var woke := false
	var hit_rival := false
	var out_at := -1.0
	var tt := 0.0
	var v_me := 0.0
	while tt < 300.0 and out_at < 0.0:
		sim.me.v = v_me
		sim.step(1.0 / 60.0)
		tt += 1.0 / 60.0
		woke = woke or (cop.state == Sim.RIDE and cop.target == rival)
		if rival.hp < rival.max_hp:
			hit_rival = true
		if rival.state == Sim.DOWN and rival.out:
			out_at = tt
		sim.events.clear()
	_ok("cop goes after a rival, not only you", woke and hit_rival and out_at > 0.0, "%.0f s until the rival was taken, you were %.0f m away" % [out_at, abs(sim.me.s - cop.s)])
	# then looks for the next nearest
	cop.retarget_t = 0.0
	sim.step(1.0 / 60.0)
	_ok("then picks the next nearest", cop.target != rival and cop.target != null, "now after %s" % (cop.target.name if cop.target != null else "nobody"))

func _cop_nearest() -> void:
	var sim := _sim(2, "kobra")
	var cop := _only_cop(sim, 400.0)
	var r := Sim.Rider.new()
	r.name = "A"
	r.s = 395.0
	r.d = 1.8
	r.v = 10.0
	r.top = 30.0
	var r2 := Sim.Rider.new()
	r2.name = "B"
	r2.s = 340.0
	r2.d = 1.8
	r2.v = 10.0
	r2.top = 30.0
	sim.riders.append(r)
	sim.riders.append(r2)
	sim.me.s = 200.0
	sim._pick_target(cop)
	_ok("targets the closest racer", cop.target == r, "picked %s" % cop.target.name)

func _cop_hits_me() -> void:
	var sim := _sim(2, "kobra")
	var cop := _only_cop(sim, 208.0)
	sim.me.s = 200.0
	sim.me.d = 1.8
	cop.d = 3.0
	cop.state = Sim.RIDE
	cop.target = sim.me
	cop.cd = 0.0
	cop.v = 20.0
	var baton := false
	var hp0: float = sim.me.hp
	for i in 240:
		sim.me.v = 20.0
		sim.me.d = 1.8
		sim.step(1.0 / 60.0)
		for ev in sim.events:
			if ev[0] == "hit" and ev[1] == sim.me and ev[2] == "baton":
				baton = true
		sim.events.clear()
	_ok("cop hits you with the baton", baton and sim.me.hp < hp0 and cop.weapon == "baton", "health %.0f → %.0f in 4 s" % [hp0, sim.me.hp])

func _cop_turns_on_attacker() -> void:
	var sim := _sim(2, "kobra")
	var cop := _only_cop(sim, 300.0)
	var r := Sim.Rider.new()
	r.name = "A"
	r.s = 301.0
	r.d = 1.8
	r.v = 10.0
	r.top = 30.0
	sim.riders.append(r)
	sim.me.s = 280.0
	cop.state = Sim.RIDE
	cop.target = r
	sim.me.attack = null
	cop.angry = 6.0
	cop.retarget_t = 0.0
	sim._pick_target(cop)
	_ok("whoever hits a cop becomes his target", cop.target == sim.me)

func _ko_cop() -> void:
	var sim := _sim(2, "kobra")
	var cop := _only_cop(sim, 201.0)
	sim.me.s = 200.0
	sim.me.d = 1.8
	cop.d = 3.2
	cop.state = Sim.RIDE
	cop.target = sim.me
	cop.inv = 0.0
	var punches := 0
	var siren_off := false
	var tt := 0.0
	while cop.state == Sim.RIDE and tt < 60.0:
		sim.me.hp = 100.0
		sim.me.v = 10.0
		cop.v = 10.0
		cop.s = sim.me.s + 1.0
		cop.d = sim.me.d + 1.3
		sim.inp.hand = true
		sim.step(1.0 / 60.0)
		tt += 1.0 / 60.0
		for ev in sim.events:
			if ev[0] == "hit" and ev[1] == cop:
				punches += 1
			if ev[0] == "siren" and ev[1] == false:
				siren_off = true
		sim.events.clear()
	_ok("you can knock a cop out", cop.state == Sim.DOWN and int(sim.stats.cop_ko) == 1 and siren_off, "%d punches, %.1f s, siren off %s" % [punches, tt, siren_off])

func _buying() -> void:
	S.reset_for_test()
	_ok("new game: Dragonfly, T-shirt, no money", S.owns("strek") and int(S.data.money) == 0 and int(S.data.gear.suit) == 0 and int(S.data.gear.helmet) == 0)
	_ok("no money, no purchase", not S.buy_bike("shmel") and not S.buy_up("strek", "eng") and not S.buy_wear("suit", 2))
	S.data.money = 10000
	_ok("buy Bumblebee for $1200", S.buy_bike("shmel") and int(S.data.money) == 8800 and S.ride_of(0).id == "shmel")
	_ok("closed league not for sale", not S.buy_bike("kobra") and not S.owns("kobra"))
	var m0: int = S.data.money
	var cost: int = S.up_cost(D.bike_by_id["shmel"], 0)
	_ok("engine level 1 costs 8% of price", S.buy_up("shmel", "eng") and int(S.data.money) == m0 - cost and int(S.upgrades("shmel").eng) == 1, "$%d" % cost)
	var st: Dictionary = D.stats_of(D.bike_by_id["shmel"], S.upgrades("shmel"))
	_ok("upgrade changes the bike", int(st.kmh) > int(D.bike_by_id["shmel"].kmh), "%d → %d km/h" % [int(D.bike_by_id["shmel"].kmh), int(st.kmh)])
	_ok("buy leather jacket, worn at once", S.buy_wear("suit", 2) and int(S.data.gear.suit) == 2)
	_ok("swap back to T-shirt free", S.wear("suit", 0) and int(S.data.gear.suit) == 0)
	_ok("cannot wear what you do not own", not S.wear("suit", 5))
	var before: int = S.data.money
	S.buy_weapon("chain")
	_ok("chain goes into stock", int(S.data.gear.chain) == 1 and int(S.data.money) == before - 60)
	_ok("best weapon by default", S.start_weapon(0) == "chain")
	S.data.gear.weaponPick = "none"
	_ok("can choose fists instead", S.start_weapon(0) == "none")
	S.data.gear.weaponPick = "best"
	S.data.gear.suits.append(5)
	_ok("racing suit forbids a weapon", S.start_weapon(5) == "none")
	var sim := Sim.new()
	var lo := S.loadout("shmel")
	sim.setup(0, "shmel", lo.u, lo.suit, lo.helmet, lo.cs, lo.ch, 1, lo.extra)
	_ok("the race uses what you bought", sim.me.weapon == "chain" and sim.me.st.kmh > 90.0 and sim.me.bike.id == "shmel", "%s, %.0f km/h" % [sim.me.weapon, sim.me.st.kmh])
	_ok("paint: try, buy, keep", S.buy_paint("shmel", 3) and int(S.upgrades("shmel").paint) == 3 and S.pick_paint("shmel", int(D.bike_by_id["shmel"].paint)))

func _save_reload() -> void:
	var money: int = S.data.money
	S.persist()
	S.load_save()
	_ok("everything survives a reload", int(S.data.money) == money and S.owns("shmel") and int(S.upgrades("shmel").eng) == 1 and (2 in S.data.gear.suits) and int(S.data.gear.chain) == 1 and S.ride_of(0).id == "shmel")
	_ok("lists still work after reload", S.wear("suit", 2) and not S.buy_wear("suit", 2))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(S.path))
	S.load_save()
	_ok("no file means a new game", int(S.data.money) == 0 and S.owns("strek") and not S.owns("shmel"))

func _ledger() -> void:
	S.reset_for_test()
	S.data.money = 1000
	var sim := Sim.new()
	sim.setup(0, "strek", {}, 0, 0, 0, 0, 1)
	sim.final_place = 2
	sim.stats.ko = 2
	sim.stats.cop_ko = 1
	sim.me.bike_hp = float(sim.me.st.dur) * 0.5
	var r := S.finish_race(sim, "finish")
	# prize 400: 2nd 60% = 240, KO 6% rounded to tens = 20 x 2, cop 100, repair 25% x 50% = 50
	_ok("finish money", int(r.total) == 240 + 40 + 100 - 50 and int(S.data.money) == 1000 + 330, str(r.ledger))
	S.reset_for_test()
	S.data.money = 1000
	var s2 := Sim.new()
	s2.setup(0, "strek", {}, 0, 0, 0, 0, 1)
	var r2 := S.finish_race(s2, "busted")
	_ok("arrest fine 30% of prize", _line(r2, "Штраф") == -120 and r2.bad, str(r2.ledger))
	_ok("insurance: arrested at the start still gets $10", int(r2.total) == 10 and int(S.data.money) == 1010, str(r2.ledger))
	var s3 := Sim.new()
	S.data.money = 50
	s3.setup(0, "strek", {}, 0, 0, 0, 0, 1)
	var r3 := S.finish_race(s3, "dead")
	_ok("hospital 20%, and you still come out ahead", _line(r3, "Больница") == -80 and int(r3.total) == 10 and int(S.data.money) == 60, str(r3.ledger))
	# difficulty: easy -20 % on prizes and fines, hard +20 %; insurance grows with the distance covered
	var s4 := Sim.new()
	S.data.money = 0
	s4.setup(0, "strek", {}, 0, 0, 0, 0, 1, {"diff": 0})
	s4.me.ps = s4.road.finish_s - 1.0
	var r4 := S.finish_race(s4, "busted")
	_ok("easy: fine 80 %, insurance 12 % x 80 % near the line", _line(r4, "Штраф") == -100 and int(r4.total) == 40, str(r4.ledger))
	var s5 := Sim.new()
	s5.setup(0, "strek", {}, 0, 0, 0, 0, 1, {"diff": 2})
	s5.final_place = 1
	s5.end_kind = "finish"
	var r5 := S.finish_race(s5, "finish")
	_ok("hard: first prize 120 %", _line(r5, "Приз за 1 место") == 480, str(r5.ledger))
	var s6 := Sim.new()
	s6.setup(0, "strek", {}, 0, 0, 0, 0, 1)
	s6.final_place = 8
	s6.end_kind = "finish"
	var r6 := S.finish_race(s6, "finish")
	_ok("last place still pays the insurance minimum", int(r6.total) == 50, str(r6.ledger))

func _line(r: Dictionary, label: String) -> int:
	for l in r.ledger:
		if l[0] == label:
			return int(l[1])
	return 0

func _weapon_stock() -> void:
	S.reset_for_test()
	S.data.gear.chain = 2
	var sim := Sim.new()
	var lo := S.loadout("strek")
	sim.setup(0, "strek", lo.u, lo.suit, lo.helmet, lo.cs, lo.ch, 1, lo.extra)
	sim.phase = "race"
	sim.crash("car", 10.0)
	var used := 0
	for ev in sim.events:
		if ev[0] == "stock":
			used += 1
			S.use_weapon(ev[1])
	_ok("fall costs the weapon", used == 1 and int(S.data.gear.chain) == 1 and sim.me.weapon == "none")
	S.reset_for_test()
	var s2 := Sim.new()
	s2.setup(0, "strek", {}, 0, 0, 0, 0, 1)
	s2.me.weapon = "baton"
	s2.final_place = 3
	var r := S.finish_race(s2, "finish")
	_ok("weapon taken off a rival is yours at the finish", int(S.data.gear.baton) == 1 and "Трофей" in str(r.note), str(r.note))

func _unlock() -> void:
	S.reset_for_test()
	var sim := Sim.new()
	sim.setup(0, "strek", {}, 0, 0, 0, 0, 1)
	sim.final_place = 4
	var r := S.finish_race(sim, "finish")
	_ok("4th place opens nothing", int(S.data.open) == 1 and int(r.next) == -1)
	sim.final_place = 3
	var r2 := S.finish_race(sim, "finish")
	_ok("top 3 opens the next track", int(S.data.open) == 2 and int(r2.next) == 1, str(r2.note))
	_ok("best place remembered", int(S.data.best.dachi) == 3)
	S.reset_for_test()
