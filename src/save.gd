extends Node
# Everything the player owns, and every rule about money. No graphics here, so it can be tested on its own.

var path := "user://save.json"
var data: Dictionary = {}
var key_codes := {}     # action -> physical keycodes, rebuilt whenever the keys change

const KEY_ACTIONS := [["gas", "Газ"], ["left", "Влево"], ["right", "Вправо"], ["brake", "Тормоз"], ["hand", "Рука"], ["kick", "Нога"], ["pause", "Пауза"]]
const DIFF_NAMES := ["Лёгкая", "Средняя", "Сложная"]
const DIFF_TAGS := ["лёгкая", "", "сложная"]
const KEY_NAMES := {"": "нет", "Up": "Вверх", "Down": "Вниз", "Left": "Влево", "Right": "Вправо", "Space": "Пробел", "Escape": "Esc", "Comma": ",", "Period": ".", "Slash": "/", "Semicolon": ";", "Apostrophe": "'", "BracketLeft": "[", "BracketRight": "]", "Minus": "-", "Equal": "=", "Backslash": "\\", "QuoteLeft": "`", "Ctrl": "Ctrl", "Shift": "Shift", "Alt": "Alt"}

func _ready() -> void:
	D.load_all()
	load_save()

func fresh() -> Dictionary:
	var strek: Dictionary = D.bike_by_id["strek"]
	return {
		"v": 1, "money": 0, "open": 1, "best": {}, "sound": true, "volume": 0.8, "vol_engine": 1.0, "vol_voice": 1.0, "mirrors": true, "difficulty": 1, "keys": default_keys(),
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
	_rebuild_keys()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var loaded: Variant = JSON.parse_string(f.get_as_text())
	if not (loaded is Dictionary):
		return
	apply(loaded)

# Takes a save from the file or from the server and makes it whole: defaults for anything missing, numbers back to ints
func apply(loaded: Dictionary) -> void:
	data = fresh()
	data.merge(loaded.duplicate(true), true)
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
	data.difficulty = clampi(int(data.get("difficulty", 1)), 0, 2)
	for id in data.bikes:
		var b: Dictionary = data.bikes[id]
		for key in ["eng", "acc", "tire", "susp", "frame", "paint"]:
			b[key] = int(b.get(key, 0))
		b.paints = _ints(b.get("paints", [b.paint]))
	for id in data.best:
		data.best[id] = int(data.best[id])
	var keys: Dictionary = default_keys()
	if data.get("keys") is Dictionary:
		for a in keys:
			var saved: Variant = data.keys.get(a)
			if saved is Array and saved.size() == 2:
				keys[a] = saved
	data.keys = keys
	_rebuild_keys()

func persist(sync := true) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()
	# logged in: the account on the server gets it a moment later
	var net: Node = get_node_or_null("/root/N")
	if sync and net != null:
		net.mark_dirty()

func reset_for_test() -> void:
	data = fresh()
	_rebuild_keys()

# ---------- sound ----------
func sound_on() -> bool:
	return bool(data.sound) and float(data.volume) > 0.001

# the slider follows the ear, not the amplitude: half way is about a quarter of the signal
func volume_db(key := "volume") -> float:
	var v: float = clamp(float(data[key]), 0.0, 1.0)
	return linear_to_db(max(v * v, 0.00001))

func voices_on() -> bool:
	return float(data.vol_voice) > 0.001

# ---------- keys ----------
func default_keys() -> Dictionary:
	var out := {}
	var k: Dictionary = D.rules["keys"]
	for a in k:
		var pair: Array = []
		for n in k[a]:
			pair.append(str(n).replace("Arrow", "").replace("Key", ""))
		out[a] = pair
	return out

func _rebuild_keys() -> void:
	key_codes.clear()
	for a in data.keys:
		var list: Array = []
		for n in data.keys[a]:
			if n != null:
				var code := OS.find_keycode_from_string(str(n))
				if code != KEY_NONE:
					list.append(code)
		key_codes[a] = list

func key_down(action: String) -> bool:
	for code in key_codes.get(action, []):
		if Input.is_physical_key_pressed(code):
			return true
	return false

func action_of_key(code: int) -> String:
	for a in key_codes:
		if code in key_codes[a]:
			return a
	return ""

func key_label(n: Variant) -> String:
	if n == null:
		return "нет"
	return KEY_NAMES.get(str(n), str(n))

func action_name(a: String) -> String:
	for x in KEY_ACTIONS:
		if x[0] == a:
			return x[1]
	return a

# Same rules as the 2D game. An empty code removes the key. Returns what to tell the player.
func assign_key(a: String, i: int, code: String) -> String:
	var K: Dictionary = data.keys
	var old: Variant = K[a][i]
	var msg := ""
	if code == "":
		if K[a][1 - i] == null:
			return "Нужна хотя бы одна клавиша на действие."
		K[a][i] = null
		msg = "Клавиша убрана."
	elif code != old:
		var from: Array = []
		for act in K:
			for slot in 2:
				if K[act][slot] == code:
					from = [act, slot]
		if not from.is_empty() and old == null and from[0] != a and K[from[0]][1 - from[1]] == null:
			return "Это единственная клавиша действия «%s». Сначала дай ему другую." % action_name(from[0])
		if not from.is_empty():
			K[from[0]][from[1]] = old
		K[a][i] = code
		if not from.is_empty() and from[0] != a:
			msg = ("Поменялись клавишами с действием «%s»." if old != null else "Клавиша забрана у действия «%s».") % action_name(from[0])
	_rebuild_keys()
	persist()
	return msg

func reset_keys() -> void:
	data.keys = default_keys()
	_rebuild_keys()
	persist()

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
		"extra": {"glove": int(g.glove), "boot": int(g.boot), "weapon": start_weapon(int(g.suit)), "paint": int(u.get("paint", D.bike_by_id[id].paint)), "diff": int(data.difficulty)}}

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

# how much of your health one fall at this speed takes
func fall_pct(kmh: float, prot: float) -> int:
	return int(round(D.fall_injury(kmh, prot)))

func fastest_kmh() -> float:
	var best := 60.0
	for id in data.bikes:
		best = max(best, float(D.stats_of(D.bike_by_id[id], upgrades(id)).kmh))
	return best

func safe_txt(prot: float, kmh := 300.0) -> String:
	return "Падение на %d км/ч: −%d%% здоровья" % [int(kmh), fall_pct(kmh, prot)]

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
const DIFF_MONEY := [0.8, 1.0, 1.2]

# what any race pays at least: 12 % of the first prize for the whole distance, less for part of it, never under $10
func min_gain(sim: Sim) -> int:
	var road: Road = sim.road
	var done: float = clamp((sim.me.ps - road.start_s) / max(1.0, road.finish_s - road.start_s), 0.0, 1.0)
	if sim.end_kind == "finish":
		done = 1.0
	return max(10, round10(float(sim.tr.prize) * 0.12 * DIFF_MONEY[clampi(sim.diff, 0, 2)] * done))
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
		text = "Упал на %d км/ч %s%s, а здоровья уже не хватило. Скорая увезла, гонка окончена." % [int(me.fall_kmh), suit["in"], "" if int(g.helmet) > 0 else " и без шлема"]
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
	# difficulty: on easy prizes and fines are 20 % smaller, on hard 20 % bigger
	var k: float = DIFF_MONEY[clampi(sim.diff, 0, 2)]
	if finished:
		add.call("Приз за %d место" % place, round10(p0 * float(D.rules.place_share[place - 1]) * k))
	if int(sim.stats.ko) > 0:
		add.call("Нокауты × %d" % int(sim.stats.ko), round10(p0 * 0.06 * k) * int(sim.stats.ko))
	if int(sim.stats.cop_ko) > 0:
		add.call("Копы вырублены × %d" % int(sim.stats.cop_ko) if int(sim.stats.cop_ko) > 1 else "Коп вырублен", round10(p0 * 0.25 * k) * int(sim.stats.cop_ko))
	if int(sim.stats.get("trick_pts", 0)) > 0:
		add.call("Трюки × %d" % int(sim.stats.tricks), round10(p0 * 0.015 * k * int(sim.stats.trick_pts)))
	if kind == "busted":
		add.call("Штраф", -round10(p0 * 0.3 * k))
	if kind == "dead":
		add.call("Больница", -round10(p0 * 0.2 * k))
	var dmg: float = float(me.st.dur) - me.bike_hp
	if dmg > 0.5:
		add.call("Ремонт", -max(10, round10(p0 * 0.25 * dmg / float(me.st.dur))))
	for r in ledger:
		total += int(r[1])
	# a race never leaves you poorer: the racer's insurance tops it up to a small sum, more the further you got
	var floor_v: int = min_gain(sim)
	if total < floor_v:
		add.call("Страховка гонщика", floor_v - total)
		total = floor_v
	data.money = max(0, int(data.money) + total)
	persist()
	return {"title": title, "text": text, "note": note, "bad": bad, "ledger": ledger, "total": total, "rows": rows, "finished": finished, "money": data.money, "place": place,
		"next": i + 1 if (i + 1 < D.tracks.size() and track_open(i + 1)) else -1}
