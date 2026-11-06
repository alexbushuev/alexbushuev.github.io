class_name GameAudio extends Node
# All sound is synthesised at start, so the download stays small. Engine pitch follows real firing frequency.

const RATE := 22050
const BASE_HZ := 100.0

var engine: AudioStreamPlayer
var engine2: AudioStreamPlayer
var siren: AudioStreamPlayer
var squeal: AudioStreamPlayer
var pool: Array[AudioStreamPlayer] = []
var cache := {}
var st: Dictionary = {}
var dip := 0.0
var enabled := true

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

func _engine_wave(cyl: int, bright: float) -> AudioStreamWAV:
	# one 100 Hz cycle repeated, built from harmonics; odd cylinder counts bark, fours sing
	var n := int(RATE / BASE_HZ) * 4
	var rng := RandomNumberGenerator.new()
	rng.seed = cyl * 11
	var out := PackedFloat32Array()
	out.resize(n)
	var phases: Array[float] = []
	for h in 22:
		phases.append(rng.randf() * TAU)
	for h in range(1, 22):
		var amp: float = 1.0 / pow(h, 1.0 - bright * 0.55)
		if cyl == 1:
			amp *= 1.0 if h % 2 == 1 else 0.55
		elif cyl == 2:
			amp *= 1.2 if h % 2 == 0 else 0.6
		else:
			amp *= 1.5 if h % 4 == 0 else (0.7 if h % 2 == 0 else 0.3)
		# detuning by whole cycles keeps the loop seamless and adds a rough beat
		var freq_cycles: float = h * 4.0 + (1.0 if h % 3 == 0 else 0.0)
		for i in n:
			out[i] += amp * sin(TAU * freq_cycles * i / n + phases[h])
	var peak := 0.001
	for v in out:
		peak = max(peak, abs(v))
	for i in n:
		out[i] = out[i] / peak * 0.8
	return _wav(out, true)

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

func _siren_wave() -> AudioStreamWAV:
	var n := RATE * 2
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		var hz: float = lerp(640.0, 1150.0, 0.5 - 0.5 * cos(TAU * t))
		ph += TAU * hz / RATE
		out[i] = sin(ph) * 0.6 + (0.2 if sin(ph * 2.0) > 0.0 else -0.2)
	return _wav(out, true)

func _squeal_wave() -> AudioStreamWAV:
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / n
		out[i] = sin(TAU * 1240.0 * t) * 0.3 + sin(TAU * 1860.0 * t) * 0.25 + sin(TAU * 3 * t) * sin(TAU * 1490.0 * t) * 0.3
	return _wav(out, true)

func _player(stream: AudioStream, vol := 0.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol
	add_child(p)
	return p

func setup(stats: Dictionary) -> void:
	st = stats
	cache.clear()
	for c in get_children():
		c.queue_free()
	pool.clear()
	engine = _player(_engine_wave(int(st.cyl), 0.2), -60.0)
	engine2 = _player(_engine_wave(int(st.cyl), 1.0), -60.0)
	siren = _player(_siren_wave(), -60.0)
	squeal = _player(_squeal_wave(), -60.0)
	engine.play()
	engine2.play()
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
			p.volume_db = vol
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
			if e[1]:
				if not siren.playing:
					siren.play()
			else:
				siren.stop()
		"denied":
			play("beep", -12.0, 0.4)

func update(delta: float, rpm: float, throttle: bool, alive: bool, slide: bool, cop_near: float) -> void:
	if not enabled or engine == null:
		return
	dip = max(0.0, dip - delta)
	var rpm_real: float = lerp(float(st.idle), float(st.red), clamp(rpm, 0.0, 1.0))
	var hz: float = rpm_real / 60.0 * float(st.cyl) * 0.5
	var pitch: float = clamp(hz / BASE_HZ, 0.1, 6.0)
	engine.pitch_scale = pitch
	engine2.pitch_scale = pitch
	var load_k: float = 1.0 if throttle else 0.45
	if dip > 0.0:
		load_k = 0.3
	if not alive:
		load_k = 0.0
	var vol_low: float = linear_to_db(max(0.0005, load_k * lerp(0.55, 0.28, rpm)))
	var vol_high: float = linear_to_db(max(0.0005, load_k * lerp(0.05, 0.42, rpm)))
	engine.volume_db = vol_low
	engine2.volume_db = vol_high
	squeal.volume_db = linear_to_db(0.0005 if not slide else 0.22)
	if slide and not squeal.playing:
		squeal.play()
	elif not slide and squeal.playing:
		squeal.stop()
	if siren.playing:
		siren.volume_db = linear_to_db(clamp(0.28 - cop_near / 500.0, 0.03, 0.28))

func stop_all() -> void:
	for c in get_children():
		if c is AudioStreamPlayer:
			c.stop()
