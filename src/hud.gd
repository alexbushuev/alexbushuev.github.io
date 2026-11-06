class_name Hud extends Control
# Numbers on screen and the touch deck. On a phone the gas works by itself: left thumb steers, right thumb brakes and hits.

signal pause_pressed

var sim: Sim
var font_big: Font
var font_mid: Font
var font_small: Font
var touch_mode := false
var buttons: Array = []     # {id, rect, kind}
var touches := {}           # touch index -> button id
var pressed := {}
var banner_txt := ""
var banner_t := 0.0
var banner_bad := false
var say_txt := ""
var say_t := 0.0
var keys_steer := 0.0
var key_state := {}
var inset := Vector2.ZERO
var mirror_tex: Texture2D       # what the rear camera sees; the mirrors show it flipped
var dash_scale := 1.0

const C_INK := Color("#16151b")
const C_PAPER := Color("#f3eedf")
const C_YEL := Color("#ffc81f")
const C_RED := Color("#d9232e")
const C_GRN := Color("#2aa84f")
const C_DECK := Color(0.06, 0.06, 0.08, 0.34)
const C_DECK_ON := Color(1.0, 0.78, 0.12, 0.62)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_mode = UiKit.has_touch()
	_layout()
	resized.connect(_layout)

func set_fonts(big: Font, mid: Font, small: Font) -> void:
	font_big = big
	font_mid = mid
	font_small = small

func _layout() -> void:
	buttons.clear()
	var w: float = size.x
	var h: float = size.y
	var u: float = min(h * 0.22, w * 0.11)
	var pad: float = max(10.0, w * 0.012)
	var sw: float = u * 1.25
	var sh: float = u * 1.2
	var gap := 8.0
	var y1: float = h - pad - sh
	buttons.append({"id": "left", "rect": Rect2(pad, y1, sw, sh), "label": "◀"})
	buttons.append({"id": "right", "rect": Rect2(pad + sw + gap, y1, sw, sh), "label": "▶"})
	var rx: float = w - pad - sw * 2.0 - gap
	buttons.append({"id": "brake", "rect": Rect2(rx, y1, sw * 2.0 + gap, sh), "label": "ТОРМОЗ"})
	var hh: float = u * 0.86
	var y2: float = y1 - gap - hh
	buttons.append({"id": "hand", "rect": Rect2(rx, y2, sw, hh), "label": "РУКА"})
	buttons.append({"id": "kick", "rect": Rect2(rx + sw + gap, y2, sw, hh), "label": "НОГА"})
	buttons.append({"id": "pause", "rect": Rect2(w - pad - 46.0, pad, 46.0, 34.0), "label": "II"})

func button_at(p: Vector2) -> String:
	var best := ""
	for b in buttons:
		if b.rect.grow(10.0).has_point(p):
			best = b.id
			if b.rect.has_point(p):
				return b.id
	return best

# paused: the deck under the pause screen must not catch fingers meant for its buttons
func set_active(on: bool) -> void:
	set_process_input(on)
	touches.clear()
	pressed.clear()

func _input(event: InputEvent) -> void:
	if sim == null:
		return
	if event is InputEventKey:
		# a touch laptop or a phone with a keyboard: whatever was used last decides
		if event.pressed and S.action_of_key(event.physical_keycode) != "":
			touch_mode = false
	elif event is InputEventScreenTouch:
		touch_mode = true
		var id := button_at(event.position)
		if event.pressed:
			touches[event.index] = id
			_press(id)
		else:
			touches.erase(event.index)
		_recount()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var id2 := button_at(event.position)
		var prev: String = touches.get(event.index, "")
		# a thumb slides across the buttons of its own side without lifting
		for side in [["left", "right"], ["brake", "hand", "kick"]]:
			if id2 != prev and prev in side and id2 in side:
				touches[event.index] = id2
				_recount()
		get_viewport().set_input_as_handled()

func _press(id: String) -> void:
	if id == "pause":
		pause_pressed.emit()

func _recount() -> void:
	pressed.clear()
	for k in touches:
		pressed[touches[k]] = true

func read_input() -> void:
	var left: bool = pressed.has("left") or S.key_down("left")
	var right: bool = pressed.has("right") or S.key_down("right")
	sim.inp.steer = (1.0 if right else 0.0) - (1.0 if left else 0.0)
	var brake: bool = pressed.has("brake") or S.key_down("brake")
	sim.inp.brake = brake
	sim.inp.gas = S.key_down("gas") or (touch_mode and not brake and sim.phase != "count")
	sim.inp.hand = pressed.has("hand") or S.key_down("hand")
	sim.inp.kick = pressed.has("kick") or S.key_down("kick")

static func race_time(t: float) -> String:
	var ms := int(round(t * 10.0))
	return "%d:%02d.%d" % [ms / 600, (ms / 10) % 60, ms % 10]

# ---------- the bike's dashboard: speedometer, rev counter, clock, mirrors ----------
static func _nice_step(max_v: float, cands: Array) -> float:
	for c in cands:
		if max_v / float(c) <= 4.5:
			return float(c)
	return float(cands[-1])

func _dial(c: Vector2, r: float, frac: float, max_v: float, label_step: float, red_from: float, unit: String, big: String) -> void:
	var a0 := deg_to_rad(150.0)
	var sweep := deg_to_rad(240.0)
	draw_circle(c, r + 3.0, Color(0.07, 0.07, 0.09, 0.82))
	draw_arc(c, r + 2.0, 0.0, TAU, 40, Color(0.75, 0.75, 0.8, 0.85), 2.0, true)
	if red_from < 1.0:
		draw_arc(c, r - 4.0, a0 + sweep * red_from, a0 + sweep, 16, C_RED, 5.0, true)
	var tick: float = label_step / 2.0
	var v := 0.0
	var fs := int(max(10.0, r * 0.25))
	while v <= max_v + 0.01:
		var a: float = a0 + sweep * v / max_v
		var dir := Vector2(cos(a), sin(a))
		var major: bool = abs(fmod(v + 0.001, label_step)) < 0.01
		draw_line(c + dir * (r - (9.0 if major else 5.0)), c + dir * (r - 1.0), C_PAPER, 2.0 if major else 1.0, true)
		if major and v > 0.01 and v < max_v - 0.01:
			_text(font_small, str(int(round(v))), c + dir * (r - 19.0) + Vector2(-14.0, fs * 0.38), fs, C_PAPER, HORIZONTAL_ALIGNMENT_CENTER, 28.0)
		v += tick
	var an: float = a0 + sweep * clamp(frac, 0.0, 1.0)
	var nd := Vector2(cos(an), sin(an))
	draw_line(c - nd * 6.0, c + nd * (r - 6.0), Color("#ff3b2f"), 3.0, true)
	draw_circle(c, 5.0, Color("#2b2a33"))
	_text(font_big, big, c + Vector2(-30.0, r * 0.66), int(r * 0.45), C_PAPER, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 3)
	_text(font_small, unit, c + Vector2(-30.0, r * 0.66 + r * 0.26), int(max(9.0, r * 0.22)), Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 60.0)

func _mirror(c: Vector2, size: Vector2, left: bool) -> void:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for i in 24:
		var a := TAU * i / 24.0
		var p := Vector2(cos(a), sin(a))
		pts.append(c + p * size * 0.5)
		# the rear camera's picture, flipped as a mirror flips it: the left mirror shows what is behind on the left
		var u: float = 0.5 - p.x * 0.25 + (-0.25 if left else 0.25)
		uvs.append(Vector2(clamp(u, 0.0, 1.0), 0.5 + p.y * 0.5))
		cols.append(Color.WHITE)
	draw_line(c + Vector2((size.x * 0.32) * (1.0 if left else -1.0), size.y * 0.45), c + Vector2((size.x * 0.5) * (1.0 if left else -1.0), size.y * 1.2), Color(0.1, 0.1, 0.12), 3.0, true)
	if mirror_tex != null:
		draw_polygon(pts, cols, uvs, mirror_tex)
	else:
		draw_colored_polygon(pts, Color(0.2, 0.22, 0.26))
	var ring := pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, Color(0.08, 0.08, 0.1), 3.0, true)

func _draw_dash(kmh: int) -> void:
	var me := sim.me
	var w: float = size.x
	var h: float = size.y
	var k: float = clamp(h / 390.0, 0.85, 1.5) * dash_scale
	var r: float = 44.0 * k
	var cx: float = w * 0.5
	var cy: float = h - r - 10.0 * k
	var gap: float = r + 30.0 * k
	# mirrors on their stalks, just outside the clocks
	if S.data.get("mirrors", true):
		var msz := Vector2(88.0, 46.0) * k
		_mirror(Vector2(cx - gap - r - msz.x * 0.25, cy - r - msz.y * 0.1), msz, true)
		_mirror(Vector2(cx + gap + r + msz.x * 0.25, cy - r - msz.y * 0.1), msz, false)
	var top_kmh: float = float(me.st.kmh)
	var ls: float = _nice_step(top_kmh * 1.1, [20, 40, 50, 60, 80, 100])
	var max_kmh: float = ceil(top_kmh * 1.1 / ls) * ls
	_dial(Vector2(cx - gap, cy), r, kmh / max_kmh, max_kmh, ls, 2.0, "км/ч", str(kmh))
	var red_k: float = float(me.st.red) / 1000.0
	var ls2: float = _nice_step(red_k + 1.0, [1, 2, 3, 4, 5])
	var max_rpm: float = ceil((red_k + 1.0) / ls2) * ls2
	var rpm_k: float = lerp(float(me.st.idle), float(me.st.red), clamp(me.rpm, 0.0, 1.0)) / 1000.0
	_dial(Vector2(cx + gap, cy), r, rpm_k / max_rpm, max_rpm, ls2, red_k * 0.92 / max_rpm, "×1000", str(me.gear + 1))
	# clock between the dials
	var tm := Time.get_time_dict_from_system()
	var box := Rect2(cx - 30.0 * k, cy - 14.0 * k, 60.0 * k, 26.0 * k)
	draw_rect(box, Color(0.06, 0.08, 0.07, 0.9))
	draw_rect(box, Color(0.6, 0.62, 0.66, 0.8), false, 1.5)
	_text(font_mid, "%02d:%02d" % [tm.hour, tm.minute], Vector2(box.position.x, box.position.y + 19.0 * k), int(17 * k), Color("#9dff8a"), HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	if me.rpm > 0.93 and int(Time.get_ticks_msec() / 90) % 2 == 0:
		draw_circle(Vector2(cx, cy + 26.0 * k), 5.0 * k, C_RED)

func handle_event(e: Array) -> void:
	match e[0]:
		"banner":
			banner_txt = e[1]
			banner_bad = e[2]
			banner_t = 1.4
		"say":
			say_txt = e[1]
			say_t = 2.2

func _process(delta: float) -> void:
	banner_t = max(0.0, banner_t - delta)
	say_t = max(0.0, say_t - delta)
	queue_redraw()

func _text(f: Font, s: String, p: Vector2, sz: int, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0, outline := 0) -> void:
	if outline > 0:
		draw_string_outline(f, p, s, align, w, sz, outline, C_INK)
	draw_string(f, p, s, align, w, sz, c)

func _bar(r: Rect2, frac: float, c: Color) -> void:
	draw_rect(r, Color(0, 0, 0, 0.55))
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2((r.size.x - 2.0) * clamp(frac, 0.0, 1.0), r.size.y - 2.0)), c)

func _draw() -> void:
	if sim == null or font_big == null:
		return
	var me := sim.me
	var w: float = size.x
	var h: float = size.y
	var kmh: int = int(round(sim.dial(me, me.v)))
	var pad := 12.0
	# race time at the top: that is what the records table counts
	var cx := w * 0.5
	var tt: float = sim.stats.t_finish if sim.phase in ["finish", "over"] and sim.stats.t_finish > 0.0 else (sim.t if sim.phase == "race" else 0.0)
	_text(font_big, race_time(tt), Vector2(cx - 100.0, 40.0), 32, C_PAPER, HORIZONTAL_ALIGNMENT_CENTER, 200.0, 6)
	_draw_dash(kmh)
	# place and progress, top left
	var place := sim.live_place()
	var place_txt := "%d/%d" % [place, sim.racers_left()]
	_text(font_big, place_txt, Vector2(pad, 40.0), 34, C_YEL, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 6)
	# how much of the track is behind you; ring tracks will show laps here
	var prog: float = clamp((me.ps - sim.road.start_s) / max(1.0, sim.road.finish_s - sim.road.start_s), 0.0, 1.0)
	var place_w: float = font_big.get_string_size(place_txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 34).x
	_text(font_big, "%d%%" % int(floor(prog * 100.0)), Vector2(pad + place_w + 12.0, 40.0), 24, C_PAPER, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 5)
	_text(font_small, "ЗДОРОВЬЕ", Vector2(pad, 62.0), 12, C_PAPER, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 3)
	_bar(Rect2(pad, 66.0, 104.0, 7.0), me.hp / 100.0, C_GRN if me.hp > 40.0 else C_RED)
	_text(font_small, "БАЙК", Vector2(pad, 87.0), 12, C_PAPER, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 3)
	_bar(Rect2(pad, 91.0, 104.0, 7.0), me.bike_hp / max(1.0, me.dur), C_PAPER)
	# nearest rival
	var nf := sim.nearest_foe()
	if nf != null:
		_text(font_small, nf.name, Vector2(w - pad - 210.0, 26.0), 15, C_PAPER, HORIZONTAL_ALIGNMENT_RIGHT, 150.0, 4)
		_bar(Rect2(w - pad - 162.0, 31.0, 102.0, 6.0), nf.hp / max(1.0, nf.max_hp), C_RED)
	# messages
	if banner_t > 0.0:
		var c := C_RED if banner_bad else C_YEL
		_text(font_big, banner_txt, Vector2(0, h * 0.34), 44, c, HORIZONTAL_ALIGNMENT_CENTER, w, 8)
	if say_t > 0.0:
		_text(font_mid, say_txt, Vector2(0, 86.0), 17, C_PAPER, HORIZONTAL_ALIGNMENT_CENTER, w, 4)
	var hint := sim.branch_hint()
	if hint != "" and banner_t <= 0.0:
		_text(font_mid, hint, Vector2(0, 112.0), 16, C_YEL, HORIZONTAL_ALIGNMENT_CENTER, w, 4)
	if sim.phase == "count":
		var n := ceili(sim.count)
		_text(font_big, str(n), Vector2(0, h * 0.5), 90, C_YEL, HORIZONTAL_ALIGNMENT_CENTER, w, 10)
	if me.flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.05, 0.05, me.flash * 1.6))
	# touch deck
	if touch_mode:
		for b in buttons:
			var on: bool = pressed.has(b.id)
			var r: Rect2 = b.rect
			var col: Color = C_DECK_ON if on else C_DECK
			if b.id == "brake" and not on:
				col = Color(0.6, 0.1, 0.1, 0.32)
			draw_rect(r, col)
			draw_rect(r, Color(1, 1, 1, 0.26), false, 1.5)
			var label: String = b.label
			if b.id == "hand":
				label = "НЕЛЬЗЯ" if me.no_hand else str(D.gear.weapons[me.weapon].label)
			var ink := Color(1, 1, 1, 0.92)
			var mid: Vector2 = r.get_center()
			if b.id == "left" or b.id == "right":
				var dir: float = -1.0 if b.id == "left" else 1.0
				var a: float = r.size.y * 0.2
				draw_colored_polygon(PackedVector2Array([mid + Vector2(dir * a, 0), mid + Vector2(-dir * a * 0.7, -a), mid + Vector2(-dir * a * 0.7, a)]), ink)
			elif b.id == "pause":
				draw_rect(Rect2(mid + Vector2(-7, -9), Vector2(5, 18)), ink)
				draw_rect(Rect2(mid + Vector2(2, -9), Vector2(5, 18)), ink)
			else:
				var fs := 15 if label.length() > 5 else 18
				_text(font_mid, label, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.36), fs, ink, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
