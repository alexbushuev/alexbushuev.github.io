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

# a short listen in the game's own mix: scooter, city bike, then a big sport bike with everything going on around it
const PREVIEW := [
	["bike", "buivol"], ["rev", 0.25, 0.95, 2.6], ["bike", "volk"], ["rev", 0.25, 0.95, 2.6], ["bike", "tsunami"],
	["rev", 0.2, 0.97, 3.0], ["shift"], ["rev", 0.72, 1.0, 1.6], ["say", "cop1", 0], ["hold", 2.4], ["fx", "none"], ["hold", 0.5], ["fx", "kick"], ["hold", 0.5], ["fx", "chain"],
	["hold", 0.5], ["say", "mazut", 1], ["hold", 2.2], ["siren", true], ["hold", 1.4], ["say", "cop3", 0], ["hold", 2.2], ["say", "babai", 0], ["hold", 1.5],
	["say", "zina", 0], ["hold", 1.5], ["say", "siply", 1], ["hold", 2.2], ["say", "karb", 1], ["hold", 1.3], ["crash"], ["hold", 1.3],
]
var preview := false
var pi := 0
var rpm_now := 0.3
var rev: Array = []
var rev_t := 0.0
var wait_t := 0.0
var alive_now := true
var want_quit := false

func _ready() -> void:
	D.load_all()
	S.data.volume = 1.0
	S.data.sound = true
	audio = GameAudio.new()
	add_child(audio)
	audio.apply_settings()
	if OS.get_environment("AUDIO_PLAN") == "preview":
		preview = true
		return
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
	var bike: Dictionary = D.bikes[0]
	for b in D.bikes:
		if int(b.cat) == int(p[2]):
			bike = b
	var want := D.rider_stats(bike, {}, 0, 0)
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

func _preview_step(delta: float) -> void:
	if not rev.is_empty():
		rev_t += delta
		var k: float = clamp(rev_t / float(rev[3]), 0.0, 1.0)
		rpm_now = lerp(float(rev[1]), float(rev[2]), k)
		if k >= 1.0:
			rev = []
	audio.update(delta, rpm_now, alive_now, alive_now, false, 6.0)
	wait_t -= delta
	while wait_t <= 0.0 and rev.is_empty():
		if pi >= PREVIEW.size():
			get_tree().quit()
			return
		var a: Array = PREVIEW[pi]
		pi += 1
		match a[0]:
			"bike":
				audio.setup(D.rider_stats(D.bike_by_id[a[1]], {}, 0, 0))
			"rev":
				rev = a
				rev_t = 0.0
			"shift":
				audio.handle_event(["shift", true])
			"say":
				audio.say(a[1], a[2])
			"hold":
				wait_t = a[1]
			"fx":
				audio.handle_event(["hit", null, a[1]])
			"siren":
				audio.handle_event(["siren", a[1]])
			"crash":
				audio.handle_event(["crash"])
				alive_now = false

func _process(delta: float) -> void:
	if preview:
		_preview_step(delta)
		return
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
