extends Node
# How long building each track takes, and how much it puts in the scene. godot --headless --path . res://tests/build_time.tscn
func _ready() -> void:
	D.load_all()
	for ti in D.tracks.size():
		var t0 := Time.get_ticks_msec()
		var sim := Sim.new()
		sim.setup(ti, D.bikes[0].id, {}, 0, 0, 0, 0, 1)
		var t1 := Time.get_ticks_msec()
		var w := World.new()
		add_child(w)
		w.build(sim.road, D.themes[int(D.tracks[ti].theme)], 600.0)
		var t2 := Time.get_ticks_msec()
		var inst := 0
		var nodes := 0
		var labels := 0
		for ch in w.chunks:
			for c in ch.get_children():
				nodes += 1
				if c is MultiMeshInstance3D:
					inst += c.multimesh.instance_count
				if c is Label3D:
					labels += 1
		print("%-8s road %4d ms, world %5d ms | %d chunks, %d nodes, %d decor, %d labels, %d solids" % [D.tracks[ti].id, t1 - t0, t2 - t1, w.chunks.size(), nodes, inst, labels, sim.road.solids.size()])
		w.queue_free()
		await get_tree().process_frame
	get_tree().quit()
