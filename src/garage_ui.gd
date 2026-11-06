class_name GarageUi extends Control
# Garage and shop: same rules and prices as the 2D game, with the real 3D bike on the left.

signal close_requested
signal race_requested(track_i: int)
signal bought

const BIKE_UPS := [
	{"id": "eng", "name": "Двигатель", "lab": "Скорость"},
	{"id": "acc", "name": "Коробка", "lab": "Разгон"},
	{"id": "tire", "name": "Шины", "lab": "Сцепление"},
	{"id": "susp", "name": "Подвеска", "lab": "Управляемость"},
	{"id": "frame", "name": "Рама", "lab": "Прочность"},
]

var room: Showroom
var shop_mode := false
var bike_id := "strek"
var tab := "bike"
var preview_paint := -1
var try_suit := -1
var try_helmet := -1
var money_l: Label
var title_l: Label
var name_l: Label
var sub_l: Label
var signs: HBoxContainer
var action: Button
var tabs: HBoxContainer
var list: ScrollList
var toast_l: Label
var toast_t := 0.0
var audio: GameAudio

func open(r: Showroom, shop: bool, a: GameAudio, id := "", cat := -1) -> void:
	room = r
	audio = a
	shop_mode = shop
	_build()
	if shop:
		var c: int = cat
		if c < 0:
			c = 0
			for k in D.leagues.size():
				if S.cat_open(k):
					c = k
		tab = "cat%d" % c
		bike_id = id if id != "" else _first_for_sale(c)
	else:
		tab = "bike"
		bike_id = id if (id != "" and S.owns(id)) else _current_owned()
	render()

func _first_for_sale(c: int) -> String:
	var first := ""
	for b in D.bikes:
		if int(b.cat) != c:
			continue
		if first == "":
			first = b.id
		if not S.owns(b.id):
			return b.id
	return first

func _current_owned() -> String:
	for k in range(D.leagues.size() - 1, -1, -1):
		var b: Variant = S.ride_of(k)
		if b != null:
			return b.id
	return "strek"

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := MarginContainer.new()
	left.anchor_right = room.fraction
	left.anchor_bottom = 1.0
	for key in ["left", "right", "top", "bottom"]:
		left.add_theme_constant_override("margin_" + key, 10)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(lv)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(UiKit.button("Назад", func() -> void: close_requested.emit()))
	title_l = UiKit.outlined(UiKit.label("", UiKit.big, 28, UiKit.YEL))
	top.add_child(title_l)
	lv.add_child(top)
	name_l = UiKit.outlined(UiKit.label("", UiKit.mid, 20, UiKit.PAPER))
	lv.add_child(name_l)
	sub_l = UiKit.outlined(UiKit.label("", UiKit.small, 14, UiKit.PAPER), 4)
	sub_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(sub_l)
	lv.add_child(UiKit.expand())
	signs = HBoxContainer.new()
	signs.add_theme_constant_override("separation", 5)
	lv.add_child(signs)
	action = UiKit.button("", _on_action, UiKit.YEL, UiKit.INK, 19)
	action.custom_minimum_size = Vector2(0, 44)
	lv.add_child(action)
	var bg := ColorRect.new()
	bg.color = UiKit.INK
	bg.anchor_left = room.fraction
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var right := MarginContainer.new()
	right.anchor_left = room.fraction
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	for key in ["left", "right"]:
		right.add_theme_constant_override("margin_" + key, 8)
	right.add_theme_constant_override("margin_top", 8)
	right.add_theme_constant_override("margin_bottom", 8)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	right.add_child(rv)
	var rt := HBoxContainer.new()
	rt.add_theme_constant_override("separation", 4)
	tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_child(tabs)
	money_l = UiKit.label("", UiKit.big, 22, UiKit.PAPER)
	rt.add_child(money_l)
	rv.add_child(rt)
	list = ScrollList.new()
	rv.add_child(list)
	toast_l = UiKit.outlined(UiKit.label("", UiKit.mid, 20, UiKit.YEL))
	toast_l.anchor_right = room.fraction
	toast_l.anchor_top = 0.5
	toast_l.anchor_bottom = 0.5
	toast_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_l.visible = false
	add_child(toast_l)

func _process(delta: float) -> void:
	if toast_t > 0.0:
		toast_t -= delta
		if toast_t <= 0.0:
			toast_l.visible = false

func toast(msg: String) -> void:
	toast_l.text = msg
	toast_l.visible = true
	toast_t = 1.6

func _pay_result(ok: bool, cost: int) -> void:
	if ok:
		if audio != null:
			audio.ui("ching")
		bought.emit()
	else:
		if audio != null:
			audio.ui("deny")
		toast("Не хватает " + S.fmt(cost - int(S.data.money)))

func worn_suit() -> int:
	return try_suit if try_suit >= 0 else int(S.data.gear.suit)

func worn_helmet() -> int:
	return try_helmet if try_helmet >= 0 else int(S.data.gear.helmet)

func _clear_try() -> void:
	preview_paint = -1
	try_suit = -1
	try_helmet = -1

func _tab_btn(id: String, txt: String) -> void:
	var on: bool = tab == id
	var b := UiKit.button(txt, func() -> void:
		_clear_try()
		tab = id
		if id.begins_with("cat"):
			bike_id = _first_for_sale(int(id.substr(3)))
		elif id == "bike" and not S.owns(bike_id):
			bike_id = _current_owned()
		list.scroll_vertical = 0
		render(), UiKit.YEL if on else UiKit.INK3, UiKit.INK if on else UiKit.PAPER, 15)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(b)

func render() -> void:
	var keep := list.scroll_vertical
	var gear_tab: bool = tab == "gear"
	var b: Dictionary = D.bike_by_id[bike_id]
	var u: Dictionary = S.upgrades(bike_id)
	var own: bool = S.owns(bike_id)
	var open_c: bool = S.cat_open(int(b.cat))
	title_l.text = "Магазин" if shop_mode else "Гараж"
	money_l.text = S.fmt(S.data.money)
	UiKit.clear(tabs)
	if shop_mode:
		_tab_btn("cat0", "Скутеры")
		_tab_btn("cat1", "Городские")
		_tab_btn("cat2", "Спорт")
		_tab_btn("gear", "Защита")
	else:
		_tab_btn("bike", "Мотоцикл")
		_tab_btn("gear", "Экипировка")
	# bike signs
	UiKit.clear(signs)
	signs.visible = not gear_tab
	if not gear_tab:
		for x in D.bikes:
			if shop_mode and int(x.cat) != int(b.cat):
				continue
			if not shop_mode and not S.owns(x.id):
				continue
			var ring: Color = UiKit.GRN if S.owns(x.id) else (UiKit.RED if S.cat_open(int(x.cat)) else Color("#77757f"))
			var id: String = x.id
			signs.add_child(UiKit.sign_btn(str(int(x.cc)), func() -> void:
				bike_id = id
				_clear_try()
				if not shop_mode:
					S.data.ride[str(int(D.bike_by_id[id].cat))] = id
					S.persist()
				list.scroll_vertical = 0
				render(), ring, id == bike_id, 40 if (not shop_mode and _owned_count() > 6) else 44))
	# heading text
	if gear_tab:
		var pr: float = float(D.gear.suits[worn_suit()].prot) + float(D.gear.helmets[worn_helmet()].prot)
		name_l.text = "Защита %d%%" % int(round(pr * 100.0))
		sub_l.text = S.safe_txt(pr)
	else:
		var st: Dictionary = D.stats_of(b, u)
		var gears: int = int(D.leagues[int(b.cat)].gears)
		name_l.text = "%s %dcc" % [b.name, int(b.cc)]
		var extra := ""
		if shop_mode:
			extra = ", в гараже" if own else ""
		else:
			extra = ", %d л.с., %d км/ч" % [int(st.hp), int(st.kmh)]
		sub_l.text = "%s, %d %s%s" % [b.type, gears, "передачи" if gears < 5 else "передач", extra]
	# list
	UiKit.clear(list.box)
	if gear_tab:
		_gear_list()
	elif shop_mode:
		var note := UiKit.label(b.note, UiKit.small, 15, UiKit.PAPER, true)
		list.box.add_child(note)
		list.box.add_child(_stat_bars(b))
		_shop_upsell(b, own)
	else:
		_bike_list(b, u)
	if not shop_mode or gear_tab:
		var test := UiKit.button("Для теста: +$25 000", func() -> void:
			S.add_test_money()
			render(), UiKit.INK2, UiKit.MUTED, 13)
		list.box.add_child(test)
	list.scroll_vertical = keep
	list.keep_scroll()
	# action button
	_action_state(b, own, open_c, gear_tab)
	_update_rig(b, u, open_c, gear_tab)

func _owned_count() -> int:
	return S.data.bikes.size()

func _update_rig(b: Dictionary, u: Dictionary, open_c: bool, gear_tab: bool) -> void:
	var paint_i: int = preview_paint if preview_paint >= 0 else int(u.get("paint", b.paint))
	var g: Dictionary = S.data.gear
	var outfit: Variant = null
	var helmet := 0
	var weapon := "none"
	if gear_tab:
		outfit = D.outfit(worn_suit(), int(g.suitColor), int(g.helmColor), int(g.glove), int(g.boot))
		helmet = worn_helmet()
		weapon = S.start_weapon(worn_suit())
	room.show_rig(b, paint_i, outfit, helmet, weapon, gear_tab, shop_mode and not open_c)

func _shop_upsell(_b: Dictionary, _own: bool) -> void:
	pass

func _action_state(b: Dictionary, own: bool, open_c: bool, gear_tab: bool) -> void:
	action.visible = true
	_set_action_look(UiKit.YEL, UiKit.INK)
	if shop_mode and gear_tab:
		action.text = "В гараж"
	elif shop_mode:
		if not open_c:
			var i: int = S.first_track_of(int(b.cat)) - 1
			action.text = "Нужен топ-3: " + str(D.tracks[i].name)
			_set_action_look(UiKit.INK3, UiKit.MUTED)
		elif own:
			action.text = "Открыть в гараже"
			_set_action_look(UiKit.INK3, UiKit.PAPER)
		else:
			action.text = "Купить за " + S.fmt(b.price)
			if int(S.data.money) < int(b.price):
				_set_action_look(UiKit.INK3, UiKit.PAPER)
	else:
		var last := -1
		for i in D.tracks.size():
			if int(D.tracks[i].cat) == int(b.cat) and S.track_open(i):
				last = i
		if last >= 0:
			action.text = "В гонку: " + str(D.tracks[last].name)
		else:
			action.text = "Трассы этой лиги закрыты"
			_set_action_look(UiKit.INK3, UiKit.MUTED)

func _set_action_look(bg: Color, fg: Color) -> void:
	action.add_theme_stylebox_override("normal", UiKit.box(bg))
	action.add_theme_stylebox_override("hover", UiKit.box(bg.lightened(0.06)))
	action.add_theme_stylebox_override("pressed", UiKit.box(bg.lightened(0.14)))
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		action.add_theme_color_override(key, fg)

func _on_action() -> void:
	var b: Dictionary = D.bike_by_id[bike_id]
	var own: bool = S.owns(bike_id)
	if shop_mode and tab == "gear":
		shop_mode = false
		tab = "bike"
		bike_id = _current_owned()
		_clear_try()
		render()
	elif shop_mode:
		if not S.cat_open(int(b.cat)):
			return
		if own:
			shop_mode = false
			tab = "bike"
			S.data.ride[str(int(b.cat))] = bike_id
			S.persist()
			render()
		else:
			_pay_result(S.buy_bike(bike_id), int(b.price))
			if own != S.owns(bike_id):
				toast("%s в гараже" % b.name)
			render()
	else:
		var last := -1
		for i in D.tracks.size():
			if int(D.tracks[i].cat) == int(b.cat) and S.track_open(i):
				last = i
		if last >= 0:
			race_requested.emit(last)

# ---------- bike tab ----------
func _up_value(b: Dictionary, u: Dictionary, id: String) -> String:
	var st: Dictionary = D.stats_of(b, u)
	match id:
		"eng":
			return "%d км/ч" % int(st.kmh)
		"acc":
			return S.accel_txt(st.acc, b) + " с"
		"tire":
			return str(int(st.grip))
		"susp":
			return str(int(st.hand))
	return str(int(st.dur))

func _row(title: String, line: String, level: int, total: int, price: int, cb: Callable, done_text := "Максимум") -> PanelContainer:
	var p := UiKit.panel()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiKit.label(title, UiKit.mid, 16, UiKit.PAPER))
	v.add_child(UiKit.label(line, UiKit.small, 13, UiKit.MUTED, true))
	if total > 0:
		v.add_child(UiKit.pips(level, total))
	h.add_child(v)
	if price >= 0:
		var poor: bool = int(S.data.money) < price
		var buy := UiKit.button(S.fmt(price), cb, UiKit.INK3 if poor else UiKit.YEL, UiKit.PAPER if poor else UiKit.INK, 15)
		buy.custom_minimum_size = Vector2(78, 38)
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(buy)
	else:
		var t := UiKit.label(done_text, UiKit.mid, 13, UiKit.GRN)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(t)
	return p

func _bike_list(b: Dictionary, u: Dictionary) -> void:
	var max_lv: int = D.rules.max_level
	for x in BIKE_UPS:
		var id: String = x.id
		var level: int = u[id]
		var now := _up_value(b, u, id)
		var line: String = "%s %s" % [x.lab, now]
		var price := -1
		if level < max_lv:
			var nxt := u.duplicate()
			nxt[id] = level + 1
			line += " → " + _up_value(b, nxt, id)
			price = S.up_cost(b, level)
		list.box.add_child(_row(x.name, line, level, max_lv, price, func() -> void:
			var p2: int = S.up_cost(b, int(S.upgrades(bike_id)[id]))
			_pay_result(S.buy_up(bike_id, id), p2)
			render()))
	# paint
	var pv: int = preview_paint if preview_paint >= 0 else int(u.paint)
	var p := UiKit.panel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UiKit.label("Краска: " + str(D.gear.paints[pv].n) + (", примерка" if preview_paint >= 0 else ""), UiKit.mid, 16, UiKit.PAPER))
	head.add_child(UiKit.expand())
	if preview_paint >= 0:
		var cost: int = S.paint_cost(b)
		var poor: bool = int(S.data.money) < cost
		head.add_child(UiKit.button(S.fmt(cost), func() -> void:
			_pay_result(S.buy_paint(bike_id, preview_paint), cost)
			if S.upgrades(bike_id).paint == preview_paint:
				preview_paint = -1
			render(), UiKit.INK3 if poor else UiKit.YEL, UiKit.PAPER if poor else UiKit.INK, 15))
	v.add_child(head)
	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", 5)
	for k in D.gear.paints.size():
		var col := Color(D.gear.paints[k].c)
		var kk: int = k
		sw.add_child(UiKit.swatch(col, func() -> void:
			if S.pick_paint(bike_id, kk):
				preview_paint = -1
			else:
				preview_paint = kk
			render(), kk == pv, not (kk in u.paints)))
	v.add_child(sw)
	list.box.add_child(p)

# ---------- shop stat bars ----------
func _stat_bars(b: Dictionary) -> VBoxContainer:
	var ms: Dictionary = D.stats_of(b, S.upgrades(b.id))
	var cur: Variant = S.ride_of(int(b.cat))
	var cs: Variant = null
	if cur != null and cur.id != b.id:
		cs = D.stats_of(cur, S.upgrades(cur.id))
	var max_hp := 0.0
	var max_kmh := 0.0
	for x in D.bikes:
		if int(x.cat) == int(b.cat):
			max_hp = max(max_hp, float(x.hp) * 1.24)
			max_kmh = max(max_kmh, float(x.kmh) * 1.12)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	var rows := [
		["Мощность", "%d л.с." % int(ms.hp), "hp", max_hp], ["Скорость", "%d км/ч" % int(ms.kmh), "kmh", max_kmh],
		["Разгон", S.accel_txt(ms.acc, b) + " с", "acc", 0.33], ["Сцепление", str(int(ms.grip)), "grip", 122.0],
		["Управляемость", str(int(ms.hand)), "hand", 120.0], ["Прочность", str(int(ms.dur)), "dur", 252.0],
	]
	for r in rows:
		var f: float = float(ms[r[2]]) / float(r[3])
		var mk: float = float(cs[r[2]]) / float(r[3]) if cs != null else -1.0
		v.add_child(UiKit.stat(r[0], r[1], f, UiKit.YEL, mk))
	if cs != null:
		v.add_child(UiKit.label("Белая метка: твой %s" % cur.name, UiKit.small, 13, UiKit.MUTED))
	return v

# ---------- gear tab ----------
func _gear_list() -> void:
	var g: Dictionary = S.data.gear
	var b: Dictionary = D.bike_by_id[bike_id] if S.owns(bike_id) else D.bike_by_id[_current_owned()]
	var ts := worn_suit()
	var th := worn_helmet()
	var fx := D.gear_fx(ts, th)
	var st := D.rider_stats(b, S.upgrades(b.id), ts, th, int(g.glove), int(g.boot))
	var base := D.stats_of(b, S.upgrades(b.id))
	list.box.add_child(UiKit.label("На %s %dcc" % [b.name, int(b.cc)], UiKit.mid, 15, UiKit.PAPER))
	var rows := [
		["Вес", S.kg_txt(fx.kg) + " кг", float(fx.kg) / 9.0], ["Обтекаемость", str(int(fx.aero)), float(fx.aero) / 100.0],
		["Рука", "нельзя" if fx.no_hand else "%d урона" % int(st.fist), 0.0 if fx.no_hand else float(st.fist) / 22.0],
		["Нога", "%d урона" % int(st.kick), float(st.kick) / 21.0],
		["Скорость", "%d из %d" % [int(round(st.kmh)), int(base.kmh)], float(st.kmh) / float(base.kmh)],
		["Разгон", S.accel_txt(st.accel, b) + " с", float(st.accel) / float(base.acc)],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	for r in rows:
		var c := UiKit.stat(r[0], r[1], r[2])
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(c)
	list.box.add_child(grid)
	list.box.add_child(_color_row("Цвет одежды: " + str(D.gear.colors[int(g.suitColor)].n).to_lower(), "suitColor"))
	list.box.add_child(_color_row("Цвет шлема: " + str(D.gear.colors[int(g.helmColor)].n).to_lower(), "helmColor"))
	list.box.add_child(UiKit.heading("Одежда"))
	for k in D.gear.suits.size():
		list.box.add_child(_wear_row("suit", k))
	list.box.add_child(UiKit.heading("Шлем"))
	for k in D.gear.helmets.size():
		list.box.add_child(_wear_row("helmet", k))
	list.box.add_child(UiKit.heading("Для драки"))
	var max_lv: int = D.rules.max_level
	for x in [["glove", "Перчатки", "Удар рукой", 10], ["boot", "Сапоги", "Удар ногой", 9]]:
		var id: String = x[0]
		var level: int = g[id]
		var line := "%s %d" % [x[2], int(x[3]) + 3 * level]
		var price := -1
		if level < max_lv:
			line += " → %d" % (int(x[3]) + 3 * (level + 1))
			price = int(D.rules.gear_cost[id][level])
		list.box.add_child(_row(x[1], line, level, max_lv, price, func() -> void:
			var p2: int = int(D.rules.gear_cost[id][int(S.data.gear[id])])
			_pay_result(S.buy_gear_up(id), p2)
			render()))
	list.box.add_child(UiKit.heading("Оружие на гонку"))
	list.box.add_child(UiKit.label("Одноразовое: упал или отобрали, покупай заново. Доехал до финиша, оно осталось. В гоночном комбезе оружие не взять.", UiKit.small, 13, UiKit.MUTED, true))
	for x in [["baton", "Дубинка", "Урон 18"], ["chain", "Цепь", "Урон 26, бьёт дальше"]]:
		var id: String = x[0]
		var n: int = g[id]
		var cost: int = D.rules.gear_cost[id]
		list.box.add_child(_row(x[1], "%s. В запасе: %d" % [x[2], n], 0, 0, cost if n < 9 else -1, func() -> void:
			_pay_result(S.buy_weapon(id), cost)
			render(), "Полно"))

func _color_row(title: String, key: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.add_child(UiKit.label(title, UiKit.small, 13, UiKit.MUTED))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var cur: int = S.data.gear[key]
	for k in D.gear.colors.size():
		var kk: int = k
		var sw := UiKit.swatch(Color(D.gear.colors[k].c), func() -> void:
			S.data.gear[key] = kk
			S.persist()
			render(), k == cur)
		sw.custom_minimum_size = Vector2(32, 30)
		h.add_child(sw)
	v.add_child(h)
	return v

func _wear_row(kind: String, k: int) -> PanelContainer:
	var g: Dictionary = S.data.gear
	var it: Dictionary = D.gear.suits[k] if kind == "suit" else D.gear.helmets[k]
	var owned: bool = k in (g.suits if kind == "suit" else g.helmets)
	var worn_now: bool = int(g[kind]) == k
	var tried: bool = (worn_suit() if kind == "suit" else worn_helmet()) == k and not worn_now
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.box(UiKit.INK3 if tried else UiKit.INK2, 0, UiKit.YEL if tried else Color.TRANSPARENT, 1 if tried else 0))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	var hits := ""
	if kind == "suit":
		hits = ", рукой нельзя, нога слабая" if it.get("noHand", false) else ", удары %d%%" % int(round(float(it.hit) * 100.0))
	# the whole left part is a try-on button
	var try_btn := UiKit.button("", func() -> void:
		if kind == "suit":
			try_suit = -1 if k == int(S.data.gear.suit) else k
		else:
			try_helmet = -1 if k == int(S.data.gear.helmet) else k
		render(), Color(0, 0, 0, 0), UiKit.PAPER, 15)
	try_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	try_btn.custom_minimum_size = Vector2(0, 46)
	var inner := VBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.add_theme_constant_override("separation", 1)
	inner.add_child(UiKit.label(it.n, UiKit.mid, 15, UiKit.PAPER))
	inner.add_child(UiKit.label("Защита %d%%, %s кг, обтекаемость %d%s%s" % [int(round(float(it.prot) * 100.0)), S.kg_txt(it.kg), int(it.aero), hits, ", примерка" if tried else ""], UiKit.small, 12, UiKit.MUTED, true))
	try_btn.add_child(inner)
	h.add_child(try_btn)
	if worn_now:
		var t := UiKit.label("Надето", UiKit.mid, 13, UiKit.GRN)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(t)
	elif owned:
		var wear := UiKit.button("Надеть", func() -> void:
			S.wear(kind, k)
			if kind == "suit":
				try_suit = -1
			else:
				try_helmet = -1
			render(), UiKit.INK3, UiKit.PAPER, 14)
		wear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(wear)
	else:
		var price: int = it.price
		var poor: bool = int(S.data.money) < price
		var buy := UiKit.button(S.fmt(price), func() -> void:
			_pay_result(S.buy_wear(kind, k), price)
			if k in (S.data.gear.suits if kind == "suit" else S.data.gear.helmets):
				if kind == "suit":
					try_suit = -1
				else:
					try_helmet = -1
			render(), UiKit.INK3 if poor else UiKit.YEL, UiKit.PAPER if poor else UiKit.INK, 14)
		buy.custom_minimum_size = Vector2(70, 36)
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(buy)
	return p
