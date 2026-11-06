class_name PreRaceUi extends Control
# Before the start: which of your bikes from this league, what you wear, what you take in your hand, who you are up against.

signal back_requested
signal start_requested(track_i: int)
signal bar_requested(league: int)
signal garage_requested

var room: Showroom
var track_i := 0
var name_l: Label
var sub_l: Label
var warn_l: Label
var list: ScrollList
var money_l: Label

func open(r: Showroom, ti: int) -> void:
	room = r
	track_i = ti
	_build()
	render()

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t: Dictionary = D.tracks[track_i]
	var left := MarginContainer.new()
	left.anchor_right = room.fraction
	left.anchor_bottom = 1.0
	for key in ["left", "right", "top", "bottom"]:
		left.add_theme_constant_override("margin_" + key, 10)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 3)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(lv)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(UiKit.button("Назад", func() -> void: back_requested.emit()))
	top.add_child(UiKit.outlined(UiKit.label(t.name, UiKit.big, 28, UiKit.YEL)))
	lv.add_child(top)
	name_l = UiKit.outlined(UiKit.label("", UiKit.mid, 19, UiKit.PAPER))
	lv.add_child(name_l)
	sub_l = UiKit.outlined(UiKit.label("", UiKit.small, 14, UiKit.PAPER), 4)
	lv.add_child(sub_l)
	lv.add_child(UiKit.expand())
	warn_l = UiKit.outlined(UiKit.label("", UiKit.mid, 15, Color("#ff6a5e")), 4)
	warn_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(warn_l)
	var go := UiKit.button("ЕДЕМ", func() -> void: start_requested.emit(track_i), UiKit.YEL, UiKit.INK, 24, UiKit.big)
	go.custom_minimum_size = Vector2(0, 50)
	lv.add_child(go)
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
	for key in ["left", "right", "top", "bottom"]:
		right.add_theme_constant_override("margin_" + key, 8)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)
	list = ScrollList.new()
	right.add_child(list)

func _choice(title: String, line: String, on: bool, cb: Callable) -> Button:
	var b := UiKit.button("", cb, UiKit.INK3 if on else UiKit.INK2, UiKit.PAPER, 15)
	var st := UiKit.box(UiKit.INK3 if on else UiKit.INK2, 0, UiKit.YEL if on else Color.TRANSPARENT, 2 if on else 0)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("pressed", st)
	b.custom_minimum_size = Vector2(0, 46)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_right = -10
	v.offset_top = 4
	v.add_theme_constant_override("separation", 0)
	v.add_child(UiKit.label(title, UiKit.mid, 15, UiKit.PAPER))
	v.add_child(UiKit.label(line, UiKit.small, 12, UiKit.MUTED))
	b.add_child(v)
	return b

func render() -> void:
	var t: Dictionary = D.tracks[track_i]
	var cat: int = t.cat
	var bike: Dictionary = S.ride_of(cat)
	var g: Dictionary = S.data.gear
	var st: Dictionary = D.stats_of(bike, S.upgrades(bike.id))
	name_l.text = "%s %dcc" % [bike.name, int(bike.cc)]
	sub_l.text = "%d км/ч, приз за первое место %s" % [int(st.kmh), S.fmt(t.prize)]
	var pr: float = min(0.95, float(D.gear.suits[int(g.suit)].prot) + float(D.gear.helmets[int(g.helmet)].prot))
	var hurt := int(round(S.fall_pct(float(st.kmh), pr) * [0.7, 1.0, 1.3][int(S.data.difficulty)]))
	warn_l.text = ""
	if hurt >= 30:
		warn_l.text = "Падение на полной скорости снимет %d%% здоровья%s" % [hurt, ", два таких подряд и больница" if hurt >= 50 else ""]
	warn_l.add_theme_color_override("font_color", Color("#ff6a5e") if hurt >= 50 else UiKit.YEL)
	var u: Dictionary = S.upgrades(bike.id)
	room.show_rig(bike, int(u.paint), D.outfit(int(g.suit), int(g.suitColor), int(g.helmColor), int(g.glove), int(g.boot)), int(g.helmet), S.start_weapon(int(g.suit)), true)
	UiKit.clear(list.box)
	# bikes
	var bikes := S.owned_in(cat)
	list.box.add_child(UiKit.heading("Мотоцикл" if bikes.size() < 2 else "Мотоцикл: выбери"))
	for b in bikes:
		var id: String = b.id
		var s2: Dictionary = D.stats_of(b, S.upgrades(id))
		var line := "%d км/ч, разгон %s с, сцепление %d, управляемость %d, прочность %d" % [int(s2.kmh), S.accel_txt(s2.acc, b), int(s2.grip), int(s2.hand), int(s2.dur)]
		list.box.add_child(_choice("%s %dcc" % [b.name, int(b.cc)], line, id == bike.id, func() -> void:
			S.data.ride[str(cat)] = id
			S.persist()
			_refresh()))
	# clothes
	list.box.add_child(UiKit.heading("Одежда"))
	for k in g.suits:
		var it: Dictionary = D.gear.suits[int(k)]
		var kk: int = k
		var hits: String = ", рукой нельзя" if it.get("noHand", false) else ", удары %d%%" % int(round(float(it.hit) * 100.0))
		list.box.add_child(_choice(it.n, "Защита %d%%, %s кг, обтекаемость %d%s" % [int(round(float(it.prot) * 100.0)), S.kg_txt(it.kg), int(it.aero), hits], int(g.suit) == kk, func() -> void:
			S.wear("suit", kk)
			_refresh()))
	list.box.add_child(UiKit.heading("Шлем"))
	for k in g.helmets:
		var it: Dictionary = D.gear.helmets[int(k)]
		var kk: int = k
		list.box.add_child(_choice(it.n, "Защита %d%%, %s кг, обтекаемость %d" % [int(round(float(it.prot) * 100.0)), S.kg_txt(it.kg), int(it.aero)], int(g.helmet) == kk, func() -> void:
			S.wear("helmet", kk)
			_refresh()))
	# weapon
	list.box.add_child(UiKit.heading("В руке"))
	var no_hand: bool = D.gear.suits[int(g.suit)].get("noHand", false)
	if no_hand:
		list.box.add_child(UiKit.label("В гоночном комбезе рукой не ударить, оружие не взять.", UiKit.small, 13, UiKit.MUTED, true))
	else:
		var cur: String = S.start_weapon(int(g.suit))
		list.box.add_child(_choice("Кулак", "Урон %d" % (10 + 3 * int(g.glove)), cur == "none", func() -> void:
			S.data.gear.weaponPick = "none"
			S.persist()
			_refresh()))
		for w in [["baton", "Дубинка", "Урон 18"], ["chain", "Цепь", "Урон 26, бьёт дальше"]]:
			var wid: String = w[0]
			var n: int = g[wid]
			if n <= 0:
				continue
			list.box.add_child(_choice(w[1], "%s. В запасе: %d" % [w[2], n], cur == wid, func() -> void:
				S.data.gear.weaponPick = wid
				S.persist()
				_refresh()))
	list.box.add_child(UiKit.button("Гараж: купить защиту, оружие, прокачать", func() -> void: garage_requested.emit(), UiKit.INK2, UiKit.PAPER, 14))
	# rivals
	list.box.add_child(UiKit.heading("Соперники"))
	var who := ""
	for e in t.roster:
		who += ("" if who == "" else ", ") + str(D.rivals[e[0]].name)
	list.box.add_child(UiKit.label(who + ". Постов полиции: %d. Сложность: %s (меняется в настройках)." % [t.cops.size(), str(S.DIFF_NAMES[int(S.data.difficulty)]).to_lower()], UiKit.small, 14, UiKit.PAPER, true))
	list.box.add_child(UiKit.button("В бар: узнать про них", func() -> void: bar_requested.emit(cat), UiKit.INK2, UiKit.PAPER, 14))
	list.keep_scroll()

func _refresh() -> void:
	render()
