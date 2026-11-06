extends Node
# Sound levels by arithmetic, keys, phone deck. godot --headless --path . res://tests/settings_test.tscn
# The real recorded output is checked with tests/audio_probe and tools/audio_measure.py.

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _ready() -> void:
	D.load_all()
	S.path = "user://settings_test_save.json"
	S.reset_for_test()
	_sound()
	_keys()
	await _deck()
	print("FAILS: ", fails)
	get_tree().quit()

func _sound() -> void:
	var tops: Array = []
	for lg in D.leagues:
		var st := {"cyl": int(lg.cyl), "idle": lg.idle, "red": lg.red, "f_lo": lg.fLo, "f_hi": lg.fHi}
		for rr in [0.1, 0.3, 0.5, 0.7, 0.9, 1.0]:
			var parts := GameAudio.engine_partials(rr, st)
			var res := GameAudio.partials_level(parts, GameAudio.engine_pitch(rr, st))
			if rr == 1.0:
				tops.append(res[0])
			print("%-18s rpm %3d%%  firing %3.0f Hz  >2 kHz %2d%%  partials %d" % [lg.full, int(rr * 100), GameAudio.engine_pitch(rr, st) * GameAudio.BASE_HZ, int(res[1] * 100), parts.size()])
			check(res[1] < 0.25, "%s rpm %d: %d%% above 2 kHz" % [lg.full, int(rr * 100), int(res[1] * 100)])
	S.data.volume = 1.0
	check(abs(S.volume_db()) < 0.01, "100% is 0 dB")
	S.data.volume = 0.5
	check(abs(S.volume_db() + 12.04) < 0.1, "50% is -12 dB")
	S.data.volume = 0.0
	check(not S.sound_on(), "0% is off")
	S.data.volume = 0.7
	S.data.sound = false
	check(not S.sound_on(), "switch off")
	S.data.sound = true
	var a := GameAudio.new()
	add_child(a)
	a.apply_settings()
	a.setup({"cyl": 4, "idle": 2600, "red": 15000, "f_lo": 900, "f_hi": 4200})
	a.update(0.016, 1.0, true, true, false, 1e9)
	check(float(a.gains.e2) > 0.0, "engine plays")
	check(float(a.gains.e0) == 0.0, "only the layers for these revs play")
	S.data.sound = false
	a.apply_settings()
	a.update(0.016, 1.0, true, true, false, 1e9)
	for id in a.gains:
		check(float(a.gains[id]) == 0.0, "switched off is silent")
	S.data.sound = true
	a.apply_settings()
	a.update(0.016, 1.0, true, true, false, 1e9)
	a.quiet()
	for id in a.gains:
		check(float(a.gains[id]) == 0.0, "pause is silent")
	a.update(0.016, 1.0, true, true, false, 1e9)
	check(float(a.gains.e2) > 0.0, "back after pause")
	var loud: float = float(a.gains.e2)
	S.data.volume = 0.35
	a.apply_settings()
	a.update(0.016, 1.0, true, true, false, 1e9)
	check(abs(linear_to_db(float(a.gains.e2) / loud) + 12.04) < 1.0, "half the slider, 12 dB down")
	S.data.volume = 0.7
	a.apply_settings()
	a.handle_event(["siren", true])
	a.update(0.016, 1.0, true, true, false, 5.0)
	check(float(a.gains.siren) > 0.0, "siren plays")
	a.update(0.016, 1.0, true, true, false, 500.0)
	check(float(a.gains.siren) == 0.0, "far cop is not heard")
	a.stop_all()
	check(a.gains.is_empty(), "stop_all")
	a.update(0.016, 1.0, true, true, false, 5.0)
	a.queue_free()

func _keys() -> void:
	S.reset_for_test()
	check(S.data.keys.gas == ["Up", "W"], "default gas keys " + str(S.data.keys.gas))
	check(S.action_of_key(KEY_UP) == "gas", "up is gas")
	check(S.action_of_key(KEY_ESCAPE) == "pause", "esc is pause")
	check(S.key_label("Space") == "Пробел", "key name")
	# a free key
	S.assign_key("gas", 0, "Space")
	check(S.action_of_key(KEY_SPACE) == "gas" and S.action_of_key(KEY_UP) == "", "free key replaces")
	# a taken key swaps
	var m := S.assign_key("gas", 0, "Z")
	check(S.action_of_key(KEY_Z) == "gas" and S.data.keys.hand[0] == "Space", "taken key swaps: " + str(S.data.keys.hand))
	check(m.contains("Рука"), "swap told: " + m)
	# removing: only the last key of an action stays
	S.assign_key("kick", 1, "")
	check(S.data.keys.kick[1] == null, "spare removed")
	m = S.assign_key("kick", 0, "")
	check(S.data.keys.kick[0] != null and m.contains("хотя бы"), "last key stays")
	# cannot take the only key of another action into an empty slot
	m = S.assign_key("left", 1, "")
	var only: Variant = S.data.keys.kick[0]
	m = S.assign_key("left", 1, str(only))
	check(S.data.keys.kick[0] == only and m.contains("единственная"), "only key protected: " + m)
	# survives a reload
	S.assign_key("brake", 0, "Space")
	S.persist()
	S.load_save()
	check(S.data.keys.brake[0] == "Space" and S.action_of_key(KEY_SPACE) == "brake", "keys survive reload")
	# a save from before there were settings
	var f := FileAccess.open(S.path, FileAccess.WRITE)
	f.store_string('{"v":1,"money":500,"sound":false}')
	f.close()
	S.load_save()
	check(S.data.money == 500 and S.data.sound == false and float(S.data.volume) == 0.7 and S.data.keys.gas == ["Up", "W"], "old save loads")
	S.reset_keys()
	check(S.action_of_key(KEY_UP) == "gas", "reset")

func _deck() -> void:
	S.reset_for_test()
	var sim := Sim.new()
	sim.setup(0, "strek", {}, 0, 0, 0, 0, 1)
	var hud := Hud.new()
	add_child(hud)
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = Vector2(844, 390)
	hud.sim = sim
	hud._layout()
	var ids: Array = []
	for b in hud.buttons:
		ids.append(b.id)
		check(b.rect.position.x >= 0.0 and b.rect.end.x <= 844.0 and b.rect.position.y >= 0.0 and b.rect.end.y <= 390.0, b.id + " on screen")
	check(not ("gas" in ids), "no gas button on the deck")
	for id in ["left", "right", "brake", "hand", "kick", "pause"]:
		check(id in ids, id + " on the deck")
	for b in hud.buttons:
		if b.id in ["left", "right"]:
			check(b.rect.end.x < 422.0, b.id + " left half")
		elif b.id != "pause":
			check(b.rect.position.x > 422.0, b.id + " right half")
		for o in hud.buttons:
			if o != b:
				check(not b.rect.intersects(o.rect), "%s overlaps %s" % [b.id, o.id])
	hud.touch_mode = true
	sim.phase = "count"
	hud.read_input()
	check(not sim.inp.gas, "no gas during the countdown")
	sim.phase = "race"
	hud.read_input()
	check(sim.inp.gas and not sim.inp.brake, "gas by itself on a phone")
	hud.pressed["brake"] = true
	hud.read_input()
	check(sim.inp.brake and not sim.inp.gas, "brake cuts the gas")
	hud.pressed.clear()
	hud.pressed["hand"] = true
	hud.read_input()
	check(sim.inp.hand and sim.inp.gas, "hit and gas together")
	hud.pressed.clear()
	# a keyboard takes over from the touch deck
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_UP
	ev.pressed = true
	hud._input(ev)
	check(not hud.touch_mode, "key press switches to keyboard")
	hud.read_input()
	check(not sim.inp.gas or Input.is_physical_key_pressed(KEY_UP), "keyboard mode has no auto gas")
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	check(S.key_down("gas"), "key is read")
	hud.read_input()
	check(sim.inp.gas, "gas key works")
	var up := InputEventKey.new()
	up.physical_keycode = KEY_UP
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	hud.read_input()
	check(not sim.inp.gas, "key released, no gas")
	var t := InputEventScreenTouch.new()
	t.pressed = true
	t.index = 0
	t.position = Vector2(30, 350)
	hud._input(t)
	check(hud.touch_mode and hud.pressed.has("left"), "touch switches back")
	hud.set_active(false)
	check(hud.pressed.is_empty() and not hud.is_processing_input(), "pause releases the deck")
	hud.queue_free()
	await get_tree().process_frame
