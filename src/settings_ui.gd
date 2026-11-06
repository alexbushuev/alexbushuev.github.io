class_name SettingsUi extends Control
# Sound and controls. Keys work like the 2D game: a main and a spare key for every action, a taken key swaps places.

signal close_requested

class VolumeBar extends Control:
	signal moved(v: float)
	signal let_go
	var value := 0.7
	var held := false

	func _init() -> void:
		custom_minimum_size = Vector2(0, 44)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			held = event.pressed
			if held:
				_set_from(event.position.x)
			else:
				let_go.emit()
		elif event is InputEventMouseMotion and held:
			_set_from(event.position.x)

	func _set_from(x: float) -> void:
		var v: float = round(clamp((x - 12.0) / max(1.0, size.x - 24.0), 0.0, 1.0) * 20.0) / 20.0
		if v != value:
			value = v
			moved.emit(v)
			queue_redraw()

	func _draw() -> void:
		var y: float = size.y * 0.5
		draw_rect(Rect2(12.0, y - 4.0, size.x - 24.0, 8.0), UiKit.INK3)
		var x: float = 12.0 + (size.x - 24.0) * value
		draw_rect(Rect2(12.0, y - 4.0, x - 12.0, 8.0), UiKit.YEL)
		draw_rect(Rect2(x - 11.0, y - 16.0, 22.0, 32.0), UiKit.PAPER)

var audio: GameAudio
var wait: Array = []     # [action, slot] while a key button waits for a press
var msg := ""
var sound_box: Control
var vol_l: Label
var bar: VolumeBar
var list: ScrollList

func open(a: GameAudio) -> void:
	audio = a
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
	top.add_theme_constant_override("separation", 10)
	top.add_child(UiKit.button("Назад", func() -> void: close_requested.emit()))
	top.add_child(UiKit.label("Настройки", UiKit.big, 28, UiKit.YEL))
	v.add_child(top)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.8
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(left)
	left.add_child(UiKit.heading("Звук"))
	sound_box = HBoxContainer.new()
	sound_box.add_theme_constant_override("separation", 8)
	left.add_child(sound_box)
	vol_l = UiKit.label("", UiKit.mid, 16, UiKit.PAPER)
	left.add_child(vol_l)
	bar = VolumeBar.new()
	bar.value = float(S.data.volume)
	bar.moved.connect(_volume_moved)
	bar.let_go.connect(func() -> void:
		S.persist()
		audio.ui("ching"))
	left.add_child(bar)
	left.add_child(UiKit.label("Отпусти ползунок, и прозвучит пример громкости.", UiKit.small, 13, UiKit.MUTED, true))
	list = ScrollList.new()
	list.size_flags_stretch_ratio = 1.2
	cols.add_child(list)
	_render_sound()
	_render_controls()

func _render_sound() -> void:
	UiKit.clear(sound_box)
	var on: bool = bool(S.data.sound)
	var b1 := UiKit.button("Включён", func() -> void: _set_sound(true), UiKit.YEL if on else UiKit.INK3, UiKit.INK if on else UiKit.PAPER, 16)
	var b2 := UiKit.button("Выключен", func() -> void: _set_sound(false), UiKit.INK3 if on else UiKit.YEL, UiKit.PAPER if on else UiKit.INK, 16)
	for b in [b1, b2]:
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sound_box.add_child(b)
	vol_l.text = "Громкость %d%%" % int(round(float(S.data.volume) * 100.0))
	vol_l.modulate = Color.WHITE if on else Color(1, 1, 1, 0.5)

func _set_sound(on: bool) -> void:
	S.data.sound = on
	S.persist()
	audio.apply_settings()
	_render_sound()
	if on:
		audio.ui("ching")

func _volume_moved(v: float) -> void:
	S.data.volume = v
	audio.apply_settings()
	vol_l.text = "Громкость %d%%" % int(round(v * 100.0))

func _render_controls() -> void:
	UiKit.clear(list.box)
	list.box.add_child(UiKit.heading("Управление"))
	if UiKit.is_phone():
		list.box.add_child(UiKit.label("Газ работает сам, отпустил тормоз и поехал.", UiKit.mid, 16, UiKit.PAPER, true))
		list.box.add_child(UiKit.label("Левый палец: руль влево и вправо.", UiKit.small, 15, UiKit.PAPER, true))
		list.box.add_child(UiKit.label("Правый палец: тормоз, рука, нога.", UiKit.small, 15, UiKit.PAPER, true))
		list.box.add_child(UiKit.label("Клавиши настраиваются, когда играешь с компьютера.", UiKit.small, 13, UiKit.MUTED, true))
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(UiKit.label("", UiKit.small, 13, UiKit.MUTED))
	grid.add_child(_col_head("Основная"))
	grid.add_child(_col_head("Доп."))
	for x in S.KEY_ACTIONS:
		var name_l := UiKit.label(x[1], UiKit.mid, 15, UiKit.PAPER)
		name_l.custom_minimum_size = Vector2(70, 0)
		grid.add_child(name_l)
		for slot in 2:
			grid.add_child(_key_button(x[0], slot))
	list.box.add_child(grid)
	var note := "Жми клавишу. Delete уберёт её, повторное нажатие на кнопку отменит." if not wait.is_empty() else msg
	var note_l := UiKit.label(note, UiKit.small, 13, UiKit.YEL, true)
	list.box.add_child(note_l)
	list.box.add_child(UiKit.button("Вернуть как было", func() -> void:
		wait = []
		S.reset_keys()
		msg = "Вернул клавиши по умолчанию."
		_render_controls(), UiKit.INK2, UiKit.PAPER, 14))
	list.keep_scroll()

func _col_head(t: String) -> Label:
	var l := UiKit.label(t, UiKit.small, 13, UiKit.MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _key_button(a: String, slot: int) -> Button:
	var waiting: bool = wait == [a, slot]
	var code: Variant = S.data.keys[a][slot]
	var txt: String = "Жми…" if waiting else S.key_label(code)
	var b := UiKit.button(txt, func() -> void:
		msg = ""
		wait = [] if wait == [a, slot] else [a, slot]
		_render_controls(), UiKit.YEL if waiting else UiKit.INK3, UiKit.INK if waiting else (UiKit.PAPER if code != null else UiKit.MUTED), 14)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 30)
	return b

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var code: int = event.physical_keycode
	if wait.is_empty():
		if code == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close_requested.emit()
		return
	get_viewport().set_input_as_handled()
	var key_name := "" if code == KEY_DELETE or code == KEY_BACKSPACE else OS.get_keycode_string(code)
	if key_name == "" and code != KEY_DELETE and code != KEY_BACKSPACE:
		return
	var w: Array = wait
	wait = []
	msg = S.assign_key(w[0], w[1], key_name)
	_render_controls()
