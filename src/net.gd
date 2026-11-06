extends Node
# The account: progress kept on the server, results sent after each race, the records tables.
# All optional. Without a connection the game plays as before; unsent results wait and go later.

signal account_changed
signal save_replaced
signal result_answer(data: Dictionary)

const ACC_PATH := "user://account.json"
const GUEST_PATH := "user://save_guest.json"
# settings of this device that the account does not carry to another one
const LOCAL_KEYS := ["keys", "sound", "volume", "vol_engine", "vol_voice", "mirrors"]

var base := ""
var login := ""
var token := ""
var rev := 0
var pending: Array = []
var _upload_t := -1.0
var _uploading := false
var _js_cb: Variant = null
var race_running := false      # the game is in a race: background work waits
var _finishing: Array = []      # races whose rivals are still being ridden to the line

func _ready() -> void:
	base = api_base()
	_load_acc()
	if logged_in():
		pull_save()

func api_base() -> String:
	var forced := OS.get_environment("GAZ_API")
	if forced != "":
		return forced
	if OS.has_feature("web"):
		var o: Variant = JavaScriptBridge.eval("location.origin", true)
		if o is String and str(o).begins_with("http"):
			return str(o) + "/gaz-api"
	return "https://cybertoilet.duckdns.org/gaz-api"

func logged_in() -> bool:
	return token != ""

func _load_acc() -> void:
	if not FileAccess.file_exists(ACC_PATH):
		return
	var f := FileAccess.open(ACC_PATH, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		login = str(d.get("login", ""))
		token = str(d.get("token", ""))
		rev = int(d.get("rev", 0))
		pending = d.get("pending", []) if d.get("pending") is Array else []

func _save_acc() -> void:
	var f := FileAccess.open(ACC_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"login": login, "token": token, "rev": rev, "pending": pending}))
		f.close()

# ---------- talking to the server ----------
func call_api(method: int, path: String, body: Variant, cb: Callable) -> void:
	var r := HTTPRequest.new()
	r.timeout = 12.0
	add_child(r)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	r.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, bytes: PackedByteArray) -> void:
		r.queue_free()
		var data: Variant = null
		if result == HTTPRequest.RESULT_SUCCESS:
			data = JSON.parse_string(bytes.get_string_from_utf8())
		var err := ""
		if result != HTTPRequest.RESULT_SUCCESS or code == 0:
			err = "Нет связи с сервером"
		elif code >= 400:
			err = str(data.error) if data is Dictionary and data.has("error") else "Сервер ответил %d" % code
			if code == 401 and token != "" and not path in ["/login", "/register"]:
				_expired()
		cb.call(data if err == "" else null, err))
	var e := r.request(base + path, headers, method, JSON.stringify(body) if body != null else "")
	if e != OK:
		r.queue_free()
		cb.call(null, "Нет связи с сервером")

func cloud_save() -> Dictionary:
	var d: Dictionary = S.data.duplicate(true)
	for k in LOCAL_KEYS:
		d.erase(k)
	return d

func _adopt(save: Dictionary) -> void:
	var keep := {}
	for k in LOCAL_KEYS:
		if S.data.has(k):
			keep[k] = S.data[k]
	S.apply(save)
	S.data.merge(keep, true)
	S.apply(S.data)
	S.persist(false)
	save_replaced.emit()

# ---------- logging in ----------
func login_with(user: String, password: String, create: bool, cb: Callable) -> void:
	var body := {"login": user, "password": password}
	if create:
		body["save"] = cloud_save()
	call_api(HTTPClient.METHOD_POST, "/register" if create else "/login", body, func(data: Variant, err: String) -> void:
		if err != "":
			cb.call(err)
			return
		accept(data, create)
		cb.call(""))

# A login that went through, from the form in the page or from the game's own form
func accept(data: Dictionary, created: bool) -> void:
	var was_guest := not logged_in()
	token = str(data.token)
	login = str(data.login)
	rev = int(data.get("rev", 0))
	if was_guest:
		# your guest progress is kept aside, and comes back if you log out
		var f := FileAccess.open(GUEST_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(S.data))
			f.close()
	var srv: Variant = data.get("save")
	if not created and srv is Dictionary and not srv.is_empty():
		_adopt(srv)
	elif not created:
		mark_dirty()
		_upload_t = 0.0
	_save_acc()
	flush_pending()
	account_changed.emit()

func logout() -> void:
	if logged_in():
		call_api(HTTPClient.METHOD_POST, "/logout", {}, func(_d: Variant, _e: String) -> void: pass)
	token = ""
	login = ""
	rev = 0
	pending.clear()
	_save_acc()
	var guest: Dictionary = S.fresh()
	if FileAccess.file_exists(GUEST_PATH):
		var f := FileAccess.open(GUEST_PATH, FileAccess.READ)
		var d: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
		if d is Dictionary:
			guest = d
	_adopt(guest)
	account_changed.emit()

func _expired() -> void:
	token = ""
	_save_acc()
	account_changed.emit()

# ---------- the save ----------
func mark_dirty() -> void:
	if logged_in():
		_upload_t = 2.0

func _process(delta: float) -> void:
	_ride_rivals()
	if _upload_t < 0.0 or _uploading:
		return
	_upload_t -= delta
	if _upload_t <= 0.0:
		_upload_t = -1.0
		_upload()

func _upload() -> void:
	if not logged_in():
		return
	_uploading = true
	call_api(HTTPClient.METHOD_PUT, "/save", {"save": cloud_save(), "rev": rev}, func(data: Variant, err: String) -> void:
		_uploading = false
		if err != "":
			_upload_t = 30.0 if err.begins_with("Нет связи") else -1.0
			return
		if data.get("conflict", false):
			# played on another device in between: that progress wins
			rev = int(data.rev)
			if data.save is Dictionary:
				_adopt(data.save)
		else:
			rev = int(data.rev)
		_save_acc())

func pull_save() -> void:
	call_api(HTTPClient.METHOD_GET, "/save", null, func(data: Variant, err: String) -> void:
		if err != "":
			return
		if int(data.rev) > rev and data.save is Dictionary:
			rev = int(data.rev)
			_adopt(data.save)
			_save_acc()
		elif int(data.rev) == rev:
			mark_dirty()
		flush_pending())

# ---------- results ----------
func send_result(sim: Sim, kind: String) -> void:
	if not logged_in():
		return
	var b: Dictionary = sim.me.bike
	var body := {
		"track": str(sim.tr.id), "bike": "%s %dcc" % [b.name, int(b.cc)], "finished": kind == "finish",
		"time_ms": int(round(sim.stats.t_finish * 1000.0)) if kind == "finish" else 0,
		"ko": int(sim.stats.ko), "ko_cops": int(sim.stats.cop_ko), "place": int(sim.final_place), "diff": sim.diff,
	}
	call_api(HTTPClient.METHOD_POST, "/result", body, func(data: Variant, err: String) -> void:
		if err != "":
			if err.begins_with("Нет связи") or err.begins_with("Сервер ответил 5"):
				pending.append(body)
				_save_acc()
			result_answer.emit({"error": err})
			return
		result_answer.emit(data)
		flush_pending())

# After your race the rivals still out there ride on, a little each frame, then their times and knockouts go up too
func finish_bots(sim: Sim) -> void:
	# only a race as designed counts for the rivals: on easy they held back, on hard they were pushed
	if not logged_in() or sim.diff != 1:
		return
	sim.start_solo()
	_finishing.append(sim)

func _ride_rivals() -> void:
	if _finishing.is_empty() or race_running:
		return
	var sim: Sim = _finishing[0]
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 6000:
		if sim.solo_done():
			_finishing.pop_front()
			var body := {"_path": "/bots", "track": str(sim.tr.id), "bots": sim.bot_stats()}
			pending.append(body)
			_save_acc()
			flush_pending()
			return
		sim.step_rivals(1.0 / 20.0)

func flush_pending() -> void:
	if pending.is_empty() or not logged_in():
		return
	var body: Dictionary = pending[0].duplicate()
	var path: String = str(body.get("_path", "/result"))
	body.erase("_path")
	call_api(HTTPClient.METHOD_POST, path, body, func(_data: Variant, err: String) -> void:
		if err.begins_with("Нет связи"):
			return
		pending.pop_front()
		_save_acc()
		flush_pending())

# ---------- the login form in the page: real text fields, so a phone shows its keyboard and remembers passwords ----------
func web_form_available() -> bool:
	return OS.has_feature("web") and JavaScriptBridge.eval("typeof window.gazAccount", true) == "object"

func open_web_form(create: bool, done: Callable) -> void:
	_js_cb = JavaScriptBridge.create_callback(func(args: Array) -> void:
		var d: Variant = JSON.parse_string(str(args[0]))
		if d is Dictionary and d.has("token"):
			accept(d, bool(d.get("created", false)))
		done.call())
	var acc: JavaScriptObject = JavaScriptBridge.get_interface("gazAccount")
	acc.open(base, "create" if create else "login", JSON.stringify(cloud_save()), _js_cb)
