extends Node
# Screens: menu -> choose bike -> race -> result. Test build: no money or garage yet, those move over next.

const STEP := 1.0 / 60.0
const BUILD_NO := 4
const TEST_GEAR := [[2, 2], [4, 2], [4, 3]]

var ui_layer: CanvasLayer
var hud_layer: CanvasLayer
var hud: Hud
var menu: Control
var overlay: Control
var view_rect: TextureRect
var view_port: SubViewport
var race_view: RaceView
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
	get_viewport().size_changed.connect(_fit_resolution)
	_fit_resolution()
	var args := OS.get_cmdline_user_args()
	if args.size() >= 3 and args[0] == "shot":
		auto_mode = "shot"
		_start_race(int(args[1]), args[2])
	else:
		_show_menu()

func _fit_resolution() -> void:
	var win: Vector2i = DisplayServer.window_get_size()
	if quality_max < 0.0:
		var phone: bool = OS.has_feature("web_ios") or OS.has_feature("web_android") or OS.has_feature("mobile")
		quality_max = 720.0 / max(win.y, 1) if phone else 1080.0 / max(win.y, 1)
		quality_max = min(quality_max, 1.0)
		quality = quality_max
		view_port.msaa_3d = Viewport.MSAA_2X if phone else Viewport.MSAA_4X
	view_port.size = Vector2i(max(16, int(win.x * quality)), max(16, int(win.y * quality)))

# ---------- menu ----------
func _clear_ui() -> void:
	for c in menu.get_children():
		c.queue_free()

func _bg(col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(r)
	return r

func _style(col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _button(txt: String, cb: Callable, col := Color("#2a2a32"), fg := Color("#f3eedf"), sz := 18) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_stylebox_override("normal", _style(col))
	b.add_theme_stylebox_override("hover", _style(col.lightened(0.08)))
	b.add_theme_stylebox_override("pressed", _style(col.lightened(0.18)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_font_size_override("font_size", sz)
	b.pressed.connect(cb)
	return b

func _label(txt: String, f: Font, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	return l

func _page() -> VBoxContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + k, 18)
	menu.add_child(m)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	m.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	return v

func _show_menu() -> void:
	_clear_ui()
	_bg(Color("#17161c"))
	var v := _page()
	var head := HBoxContainer.new()
	head.add_child(_label("ГАЗ И ЦЕПЬ", font_big, 46, Color("#ffc81f")))
	var tag := _label("  3D · сборка %d" % BUILD_NO, font_small, 18, Color("#a9a7b4"))
	head.add_child(tag)
	v.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	for i in D.tracks.size():
		var t: Dictionary = D.tracks[i]
		var lg: Dictionary = D.leagues[int(t.cat)]
		var b := _button("%s\n%s" % [t.name, lg.full], _show_bikes.bind(i), ["#3a3524", "#24344a", "#4a2424"][int(t.cat)])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 64)
		grid.add_child(b)

func _show_bikes(track_i: int) -> void:
	_clear_ui()
	_bg(Color("#17161c"))
	var v := _page()
	var t: Dictionary = D.tracks[track_i]
	var head := HBoxContainer.new()
	head.add_child(_button("Назад", _show_menu))
	var l := _label("  " + str(t.name) + ": на чём едем", font_mid, 22, Color("#f3eedf"))
	head.add_child(l)
	v.add_child(head)
	for b in D.bikes:
		if int(b.cat) != int(t.cat):
			continue
		var txt := "%s %dcc   %d км/ч · %s" % [b.name, int(b.cc), int(b.kmh), b.type]
		var btn := _button(txt, _start_race.bind(track_i, b.id))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 50)
		v.add_child(btn)

# ---------- race ----------
func _start_race(track_i: int, bike_id: String) -> void:
	_clear_ui()
	pending_track = track_i
	pending_bike = bike_id
	_bg(Color("#17161c"))
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(c)
	c.add_child(_label("Строим трассу…", font_big, 36, Color("#ffc81f")))
	await get_tree().process_frame
	await get_tree().process_frame
	_end_race_nodes()
	sim = Sim.new()
	var g: Array = TEST_GEAR[int(D.tracks[track_i].cat)]
	sim.setup(track_i, bike_id, {}, g[0], g[1], 0, 5, randi())
	race_view = RaceView.new()
	view_port.add_child(race_view)
	await race_view.build(sim)
	hud = Hud.new()
	hud_layer.add_child(hud)
	hud.set_fonts(font_big, font_mid, font_small)
	hud.sim = sim
	hud.pause_pressed.connect(_toggle_pause)
	audio.setup(sim.me.st)
	_clear_ui()
	running = true
	paused = false
	acc = 0.0
	if auto_mode == "shot":
		_run_shots()

func _end_race_nodes() -> void:
	running = false
	if race_view != null:
		race_view.queue_free()
		race_view = null
	if hud != null:
		hud.queue_free()
		hud = null
	audio.stop_all()

func _toggle_pause() -> void:
	if sim == null or not running:
		return
	paused = not paused
	if paused:
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
	v.add_child(_button("Заново", _start_race.bind(pending_track, pending_bike)))
	v.add_child(_button("В меню", _quit_to_menu))

func _quit_to_menu() -> void:
	_end_race_nodes()
	sim = null
	_show_menu()

func _show_result(kind: String) -> void:
	audio.stop_all()
	_clear_ui()
	_bg(Color(0, 0, 0, 0.62))
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	c.add_child(v)
	var title := "Финиш"
	var sub := ""
	match kind:
		"finish":
			title = "Место %d из 8" % sim.final_place
			sub = "Время %d:%02d · нокаутов %d · падений %d" % [int(sim.stats.t_finish) / 60, int(sim.stats.t_finish) % 60, sim.stats.ko, sim.me.falls]
		"dead":
			title = "Скорая уже едет"
			sub = "Падение на %d км/ч. Защита решает." % int(sim.me.fall_kmh)
		"busted":
			title = "Арест"
			sub = "Упал рядом с копом"
		"wrecked":
			title = "Байк разбит"
			sub = "Дальше пешком"
	v.add_child(_label(title, font_big, 48, Color("#ffc81f")))
	v.add_child(_label(sub, font_mid, 20, Color("#f3eedf")))
	v.add_child(_button("Ещё раз", _start_race.bind(pending_track, pending_bike), Color("#ffc81f"), Color("#16151b"), 22))
	v.add_child(_button("В меню", _quit_to_menu))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and running:
		if event.physical_keycode == KEY_ESCAPE or event.physical_keycode == KEY_P:
			_toggle_pause()

func _process(delta: float) -> void:
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
	for e in sim.events:
		race_view.handle_event(e)
		audio.handle_event(e)
		hud.handle_event(e)
		if e[0] == "over":
			running = false
			_show_result(e[1])
	sim.events.clear()
	var near := 1e9
	for c in sim.cops:
		if c.state == Sim.RIDE:
			near = min(near, abs(c.s - sim.me.s))
	audio.update(delta, sim.me.rpm, sim.me.gas_on, sim.me.state == Sim.RIDE, sim.me.slide and sim.phase == "race", near)
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
	for k in 120:
		sim.step(STEP)
	sim.events.clear()
	await snap.call("down")
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
