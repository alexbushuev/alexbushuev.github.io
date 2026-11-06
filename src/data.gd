extends Node
# Loads the portable game data (data/*.json, models/models.json) and does the arithmetic the 2D game did on it.

var leagues: Array
var tracks: Array
var bikes: Array
var bike_by_id := {}
var gear: Dictionary
var rivals: Dictionary
var themes: Array
var rules: Dictionary
var models: Dictionary
var decor_solid: Dictionary
var sound: Dictionary

func _load(n: String) -> Variant:
	var f := FileAccess.open(n, FileAccess.READ)
	if f == null:
		push_error("no file " + n)
		return null
	return JSON.parse_string(f.get_as_text())

func _ready() -> void:
	load_all()

func load_all() -> void:
	if leagues.size() > 0:
		return
	leagues = _load("res://data/leagues.json")
	tracks = _load("res://data/tracks.json")
	bikes = _load("res://data/bikes.json")
	gear = _load("res://data/gear.json")
	rivals = _load("res://data/rivals.json")
	themes = _load("res://data/themes.json")
	rules = _load("res://data/rules.json")
	sound = _load("res://data/sound.json")
	decor_solid = _load("res://data/decor_solid.json")
	models = _load("res://models/models.json")
	for b in bikes:
		bike_by_id[b.id] = b

func hexc(s: String) -> Color:
	return Color(s)

func aero_loss(aero: float, kmh: float) -> float:
	return (100.0 - aero) / 100.0 * pow(kmh / 300.0, 2) * 0.08

func weight_loss(kg: float, hp: float) -> float:
	return kg * 0.02 / (1.0 + hp / 25.0)

func gear_fx(ts: int, th: int) -> Dictionary:
	var a: Dictionary = gear.suits[ts]
	var h: Dictionary = gear.helmets[th]
	var no_hand: bool = a.get("noHand", false)
	var hk: float = a.kick if no_hand else a.hit
	return {
		"kg": a.kg + h.kg, "aero": round(a.aero * 0.75 + h.aero * 0.25), "prot": min(0.95, a.prot + h.prot),
		"hit": a.hit, "kick": a.kick, "no_hand": no_hand, "cd_k": 1.0 / (0.5 + 0.5 * hk), "reach_k": 0.75 + 0.25 * hk,
	}

func stats_of(b: Dictionary, u: Dictionary) -> Dictionary:
	return {
		"kmh": round(b.kmh * (1.0 + 0.03 * u.get("eng", 0))), "hp": round(b.hp * (1.0 + 0.06 * u.get("eng", 0))),
		"acc": b.acc * (1.0 + 0.1 * u.get("acc", 0)), "grip": b.grip + 8.0 * u.get("tire", 0),
		"hand": b.hand + 8.0 * u.get("susp", 0), "dur": round(b.dur * (1.0 + 0.12 * u.get("frame", 0))),
	}

# Real units from here on: metres, seconds. grip and handling turn into lateral acceleration.
# How fast the world really moves for a speedometer reading. Same as speedOf() in the 2D game:
# 300 km/h on the dial crosses three road widths a second, not six. The dial keeps its numbers, the road stays readable.
func world_speed(kmh: float) -> float:
	return 9.72 + 0.1116 * kmh

func grip_f(grip: float) -> float:
	return 1.35 - 0.0075 * grip

func steer_k(hand: float) -> float:
	return 0.72 + 0.006 * hand

# fastest steady cornering, m/s2. Same limit as cornerLimit() in the 2D game, in real units
func a_grip(grip: float, hand: float) -> float:
	return 8.69 * steer_k(hand) / grip_f(grip)

# strong arcade brakes that grow with top speed, like the 2D game
func a_brake(grip: float, top: float) -> float:
	return max(9.0 + 0.05 * grip, top * 0.45)

func rider_stats(b: Dictionary, u: Dictionary, ts: int, th: int, glove := 0, boot := 0, weapon := "none") -> Dictionary:
	var s := stats_of(b, u)
	var fx := gear_fx(ts, th)
	var c: Dictionary = leagues[int(b.cat)]
	var kmh: float = s.kmh * (1.0 - aero_loss(fx.aero, s.kmh))
	return {
		"gears": int(c.gears), "shift": c.shift, "cyl": int(c.cyl), "idle": c.idle, "red": c.red, "voice": sound_voice(b),
		"kmh": kmh, "top": world_speed(kmh), "accel": s.acc * (1.0 - weight_loss(fx.kg, s.hp)),
		"a_grip": a_grip(s.grip, s.hand), "a_brake": a_brake(s.grip, world_speed(kmh)), "off": 1.2 - 0.006 * s.grip,
		"grip_f": grip_f(s.grip), "steer": steer_k(s.hand), "dur": s.dur, "prot": fx.prot, "no_hand": fx.no_hand, "hit_k": fx.hit,
		"cd_k": fx.cd_k, "reach_k": fx.reach_k, "fist": max(1, round((10 + 3 * glove) * fx.hit)),
		"kick": max(1, round((9 + 3 * boot) * fx.kick)), "push": 1.0 + 0.15 * boot,
		"weapon": "none" if fx.no_hand else weapon,
	}

# Each league's engine note; a bigger engine sits a little lower than a smaller one in its league
func sound_voice(b: Dictionary) -> Dictionary:
	var v: Dictionary = sound.leagues[int(b.cat)].duplicate()
	v["k"] = clamp(pow(float(v.cc) / max(1.0, float(b.cc)), 0.2), 0.8, 1.25)
	return v

func outfit(ts: int, cs: int, ch: int, glove := 0, boot := 0) -> Dictionary:
	var col: Dictionary = gear.colors[cs]
	var hc: Dictionary = gear.colors[ch]
	var skin := "#e0b48c"
	return {
		"jacket": col.c, "stripe": col.s if ts > 0 else col.c,
		"pants": col.c if ts >= 4 else ("#22222a" if ts >= 2 else "#3a5a8a"),
		"boots": "#5a5a66" if boot >= 3 else ("#0e0e12" if ts > 0 else "#c9c9c9"),
		"glove": ("#8a8a98" if glove >= 3 else "#16151b") if ts > 0 else skin,
		"skin": skin, "helmet": hc.c, "hs": hc.s, "sleeve": skin if ts == 0 else col.c,
	}
