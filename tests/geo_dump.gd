extends Node
# Writes the main road and its side roads as plain points, for a picture. godot --headless --path . res://tests/geo_dump.tscn -- <track> <out.json>
func _ready() -> void:
	D.load_all()
	var a := OS.get_cmdline_user_args()
	var road := Road.new()
	road.build(D.tracks[int(a[0])])
	var out := {"main": [], "branches": [], "features": []}
	for i in range(0, road.n, 3):
		out.main.append([road.pos[i].x, road.pos[i].z])
	for b in road.branches:
		var pts: Array = []
		for i in range(0, b.n, 2):
			pts.append([b.pos[i].x, b.pos[i].z])
		var m0 := road.world(b.s0, 0.0)
		var m1 := road.world(b.s1, 0.0)
		out.branches.append({"pts": pts, "kind": b.kind, "s0": [m0.x, m0.z], "s1": [m1.x, m1.z]})
	for f in road.features:
		var s: float = float(f.get("s_a", f.get("s", 0.0)))
		var p := road.world(s, 0.0)
		out.features.append([f.kind, p.x, p.z])
	var fl := FileAccess.open(a[1], FileAccess.WRITE)
	fl.store_string(JSON.stringify(out))
	fl.close()
	get_tree().quit()
