class_name UiKit extends RefCounted
# Small helpers so every screen looks the same and every list scrolls the same way on a phone.

const INK := Color("#17161c")
const INK2 := Color("#24232b")
const INK3 := Color("#2f2e38")
const PAPER := Color("#f3eedf")
const MUTED := Color("#a9a7b4")
const YEL := Color("#ffc81f")
const RED := Color("#d9232e")
const GRN := Color("#2aa84f")

static var big: Font
static var mid: Font
static var small: Font
static var drag_total := 0.0

static func is_phone() -> bool:
	return OS.has_feature("web_ios") or OS.has_feature("web_android") or OS.has_feature("mobile")

static func has_touch() -> bool:
	return is_phone() or DisplayServer.is_touchscreen_available()

static func label(txt: String, f: Font = null, sz := 16, col := PAPER, wrap := false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", f if f != null else small)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# readable over the 3D picture
static func outlined(l: Label, width := 5) -> Label:
	l.add_theme_constant_override("outline_size", width)
	l.add_theme_color_override("font_outline_color", INK)
	return l

static func box(col: Color, radius := 0, border_col := Color.TRANSPARENT, border := 0, mx := 10, my := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	s.border_color = border_col
	s.set_border_width_all(border)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	return s

# A press only counts if the finger did not drag the list
static func button(txt: String, cb: Callable, bg := INK3, fg := PAPER, sz := 16, f: Font = null) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_stylebox_override("normal", box(bg))
	b.add_theme_stylebox_override("hover", box(bg.lightened(0.07)))
	b.add_theme_stylebox_override("pressed", box(bg.lightened(0.16)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, fg)
	b.add_theme_font_override("font", f if f != null else mid)
	b.add_theme_font_size_override("font_size", sz)
	b.focus_mode = Control.FOCUS_NONE
	b.button_down.connect(func() -> void: UiKit.drag_total = 0.0)
	b.pressed.connect(func() -> void:
		if UiKit.drag_total < 14.0:
			cb.call())
	return b

# Round road-sign button: a bike's cc. Green ring = you own it, red = for sale, grey = league closed
static func sign_btn(txt: String, cb: Callable, ring: Color, on: bool, size := 42) -> Button:
	var b := button(txt, cb, PAPER if on else Color("#e6e1d2"), INK, 13 if txt.length() < 4 else 11)
	var st := box(PAPER if on else Color("#d8d3c4"), size, ring, 5, 0, 0)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("pressed", st)
	b.custom_minimum_size = Vector2(size, size)
	return b

static func sign_label(txt: String, ring: Color, size := 42) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(PAPER, size, ring, 5, 0, 0))
	p.custom_minimum_size = Vector2(size, size)
	var l := label(txt, mid, 13 if txt.length() < 4 else 11, INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

static func swatch(col: Color, cb: Callable, on: bool, locked := false) -> Button:
	var b := button("$" if locked else "", cb, col, INK if col.get_luminance() > 0.5 else PAPER, 13)
	var st := box(col, 4, YEL if on else Color(1, 1, 1, 0.25), 3 if on else 1, 0, 0)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("pressed", st)
	b.custom_minimum_size = Vector2(38, 34)
	return b

static func panel(col := INK2, mx := 10, my := 6) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(col, 0, Color.TRANSPARENT, 0, mx, my))
	return p

# Stat bar with a name and a value
static func stat(name_s: String, value: String, frac: float, col := YEL, mark := -1.0) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	var h := HBoxContainer.new()
	h.add_child(label(name_s, small, 13, MUTED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	h.add_child(label(value, mid, 13, PAPER))
	v.add_child(h)
	var bar := Bar.new()
	bar.frac = clamp(frac, 0.0, 1.0)
	bar.col = col
	bar.mark = mark
	bar.custom_minimum_size = Vector2(0, 6)
	v.add_child(bar)
	return v

class Bar extends Control:
	var frac := 0.0
	var col := Color.WHITE
	var mark := -1.0
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * frac, size.y)), col)
		if mark >= 0.0:
			draw_rect(Rect2(size.x * clamp(mark, 0.0, 1.0) - 1.0, -1.0, 2.0, size.y + 2.0), Color.WHITE)

static func pips(level: int, total: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	for k in total:
		var c := ColorRect.new()
		c.color = YEL if k < level else Color(1, 1, 1, 0.16)
		c.custom_minimum_size = Vector2(16, 5)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(c)
	return h

static func heading(txt: String) -> Label:
	var l := label(txt.to_upper(), mid, 13, YEL)
	return l

static func expand() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()
