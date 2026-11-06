class_name RecordsUi extends Control
# The shared tables: best times by league and track, and the fighters by knockouts.

signal close_requested

var tab := "time"
var league := 0
var body: Control
var status_l: Label
var records: Dictionary = {}
var fighters: Array = []
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
	N.call_api(HTTPClient.METHOD_GET, "/records", null, func(data: Variant, err: String) -> void:
		if err != "":
			error = err
		else:
			records = data.tracks if data.tracks is Dictionary else {}
		loaded += 1
		render())
	N.call_api(HTTPClient.METHOD_GET, "/fighters", null, func(data: Variant, err: String) -> void:
		if err != "":
			error = err
		else:
			fighters = data.rows
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
	tabs.add_child(_tab_btn("Время на трассах", tab == "time", func() -> void:
		tab = "time"
		render()))
	tabs.add_child(_tab_btn("Бойцы", tab == "fight", func() -> void:
		tab = "fight"
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
	if tab == "time":
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
		for t in D.tracks:
			if int(t.cat) != league:
				continue
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_child(UiKit.label(str(t.name), UiKit.mid, 18, UiKit.YEL))
			var list := ScrollList.new()
			col.add_child(list)
			var rows: Array = records.get(t.id, [])
			if rows.is_empty():
				list.box.add_child(UiKit.label("Пока никто не финишировал", UiKit.small, 14, UiKit.MUTED))
			for i in rows.size():
				var r: Dictionary = rows[i]
				list.box.add_child(_row([str(i + 1), str(r.login), str(r.bike), Hud.race_time(float(r.time_ms) / 1000.0)], [26, 0, 0, 62], r.login == N.login))
			cols.add_child(col)
		body.add_child(cols)
	else:
		var list2 := ScrollList.new()
		list2.box.add_child(_row(["", "Боец", "Всего", "Гонщиков", "Копов"], [26, 0, 70, 90, 70], false, true))
		if fighters.is_empty():
			list2.box.add_child(UiKit.label("Пока никто никого не вырубил", UiKit.small, 14, UiKit.MUTED))
		for i in fighters.size():
			var f: Dictionary = fighters[i]
			list2.box.add_child(_row([str(i + 1), str(f.login), str(int(f.ko)), str(int(f.ko_riders)), str(int(f.ko_cops))], [26, 0, 70, 90, 70], f.login == N.login))
		body.add_child(list2)

# one line of a table; a width of 0 takes what is left
func _row(cells: Array, widths: Array, mine: bool, head := false) -> PanelContainer:
	var p := UiKit.panel(UiKit.INK3 if mine else UiKit.INK2, 8, 4)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	for i in cells.size():
		var l := UiKit.label(cells[i], UiKit.mid if (i == 1 or head) else UiKit.small, 15, UiKit.YEL if mine else (UiKit.MUTED if head else UiKit.PAPER))
		if widths[i] > 0:
			l.custom_minimum_size = Vector2(widths[i], 0)
			if i > 1:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
		h.add_child(l)
	return p
