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
	_race_count()
	print("FAILS: ", fails)
	get_tree().quit()

func _sound() -> void:
	var tops: Array = []
	for b in D.bikes:
		var st := D.rider_stats(b, {}, 0, 0)
		for rr in [0.2, 0.6, 1.0]:
			var pitch := GameAudio.engine_pitch(rr, st)
			var parts := GameAudio.engine_partials(rr, st)
			var res := GameAudio.partials_level(parts, pitch)
			var hz: float = pitch * GameAudio.BASE_HZ
			if rr == 1.0:
				print("%-10s %4dcc  note at redline %3.0f Hz, half note %3.0f Hz, above 1 kHz %2d%%" % [b.name, int(b.cc), hz, hz / 2.0, int(res[1] * 100)])
				tops.append(hz)
			check(res[1] < 0.35, "%s rpm %d: %d%% above 1 kHz" % [b.name, int(rr * 100), int(res[1] * 100)])
			check(hz < 215.0, "%s rpm %d: the note is %d Hz, a whine" % [b.name, int(rr * 100), int(hz)])
	S.data.volume = 1.0
	check(abs(S.volume_db()) < 0.01, "100% is 0 dB")
	S.data.volume = 0.5
	check(abs(S.volume_db() + 12.04) < 0.1, "50% is -12 dB")
	S.data.volume = 0.0
	check(not S.sound_on(), "0% is off")
	S.data.volume = 0.8
	S.data.sound = false
	check(not S.sound_on(), "switch off")
	S.data.sound = true
	var a := GameAudio.new()
	add_child(a)
	a.apply_settings()
	a.setup(D.rider_stats(D.bike_by_id["tsunami"], {}, 0, 0))
	a.update(0.016, 1.0, true, true, false, 1e9)
	check(float(a.gains.e1) > 0.0, "engine plays")
	check(float(a.gains.e0) == 0.0, "only the layer for these revs plays")
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
	check(float(a.gains.e1) > 0.0, "back after pause")
	for k in 40:
		a.update(0.016, 1.0, true, true, false, 1e9)
	var loud: float = float(a.gains.e1)
	a.say("cop1", 0)
	check(a.voice_player.playing or a.duck_voice_t > 0.0, "a line plays")
	for k in 20:
		a.update(0.016, 1.0, true, true, false, 1e9)
	check(float(a.gains.e1) < loud * 0.6, "engine steps back for a voice")
	a.voice_player.stop()
	a.duck_voice_t = 0.0
	for k in 60:
		a.update(0.016, 1.0, true, true, false, 1e9)
	S.data.vol_voice = 0.0
	a.apply_settings()
	a.say("cop1", 0)
	check(not a.voice_player.playing and a.duck_voice_t == 0.0, "voices off")
	S.data.vol_voice = 1.0
	S.data.vol_engine = 0.5
	a.apply_settings()
	for k in 60:
		a.update(0.016, 1.0, true, true, false, 1e9)
	check(abs(linear_to_db(float(a.gains.e1) / loud) + 12.04) < 1.0, "engine slider")
	S.data.vol_engine = 1.0
	a.apply_settings()
	var was: float = float(S.data.volume)
	S.data.volume = was * 0.5
	a.apply_settings()
	for k in 60:
		a.update(0.016, 1.0, true, true, false, 1e9)
	check(abs(linear_to_db(float(a.gains.e1) / loud) + 12.04) < 1.0, "half the slider, 12 dB down")
	S.data.volume = was
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
	check(S.data.money == 500 and S.data.sound == false and float(S.data.volume) == 0.8 and float(S.data.vol_engine) == 1.0 and S.data.keys.gas == ["Up", "W"], "old save loads")
	S.reset_keys()
	check(S.action_of_key(KEY_UP) == "gas", "reset")

func _race_count() -> void:
	var sim := Sim.new()
	sim.setup(0, "strek", {}, 0, 0, 0, 0, 1)
	check(sim.racers_left() == 8, "eight start: %d" % sim.racers_left())
	var first: Sim.Rider = null
	for f in sim.foes:
		if not f.is_cop:
			first = f
			break
	first.s = sim.me.s + 50.0
	sim._calc_ps(first)
	var before := sim.live_place()
	first.out = true
	check(sim.racers_left() == 7, "one out: %d" % sim.racers_left())
	check(sim.live_place() == before - 1, "someone out ahead no longer counts for your place")
	# a line says who is talking so the right voice plays
	var cop: Sim.Rider = sim.cops[0]
	sim.t = 100.0
	sim.say_at = 0.0
	sim.events.clear()
	sim._say(cop, 1.0)
	var e: Array = sim.events[0]
	check(e[0] == "say" and e[2] == "cop1" and FileAccess.file_exists("res://audio/voices/%s_%d.wav" % [e[2], e[3]]), "cop line has a clip: " + str(e))
	for id in D.rivals:
		for i in D.rivals[id].say.size():
			check(FileAccess.file_exists("res://audio/voices/%s_%d.wav" % [id, i]), "clip %s %d" % [id, i])
	for c in D.sound.cops:
		for i in c.say.size():
			check(FileAccess.file_exists("res://audio/voices/%s_%d.wav" % [c.id, i]), "clip %s %d" % [c.id, i])

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
