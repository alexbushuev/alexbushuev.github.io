extends Node
# Plays the game's real sound on a fixed timeline so Movie Maker can record exactly what the mixer puts out.
# xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 320x180 --write-movie /tmp/a.avi res://tests/audio_probe.tscn
# then: python3 tools/audio_measure.py /tmp/a.avi

var audio: GameAudio
var t := 0.0
var marks: Array = []   # [time, name] for the measuring script
var plan: Array = []    # [seconds, name, league, rpm, throttle, siren, slide, hit]
var i := 0
var left := 0.0

func _ready() -> void:
	D.load_all()
	S.data.volume = 1.0
	S.data.sound = true
	audio = GameAudio.new()
	add_child(audio)
	audio.apply_settings()
	for c in D.leagues.size():
		for r in [0.3, 0.7, 1.0]:
			plan.append([1.5, "L%d rpm%d" % [c, int(r * 100)], c, r, true, false, false, ""])
		plan.append([1.0, "L%d off-throttle" % c, c, 0.8, false, false, false, ""])
	plan.append([2.5, "siren alone at redline", 2, 1.0, true, true, false, ""])
	plan.append([1.5, "squeal at redline", 2, 1.0, true, false, true, ""])
	for h in ["fist", "kick", "baton", "chain", "hurt", "ko", "crash"]:
		plan.append([1.2, "hit " + h + " at redline", 2, 1.0, true, false, false, h])
	_enter(plan[0])

func _enter(p: Array) -> void:
	var lg: Dictionary = D.leagues[p[2]]
	var want := {"cyl": int(lg.cyl), "idle": lg.idle, "red": lg.red, "f_lo": lg.fLo, "f_hi": lg.fHi}
	if audio.st.is_empty() or audio.st.cyl != want.cyl:
		audio.setup(want)
	marks.append("%.3f %s" % [t, p[1]])
	left = p[0]
	if p[5]:
		audio.handle_event(["siren", true])
	else:
		audio.handle_event(["siren", false])
	match p[7]:
		"fist": audio.handle_event(["hit", null, "none"])
		"kick": audio.handle_event(["hit", null, "kick"])
		"baton": audio.handle_event(["hit", null, "baton"])
		"chain": audio.handle_event(["hit", null, "chain"])
		"hurt": audio.handle_event(["hurt"])
		"ko": audio.handle_event(["ko"])
		"crash": audio.handle_event(["crash"])

func _process(delta: float) -> void:
	var p: Array = plan[i]
	audio.update(delta, p[3], p[4], true, p[6], 6.0)
	t += delta
	left -= delta
	if left <= 0.0:
		i += 1
		if i >= plan.size():
			var f := FileAccess.open(OS.get_environment("AUDIO_MARKS"), FileAccess.WRITE)
			if f != null:
				f.store_string("\n".join(marks))
				f.close()
			get_tree().quit()
			return
		_enter(plan[i])
