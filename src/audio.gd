class_name GameAudio extends Node
# All sound is synthesised at start, so the download stays small. Engine pitch follows real firing frequency.

const RATE := 22050
const LOOP := 880                 # samples in a loop: four firing periods at pitch 1
const BASE_HZ := RATE * 4.0 / LOOP
const TONE_RPM: Array[float] = [0.15, 0.55, 1.0]    # the engine note is three layers, each voiced for its own revs
const TONE_CAP := 1900.0          # nothing strong above this: 2-5 kHz is where the ear hurts first
# What the ear gets with the volume slider at 100 %, dB(A) below full scale. tests/audio_probe measures the real output.
const DBA_LOW := -30.0
const DBA_TOP := -26.0
const OFF_GAS_DB := -8.0
const FX_DB := -8.0
const SIREN_GAIN := 0.076
const SQUEAL_GAIN := 0.075

var js: Variant = null            # on the web the page plays the loops: Godot's own web loop clicks at every pass
var loops := {}                   # id -> player, everywhere else
var gains := {}                   # id -> gain the loop was last given
var layer_k: Array[float] = []    # gain that brings a layer to 0 dB(A)
var siren_on := false
var pool: Array[AudioStreamPlayer] = []
var cache := {}
var st: Dictionary = {}
var dip := 0.0
var enabled := true
var master_db := 0.0
var load_now := 0.0
var clock := 0.0
var _pitch_now := 1.0
var ui_player: AudioStreamPlayer
var ui_sounds := {}

func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	var b := PackedByteArray()
	b.resize(samples.size() * 2)
	for i in samples.size():
		b.encode_s16(i * 2, int(clamp(samples[i], -1.0, 1.0) * 32000.0))
	w.data = b
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

# ---------- engine note ----------
static func a_gain(f: float) -> float:
	var f2 := f * f
	var r := (12194.0 * 12194.0 * f2 * f2) / ((f2 + 424.36) * sqrt((f2 + 11599.3) * (f2 + 544496.4)) * (f2 + 148693636.0))
	return r * 1.2589

static func engine_pitch(rpm: float, s: Dictionary) -> float:
	var rpm_real: float = lerp(float(s.idle), float(s.red), clamp(rpm, 0.0, 1.0))
	return clamp(rpm_real / 60.0 * float(s.cyl) * 0.5 / BASE_HZ, 0.1, 6.0)

# One layer as a list of [cycles in the loop, amplitude]. Four cycles are one firing period, so m=4 is the firing note,
# m=2 the half-order growl, and the few others are the unevenness between strokes. Same voicing as the 2D game.
static func engine_partials(rpm: float, s: Dictionary) -> Array:
	var f0: float = engine_pitch(rpm, s) * BASE_HZ / 4.0
	var cut: float = lerp(float(s.f_lo), min(float(s.f_hi), TONE_CAP), rpm)
	var cyl := int(s.cyl)
	var rough: float = 0.28 if cyl == 1 else (0.16 if cyl == 2 else 0.06)
	var out: Array = []
	for m in range(1, 121):
		var h: float = m / 4.0
		var amp := 0.0
		if m % 4 == 0:
			amp = (1.0 if int(h) % 2 == 1 else 0.72) / (1.0 + 0.24 * h)
		elif m == 2:
			amp = 0.34
		elif m < 12:
			amp = rough / (1.0 + 0.24 * h)
		else:
			continue
		var f: float = m * f0
		amp /= sqrt(1.0 + pow(f / cut, 4.0))     # the 2D game's low-pass, steeper
		amp /= sqrt(1.0 + pow(70.0 / f, 4.0))    # sub-bass nobody hears on a phone only eats headroom
		if amp > 0.004:
			out.append([m, amp])
	return out

# Level in dB(A) and the part of it above 2 kHz, for partials of amplitude scaled to the loop's full scale
static func partials_level(parts: Array, pitch: float) -> Array:
	var f0: float = pitch * BASE_HZ / 4.0
	var all := 0.0
	var high := 0.0
	for p in parts:
		var f: float = p[0] * f0
		var e: float = pow(p[1] * a_gain(f), 2.0) / 2.0
		all += e
		if f >= 2000.0:
			high += e
	return [10.0 * log(max(all, 1e-12)) / log(10.0), high / max(all, 1e-12)]

static func tone_mix(rpm: float) -> Array[float]:
	var x: float = clamp(rpm, TONE_RPM[0], 1.0)
	if x <= TONE_RPM[1]:
		var k: float = (x - TONE_RPM[0]) / (TONE_RPM[1] - TONE_RPM[0])
		return [1.0 - k, k, 0.0]
	var k2: float = (x - TONE_RPM[1]) / (TONE_RPM[2] - TONE_RPM[1])
	return [0.0, 1.0 - k2, k2]

func _engine_layer(rpm: float, s: Dictionary) -> PackedFloat32Array:
	var parts := engine_partials(rpm, s)
	var table := PackedFloat32Array()
	table.resize(LOOP)
	for i in LOOP:
		table[i] = cos(TAU * i / LOOP)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s.cyl) * 11
	var out := PackedFloat32Array()
	out.resize(LOOP)
	for p in parts:
		var m: int = p[0]
		var amp: float = p[1]
		# firing harmonics in step make strokes you can hear; the rest stays loose
		var ph: int = 0 if m % 4 == 0 else rng.randi_range(0, LOOP - 1)
		for i in LOOP:
			out[i] += amp * table[(m * i + ph) % LOOP]
	var peak := 0.001
	for v in out:
		peak = max(peak, abs(v))
	var norm: float = 0.8 / peak
	for i in LOOP:
		out[i] *= norm
	for p in parts:
		p[1] = p[1] * norm
	var lvl: float = partials_level(parts, engine_pitch(rpm, s))[0]
	layer_k.append(db_to_linear(-lvl))
	return out

func _noise_burst(dur: float, decay: float, lp: float, tone_hz := 0.0, tone_amt := 0.0) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(dur * 1000 + lp * 100)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * lp
		var v: float = y * (1.0 - tone_amt) + sin(TAU * tone_hz * t) * tone_amt
		out[i] = v * exp(-t * decay) * 0.95
	return _wav(out)

func _beep(hz: float, dur: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = (0.6 if sin(TAU * hz * t) > 0.0 else -0.6) * min(1.0, (dur - t) * 30.0) * 0.5
	return _wav(out)

func _siren_wave() -> PackedFloat32Array:
	var n := RATE * 2
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		var hz: float = lerp(640.0, 1150.0, 0.5 - 0.5 * cos(TAU * t))
		ph += TAU * hz / RATE
		out[i] = sin(ph) * 0.62 + sin(ph * 2.0) * 0.12 + sin(ph * 3.0) * 0.05
	return out

func _squeal_wave() -> PackedFloat32Array:
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / n
		out[i] = sin(TAU * 1240.0 * t) * 0.3 + sin(TAU * 1860.0 * t) * 0.25 + sin(TAU * 3 * t) * sin(TAU * 1490.0 * t) * 0.3
	return out

func _player(stream: AudioStream, vol := 0.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol
	add_child(p)
	return p

func _loop_make(id: String, w: PackedFloat32Array) -> void:
	gains[id] = 0.0
	if js != null:
		var b := PackedByteArray()
		b.resize(w.size() * 2)
		for i in w.size():
			b.encode_s16(i * 2, int(clamp(w[i], -1.0, 1.0) * 32000.0))
		js.make(id, Marshalls.raw_to_base64(b), RATE)
	else:
		var p := _player(_wav(w, true), -80.0)
		p.play()
		loops[id] = p

func _loop_set(id: String, pitch: float, gain: float) -> void:
	if not gains.has(id):
		return
	var changed: bool = abs(gain - float(gains[id])) > 0.00001
	gains[id] = gain
	if js != null:
		if changed:
			js.voice(id, pitch, gain)
	else:
		var p: AudioStreamPlayer = loops[id]
		p.pitch_scale = pitch
		p.volume_db = linear_to_db(max(gain, 0.00005))

func _ready() -> void:
	if OS.has_feature("web"):
		js = JavaScriptBridge.get_interface("gazLoops")
	ui_player = _player(null)
	ui_sounds["ching"] = _coin()
	ui_sounds["deny"] = _beep(170.0, 0.14)

func _coin() -> AudioStreamWAV:
	var n := int(RATE * 0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var hz: float = 1320.0 if t < 0.07 else 1760.0
		out[i] = sin(TAU * hz * t) * 0.45 * exp(-t * 11.0)
	return _wav(out)

func ui(name_s: String) -> void:
	if enabled and ui_player != null and ui_sounds.has(name_s):
		ui_player.stream = ui_sounds[name_s]
		ui_player.volume_db = -14.0 + master_db
		ui_player.play()

# Reads the saved settings. Volume is added to every player here rather than to a bus, so it works the same on the web.
func apply_settings() -> void:
	enabled = S.sound_on()
	master_db = S.volume_db()
	if not enabled:
		quiet()

# Silence for loops that keep running: pause screen, sound switched off. update() brings them back.
func quiet() -> void:
	for id in gains:
		_loop_set(id, 1.0 if id.begins_with("s") else _pitch_now, 0.0)

func setup(stats: Dictionary) -> void:
	st = stats
	cache.clear()
	_loops_clear()
	for c in get_children():
		if c != ui_player:
			c.queue_free()
	pool.clear()
	layer_k.clear()
	for i in TONE_RPM.size():
		_loop_make("e%d" % i, _engine_layer(TONE_RPM[i], st))
	_loop_make("siren", _siren_wave())
	_loop_make("squeal", _squeal_wave())
	siren_on = false
	load_now = 0.0
	_pitch_now = 1.0
	cache["fist"] = _noise_burst(0.12, 26.0, 0.5, 130.0, 0.45)
	cache["kick"] = _noise_burst(0.16, 20.0, 0.35, 95.0, 0.5)
	cache["baton"] = _noise_burst(0.1, 34.0, 0.8, 620.0, 0.35)
	cache["chain"] = _noise_burst(0.2, 16.0, 0.95, 1900.0, 0.2)
	cache["whiff"] = _noise_burst(0.14, 22.0, 0.15)
	cache["hurt"] = _noise_burst(0.2, 14.0, 0.28, 170.0, 0.5)
	cache["crash"] = _noise_burst(0.9, 4.0, 0.55, 60.0, 0.3)
	cache["ko"] = _noise_burst(0.4, 8.0, 0.45, 75.0, 0.35)
	cache["shift"] = _noise_burst(0.05, 70.0, 0.9, 260.0, 0.3)
	cache["beep"] = _beep(520.0, 0.14)
	cache["go"] = _beep(880.0, 0.32)
	for i in 6:
		pool.append(_player(null))

func play(name_s: String, vol := 0.0, pitch := 1.0) -> void:
	if not enabled or not cache.has(name_s):
		return
	for p in pool:
		if not p.playing:
			p.stream = cache[name_s]
			p.volume_db = vol + FX_DB + master_db
			p.pitch_scale = pitch
			p.play()
			return

func handle_event(e: Array) -> void:
	match e[0]:
		"hit":
			play("kick" if e[2] == "kick" else ("fist" if e[2] == "none" else str(e[2])), 0.0, randf_range(0.92, 1.1))
		"whiff":
			play("whiff", -8.0)
		"hurt":
			play("hurt", -2.0)
		"crash":
			play("crash", 0.0)
		"ko":
			play("ko", -3.0)
		"shift":
			dip = 0.07 if e[1] else 0.03
			play("shift", -10.0 if e[1] else -16.0)
		"count":
			play("beep", -5.0)
		"go":
			play("go", -4.0)
		"siren":
			siren_on = e[1]
		"scrape":
			play("baton", -8.0, 0.6)
		"bump":
			play("kick", -5.0, 0.8)
		"denied":
			play("beep", -12.0, 0.4)

func update(delta: float, rpm: float, throttle: bool, alive: bool, slide: bool, cop_near: float) -> void:
	if gains.is_empty():
		return
	if not enabled:
		quiet()
		return
	dip = max(0.0, dip - delta)
	clock += delta
	# the note never sits perfectly still
	_pitch_now = engine_pitch(rpm, st) * (1.0 + 0.004 * sin(TAU * 5.3 * clock))
	var load_k: float = 1.0 if throttle else db_to_linear(OFF_GAS_DB)
	if dip > 0.0:
		load_k = 0.3
	if not alive:
		load_k = 0.0
	load_now += (load_k - load_now) * min(1.0, delta * 30.0)
	var level: float = db_to_linear(lerp(DBA_LOW, DBA_TOP, clamp(rpm, 0.0, 1.0)) + master_db) * load_now
	var mix := tone_mix(rpm)
	var g: Array[float] = []
	for i in mix.size():
		g.append(min(1.0, mix[i] * layer_k[i] * level))
	if js != null:
		for i in g.size():
			gains["e%d" % i] = g[i]
		js.engine(_pitch_now, g[0], g[1], g[2])
	else:
		for i in g.size():
			_loop_set("e%d" % i, _pitch_now, g[i])
	var master: float = db_to_linear(master_db)
	_loop_set("squeal", 1.0, SQUEAL_GAIN * master if slide else 0.0)
	var near: float = clamp(1.0 - cop_near / 112.0, 0.0, 1.0)
	_loop_set("siren", 1.0, SIREN_GAIN * near * master if siren_on else 0.0)

func _loops_clear() -> void:
	if js != null:
		js.clear()
	for id in loops:
		loops[id].queue_free()
	loops.clear()
	gains.clear()

func stop_all() -> void:
	_loops_clear()
	for p in pool:
		p.stop()
