extends Node
# Screens: menu, garage, shop, bar, start screen, race, result.

const STEP := 1.0 / 60.0
const BUILD_NO := 11
const TEST_GEAR := [[2, 2], [4, 2], [4, 3]]

var ui_layer: CanvasLayer
var hud_layer: CanvasLayer
var hud: Hud
var menu: Control
var overlay: Control
var view_rect: TextureRect
var view_port: SubViewport
var mirror_vp: SubViewport
var mirror_cam: Camera3D
var race_view: RaceView
var room: Showroom
var audio: GameAudio
var sim: Sim
var running := false
var paused := false
var acc := 0.0
var font_big: FontFile
var font_mid: FontFile
var font_small: FontFile
var pending_track := 0
var pending_bike := ""
var fps_low_t := 0.0
var quality := 1.0
var quality_max := -1.0
var auto_mode := ""     # command line: screenshot tests
var settings_open := false
var film: Incident = null     # your end of the race, played as a little scene before the results
var film_kind := ""
var film_res: Dictionary = {}

func _font(lat: String, cyr: String) -> FontFile:
	var f: FontFile = load("res://assets/fonts/" + lat)
	var c: FontFile = load("res://assets/fonts/" + cyr)
	f.fallbacks = [c]
	return f

func _ready() -> void:
	D.load_all()
	font_big = _font("fira-sans-extra-condensed-latin-900-italic.woff2", "fira-sans-extra-condensed-cyrillic-900-italic.woff2")
	font_mid = _font("fira-sans-condensed-latin-700-normal.woff2", "fira-sans-condensed-cyrillic-700-normal.woff2")
	font_small = _font("fira-sans-condensed-latin-500-normal.woff2", "fira-sans-condensed-cyrillic-500-normal.woff2")
	UiKit.big = font_big
	UiKit.mid = font_mid
	UiKit.small = font_small
	var th := Theme.new()
	th.default_font = font_mid
	th.default_font_size = 18
	# 3D draws into its own picture at real screen pixels and is laid under the interface
	view_port = SubViewport.new()
	view_port.own_world_3d = true
	view_port.handle_input_locally = false
	view_port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view_port.msaa_3d = Viewport.MSAA_4X
	add_child(view_port)
	view_rect = TextureRect.new()
	view_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view_rect.stretch_mode = TextureRect.STRETCH_SCALE
	view_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_rect.texture = view_port.get_texture()
	add_child(view_rect)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 1
	add_child(hud_layer)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 2
	add_child(ui_layer)
	var root_ui := Control.new()
	root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ui.theme = th
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(root_ui)
	menu = root_ui
	audio = GameAudio.new()
	add_child(audio)
	audio.apply_settings()
	get_viewport().size_changed.connect(_fit_resolution)
	# progress came from the server (another device, or a log-in): the menu shows it at once
	N.save_replaced.connect(func() -> void:
		if not running and room == null and menu.get_child_count() > 0 and menu.get_child(menu.get_child_count() - 1) is MarginContainer:
			_show_menu())
	_fit_resolution()
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "ui":
		auto_mode = "ui"
		_ui_shots(args[1])
	elif args.size() >= 3 and args[0] == "shot":
		auto_mode = "shot"
		_start_race_test(int(args[1]), args[2])
	elif args.size() >= 5 and args[0] == "flow":
		# the real end of a race, film and result screen included: flow <track> <bike> <finish|busted|dead|wrecked> <out>
		auto_mode = "flow"
		_flow_test(int(args[1]), args[2], args[3], args[4])
	else:
		_show_menu()

func _fit_resolution() -> void:
	var win: Vector2i = DisplayServer.window_get_size()
	if quality_max < 0.0:
		var phone: bool = UiKit.is_phone()
		quality_max = 720.0 / max(win.y, 1) if phone else 1080.0 / max(win.y, 1)
		quality_max = min(quality_max, 1.0)
		quality = quality_max
		view_port.msaa_3d = Viewport.MSAA_2X if phone else Viewport.MSAA_4X
	view_port.size = Vector2i(max(16, int(win.x * quality)), max(16, int(win.y * quality)))
	if room != null:
		room.layout()

# ---------- menu ----------
func _clear_ui() -> void:
	for c in menu.get_children():
		menu.remove_child(c)
		c.queue_free()

func _bg(col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(r)
	return r

func _button(txt: String, cb: Callable, col := UiKit.INK3, fg := UiKit.PAPER, sz := 16) -> Button:
	return UiKit.button(txt, cb, col, fg, sz)

func _label(txt: String, f: Font, sz: int, col: Color) -> Label:
	return UiKit.label(txt, f, sz, col)

func _drop_room() -> void:
	if room != null:
		view_port.remove_child(room)
		room.queue_free()
		room = null

func _make_room(kind: String) -> Showroom:
	_end_race_nodes()
	_drop_room()
	room = Showroom.new()
	view_port.add_child(room)
	room.build(kind)
	return room

func _show_menu() -> void:
	_end_race_nodes()
	_drop_room()
	sim = null
	_clear_ui()
	_bg(UiKit.INK)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for key in ["left", "right"]:
		m.add_theme_constant_override("margin_" + key, 14)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 8)
	menu.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(_label("ГАЗ И ЦЕПЬ", font_big, 34, UiKit.YEL))
	head.add_child(_label("3D · сборка %d" % BUILD_NO, font_small, 14, UiKit.MUTED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(_label(S.fmt(S.data.money), font_big, 24, UiKit.PAPER))
	var acc := _button(N.login if N.logged_in() else "Войти", _open_account, UiKit.INK3 if N.logged_in() else UiKit.GRN, UiKit.PAPER)
	head.add_child(acc)
	v.add_child(head)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	for x in [["Гараж", _open_garage.bind(""), UiKit.YEL, UiKit.INK], ["Магазин", _open_shop.bind(-1, ""), UiKit.PAPER, UiKit.INK],
			["Бар", _open_bar.bind(-1), Color("#7a1f3d"), UiKit.PAPER], ["Рекорды", _open_records.bind(-1), Color("#1f4fb8"), UiKit.PAPER],
			["Настройки", _open_settings, UiKit.INK3, UiKit.PAPER]]:
		var nb := _button(x[0], x[1], x[2], x[3])
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.custom_minimum_size = Vector2(0, 36)
		nav.add_child(nb)
	v.add_child(nav)
	var list := ScrollList.new()
	v.add_child(list)
	for c in D.leagues.size():
		var lg: Dictionary = D.leagues[c]
		var open_c: bool = S.cat_open(c)
		var bike: Variant = S.ride_of(c)
		var p := UiKit.panel(UiKit.INK2, 8, 6)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		p.add_child(h)
		var ring: Color = UiKit.RED if open_c else Color("#77757f")
		var sign_w := UiKit.sign_label(str(lg.sign), ring, 46)
		sign_w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sign_w)
		var tv := VBoxContainer.new()
		tv.custom_minimum_size = Vector2(190, 0)
		tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tv.add_theme_constant_override("separation", 0)
		tv.add_child(_label(lg.full, font_mid, 18, UiKit.PAPER if open_c else UiKit.MUTED))
		var sub: String = str(lg.range)
		if open_c:
			if bike != null:
				sub = "%s %dcc, %d км/ч" % [bike.name, int(bike.cc), int(D.stats_of(bike, S.upgrades(bike.id)).kmh)]
			else:
				sub = "Нужен байк из магазина"
		tv.add_child(_label(sub, font_small, 13, UiKit.MUTED))
		h.add_child(tv)
		for i in D.tracks.size():
			var t: Dictionary = D.tracks[i]
			if int(t.cat) != c:
				continue
			var op: bool = S.track_open(i)
			var best: Variant = S.data.best.get(t.id)
			var st: String
			if not op:
				st = "Нужен топ-3: " + str(D.tracks[i - 1].name)
			elif bike == null:
				st = "Сначала байк"
			elif best != null:
				st = "%d место" % int(best)
			else:
				st = "Едем"
			var b := _button("%s\n%s" % [t.name, st], _begin.bind(i), Color("#3f3d4a") if op else Color(0.12, 0.12, 0.14), UiKit.PAPER if op else UiKit.MUTED, 14)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size = Vector2(0, 58)
			h.add_child(b)
		list.box.add_child(p)
	var tests := HBoxContainer.new()
	tests.add_theme_constant_override("separation", 6)
	if int(S.data.open) < D.tracks.size():
		tests.add_child(_button("Для теста: открыть все трассы", func() -> void:
			S.open_everything()
			_show_menu(), UiKit.INK2, UiKit.MUTED, 13))
	tests.add_child(_button("Для теста: +$25 000", func() -> void:
		S.add_test_money()
		_show_menu(), UiKit.INK2, UiKit.MUTED, 13))
	list.box.add_child(tests)

func _open_account() -> void:
	_clear_ui()
	_bg(UiKit.INK)
	var ui := AccountUi.new()
	menu.add_child(ui)
	ui.open()
	ui.close_requested.connect(_show_menu)

func _open_records(lg: int) -> void:
	_clear_ui()
	_bg(UiKit.INK)
	var ui := RecordsUi.new()
	menu.add_child(ui)
	var start: int = lg
	if start < 0:
		start = 0
		for c in D.leagues.size():
			if S.cat_open(c):
				start = c
	ui.open(start)
	ui.close_requested.connect(_show_menu)

func _open_settings() -> void:
	settings_open = true
	_clear_ui()
	_bg(UiKit.INK if not paused else Color(0.05, 0.05, 0.07, 0.86))
	var ui := SettingsUi.new()
	menu.add_child(ui)
	ui.open(audio)
	ui.close_requested.connect(_close_settings)

func _close_settings() -> void:
	settings_open = false
	if paused and running:
		_show_pause()
	else:
		_show_menu()

func _begin(i: int) -> void:
	if not S.track_open(i):
		audio.ui("deny")
		return
	var cat: int = D.tracks[i].cat
	if S.ride_of(cat) == null:
		var owned := S.owned_in(cat)
		if owned.size() > 0:
			S.data.ride[str(cat)] = owned[0].id
			S.persist()
		else:
			_open_shop(cat, "")
			return
	_open_prerace(i)

func _open_prerace(i: int) -> void:
	_clear_ui()
	pending_track = i
	var r := _make_room("garage")
	var ui := PreRaceUi.new()
	menu.add_child(ui)
	ui.open(r, i)
	ui.back_requested.connect(_show_menu)
	ui.start_requested.connect(_start_race)
	ui.bar_requested.connect(_open_bar_from_start)
	ui.garage_requested.connect(_open_garage.bind(""))

func _open_bar_from_start(league: int) -> void:
	_open_bar(league)

func _open_garage(id: String) -> void:
	_open_stock(false, id, -1)

func _open_shop(cat: int, id: String) -> void:
	_open_stock(true, id, cat)

func _open_stock(shop: bool, id: String, cat: int) -> void:
	_clear_ui()
	var r := _make_room("shop" if shop else "garage")
	var ui := GarageUi.new()
	menu.add_child(ui)
	ui.open(r, shop, audio, id, cat)
	ui.close_requested.connect(_show_menu)
	ui.race_requested.connect(_begin)

func _open_bar(league: int) -> void:
	_clear_ui()
	var r := _make_room("bar")
	var ui := BarUi.new()
	menu.add_child(ui)
	ui.open(r, league)
	ui.close_requested.connect(_show_menu)

# ---------- race ----------
func _start_race(track_i: int) -> void:
	var bike: Dictionary = S.ride_of(int(D.tracks[track_i].cat))
	var lo := S.loadout(bike.id)
	await _launch_race(track_i, bike.id, lo.u, lo.suit, lo.helmet, lo.cs, lo.ch, lo.extra)

func _start_race_test(track_i: int, bike_id: String) -> void:
	var g: Array = TEST_GEAR[int(D.tracks[track_i].cat)]
	await _launch_race(track_i, bike_id, {}, g[0], g[1], 0, 5, {"weapon": "chain"})

func _launch_race(track_i: int, bike_id: String, u: Dictionary, ts: int, th: int, cs: int, ch: int, extra: Dictionary) -> void:
	_clear_ui()
	pending_track = track_i
	pending_bike = bike_id
	_bg(UiKit.INK)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(c)
	c.add_child(_label("Строим трассу…", font_big, 36, UiKit.YEL))
	await get_tree().process_frame
	await get_tree().process_frame
	_end_race_nodes()
	_drop_room()
	sim = Sim.new()
	sim.setup(track_i, bike_id, u, ts, th, cs, ch, randi(), extra)
	race_view = RaceView.new()
	view_port.add_child(race_view)
	await race_view.build(sim)
	hud = Hud.new()
	hud_layer.add_child(hud)
	hud.set_fonts(font_big, font_mid, font_small)
	hud.sim = sim
	hud.pause_pressed.connect(_toggle_pause)
	audio.setup(sim.me.st)
	_make_mirror()
	_clear_ui()
	running = true
	paused = false
	acc = 0.0
	if auto_mode == "shot":
		_run_shots()

# The rear view: a small second camera in the same world, drawn every other frame
func _make_mirror() -> void:
	if mirror_vp != null:
		mirror_vp.queue_free()
		mirror_vp = null
	if not S.data.get("mirrors", true):
		hud.mirror_tex = null
		return
	mirror_vp = SubViewport.new()
	mirror_vp.size = Vector2i(320, 92)
	mirror_vp.world_3d = view_port.find_world_3d()
	mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	mirror_vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(mirror_vp)
	mirror_cam = Camera3D.new()
	mirror_cam.fov = 38.0
	mirror_cam.near = 0.3
	mirror_cam.far = 190.0
	mirror_vp.add_child(mirror_cam)
	mirror_cam.current = true
	hud.mirror_tex = mirror_vp.get_texture()

func _update_mirror() -> void:
	if mirror_vp == null or mirror_cam == null:
		return
	var me := sim.me
	var on: Road = sim.rd(me)
	var s_now: float = me.s if me.state == Sim.RIDE else me.fly_s
	var d_now: float = me.d if me.state == Sim.RIDE else me.fly_d
	var p := on.world(s_now - 1.3, d_now, 1.35 + me.air_h)
	var back := on.world(s_now - 40.0, d_now * 0.7, 0.9 + me.air_h * 0.5)
	mirror_cam.look_at_from_position(p, back, Vector3.UP)
	# every other frame is plenty for a mirror, and halves what it costs
	mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE if Engine.get_process_frames() % 2 == 0 else SubViewport.UPDATE_DISABLED

func _end_race_nodes() -> void:
	running = false
	if mirror_vp != null:
		mirror_vp.queue_free()
		mirror_vp = null
		mirror_cam = null
	if race_view != null:
		race_view.queue_free()
		race_view = null
	if hud != null:
		hud.queue_free()
		hud = null
	audio.stop_all()

func _toggle_pause() -> void:
	if sim == null or not running or film != null:
		return
	paused = not paused
	hud.set_active(not paused)
	if paused:
		audio.quiet()
		_show_pause()
	else:
		_clear_ui()

func _show_pause() -> void:
	_clear_ui()
	_bg(Color(0, 0, 0, 0.6))
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	c.add_child(v)
	v.add_child(_label("Пауза", font_big, 44, Color("#ffc81f")))
	v.add_child(_button("Дальше", _toggle_pause, Color("#ffc81f"), Color("#16151b"), 22))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_button("Заново", _start_race.bind(pending_track)))
	row.add_child(_button("Настройки", _open_settings))
	row.add_child(_button("В меню", _quit_to_menu))
	v.add_child(row)

func _quit_to_menu() -> void:
	paused = false
	_show_menu()

func _show_result(kind: String) -> void:
	audio.stop_all()
	var res := _settle(kind)
	N.finish_bots(sim)
	_result_screen(res)

# the money and the records are settled the moment the race ends, before any scene plays
func _settle(kind: String) -> Dictionary:
	var res := S.finish_race(sim, kind)
	res["time"] = sim.stats.t_finish if kind == "finish" else -1.0
	res["cat"] = int(sim.tr.cat)
	N.send_result(sim, kind)
	return res

# ---------- the end of your race as a little film: cheering or raging by the bike, the police, the ambulance ----------
func _start_film(kind: String) -> void:
	film_kind = kind
	film_res = _settle(kind)
	var place: int = sim.final_place
	var scene := "rage"
	var caption := ""
	match kind:
		"finish":
			scene = "joy" if place >= 1 and place <= 3 else "rage"
			caption = "ПОБЕДА!" if place == 1 else ("%d МЕСТО!" % place if place <= 3 else "%d МЕСТО" % place)
		"wrecked":
			caption = "МОТОЦИКЛ В ХЛАМ"
		"busted":
			scene = "arrest"
			caption = "ЗАДЕРЖАН"
		"dead":
			scene = "medic"
			caption = "В БОЛЬНИЦУ"
	sim.me_parked = true
	hud.visible = false
	film = race_view.start_movie(scene)
	film.finished.connect(_end_film)
	audio.siren_on = scene == "arrest" or scene == "medic"
	_film_overlay(caption)

func _film_overlay(caption: String) -> void:
	_clear_ui()
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			_end_film())
	menu.add_child(root)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.92)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 0.88
		bar.anchor_bottom = 0.12 if top else 1.0
		root.add_child(bar)
		var tw := create_tween()
		bar.modulate.a = 0.0
		tw.tween_property(bar, "modulate:a", 1.0, 0.4)
	var cap := _label(caption, font_big, 40, UiKit.YEL if film_kind == "finish" and sim.final_place <= 3 else Color("#ff6a5e"))
	cap.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	cap.anchor_top = 0.0
	cap.anchor_bottom = 0.12
	cap.offset_top = 0
	cap.offset_bottom = 0
	cap.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cap)
	var hint := _label("Нажми, чтобы пропустить", font_small, 15, UiKit.MUTED)
	hint.anchor_left = 0.0
	hint.anchor_right = 1.0
	hint.anchor_top = 0.88
	hint.anchor_bottom = 1.0
	hint.offset_right = -20
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)

func _end_film() -> void:
	if film == null:
		return
	film = null
	running = false
	audio.stop_all()
	N.finish_bots(sim)
	_result_screen(film_res)

func _result_screen(res: Dictionary) -> void:
	_clear_ui()
	_bg(Color(0.04, 0.04, 0.06, 0.8))
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for key in ["left", "right"]:
		m.add_theme_constant_override("margin_" + key, 24)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 10)
	menu.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 16)
	title_row.add_child(_label(res.title, font_big, 40, UiKit.RED if res.bad else UiKit.YEL))
	if float(res.get("time", -1.0)) > 0.0:
		title_row.add_child(_label(Hud.race_time(float(res.time)), font_big, 32, UiKit.PAPER))
	var rec_l := _label("", font_mid, 16, UiKit.YEL)
	rec_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(rec_l)
	if res.get("time", -1.0) > 0.0 and not N.logged_in():
		rec_l.text = "Войди в аккаунт, и время попадёт в рекорды"
		rec_l.add_theme_color_override("font_color", UiKit.MUTED)
	elif N.logged_in():
		rec_l.text = "Отправляю…"
		N.result_answer.connect(func(d: Dictionary) -> void:
			if not is_instance_valid(rec_l):
				return
			if d.has("error"):
				rec_l.text = "Не отправилось: " + str(d.error) + (", отправлю позже" if N.pending.size() > 0 else "")
			else:
				var parts: Array = []
				if d.get("best", false):
					parts.append("новый рекорд, %d-й по времени" % int(d.rank))
				elif d.get("rank") != null:
					parts.append("%d-й по времени" % int(d.rank))
				if d.get("ko_best", false):
					parts.append("лучший заезд по нокаутам, %d-й" % int(d.ko_rank))
				var line: String = ", ".join(parts)
				rec_l.text = (line.substr(0, 1).to_upper() + line.substr(1)) if line != "" else "Записано", CONNECT_ONE_SHOT)
	v.add_child(title_row)
	v.add_child(UiKit.label(res.text, font_mid, 16, UiKit.PAPER, true))
	if res.note != "":
		v.add_child(UiKit.label(res.note, font_mid, 15, UiKit.YEL, true))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	if res.finished:
		var table := VBoxContainer.new()
		table.add_theme_constant_override("separation", 0)
		table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var rows: Array = res.rows
		for k in min(8, rows.size()):
			var me_row: bool = rows[k] == "Ты"
			table.add_child(UiKit.label("%d. %s" % [k + 1, rows[k]], font_mid if me_row else font_small, 14, UiKit.YEL if me_row else UiKit.PAPER))
		cols.add_child(table)
	var led := VBoxContainer.new()
	led.add_theme_constant_override("separation", 2)
	led.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ledger: Array = res.ledger
	if ledger.is_empty():
		led.add_child(_ledger_line("За гонку", "$0", UiKit.PAPER))
	for r in ledger:
		var n: int = r[1]
		led.add_child(_ledger_line(r[0], ("+" if n >= 0 else "−") + S.fmt(n), UiKit.GRN if n >= 0 else UiKit.RED))
	led.add_child(_ledger_line("На счету", S.fmt(res.money), UiKit.PAPER, true))
	cols.add_child(led)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var nxt: int = res.next
	if nxt >= 0:
		var has_bike: bool = S.ride_of(int(D.tracks[nxt].cat)) != null or S.owned_in(int(D.tracks[nxt].cat)).size() > 0
		var b := _button(str(D.tracks[nxt].name) if has_bike else "В магазин", _begin.bind(nxt), UiKit.YEL, UiKit.INK, 18)
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	for x in [["Ещё раз", _begin.bind(pending_track)], ["Гараж", _open_garage.bind("")], ["Рекорды", _open_records.bind(int(res.get("cat", 0)))], ["В меню", _show_menu]]:
		var b2 := _button(x[0], x[1], UiKit.INK3, UiKit.PAPER, 18)
		b2.custom_minimum_size = Vector2(0, 44)
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b2)
	v.add_child(row)

func _ledger_line(a: String, b: String, col: Color, bold := false) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_child(_label(a, font_mid if bold else font_small, 15, UiKit.PAPER))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	h.add_child(_label(b, font_mid, 15, col))
	return h

func _unhandled_input(event: InputEvent) -> void:
	if film != null and event is InputEventKey and event.pressed and not event.echo:
		_end_film()
		return
	if event is InputEventKey and event.pressed and not event.echo and running and not settings_open:
		if S.action_of_key(event.physical_keycode) == "pause":
			_toggle_pause()

# With the gas on by itself the bike would ride on while a notification or another app has the screen
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if running and not paused and auto_mode == "":
			_toggle_pause()

func _process(delta: float) -> void:
	N.race_running = running and not paused
	if not running or sim == null:
		return
	if paused:
		return
	if auto_mode == "":
		hud.read_input()
	acc = min(acc + delta, 0.1)
	while acc >= STEP:
		acc -= STEP
		sim.step(STEP)
	var over_kind := ""
	for e in sim.events:
		race_view.handle_event(e)
		audio.handle_event(e)
		hud.handle_event(e)
		if e[0] == "stock":
			S.use_weapon(e[1])
		elif e[0] == "over":
			over_kind = e[1]
	sim.events.clear()
	if over_kind != "":
		if (auto_mode == "" or auto_mode == "flow") and race_view != null and over_kind in ["finish", "busted", "dead", "wrecked"]:
			_start_film(over_kind)
		else:
			running = false
			_show_result(over_kind)
			return
	if film != null:
		# the scene's own sound: no engine, a siren while the police or the ambulance is there
		audio.update(delta, 0.1, false, false, false, 25.0)
		return
	var near := 1e9
	for c in sim.cops:
		if c.state == Sim.RIDE:
			near = min(near, abs(c.ps - sim.me.ps))
	audio.update(delta, sim.me.rpm, sim.me.gas_on, sim.me.state == Sim.RIDE, sim.me.slide and sim.phase == "race", near)
	_update_mirror()
	_adapt_quality(delta)

func _adapt_quality(delta: float) -> void:
	# only if a device really struggles: a slightly softer picture rather than a stuttering game
	if Engine.get_frames_per_second() < 36 and sim.phase == "race" and auto_mode == "":
		fps_low_t += delta
		if fps_low_t > 3.0 and quality > 0.45:
			quality *= 0.85
			_fit_resolution()
			fps_low_t = 0.0
	else:
		fps_low_t = 0.0

# ---------- screenshot test: the bot drives, frames get saved at chosen times ----------
func _run_shots() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[3]
	sim.bot = true
	if args.size() > 5:
		sim.bot_peace = args[5] == "peace"
	var mode: String = args[5] if args.size() > 5 else ""
	hud.touch_mode = true
	if mode == "pose":
		await _pose_shots(out)
		return
	if mode == "brake":
		await _brake_shots(out)
		return
	if mode == "cop":
		await _cop_shots(out)
		return
	if mode == "tour":
		await _tour_shots(out)
		return
	if mode == "b10":
		await _b10_shots(out)
		return
	if mode == "b11":
		await _b11_shots(out)
		return
	if mode == "incident":
		await _incident_shots(out)
		return
	if mode.begins_with("film_"):
		await _film_shots(out, mode.substr(5))
		return
	var times: Array = str(args[4]).split(",")
	var i := 0
	Engine.max_fps = 0
	while i < times.size():
		await get_tree().process_frame
		var want: float = float(times[i])
		# fast-forward the race to the next shot
		if sim.phase != "count" and sim.t < want:
			for k in 30:
				sim.step(STEP)
		elif sim.phase == "count":
			for k in 30:
				sim.step(STEP)
		for e in sim.events:
			race_view.handle_event(e)
			hud.handle_event(e)
		sim.events.clear()
		if sim.phase != "count" and sim.t >= want:
			for k in 3:
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s_%s.png" % [out, times[i]])
			print("shot t=%.1f s=%.0f d=%.1f v=%.0f km/h place=%d phase=%s fps=%d" % [sim.t, sim.me.s, sim.me.d, sim.me.v * 3.6, sim.live_place(), sim.phase, Engine.get_frames_per_second()])
			i += 1
	get_tree().quit()

func _pose_shots(out: String) -> void:
	race_view.debug_close = true
	sim.bot_peace = true
	for k in 500:
		sim.step(STEP)
	sim.events.clear()
	var me := sim.me
	var snap := func(n: String) -> void:
		for k in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, n])
	await snap.call("ride")
	me.weapon = "chain"
	me.attack = {"type": "hand", "t": 0.1, "side": 1, "w": {"reach": 2.0, "cd": 0.42, "hit_at": 0.18, "dmg": 10}, "done": true, "weapon": "chain"}
	await snap.call("punch")
	me.attack = {"type": "kick", "t": 0.14, "side": -1, "w": {"reach": 2.0, "cd": 0.36, "hit_at": 0.14, "dmg": 10}, "done": true, "weapon": "none"}
	await snap.call("kick")
	me.attack = null
	me.weapon = "none"
	sim.me.inv = 0.0
	sim.crash("car")
	for k in 26:
		sim.step(STEP)
	sim.events.clear()
	await snap.call("fly")
	for k in 40:
		sim.step(STEP)
	sim.events.clear()
	await snap.call("down")
	# back on his feet, running to the bike, lifting it
	race_view.debug_close = false
	var shots := {1: "getup", 2: "run", 3: "lift"}
	var taken := {}
	for k in 600:
		sim.step(STEP)
		sim.events.clear()
		var ph: int = me.run_phase
		if me.state == Sim.DOWN and shots.has(ph) and not taken.has(ph) and me.run_t > (0.25 if ph != 2 else 0.3):
			taken[ph] = true
			for j in 3:
				await get_tree().process_frame
			await snap.call(shots[ph])
		if me.state == Sim.RIDE:
			break
	print("back on the bike after %.1f s, down at %.0f m, body at %.0f m" % [me.down_t, me.s, me.fly_s])
	get_tree().quit()

func _brake_shots(out: String) -> void:
	sim.bot_peace = true
	for k in 400:
		sim.step(STEP)
	sim.events.clear()
	var me := sim.me
	sim.bot = false
	me.v = 8.0
	sim.inp.steer = 0.0
	sim.inp.gas = false
	var i := 0
	for kind in ["sedan", "van", "truck"]:
		for c in sim.cars:
			if c.dir > 0 and c.kind == kind:
				c.s = me.s + 11.0 + c.len * 0.5
				c.d = me.d
				c.v = me.v
				c.braking = true
				for k in 5:
					c.braking = true
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, kind])
				c.s = me.s + 4000.0
				break
		i += 1
	# a queue stopping behind a stopped bike, seen from the side
	var behind: Array = []
	for c in sim.cars:
		if c.dir > 0:
			behind.append(c)
		if behind.size() == 2:
			break
	me.v = 0.0
	race_view.debug_close = true
	for j in behind.size():
		behind[j].d = me.d
		behind[j].s = me.s - 4.0 - behind[j].len * 0.5 - j * 8.0
		behind[j].v = 0.0
		behind[j].braking = true
	for k in 5:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s_queue.png" % out)
	get_tree().quit()

# Walks through every new screen, saves pictures, and checks purchases survive a reload. Writes a test save, not yours.
func _ui_shots(out: String) -> void:
	S.path = "user://ui_test_save.json"
	S.reset_for_test()
	S.data.money = 30000
	var snap := func(n: String) -> void:
		for k in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, n])
	_show_menu()
	await snap.call("menu")
	_open_settings()
	await snap.call("settings")
	settings_open = false
	_open_garage("")
	await snap.call("garage")
	var g: GarageUi = menu.get_child(0)
	g.tab = "gear"
	g.render()
	await snap.call("gear")
	S.buy_wear("suit", 2)
	S.buy_wear("helmet", 2)
	S.buy_weapon("chain")
	g.render()
	await snap.call("gear2")
	_open_shop(0, "buivol")
	await snap.call("shop")
	S.buy_bike("buivol")
	S.buy_up("buivol", "eng")
	_open_garage("buivol")
	await snap.call("garage2")
	_open_prerace(0)
	await snap.call("start")
	S.open_everything()
	_show_menu()
	await snap.call("menu2")
	_open_bar(0)
	await snap.call("bar")
	var b: BarUi = menu.get_child(0)
	b.who = "zina"
	b.render()
	await snap.call("bar2")
	b.tab = 2
	b.who = "gvozd"
	b.render()
	await snap.call("bar3")
	b.tab = 3
	b.render()
	await snap.call("bar4")
	_result_screen({"title": "2 место", "text": "Призовое место на трассе Дачи.", "note": "Открыта трасса Рисовые поля.", "bad": false, "finished": true, "rows": ["Гвоздь", "Ты", "Хром", "Мазут", "Рыжий", "Валера", "Сиплый, сход", "Карбюратор"], "ledger": [["Приз за 2 место", 240], ["Нокауты × 2", 48], ["Коп вырублен", 100], ["Ремонт", -30]], "money": 1358, "next": 1})
	await snap.call("result")
	get_tree().quit()

# Puts the rider in front of every new thing on the track and takes a picture: tunnels, overpasses, side roads
func _tour_shots(out: String) -> void:
	sim.bot_peace = true
	for k in 240:
		sim.step(STEP)
	sim.events.clear()
	var me := sim.me
	var spots: Array = []
	for f in sim.road.features:
		match f.kind:
			"tunnel":
				spots.append(["tunnel_in", 0, float(f.s_a) - 70.0, 1.8])
				spots.append(["tunnel_mid", 0, float(f.s_a) + 60.0, 1.8])
			"bridge":
				spots.append(["bridge", 0, float(f.s) - 45.0, 0.6])
	for i in sim.road.branches.size():
		var b: Road = sim.road.branches[i]
		var kind: String = b.kind
		spots.append([kind + "_sign", 0, b.s0 - 120.0, b.side * 5.4])
		spots.append([kind + "_split", 0, b.s0 - 30.0, b.side * 5.4])
		spots.append([kind + "_on", i + 1, b.length * 0.4, 0.0])
	var n := 0
	for sp in spots:
		me.path = sp[1]
		me.s = sp[2]
		me.d = sp[3]
		me.v = 6.0
		me.state = Sim.RIDE
		me.inv = 5.0
		sim._calc_ps(me)
		race_view.cam_d = me.d
		race_view.last_path = me.path
		for k in 12:
			sim.events.clear()
			me.v = 6.0
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%02d_%s.png" % [out, n, sp[0]])
		n += 1
	get_tree().quit()

func _flow_test(track_i: int, bike_id: String, kind: String, out: String) -> void:
	await _start_race_test(track_i, bike_id)
	sim.bot = true
	sim.bot_peace = true
	var snap := func(n: String) -> void:
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, n])
	for k in 240:
		await get_tree().process_frame
	match kind:
		"finish":
			sim.me.s = sim.road.finish_s - 40.0
			sim.me.path = 0
		"busted", "dead", "wrecked":
			sim.me.inv = 0.0
			if kind == "dead":
				sim.me.hp = 1.0
			if kind == "wrecked":
				sim.me.bike_hp = 1.0
			if kind == "busted":
				sim.cops[0].state = Sim.RIDE
				sim.cops[0].s = sim.me.s + 10.0
			sim.crash("car", 150.0 if kind == "dead" else 40.0)
	var t0 := Time.get_ticks_msec()
	while film == null and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	print("film started: ", film != null, " kind ", film_kind, " place ", sim.final_place, " end ", sim.end_kind)
	if film == null:
		get_tree().quit()
		return
	for k in 3:
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 1600:
			await get_tree().process_frame
		await snap.call("film%d" % k)
	_end_film()
	for k in 20:
		await get_tree().process_frame
	await snap.call("result")
	print("money ", S.data.money, " ledger ", film_res.ledger)
	get_tree().quit()

# build 11: a rival arrested and one taken away by ambulance ahead of you, as you ride up to them
func _incident_shots(out: String) -> void:
	sim.bot_peace = true
	for k in 300:
		sim.step(STEP)
	sim.events.clear()
	var me := sim.me
	for i in 2:
		var f: Sim.Rider = sim.foes[i]
		f.path = 0
		f.state = Sim.DOWN
		f.out = true
		f.arrested = i == 0
		f.run_phase = 0
		f.lie_t = 1.0
		f.down_dur = 1e9
		f.v = 0.0
		f.s = me.s + 45.0 + i * 30.0
		f.d = 6.5 if i == 0 else -2.0
		f.fly_s = f.s - 4.0
		f.fly_d = f.d - 0.6
		f.fly_y = 0.18
		f.fly_v = 0.0
		f.fly_vy = 0.0
	var n := 0
	while n < 14:
		for k in 6:
			me.v = min(me.v, 1.0)
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_inc_%02d.png" % [out, n])
		print("frame %d: me %.0f, incidents %d" % [n, me.s, race_view.incidents.size()])
		n += 1
	get_tree().quit()

# build 11: the end-of-race scenes, a frame every second
func _film_shots(out: String, scene: String) -> void:
	sim.bot_peace = true
	for k in 400:
		sim.step(STEP)
	sim.events.clear()
	var me := sim.me
	if scene == "arrest" or scene == "medic":
		sim.crash("car", 120.0)
		for k in 200:
			sim.step(STEP)
		me.run_phase = 0
		me.lie_t = 1.0
	sim.me_parked = true
	hud.visible = false
	var m := race_view.start_movie(scene)
	var n := 0
	var t0 := Time.get_ticks_msec()
	while not m.done and n < 20:
		await get_tree().process_frame
		if m.t >= n * 1.0:
			get_viewport().get_texture().get_image().save_png("%s_%s_%02d.png" % [out, scene, n])
			n += 1
	print("%s: %d frames, scene took %.1f s, real %d ms" % [scene, n, m.t, Time.get_ticks_msec() - t0])
	get_tree().quit()

# build 11: every trick in the air, close up, and the moods after the line
func _b11_shots(out: String) -> void:
	sim.bot_peace = true
	for k in 240:
		sim.step(STEP)
	sim.events.clear()
	var me := sim.me
	var snap := func(n: String) -> void:
		sim.events.clear()
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, n])
		print("%s: air %.1f m trick %s u=%.2f emote %s %.2f state %d phase %s" % [n, me.air_h, me.trick, me.trick_t / max(0.1, me.trick_len), me.emote, me.emote_t, me.state, sim.phase])
	for f in sim.foes:
		f.s = 1e5
	for c in sim.cars:
		c.s = -5000.0
		c.v = 0.0
		c.v0 = 0.1
	sim.peds.clear()
	sim._cross_i = 999
	var kk: Dictionary = sim.road.kickers[0]
	for trick in ["flip", "whip", "seat", "superman", "nacnac", "heel", "nohands"]:
		me.path = 0
		me.s = float(kk.s) - 120.0
		me.d = 1.8
		me.v = me.top
		me.state = Sim.RIDE
		me.inv = 0.0
		me.air = false
		race_view.cam_d = 1.8
		var got := false
		for k in 600:
			me.v = max(me.v, me.top * 0.98)
			sim.step(STEP)
			sim.events.clear()
			await get_tree().process_frame
			if me.air and me.trick != trick:
				me.trick = trick
			if me.air and me.trick_t > me.trick_len * 0.3 and not got:
				got = true
				race_view.debug_close = true
				await snap.call("t_" + trick)
				race_view.debug_close = false
				await snap.call("v_" + trick)
			if got and not me.air:
				break
	# moods after the line
	for mood in [["joy", 1.0], ["angry", 1.0], ["sad", 0.8]]:
		me.s = 900.0
		me.d = 1.8
		me.v = 8.0
		me.air = false
		me.emote = mood[0]
		me.emote_k = mood[1]
		me.emote_t = 0.0
		for k in 20:
			me.v = 8.0
			sim.step(STEP)
			await get_tree().process_frame
		me.emote_t = 1.3
		me.inv = 0.0
		race_view.debug_close = true
		await snap.call("e_" + mood[0])
		race_view.debug_close = false
	get_tree().quit()

# build 10: a jump off a crest, people on a crossing, a slope sign, a rival knocked down on foot
func _b10_shots(out: String) -> void:
	sim.bot_peace = true
	for k in 240:
		sim.step(STEP)
	sim.events.clear()
	var me := sim.me
	var snap := func(n: String) -> void:
		for e in sim.events:
			race_view.handle_event(e)
			hud.handle_event(e)
		sim.events.clear()
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, n])
		print("%s: s=%.0f v=%.0f air=%.1f m" % [n, me.s, sim.dial(me, me.v), me.air_h])
	var place := func(s: float, d: float, v: float) -> void:
		me.path = 0
		me.s = s
		me.d = d
		me.v = v
		me.state = Sim.RIDE
		me.inv = 3.0
		me.air = false
		sim._calc_ps(me)
		race_view.cam_d = d
		for f in sim.foes:
			if not f.is_cop:
				f.s = s + 900.0
	# the jump: flat out over the first crest
	if not sim.road.kickers.is_empty():
		var kk: Dictionary = sim.road.kickers[0]
		place.call(float(kk.s) - 150.0, 1.8, me.top * 0.95)
		var n := 0
		var taken := 0
		for k in 900:
			sim.step(STEP)
			await get_tree().process_frame
			if me.s > float(kk.s) - 30.0 and k % 5 == 0 and taken < 8:
				race_view.debug_close = taken == 2
				await snap.call("jump%d" % taken)
				race_view.debug_close = false
				taken += 1
			if taken >= 8:
				break
	# slope signs
	for i in min(2, sim.road.slopes.size()):
		place.call(float(sim.road.slopes[i][0]) - 100.0, 1.8, 3.0)
		for k in 8:
			me.v = 3.0
			sim.step(STEP)
			await get_tree().process_frame
		await snap.call("slope%d" % i)
	# a crossing with a light and a heavy one on it
	if not sim.road.crossings.is_empty():
		var cs: float = sim.road.crossings[0].s
		sim._cross_i = 999
		sim.peds.clear()
		for h in [false, true]:
			var p := Sim.Ped.new()
			p.s = cs + (0.0 if h else 1.2)
			p.d = -1.0 if h else 4.6
			p.heavy = h
			p.v = 0.0
			p.dir = 1.0
			p.look = 2
			sim.peds.append(p)
		place.call(cs - 40.0, 1.8, 2.0)
		for k in 20:
			me.v = 2.0
			sim.step(STEP)
			await get_tree().process_frame
		await snap.call("crossing")
		# ride into the light one
		sim.bot = false
		sim.inp = {"steer": 0.0, "gas": false, "brake": false, "hand": false, "kick": false}
		me.d = sim.peds[0].d
		me.v = 18.0
		for k in 160:
			sim.step(STEP)
			await get_tree().process_frame
			if sim.peds.size() > 0 and sim.peds[0].state == 1 and k % 8 == 0:
				await snap.call("pedhit%03d" % k)
		sim.bot = true
	# a rival on his feet, running back to his bike
	var f: Sim.Rider = sim.foes[0]
	place.call(1200.0, 1.8, 3.0)
	f.s = 1214.0
	f.d = 5.4
	f.v = 0.0
	f.state = Sim.DOWN
	f.run_phase = 2
	f.run_t = 0.3
	f.fly_s = 1211.0
	f.fly_d = 1.6
	f.down_dur = 0.0
	for k in 10:
		me.v = 3.0
		sim.step(STEP)
		await get_tree().process_frame
	await snap.call("onfoot")
	get_tree().quit()

func _cop_shots(out: String) -> void:
	sim.bot_peace = true
	for k in 300:
		sim.step(STEP)
	sim.events.clear()
	var me := sim.me
	var cop: Sim.Rider = sim.cops[0]
	cop.state = Sim.RIDE
	cop.target = me
	cop.s = me.s + 0.4
	cop.d = me.d + 1.5
	cop.v = me.v
	var frames := [["ride", 0.0], ["back", 0.14], ["swing", 0.27]]
	for fr in frames:
		cop.attack = null if fr[1] == 0.0 else {"t": fr[1], "side": -1, "done": true, "weapon": "baton", "type": "hand"}
		for n in ["", "c"]:
			race_view.debug_close = n == "c"
			for k in 5:
				cop.s = me.s + 0.4
				cop.d = me.d + 1.5
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s_%s%s.png" % [out, fr[0], n])
	get_tree().quit()
