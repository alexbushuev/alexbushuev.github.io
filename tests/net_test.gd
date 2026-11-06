extends Node
# Account, save sync and results against a running server. GAZ_API=http://127.0.0.1:8788/gaz-api godot --headless --path . res://tests/net_test.tscn

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _call(method: int, path: String, body: Variant) -> Array:
	var out := [null, "pending"]
	N.call_api(method, path, body, func(d: Variant, e: String) -> void:
		out[0] = d
		out[1] = e)
	while out[1] == "pending":
		await get_tree().process_frame
	return out

func _ready() -> void:
	S.path = "user://net_test_save.json"
	S.reset_for_test()
	N.logout()
	await _wait(0.3)
	S.data.money = 4321
	S.data.volume = 0.33
	S.persist()
	var name := "т%d" % (Time.get_ticks_msec() % 100000)
	# new account takes the guest progress with it
	var done := [""]
	var finished := [false]
	N.login_with(name, "1", true, func(e: String) -> void:
		done[0] = e
		finished[0] = true)
	while not finished[0]:
		await get_tree().process_frame
	check(done[0] == "" and N.logged_in() and N.login == name, "register: " + done[0])
	var r := await _call(HTTPClient.METHOD_GET, "/save", null)
	check(r[0] != null and int(r[0].save.money) == 4321 and not r[0].save.has("volume"), "guest progress went to the account, without device settings")
	# a change goes up by itself a moment later
	S.data.money = 5000
	S.persist()
	await _wait(3.5)
	r = await _call(HTTPClient.METHOD_GET, "/save", null)
	check(int(r[0].save.money) == 5000 and int(r[0].rev) == N.rev, "change synced, rev %s/%d" % [str(r[0].rev), N.rev])
	# another device writes in between: its progress wins here
	var other := HTTPRequest.new()
	add_child(other)
	other.request(N.base + "/save", ["Content-Type: application/json", "Authorization: Bearer " + N.token], HTTPClient.METHOD_PUT, JSON.stringify({"save": {"money": 777, "open": 3}, "rev": N.rev}))
	await other.request_completed
	S.data.money = 6000
	S.persist()
	await _wait(3.5)
	check(int(S.data.money) == 777 and int(S.data.open) == 3 and float(S.data.volume) == 0.33, "the other device's save adopted, local volume kept (money %d)" % int(S.data.money))
	# a race result
	var sim := Sim.new()
	sim.setup(0, "strek", {}, 0, 0, 0, 0, 1)
	sim.stats.t_finish = 61.25
	sim.stats.ko = 4
	sim.stats.cop_ko = 1
	sim.final_place = 2
	var ans := [null]
	N.result_answer.connect(func(d: Dictionary) -> void: ans[0] = d, CONNECT_ONE_SHOT)
	N.send_result(sim, "finish")
	while ans[0] == null:
		await get_tree().process_frame
	check(ans[0].get("best", false) and int(ans[0].rank) >= 1, "result recorded: " + str(ans[0]))
	r = await _call(HTTPClient.METHOD_GET, "/records", null)
	var mine := false
	for row in r[0].time.get("dachi", []):
		if row.login == name and int(row.time_ms) == 61250 and str(row.bike) == "Dragonfly 50cc":
			mine = true
	check(mine, "my time in the table with the bike")
	r = await _call(HTTPClient.METHOD_GET, "/fighters", null)
	var f_ok := false
	for row in r[0].rows:
		if row.login == name and int(row.ko) == 5 and int(row.ko_riders) == 4 and int(row.ko_cops) == 1:
			f_ok = true
	check(f_ok, "fighters table")
	# the rivals of that race ride on to the line and go into the tables as players of their own
	N.race_running = false
	N.finish_bots(sim)
	var waited := 0.0
	var frames := 0
	while not N._finishing.is_empty() and frames < 3000:
		await get_tree().process_frame
		frames += 1
	print("rivals ridden to the line in %d frames, sim t %.0f" % [frames, sim.t])
	await _wait(1.5)
	r = await _call(HTTPClient.METHOD_GET, "/records", null)
	var bots_in := 0
	for row in r[0].time.get("dachi", []):
		if int(row.bot) == 1:
			bots_in += 1
	check(bots_in > 0 and r[0].has("ko"), "rivals in the dachi time table: %d" % bots_in)
	var seen := {}
	var twice := false
	for row in r[0].time.get("dachi", []):
		twice = twice or seen.has(row.login + str(row.bot))
		seen[row.login + str(row.bot)] = true
	check(not twice and r[0].time.get("dachi", []).size() <= 10, "top ten, nobody twice")
	# offline: the result waits
	var real_base := N.base
	N.base = "http://127.0.0.1:9/gaz-api"
	ans[0] = null
	N.result_answer.connect(func(d: Dictionary) -> void: ans[0] = d, CONNECT_ONE_SHOT)
	N.send_result(sim, "dead")
	while ans[0] == null:
		await get_tree().process_frame
	check(N.pending.size() == 1, "offline result kept for later")
	N.base = real_base
	N.flush_pending()
	await _wait(1.5)
	check(N.pending.is_empty(), "sent once back online")
	# log out: the guest progress comes back
	N.logout()
	check(not N.logged_in() and int(S.data.money) == 4321, "logged out, guest progress back (money %d)" % int(S.data.money))
	# log in again: the account's progress
	finished[0] = false
	N.login_with(name.to_upper(), "1", false, func(e: String) -> void:
		done[0] = e
		finished[0] = true)
	while not finished[0]:
		await get_tree().process_frame
	check(done[0] == "" and int(S.data.money) == 777, "logged in again, account progress (money %d) %s" % [int(S.data.money), done[0]])
	finished[0] = false
	N.login_with(name, "2", false, func(e: String) -> void:
		done[0] = e
		finished[0] = true)
	while not finished[0]:
		await get_tree().process_frame
	check(done[0].contains("Неверный"), "wrong password told: " + done[0])
	N.logout()
	print("FAILS: ", fails)
	get_tree().quit()
