class_name ScrollList extends ScrollContainer
# A list that scrolls under the finger even when the finger starts on a button, and with the wheel on a computer.

var box: VBoxContainer

func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 5)
	add_child(box)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			UiKit.drag_total = 0.0
	elif event is InputEventScreenDrag:
		UiKit.drag_total += event.relative.length()
		if get_global_rect().has_point(event.position):
			scroll_vertical -= int(event.relative.y)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available():
			UiKit.drag_total = 0.0
		if get_global_rect().has_point(event.position):
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				scroll_vertical -= 40
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				scroll_vertical += 40

func keep_scroll() -> void:
	var y := scroll_vertical
	await get_tree().process_frame
	scroll_vertical = y
