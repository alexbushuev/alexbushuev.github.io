#!/usr/bin/env python3
# Starts the server on a fresh database and checks every rule of the tables.  python3 server/test_api.py
import json, os, subprocess, sys, tempfile, time, urllib.request, sqlite3

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = 8799
B = "http://127.0.0.1:%d/gaz-api" % PORT
fails = 0


def ok(c, what):
    global fails
    if not c:
        fails += 1
        print("FAIL", what)


def call(m, p, body=None, tok=None):
    req = urllib.request.Request(B + p, method=m, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + tok} if tok else {})})
    try:
        r = urllib.request.urlopen(req, timeout=10)
        return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


tmp = tempfile.mkdtemp()
db = os.path.join(tmp, "t.db")
# a database from version 1, with results already in it: the knockout tables must be built from them
c = sqlite3.connect(db)
c.executescript("""
create table users(id integer primary key, login text not null, login_key text not null unique, pw text not null,
  created integer not null, save text, save_rev integer not null default 0,
  ko integer not null default 0, ko_riders integer not null default 0, ko_cops integer not null default 0);
create table results(id integer primary key, user_id integer not null, track text not null, time_ms integer,
  bike text, ko integer, ko_cops integer, finished integer, place integer, at integer not null);
insert into users(id, login, login_key, pw, created, ko, ko_riders, ko_cops) values(1, 'Старый', 'старый', '!', 0, 7, 5, 2);
insert into results(user_id, track, time_ms, bike, ko, ko_cops, finished, place, at) values(1, 'dachi', 0, 'Gecko 125cc', 3, 1, 0, 0, 1);
insert into results(user_id, track, time_ms, bike, ko, ko_cops, finished, place, at) values(1, 'dachi', 0, 'Gecko 125cc', 2, 1, 0, 0, 2);
""")
c.commit()
c.close()
env = dict(os.environ, GAZ_DB=db, GAZ_PORT=str(PORT))
srv = subprocess.Popen([sys.executable, os.path.join(HERE, "gaz_api.py")], env=env, stderr=subprocess.PIPE)
time.sleep(1.2)
try:
    s, r = call("GET", "/ping")
    ok(r.get("v") == 2, "version 2")
    s, r = call("GET", "/records")
    ok(r["ko"].get("dachi", [{}])[0].get("ko") == 4 and r["ko"]["dachi"][0]["login"] == "Старый", "old results became knockout records: %s" % r["ko"])
    s, r = call("POST", "/register", {"login": "Санечка", "password": "1"})
    me = r["token"]
    # ten runs of one player on one track: one row, the best
    for t, ko, kc in [(120000, 1, 0), (110000, 4, 0), (115000, 2, 3), (130000, 0, 0), (109000, 0, 0), (111000, 5, 0), (140000, 1, 1), (125000, 0, 0), (118000, 4, 1), (119000, 0, 0)]:
        call("POST", "/result", {"track": "rice", "bike": "Buffalo 200cc", "time_ms": t, "ko": ko, "ko_cops": kc, "finished": True}, me)
    s, r = call("GET", "/records", None, me)
    rows = [x for x in r["time"]["rice"] if x["login"] == "Санечка"]
    ok(len(rows) == 1 and rows[0]["time_ms"] == 109000, "one time row per player, the best: %s" % rows)
    krows = [x for x in r["ko"]["rice"] if x["login"] == "Санечка"]
    ok(len(krows) == 1 and krows[0]["ko"] == 5 and krows[0]["ko_cops"] == 3, "one knockout row per player, the best race (5, more cops wins a tie): %s" % krows)
    ok(r["mine"]["time"]["rice"]["rank"] == 1, "my place")
    # bots: each a player of his own, once per track, best only
    roster = [("gvozd", "Гвоздь"), ("karb", "Карбюратор"), ("hrom", "Хром"), ("babai", "Бабай"), ("ryzhiy", "Рыжий"), ("valera", "Валера"), ("mazut", "Мазут")]
    for k in range(3):
        bots = [{"id": b, "name": n, "bike": "Falcon 600cc", "finished": i != 6, "time_ms": 100000 + i * 3000 + k * 500 - (k == 2) * 9000 * (i == 0), "ko": (i + k) % 3, "ko_cops": 0} for i, (b, n) in enumerate(roster)]
        s, r = call("POST", "/bots", {"track": "rice", "bots": bots}, me)
        ok(s == 200 and r["bots"] == 7, "bots accepted")
    s, r = call("GET", "/records", None, me)
    names = [x["login"] for x in r["time"]["rice"]]
    ok(len(names) == len(set(names)), "nobody twice in the time table: %s" % names)
    ok(len(r["time"]["rice"]) <= 10, "top 10 only")
    gv = [x for x in r["time"]["rice"] if x["login"] == "Гвоздь"]
    ok(gv and gv[0]["time_ms"] == 92000 and gv[0]["bot"] == 1, "bot keeps his best time and is marked a bot: %s" % gv)
    ok(r["time"]["rice"][0]["login"] == "Гвоздь", "a bot can beat you")
    ok(not any(x["login"] == "Мазут" for x in r["time"]["rice"]), "a bot who never finished has no time")
    kn = [x["login"] for x in r["ko"]["rice"]]
    ok(len(kn) == len(set(kn)), "nobody twice in the knockout table: %s" % kn)
    # a real player called like a bot is a different player
    s, r = call("POST", "/register", {"login": "Гвоздь", "password": "2"})
    ok(s == 200, "a person may take a bot's name, the bot stays apart")
    s, r = call("POST", "/login", {"login": "bot:gvozd", "password": "!"})
    ok(s in (400, 401), "nobody logs in as a bot")
    # more than ten people: top ten, and you see your own place
    for i in range(12):
        s, r = call("POST", "/register", {"login": "Игрок%d" % i, "password": "x"})
        call("POST", "/result", {"track": "dachi", "bike": "Dragonfly 50cc", "time_ms": 60000 + i * 1000, "ko": 0, "ko_cops": 0, "finished": True}, r["token"])
    call("POST", "/result", {"track": "dachi", "bike": "Dragonfly 50cc", "time_ms": 99000, "ko": 0, "ko_cops": 0, "finished": True}, me)
    s, r = call("GET", "/records", None, me)
    ok(len(r["time"]["dachi"]) == 10 and r["mine"]["time"]["dachi"]["rank"] == 13, "top 10 shown, my 13th place told: %s" % r["mine"]["time"].get("dachi"))
    s, r = call("GET", "/fighters", None, me)
    ok(len(r["rows"]) <= 10 and r["rows"][0]["ko"] >= r["rows"][-1]["ko"], "career fighters top 10")
    s, r = call("POST", "/bots", {"track": "rice", "bots": [{"id": "x" * 40, "name": "a"}]}, me)
    ok(s == 200 and r["bots"] == 0, "bad bot ids ignored")
    s, r = call("POST", "/bots", {"track": "rice", "bots": []})
    ok(s == 401, "bots need a logged-in player")
finally:
    srv.terminate()
    err = srv.stderr.read().decode()
    if "error:" in err:
        print(err)
print("FAILS", fails)
