class_name RecordsUi extends Control
# The shared tables, top ten each: by league and track, the best time of every player and his best race by knockouts.
# The rivals count as players of their own. One more table: knockouts over all races.

signal close_requested

var tab := "time"
var league := 0
var body: Control
var status_l: Label
var data: Dictionary = {}
var fighters: Dictionary = {}
var loaded := 0
var error := ""

func open(start_league := 0) -> void:
	league = clamp(start_league, 0, D.leagues.size() - 1)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for key in ["left", "right"]:
		m.add_theme_constant_override("margin_" + key, 14)
	for key in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + key, 8)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(UiKit.button("Назад", func() -> void: close_requested.emit()))
	top.add_child(UiKit.label("Рекорды", UiKit.big, 28, UiKit.YEL))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	status_l = UiKit.label("", UiKit.small, 14, UiKit.MUTED)
	top.add_child(status_l)
	v.add_child(top)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(body)
	_fetch()
	render()

func _fetch() -> void:
	loaded = 0
	error = ""
	N.call_api(HTTPClient.METHOD_GET, "/records", null, func(d: Variant, err: String) -> void:
		if err != "":
			error = err
		else:
			data = d
		loaded += 1
		render())
	N.call_api(HTTPClient.METHOD_GET, "/fighters", null, func(d: Variant, err: String) -> void:
		if err != "":
			error = err
		else:
			fighters = d
		loaded += 1
		render())

func _tab_btn(txt: String, on: bool, cb: Callable) -> Button:
	var b := UiKit.button(txt, cb, UiKit.YEL if on else UiKit.INK3, UiKit.INK if on else UiKit.PAPER, 15)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b

func render() -> void:
	if body == null:
		return
	UiKit.clear(body)
	status_l.text = ("Ты: " + N.login) if N.logged_in() else "Войди в аккаунт, чтобы попасть сюда"
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for x in [["time", "Время"], ["ko", "Нокауты за заезд"], ["all", "Нокауты за всё время"]]:
		var id: String = x[0]
		tabs.add_child(_tab_btn(x[1], tab == id, func() -> void:
			tab = id
			render()))
	body.add_child(tabs)
	if loaded < 2 and error == "":
		body.add_child(UiKit.label("Загружаю…", UiKit.mid, 16, UiKit.MUTED))
		return
	if error != "":
		body.add_child(UiKit.label("Сервер рекордов недоступен: %s" % error, UiKit.mid, 15, UiKit.RED, true))
		body.add_child(UiKit.button("Ещё раз", func() -> void:
			_fetch()
			render(), UiKit.INK3, UiKit.PAPER, 15))
		return
	if tab == "all":
		var list2 := ScrollList.new()
		list2.box.add_child(_row(["", "Боец", "Всего", "Гонщиков", "Копов"], [26, 0, 62, 80, 62], false, false, true))
		var rows: Array = fighters.get("rows", [])
		if rows.is_empty():
			list2.box.add_child(UiKit.label("Пока никто никого не вырубил", UiKit.small, 14, UiKit.MUTED))
		for i in rows.size():
			var f: Dictionary = rows[i]
			list2.box.add_child(_row([str(i + 1), str(f.login), str(int(f.ko)), str(int(f.ko_riders)), str(int(f.ko_cops))], [26, 0, 62, 80, 62], _mine(f), bool(f.get("bot", 0))))
		var me: Variant = fighters.get("mine")
		if me is Dictionary and int(me.rank) > 10:
			list2.box.add_child(UiKit.label("Ты %d-й, нокаутов: %d" % [int(me.rank), int(me.ko)], UiKit.mid, 15, UiKit.YEL))
		body.add_child(list2)
		return
	var lg := HBoxContainer.new()
	lg.add_theme_constant_override("separation", 6)
	for c in D.leagues.size():
		var cc := c
		lg.add_child(_tab_btn(str(D.leagues[c].full), league == c, func() -> void:
			league = cc
			render()))
	body.add_child(lg)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var src: Dictionary = data.get(tab, data.get("tracks", {}) if tab == "time" else {})
	var mine: Dictionary = data.get("mine", {}).get(tab, {})
	for t in D.tracks:
		if int(t.cat) != league:
			continue
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UiKit.label(str(t.name), UiKit.mid, 18, UiKit.YEL))
		var list := ScrollList.new()
		col.add_child(list)
		var rows: Array = src.get(t.id, [])
		if rows.is_empty():
			list.box.add_child(UiKit.label("Пока никто не финишировал" if tab == "time" else "Пока без нокаутов", UiKit.small, 14, UiKit.MUTED))
		elif tab == "ko":
			list.box.add_child(_row(["", "", "Байк", "Всего", "Гонщ.", "Копов"], [22, 0, 0, 40, 40, 40], false, false, true))
		for i in rows.size():
			var r: Dictionary = rows[i]
			if tab == "time":
				list.box.add_child(_row([str(i + 1), str(r.login), str(r.bike), Hud.race_time(float(r.time_ms) / 1000.0)], [22, 0, 0, 58], _mine(r), bool(r.get("bot", 0))))
			else:
				list.box.add_child(_row([str(i + 1), str(r.login), str(r.bike), str(int(r.ko)), str(int(r.ko_riders)), str(int(r.ko_cops))], [22, 0, 0, 40, 40, 40], _mine(r), bool(r.get("bot", 0))))
		var my: Variant = mine.get(t.id)
		if my is Dictionary and int(my.rank) > rows.size():
			var val: String = Hud.race_time(float(my.time_ms) / 1000.0) if tab == "time" else "нокаутов %d" % int(my.ko)
			list.box.add_child(UiKit.label("Ты %d-й, %s" % [int(my.rank), val], UiKit.mid, 14, UiKit.YEL))
		cols.add_child(col)
	body.add_child(cols)

func _mine(r: Dictionary) -> bool:
	return N.logged_in() and str(r.login) == N.login and not bool(r.get("bot", 0))

# one line of a table; a width of 0 takes what is left. Rivals carry a grey mark
func _row(cells: Array, widths: Array, mine: bool, bot := false, head := false) -> PanelContainer:
	var p := UiKit.panel(UiKit.INK3 if mine else UiKit.INK2, 8, 3)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	for i in cells.size():
		var col: Color = UiKit.YEL if mine else (UiKit.MUTED if head else UiKit.PAPER)
		if i == 1 and bot:
			var nb := HBoxContainer.new()
			nb.add_theme_constant_override("separation", 4)
			nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var nl := UiKit.label(cells[i], UiKit.mid, 14, Color("#c9c6d4"))
			nl.clip_text = true
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nb.add_child(nl)
			var tag := UiKit.label("бот", UiKit.small, 11, UiKit.MUTED)
			tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			nb.add_child(tag)
			h.add_child(nb)
			continue
		var l := UiKit.label(cells[i], UiKit.mid if (i == 1 or head) else UiKit.small, 14, col)
		if widths[i] > 0:
			l.custom_minimum_size = Vector2(widths[i], 0)
			if i > 1:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
		h.add_child(l)
	return p
