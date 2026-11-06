class_name AccountUi extends Control
# Your account: log in or make one, see who you are, log out. In a browser the fields are the page's own.

signal close_requested

var box: VBoxContainer
var msg := ""
var f_login: LineEdit
var f_pw: LineEdit

func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for key in ["left", "right"]:
		m.add_theme_constant_override("margin_" + key, 18)
	for key in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + key, 10)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(box)
	N.account_changed.connect(render)
	render()

func render() -> void:
	if box == null:
		return
	UiKit.clear(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.add_child(UiKit.button("Назад", func() -> void: close_requested.emit()))
	top.add_child(UiKit.label("Аккаунт", UiKit.big, 28, UiKit.YEL))
	box.add_child(top)
	if N.logged_in():
		box.add_child(UiKit.label("Ты вошёл как %s" % N.login, UiKit.mid, 22, UiKit.PAPER))
		box.add_child(UiKit.label("Прогресс хранится на сервере: зайди этим логином с другого устройства, и всё будет там. Каждый финиш попадает в таблицу рекордов, каждый нокаут в таблицу бойцов.", UiKit.small, 15, UiKit.MUTED, true))
		if N.pending.size() > 0:
			box.add_child(UiKit.label("Ждут отправки заездов: %d. Уйдут, когда будет связь." % N.pending.size(), UiKit.small, 15, UiKit.YEL, true))
		var out := UiKit.button("Выйти", func() -> void:
			N.logout()
			msg = "Вышел. В игре снова твой прогресс без аккаунта."
			render(), UiKit.INK3, UiKit.PAPER, 17)
		out.custom_minimum_size = Vector2(160, 42)
		out.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		box.add_child(out)
	else:
		box.add_child(UiKit.label("Аккаунт хранит прогресс на сервере и ставит тебя в таблицы рекордов и бойцов. Нужны только логин и любой пароль.", UiKit.small, 16, UiKit.PAPER, true))
		if N.web_form_available():
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			for x in [["Войти", false, UiKit.YEL, UiKit.INK], ["Создать аккаунт", true, UiKit.INK3, UiKit.PAPER]]:
				var create: bool = x[1]
				var b := UiKit.button(x[0], func() -> void:
					msg = ""
					N.open_web_form(create, func() -> void: render()), x[2], x[3], 18)
				b.custom_minimum_size = Vector2(190, 46)
				row.add_child(b)
			box.add_child(row)
		else:
			f_login = LineEdit.new()
			f_login.placeholder_text = "Логин"
			f_login.max_length = 20
			f_pw = LineEdit.new()
			f_pw.placeholder_text = "Пароль"
			f_pw.secret = true
			for f in [f_login, f_pw]:
				f.custom_minimum_size = Vector2(320, 40)
				f.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				box.add_child(f)
			var row2 := HBoxContainer.new()
			row2.add_theme_constant_override("separation", 10)
			for x in [["Войти", false], ["Создать аккаунт", true]]:
				var create2: bool = x[1]
				row2.add_child(UiKit.button(x[0], func() -> void: _native(create2), UiKit.YEL if not create2 else UiKit.INK3, UiKit.INK if not create2 else UiKit.PAPER, 17))
			box.add_child(row2)
		box.add_child(UiKit.label("Восстановить пароль нельзя, запомни его. Прогресс без аккаунта не пропадёт: при новом аккаунте он перейдёт в него, а при входе в старый вернётся, когда выйдешь.", UiKit.small, 13, UiKit.MUTED, true))
	if msg != "":
		box.add_child(UiKit.label(msg, UiKit.mid, 15, UiKit.YEL, true))

func _native(create: bool) -> void:
	var user: String = f_login.text.strip_edges() if f_login != null else ""
	var pw: String = f_pw.text if f_pw != null else ""
	msg = "Секунду…"
	render()
	N.login_with(user, pw, create, func(err: String) -> void:
		msg = err
		render())
