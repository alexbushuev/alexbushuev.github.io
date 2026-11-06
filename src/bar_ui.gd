class_name BarUi extends Control
# The bikers' bar: who you race against, how they ride, what they carry and how to deal with them.

signal close_requested

const STYLE_NAMES := {"calm": "спокойный", "racer": "гонщик", "brawler": "драчун", "thief": "вор", "coward": "трус", "blocker": "блокировщик", "maniac": "псих"}
const STYLE_TXT := {
	"calm": "Едет своим темпом и не лезет, пока его не ударить. Бьёт только в ответ.",
	"racer": "Приехал гоняться, а не драться. Просто быстро едет. Ударишь, получишь в ответ.",
	"brawler": "Ищет драку. Притормаживает рядом с тобой и бьёт, пока не вырубишь или не оторвёшься.",
	"thief": "Охотится за твоим оружием: с цепью или дубинкой догонит и попробует отобрать. Без оружия ты ему почти не интересен.",
	"coward": "Ударишь, и он удирает к обочине, отвечает редко. Лёгкий нокаут и лёгкие деньги.",
	"blocker": "Встаёт перед тобой и закрывает полосу. Не висни за ним, обгоняй сразу и с запасом.",
	"maniac": "Газ в пол, на трафик почти не смотрит, бывает, выезжает на встречку. Часто разбивается сам.",
}
const COP_TXT := "Стоит на обочине и выезжает, как только рядом окажется гонщик. Бьёт дубинкой ближайшего, не отстаёт, пока его не вырубить. Упадёшь рядом с ним, арест и штраф. Соперника, которого вырубил, забирает. Вырубишь его сам, получишь четверть приза."

var room: Showroom
var tab := 0        # league index, 3 = police
var who := ""
var name_l: Label
var sub_l: Label
var quote_l: Label
var tabs: HBoxContainer
var people: GridContainer
var list: ScrollList

func open(r: Showroom, league := -1) -> void:
	room = r
	_build()
	tab = league
	if tab < 0:
		tab = 0
		for k in D.leagues.size():
			if S.cat_open(k):
				tab = k
	who = ""
	render()

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
	lv.add_theme_constant_override("separation", 3)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(lv)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(UiKit.button("Назад", func() -> void: close_requested.emit()))
	top.add_child(UiKit.outlined(UiKit.label("Бар «Цепь»", UiKit.big, 28, UiKit.YEL)))
	lv.add_child(top)
	name_l = UiKit.outlined(UiKit.label("", UiKit.mid, 20, UiKit.PAPER))
	lv.add_child(name_l)
	sub_l = UiKit.outlined(UiKit.label("", UiKit.small, 14, UiKit.PAPER), 4)
	lv.add_child(sub_l)
	lv.add_child(UiKit.expand())
	quote_l = UiKit.outlined(UiKit.label("", UiKit.mid, 16, UiKit.YEL), 4)
	quote_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(quote_l)
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
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	right.add_child(rv)
	tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	rv.add_child(tabs)
	people = GridContainer.new()
	people.columns = 6
	people.add_theme_constant_override("h_separation", 3)
	people.add_theme_constant_override("v_separation", 3)
	rv.add_child(people)
	list = ScrollList.new()
	rv.add_child(list)

# Which rivals turn up in a league, and on what
func _league_people(c: int) -> Array:
	var out: Array = []
	for i in D.tracks.size():
		var t: Dictionary = D.tracks[i]
		if int(t.cat) != c:
			continue
		for e in t.roster:
			if not (e[0] in out):
				out.append(e[0])
	return out

func _appearances(id: String, c: int) -> Array:
	var out: Array = []
	for i in D.tracks.size():
		var t: Dictionary = D.tracks[i]
		if int(t.cat) != c:
			continue
		for e in t.roster:
			if e[0] == id:
				var ch: Dictionary = D.rivals[id]
				out.append({"track": t, "bike": D.bike_by_id[e[1]], "weapon": e[2] if e.size() > 2 else ch.get("weapon", "none")})
	return out

func _tab_btn(k: int, txt: String) -> void:
	var on: bool = tab == k
	var b := UiKit.button(txt, func() -> void:
		tab = k
		who = ""
		list.scroll_vertical = 0
		render(), UiKit.YEL if on else UiKit.INK3, UiKit.INK if on else UiKit.PAPER, 15)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(b)

func render() -> void:
	UiKit.clear(tabs)
	_tab_btn(0, "Скутеры")
	_tab_btn(1, "Городские")
	_tab_btn(2, "Спорт")
	_tab_btn(3, "Полиция")
	UiKit.clear(people)
	UiKit.clear(list.box)
	if tab == 3:
		_render_cop()
		return
	var open_c: bool = S.cat_open(tab)
	var ids := _league_people(tab)
	if who == "" or not (who in ids):
		who = ids[0]
	for id in ids:
		var ch: Dictionary = D.rivals[id]
		var on: bool = id == who
		var txt: String = str(ch.name) if open_c else "???"
		var b := UiKit.button(txt, func() -> void:
			who = id
			list.scroll_vertical = 0
			render(), UiKit.YEL if on else UiKit.INK2, UiKit.INK if on else UiKit.PAPER, 12)
		for key in ["normal", "hover", "pressed"]:
			var st: StyleBoxFlat = b.get_theme_stylebox(key).duplicate()
			st.content_margin_left = 2
			st.content_margin_right = 2
			b.add_theme_stylebox_override(key, st)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 32)
		people.add_child(b)
	if not open_c:
		var i: int = S.first_track_of(tab) - 1
		name_l.text = "Пока не знаем"
		sub_l.text = "Лига закрыта"
		quote_l.text = ""
		list.box.add_child(UiKit.label("Бармен про них не расскажет, пока не войдёшь в топ-3 на трассе %s. Зато они уже слышали про тебя." % D.tracks[i].name, UiKit.small, 15, UiKit.PAPER, true))
		var a0: Array = _appearances(who, tab)
		room.show_rig(a0[0].bike, 0, null, 0, "none", false, true)
		return
	_render_person(who)

func _render_person(id: String) -> void:
	var ch: Dictionary = D.rivals[id]
	var apps: Array = _appearances(id, tab)
	var main: Dictionary = apps[0]
	var fx := D.gear_fx(int(ch.suit), int(ch.helmet))
	name_l.text = ch.name
	sub_l.text = STYLE_NAMES.get(ch.style, "") + ", " + str(D.gear.suits[int(ch.suit)]["in"])
	var said: Array = ch.say
	quote_l.text = "«" + str(said[0]) + "»"
	var b: Variant = main.bike
	room.show_rig(b, int(ch.paint), D.outfit(int(ch.suit), int(ch.c), int(ch.h)), int(ch.helmet), "none" if fx.no_hand else main.weapon, true)
	list.box.add_child(UiKit.label(STYLE_TXT.get(ch.style, ""), UiKit.small, 15, UiKit.PAPER, true))
	var t0: Dictionary = main.track
	var base_hp: float = float(t0.foeHp) * float(ch.hp)
	var w: Dictionary = D.gear.weapons[main.weapon if not fx.no_hand else "none"]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	var rows := [
		["Мастерство езды", "%d%%" % int(round(float(ch.skill) * 100.0)), (float(ch.skill) - 0.8) / 0.2],
		["Агрессия", "%d%%" % int(round(float(ch.aggr) * 100.0)), float(ch.aggr)],
		["Живучесть", "%d" % int(base_hp), base_hp / 95.0],
		["Защита", "%d%%" % int(round(float(fx.prot) * 100.0)), float(fx.prot)],
		["Удар", "%d" % int(round(float(w.foe) * float(t0.foeDmg) * (float(fx.kick) if fx.no_hand else float(fx.hit)))), float(w.foe) * float(t0.foeDmg) / 17.0],
		["Обтекаемость", str(int(fx.aero)), float(fx.aero) / 100.0],
	]
	for r in rows:
		var c := UiKit.stat(r[0], r[1], r[2], UiKit.RED if r[0] == "Удар" or r[0] == "Агрессия" else UiKit.YEL)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(c)
	list.box.add_child(grid)
	list.box.add_child(UiKit.heading("Где встретишь"))
	for a in apps:
		var wn: String = "без оружия" if a.weapon == "none" or fx.no_hand else "в руке " + str(D.gear.weapons[a.weapon].acc)
		var p := UiKit.panel()
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		v.add_child(UiKit.label(a.track.name, UiKit.mid, 15, UiKit.PAPER))
		v.add_child(UiKit.label("%s %dcc, %d км/ч, %s" % [a.bike.name, int(a.bike.cc), int(a.bike.kmh), wn], UiKit.small, 13, UiKit.MUTED, true))
		p.add_child(v)
		list.box.add_child(p)
	list.box.add_child(UiKit.heading("Что говорит"))
	var quotes := ""
	for q in said:
		quotes += "«%s»  " % q
	list.box.add_child(UiKit.label(quotes, UiKit.small, 14, UiKit.MUTED, true))
	if fx.no_hand:
		list.box.add_child(UiKit.label("В гоночном комбезе рукой не бьёт, только ногой. Зато падать ему не страшно.", UiKit.small, 14, UiKit.PAPER, true))

func _render_cop() -> void:
	name_l.text = "Инспектор"
	sub_l.text = "полиция, дубинка"
	quote_l.text = "«Стоять! Документы!»"
	var c: int = 0
	for k in D.leagues.size():
		if S.cat_open(k):
			c = k
	var art: String = D.leagues[c].cop
	var o := {"jacket": "#1f3f8a", "stripe": "#f3eedf", "pants": "#1a2a55", "boots": "#0e0e12", "glove": "#16151b", "skin": "#e0b48c", "helmet": "#e9e6dc", "hs": "#1f3f8a", "sleeve": "#1f3f8a"}
	room.show_rig({"art": art, "kmh": 100, "name": "Полиция", "cat": c, "cc": 0}, -1, o, 2, "baton", true, false, true)
	list.box.add_child(UiKit.label(COP_TXT, UiKit.small, 15, UiKit.PAPER, true))
	list.box.add_child(UiKit.heading("По трассам"))
	var baton: Dictionary = D.gear.weapons.baton
	for i in D.tracks.size():
		var t: Dictionary = D.tracks[i]
		var known: bool = S.track_open(i)
		var p := UiKit.panel()
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		v.add_child(UiKit.label(t.name if known else "???", UiKit.mid, 15, UiKit.PAPER))
		if known:
			v.add_child(UiKit.label("Постов: %d, живучесть %d, удар %d, за нокаут %s" % [t.cops.size(), int(t.copHp), int(round(float(baton.foe) * float(t.foeDmg) * 1.2)), S.fmt(S.round10(float(t.prize) * 0.25))], UiKit.small, 13, UiKit.MUTED, true))
		p.add_child(v)
		list.box.add_child(p)
