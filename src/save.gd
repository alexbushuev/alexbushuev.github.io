extends Node
# Everything the player owns, and every rule about money. No graphics here, so it can be tested on its own.

var path := "user://save.json"
var data: Dictionary = {}

func _ready() -> void:
	D.load_all()
	load_save()

func fresh() -> Dictionary:
	var strek: Dictionary = D.bike_by_id["strek"]
	return {
		"v": 1, "money": 0, "open": 1, "best": {}, "sound": true,
		"bikes": {"strek": new_bike(strek)}, "ride": {"0": "strek"},
		"gear": {"glove": 0, "boot": 0, "baton": 0, "chain": 0, "suit": 0, "suits": [0], "helmet": 0, "helmets": [0], "suitColor": 0, "helmColor": 5, "weaponPick": "best"},
	}

func new_bike(b: Dictionary) -> Dictionary:
	return {"eng": 0, "acc": 0, "tire": 0, "susp": 0, "frame": 0, "paint": int(b.paint), "paints": [int(b.paint)]}

func _ints(a: Array) -> Array:
	var out: Array = []
	for x in a:
		out.append(int(x))
	return out

func load_save() -> void:
	data = fresh()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var loaded: Variant = JSON.parse_string(f.get_as_text())
	if not (loaded is Dictionary):
		return
	data.merge(loaded, true)
	var base: Dictionary = fresh().gear
	base.merge(data.gear, true)
	data.gear = base
	# JSON turns every number into a float; lists are compared by value, so bring them back
	for key in ["glove", "boot", "baton", "chain", "suit", "helmet", "suitColor", "helmColor"]:
		data.gear[key] = int(data.gear[key])
	data.gear.suits = _ints(data.gear.suits)
	data.gear.helmets = _ints(data.gear.helmets)
	data.money = int(data.money)
	data.open = int(data.open)
	for id in data.bikes:
		var b: Dictionary = data.bikes[id]
		for key in ["eng", "acc", "tire", "susp", "frame", "paint"]:
			b[key] = int(b.get(key, 0))
		b.paints = _ints(b.get("paints", [b.paint]))
	for id in data.best:
		data.best[id] = int(data.best[id])

func persist() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()

func reset_for_test() -> void:
	data = fresh()

# ---------- lookups ----------
func track_open(i: int) -> bool:
	return i < int(data.open)

func cat_open(c: int) -> bool:
	for i in D.tracks.size():
		if int(D.tracks[i].cat) == c and track_open(i):
			return true
	return false

func first_track_of(c: int) -> int:
	for i in D.tracks.size():
		if int(D.tracks[i].cat) == c:
			return i
	return 0

func owns(id: String) -> bool:
	return data.bikes.has(id)

func ride_of(c: int) -> Variant:
	var id: Variant = data.ride.get(str(c))
	if id != null and owns(str(id)):
		return D.bike_by_id[id]
	return null

func owned_in(c: int) -> Array:
	var out: Array = []
	for b in D.bikes:
		if int(b.cat) == c and owns(b.id):
			out.append(b)
	return out

func upgrades(id: String) -> Dictionary:
	return data.bikes.get(id, {})

func start_weapon(suit: int) -> String:
	var g: Dictionary = data.gear
	if D.gear.suits[suit].get("noHand", false):
		return "none"
	var pick: String = g.get("weaponPick", "best")
	if pick == "none":
		return "none"
	if pick != "best" and int(g.get(pick, 0)) > 0:
		return pick
	return "chain" if int(g.chain) > 0 else ("baton" if int(g.baton) > 0 else "none")

func loadout(id: String) -> Dictionary:
	var g: Dictionary = data.gear
	var u: Dictionary = upgrades(id)
	return {"u": u, "suit": int(g.suit), "helmet": int(g.helmet), "cs": int(g.suitColor), "ch": int(g.helmColor),
		"extra": {"glove": int(g.glove), "boot": int(g.boot), "weapon": start_weapon(int(g.suit)), "paint": int(u.get("paint", D.bike_by_id[id].paint))}}

func round10(v: float) -> int:
	return int(round(v / 10.0)) * 10

func round50(v: float) -> int:
	return int(round(v / 50.0)) * 50

func fmt(n: float) -> String:
	var s := str(abs(int(round(n))))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return "$" + s + out

func safe_kmh(prot: float) -> float:
	return 100.0 / (float(D.rules.fall_k) * (1.0 - prot))

func safe_txt(prot: float) -> String:
	var v := safe_kmh(prot)
	return "Переживёшь падение на любой скорости" if v >= 400.0 else "Переживёшь падение до %d км/ч" % int(round(v))

func accel_txt(a: float, b: Dictionary) -> String:
	var c: Dictionary = D.leagues[int(b.cat)]
	return ("%.1f" % (2.08 / a + (int(c.gears) - 1) * float(c.shift))).replace(".", ",")

func kg_txt(v: float) -> String:
	return ("%.1f" % v).replace(".0", "").replace(".", ",")

# ---------- prices ----------
func cost_base(b: Dictionary) -> float:
	return max(float(b.price), 1000.0)

func up_cost(b: Dictionary, level: int) -> int:
	return round50(cost_base(b) * float(D.rules.upgrade_cost[level]))

func paint_cost(b: Dictionary) -> int:
	return round50(cost_base(b) * 0.1)

func spend(cost: int) -> bool:
	if int(data.money) < cost:
		return false
	data.money = int(data.money) - cost
	return true

# ---------- buying. Each returns true if it went through ----------
func buy_bike(id: String) -> bool:
	var b: Dictionary = D.bike_by_id[id]
	if owns(id) or not cat_open(int(b.cat)) or not spend(int(b.price)):
		return false
	data.bikes[id] = new_bike(b)
	data.ride[str(int(b.cat))] = id
	persist()
	return true

func buy_up(id: String, up: String) -> bool:
	var u: Dictionary = upgrades(id)
	var level: int = int(u.get(up, 0))
	if u.is_empty() or level >= int(D.rules.max_level) or not spend(up_cost(D.bike_by_id[id], level)):
		return false
	u[up] = level + 1
	persist()
	return true

func pick_paint(id: String, k: int) -> bool:
	var u: Dictionary = upgrades(id)
	if u.is_empty() or not (k in u.paints):
		return false
	u.paint = k
	persist()
	return true

func buy_paint(id: String, k: int) -> bool:
	var u: Dictionary = upgrades(id)
	if u.is_empty() or (k in u.paints) or not spend(paint_cost(D.bike_by_id[id])):
		return false
	u.paints.append(k)
	u.paint = k
	persist()
	return true

func buy_gear_up(up: String) -> bool:
	var level: int = int(data.gear[up])
	if level >= int(D.rules.max_level) or not spend(int(D.rules.gear_cost[up][level])):
		return false
	data.gear[up] = level + 1
	persist()
	return true

func buy_weapon(w: String) -> bool:
	if int(data.gear[w]) >= 9 or not spend(int(D.rules.gear_cost[w])):
		return false
	data.gear[w] = int(data.gear[w]) + 1
	persist()
	return true

func buy_wear(kind: String, k: int) -> bool:
	var list: Array = data.gear.suits if kind == "suit" else data.gear.helmets
	var items: Array = D.gear.suits if kind == "suit" else D.gear.helmets
	if k in list or not spend(int(items[k].price)):
		return false
	list.append(k)
	data.gear[kind] = k
	persist()
	return true

func wear(kind: String, k: int) -> bool:
	var list: Array = data.gear.suits if kind == "suit" else data.gear.helmets
	if not (k in list):
		return false
	data.gear[kind] = k
	persist()
	return true

func use_weapon(w: String) -> void:
	data.gear[w] = max(0, int(data.gear[w]) - 1)
	persist()

func add_test_money() -> void:
	data.money = int(data.money) + 25000
	persist()

func open_everything() -> void:
	data.open = D.tracks.size()
	persist()

# ---------- end of a race: same ledger as the 2D game ----------
func finish_race(sim: Sim, kind: String) -> Dictionary:
	var tr: Dictionary = sim.tr
	var i: int = sim.track_i
	var me: Sim.Rider = sim.me
	var p0: float = tr.prize
	var finished: bool = kind == "finish"
	var place: int = sim.final_place
	var g: Dictionary = data.gear
	var title := ""
	var text := ""
	var note := ""
	var bad := false
	if finished:
		title = "%d место" % place
		text = ("Призовое место на трассе %s." % tr.name) if place <= 3 else "До призовых не дотянул. Нужно топ-3."
		var prev: Variant = data.best.get(tr.id)
		if prev == null or place < int(prev):
			data.best[tr.id] = place
		if place <= 3 and i + 1 < D.tracks.size() and int(data.open) < i + 2:
			var nl: Dictionary = D.tracks[i + 1]
			data.open = i + 2
			note = ("Открыта трасса %s." % nl.name) if int(nl.cat) == int(tr.cat) else ("Открыта %s. Байки уже в магазине." % str(D.leagues[int(nl.cat)].full).to_lower())
	elif kind == "busted":
		title = "Задержан"
		bad = true
		text = "Упал рядом с полицейским. Гонка окончена."
	elif kind == "dead":
		title = "В больнице"
		bad = true
		var suit: Dictionary = D.gear.suits[int(g.suit)]
		text = "Упал на %d км/ч %s%s. Скорая увезла, гонка окончена." % [int(me.fall_kmh), suit["in"], "" if int(g.helmet) > 0 else " и без шлема"]
		if float(suit.prot) + float(D.gear.helmets[int(g.helmet)].prot) < 0.5:
			note = "Защита покупается в гараже, раздел «Экипировка»."
	else:
		title = "Мотоцикл в хлам"
		bad = true
		text = "Больше ехать не на чем. Гонка окончена."
	if finished and me.weapon != "none" and not (me.start_w == me.weapon and not me.start_gone):
		g[me.weapon] = min(9, int(g[me.weapon]) + 1)
		note = (note + " " if note != "" else "") + "Трофей: %s теперь в гараже." % D.gear.weapons[me.weapon].name
	# standings
	var rows: Array = []
	if finished:
		var ahead: Array = sim.order.slice(0, place - 1)
		for f in ahead:
			rows.append(f.name)
		rows.append("Ты")
		for f in sim.order.slice(ahead.size()):
			rows.append(f.name)
		var rest: Array = []
		for f in sim.foes:
			if not f.is_cop and not f.finished:
				rest.append(f)
		rest.sort_custom(func(a: Sim.Rider, b: Sim.Rider) -> bool: return (not a.out and b.out) or (a.out == b.out and a.s > b.s))
		for f in rest:
			rows.append(f.name + ", сход" if f.out else f.name)
	# money
	var ledger: Array = []
	var total := 0
	var add := func(label: String, v: int) -> void:
		ledger.append([label, v])
	if finished:
		add.call("Приз за %d место" % place, round10(p0 * float(D.rules.place_share[place - 1])))
	if int(sim.stats.ko) > 0:
		add.call("Нокауты × %d" % int(sim.stats.ko), round10(p0 * 0.06) * int(sim.stats.ko))
	if int(sim.stats.cop_ko) > 0:
		add.call("Копы вырублены × %d" % int(sim.stats.cop_ko) if int(sim.stats.cop_ko) > 1 else "Коп вырублен", round10(p0 * 0.25) * int(sim.stats.cop_ko))
	if kind == "busted":
		add.call("Штраф", -round10(p0 * 0.3))
	if kind == "dead":
		add.call("Больница", -round10(p0 * 0.2))
	var dmg: float = float(me.st.dur) - me.bike_hp
	if dmg > 0.5:
		add.call("Ремонт", -max(10, round10(p0 * 0.25 * dmg / float(me.st.dur))))
	for r in ledger:
		total += int(r[1])
	data.money = max(0, int(data.money) + total)
	persist()
	return {"title": title, "text": text, "note": note, "bad": bad, "ledger": ledger, "total": total, "rows": rows, "finished": finished, "money": data.money, "place": place,
		"next": i + 1 if (i + 1 < D.tracks.size() and track_open(i + 1)) else -1}
