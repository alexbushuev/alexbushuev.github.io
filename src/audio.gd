class_name GameAudio extends Node
# All sound is synthesised at start, so the download stays small. Engine pitch follows real firing frequency.

const RATE := 22050
const LOOP := 3520                # 16 firing periods at pitch 1: long enough to hold a slow rough beat inside the note
const BASE_HZ := RATE * 16.0 / LOOP
const TONE_RPM: Array[float] = [0.2, 1.0]    # the note is two layers, each voiced for its own revs

var js: Variant = null            # on the web the page plays the loops: Godot's own web loop clicks at every pass
var loops := {}                   # id -> player, everywhere else
var gains := {}                   # id -> gain the loop was last given
var pitches := {}
var layer_k: Array[float] = []    # gain that brings a layer to 0 dB(A)
var siren_on := false
var pool: Array[AudioStreamPlayer] = []
var cache := {}
var voice_cache := {}
var st: Dictionary = {}
var dip := 0.0
var enabled := true
var master_db := 0.0
var engine_db := 0.0
var voice_db := 0.0
var load_now := 0.0
var duck_now := 1.0
var duck_voice_t := 0.0
var duck_hit_t := 0.0
var clock := 0.0
var _pitch_now := 1.0
var mix: Dictionary = {}
var ui_player: AudioStreamPlayer
var voice_player: AudioStreamPlayer
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
	var v: Dictionary = s.voice
	var hz: float = lerp(float(v.hz[0]), float(v.hz[1]), clamp(rpm, 0.0, 1.0)) * float(v.k)
	return hz / BASE_HZ

# One layer as a list of [cycles in the loop, amplitude]. Sixteen cycles are one firing period.
# The note sits low and the growl comes from what lies under and around it: half and quarter orders, and pairs a hair off
# each harmonic that beat slowly. Top end is cut hard: a lion has chest, not whistle.
static func engine_partials(rpm: float, s: Dictionary) -> Array:
	var v: Dictionary = s.voice
	var f0: float = engine_pitch(rpm, s) * BASE_HZ / 16.0
	var cut: float = lerp(float(v.cut[0]), float(v.cut[1]), rpm)
	var form: float = float(v.formant)
	var cyl := int(s.cyl)
	var want := {}
	for h in range(1, 25):
		var a: float = (1.0 if h == 1 or cyl >= 4 or h % 2 == 0 else 0.7) / (1.0 + 0.3 * h)
		want[16 * h] = a
		if h <= 8:
			want[16 * h - 1] = a * float(v.rough)
			want[16 * h + 1] = a * float(v.rough) * 0.7
	var sub: float = float(v.sub)
	want[8] = sub
	want[24] = sub * 0.55
	want[40] = sub * 0.32
	want[56] = sub * 0.18
	var qt: float = float(v.quarter)
	want[4] = qt
	want[12] = qt * 0.8
	want[20] = qt * 0.6
	want[28] = qt * 0.4
	var out: Array = []
	for k in want:
		var f: float = k * f0
		var amp: float = want[k]
		amp /= sqrt(1.0 + pow(f / cut, 4.0))
		amp /= sqrt(1.0 + pow(38.0 / f, 4.0))     # below this it is only felt as distortion in small headphones
		amp *= 1.0 + 1.1 * exp(-pow(log(f / form) / 0.5, 2.0))
		if amp > 0.004:
			out.append([k, amp])
	return out

# Level in dB(A) and the part of it above 1 kHz, for partials of amplitude scaled to the loop's full scale
static func partials_level(parts: Array, pitch: float) -> Array:
	var f0: float = pitch * BASE_HZ / 16.0
	var all := 0.0
	var high := 0.0
	for p in parts:
		var f: float = p[0] * f0
		var e: float = pow(p[1] * a_gain(f), 2.0) / 2.0
		all += e
		if f >= 1000.0:
			high += e
	return [10.0 * log(max(all, 1e-12)) / log(10.0), high / max(all, 1e-12)]

static func tone_mix(rpm: float) -> Array[float]:
	var k: float = (clamp(rpm, TONE_RPM[0], TONE_RPM[1]) - TONE_RPM[0]) / (TONE_RPM[1] - TONE_RPM[0])
	return [1.0 - k, k]

# air through the exhaust: under the note, follows the revs
func _air_wave() -> PackedFloat32Array:
	var n := int(RATE * 1.5)
	var fade := 2000
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lo := 0.0
	var lo2 := 0.0
	var peak := 0.001
	for i in n + fade:
		var w: float = rng.randf_range(-1.0, 1.0)
		lo += (w - lo) * 0.2
		lo2 += (w - lo2) * 0.03
		raw[i] = lo - lo2
		peak = max(peak, abs(raw[i]))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = raw[i] / peak * 0.8
	for i in fade:
		var k: float = float(i) / fade
		out[i] = out[i] * k + raw[n + i] / peak * 0.8 * (1.0 - k)
	return out

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
		var ph: int = 0 if m % 16 == 0 else rng.randi_range(0, LOOP - 1)
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
	pitches[id] = 1.0
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
	if abs(gain - float(gains[id])) < 0.00001 and abs(pitch - float(pitches[id])) < 0.0005:
		return
	gains[id] = gain
	pitches[id] = pitch
	if js != null:
		js.voice(id, pitch, gain)
	else:
		var p: AudioStreamPlayer = loops[id]
		p.pitch_scale = pitch
		p.volume_db = linear_to_db(max(gain, 0.00005))

func _ready() -> void:
	if OS.has_feature("web"):
		js = JavaScriptBridge.get_interface("gazLoops")
	mix = D.sound.mix
	ui_player = _player(null)
	voice_player = _player(null)
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
		ui_player.volume_db = -10.0 + master_db
		ui_player.play()

# A line over the radio: baked by tools/make_voices.py. One radio, so a new line cuts off the old one.
func say(voice_id: String, i: int) -> void:
	if not enabled or not S.voices_on():
		return
	var path := "res://audio/voices/%s_%d.wav" % [voice_id, i]
	if not voice_cache.has(path):
		voice_cache[path] = load(path) if ResourceLoader.exists(path) else null
	var w: AudioStream = voice_cache[path]
	if w == null:
		return
	voice_player.stop()
	voice_player.stream = w
	voice_player.volume_db = float(mix.voice_db) + master_db + voice_db
	voice_player.play()
	duck_voice_t = w.get_length()

# Reads the saved settings. Volume is added to every player here rather than to a bus, so it works the same on the web.
func apply_settings() -> void:
	enabled = S.sound_on()
	master_db = S.volume_db()
	engine_db = S.volume_db("vol_engine")
	voice_db = S.volume_db("vol_voice")
	if voice_player != null:
		voice_player.volume_db = float(mix.voice_db) + master_db + voice_db
	if not enabled:
		quiet()
		if voice_player != null:
			voice_player.stop()

# Silence for loops that keep running: pause screen, sound switched off. update() brings them back.
func quiet() -> void:
	for id in gains:
		_loop_set(id, float(pitches[id]), 0.0)

func setup(stats: Dictionary) -> void:
	st = stats
	cache.clear()
	_loops_clear()
	for c in get_children():
		if c != ui_player and c != voice_player:
			c.queue_free()
	pool.clear()
	layer_k.clear()
	for i in TONE_RPM.size():
		_loop_make("e%d" % i, _engine_layer(TONE_RPM[i], st))
	_loop_make("air", _air_wave())
	_loop_make("siren", _siren_wave())
	_loop_make("squeal", _squeal_wave())
	siren_on = false
	load_now = 0.0
	duck_now = 1.0
	duck_voice_t = 0.0
	duck_hit_t = 0.0
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
			p.volume_db = vol + float(mix.fx_db) + master_db
			p.pitch_scale = pitch
			p.play()
			return

func handle_event(e: Array) -> void:
	match e[0]:
		"hit":
			play("kick" if e[2] == "kick" else ("fist" if e[2] == "none" else str(e[2])), 0.0, randf_range(0.92, 1.1))
			duck_hit_t = 0.14
		"say":
			if e.size() > 3:
				say(e[2], e[3])
		"whiff":
			play("whiff", -8.0)
		"hurt":
			play("hurt", -2.0)
		"crash":
			play("crash", 0.0)
			duck_hit_t = 0.5
		"ko":
			play("ko", -3.0)
			duck_hit_t = 0.3
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
		"ped":
			play("ko", -2.0 if e[1] else -6.0, 0.8 if e[1] else 1.3)
		"land":
			# suspension bottoming out: louder and lower the harder he comes down
			var hv: float = float(e[1]) if e[1] != null else 2.0
			play("ko", clamp(-16.0 + hv * 1.6, -16.0, -2.0), clamp(1.15 - hv * 0.05, 0.65, 1.1))
		"denied":
			play("beep", -12.0, 0.4)

func update(delta: float, rpm: float, throttle: bool, alive: bool, slide: bool, cop_near: float) -> void:
	if gains.is_empty():
		return
	if not enabled:
		quiet()
		return
	dip = max(0.0, dip - delta)
	duck_voice_t = max(0.0, duck_voice_t - delta)
	duck_hit_t = max(0.0, duck_hit_t - delta)
	clock += delta
	# the note never sits perfectly still
	_pitch_now = engine_pitch(rpm, st) * (1.0 + 0.004 * sin(TAU * 5.3 * clock))
	var load_k: float = 1.0 if throttle else db_to_linear(float(mix.off_gas_db))
	if dip > 0.0:
		load_k = 0.3
	if not alive:
		load_k = 0.0
	load_now += (load_k - load_now) * min(1.0, delta * 30.0)
	# the engine steps back for what you need to hear
	var duck_db := 0.0
	if duck_voice_t > 0.0:
		duck_db = float(mix.duck_voice_db)
	if duck_hit_t > 0.0:
		duck_db = min(duck_db, float(mix.duck_hit_db))
	duck_now += (db_to_linear(duck_db) - duck_now) * min(1.0, delta * (40.0 if duck_db < 0.0 else 7.0))
	var master: float = db_to_linear(master_db)
	var eng: float = master * db_to_linear(engine_db) * load_now * duck_now
	var level: float = db_to_linear(lerp(float(mix.engine_dba_low), float(mix.engine_dba_top), clamp(rpm, 0.0, 1.0))) * eng
	var tone := tone_mix(rpm)
	for i in tone.size():
		_loop_set("e%d" % i, _pitch_now, min(1.0, tone[i] * layer_k[i] * level))
	_loop_set("air", lerp(0.75, 1.5, clamp(rpm, 0.0, 1.0)), float(mix.air_gain) * eng * lerp(0.5, 1.0, clamp(rpm, 0.0, 1.0)) * (1.0 if throttle else 0.4))
	_loop_set("squeal", 1.0, float(mix.squeal_gain) * master if slide else 0.0)
	var near: float = clamp(1.0 - cop_near / 112.0, 0.0, 1.0)
	_loop_set("siren", 1.0, float(mix.siren_gain) * near * master if siren_on else 0.0)

func _loops_clear() -> void:
	if js != null:
		js.clear()
	for id in loops:
		loops[id].queue_free()
	loops.clear()
	gains.clear()
	pitches.clear()

func stop_all() -> void:
	_loops_clear()
	for p in pool:
		p.stop()
	voice_player.stop()
