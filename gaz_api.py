#!/usr/bin/env python3
"""Газ и цепь: accounts, saves, records and the fighters table.

Plain Python 3 standard library and SQLite, nothing to install. Listens on 127.0.0.1 only; Caddy forwards /gaz-api/* here.
    GAZ_DB=/path/gaz.db GAZ_PORT=8787 python3 gaz_api.py
Restarts itself (exits, systemd starts it again) when this file is replaced by a newer version.
"""
import hashlib, hmac, json, os, re, secrets, sqlite3, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

VERSION = 3
TOP = 10
BOT_RE = re.compile(r"^[a-z]{2,12}$")
DB = os.environ.get("GAZ_DB", os.path.join(os.path.dirname(os.path.abspath(__file__)), "gaz.db"))
PORT = int(os.environ.get("GAZ_PORT", "8787"))
PREFIX = "/gaz-api"
MAX_BODY = 256 * 1024
LOGIN_RE = re.compile(r"^[\w .\-]{2,20}$", re.UNICODE)
TRACK_RE = re.compile(r"^[a-z0-9_]{1,24}$")

SCHEMA = """
create table if not exists users(
  id integer primary key, login text not null, login_key text not null unique, pw text not null,
  created integer not null, save text, save_rev integer not null default 0,
  ko integer not null default 0, ko_riders integer not null default 0, ko_cops integer not null default 0);
create table if not exists tokens(hash text primary key, user_id integer not null, created integer not null, last integer not null);
create table if not exists records(user_id integer not null, track text not null, time_ms integer not null, bike text not null,
  at integer not null, primary key(user_id, track));
create table if not exists results(id integer primary key, user_id integer not null, track text not null, time_ms integer,
  bike text, ko integer, ko_cops integer, finished integer, place integer, at integer not null);
create index if not exists records_track on records(track, time_ms);
create table if not exists ko_records(user_id integer not null, track text not null, ko integer not null, ko_riders integer not null,
  ko_cops integer not null, bike text not null, at integer not null, primary key(user_id, track));
create index if not exists ko_track on ko_records(track, ko);
create table if not exists meta(k text primary key, v text);
"""


def migrate(c):
    cols = [r[1] for r in c.execute("pragma table_info(users)").fetchall()]
    if "is_bot" not in cols:
        c.execute("alter table users add column is_bot integer not null default 0")
    # difficulty of the race a record was set on: 0 easy, 1 normal, 2 hard
    for tbl in ("records", "ko_records"):
        if "diff" not in [r[1] for r in c.execute("pragma table_info(%s)" % tbl).fetchall()]:
            c.execute("alter table %s add column diff integer not null default 1" % tbl)
    # build 10: hills, jumps and the rivals' bikes changed the tracks, so the times start over; knockouts of people stay
    if c.execute("select v from meta where k = 'reset10'").fetchone() is None:
        c.execute("delete from records")
        c.execute("delete from ko_records where user_id in (select id from users where is_bot = 1)")
        c.execute("insert into meta(k, v) values('reset10', '1')")
    # the knockouts tables came later: rebuild them from the results kept so far
    if c.execute("select count(*) from ko_records").fetchone()[0] == 0:
        for r in c.execute("select user_id, track, ko, ko_cops, bike, at from results where ko + ko_cops > 0 order by at").fetchall():
            ko_best(c, r[0], r[1], r[2], r[3], r[4] or "", r[5])
    c.commit()


# one row per player and track: his best time, his best race by knockouts
def time_best(c, uid, track, t, bike, now, diff=1):
    if not (20000 <= t <= 3600000):
        return False
    old = c.execute("select time_ms from records where user_id = ? and track = ?", (uid, track)).fetchone()
    if old is None or t < old[0]:
        c.execute("insert or replace into records(user_id, track, time_ms, bike, at, diff) values(?,?,?,?,?,?)", (uid, track, t, bike, now, diff))
        return True
    return False


def ko_best(c, uid, track, ko, ko_cops, bike, now, diff=1):
    total = ko + ko_cops
    if total <= 0:
        return False
    old = c.execute("select ko, ko_cops from ko_records where user_id = ? and track = ?", (uid, track)).fetchone()
    if old is None or total > old[0] or (total == old[0] and ko_cops > old[1]):
        c.execute("insert or replace into ko_records(user_id, track, ko, ko_riders, ko_cops, bike, at, diff) values(?,?,?,?,?,?,?,?)",
                  (uid, track, total, ko, ko_cops, bike, now, diff))
        return True
    return False


def bot_user(c, bid, name):
    key = "bot:" + bid
    row = c.execute("select id, login from users where login_key = ?", (key,)).fetchone()
    if row is None:
        cur = c.execute("insert into users(login, login_key, pw, created, is_bot) values(?,?,?,?,1)", (name, key, "!", int(time.time())))
        return cur.lastrowid
    if row[1] != name:
        c.execute("update users set login = ? where id = ?", (name, row[0]))
    return row[0]


def db():
    c = sqlite3.connect(DB, timeout=10)
    c.row_factory = sqlite3.Row
    c.execute("pragma journal_mode=wal")
    c.execute("pragma foreign_keys=on")
    return c


def hash_pw(pw, salt=None):
    salt = salt or secrets.token_bytes(16)
    h = hashlib.scrypt(pw.encode("utf-8"), salt=salt, n=2 ** 14, r=8, p=1, dklen=32)
    return "scrypt$" + salt.hex() + "$" + h.hex()


def check_pw(pw, stored):
    try:
        _, salt, h = stored.split("$")
        return hmac.compare_digest(hash_pw(pw, bytes.fromhex(salt)), stored)
    except Exception:
        return False


def tok_hash(t):
    return hashlib.sha256(t.encode("utf-8")).hexdigest()


# a few attempts per minute from one address, so nobody can guess passwords quickly
_hits = {}
_hits_lock = threading.Lock()


def limited(key, n, window):
    now = time.time()
    with _hits_lock:
        q = [t for t in _hits.get(key, []) if now - t < window]
        if len(q) >= n:
            _hits[key] = q
            return True
        q.append(now)
        _hits[key] = q
        if len(_hits) > 20000:
            _hits.clear()
        return False


class Fail(Exception):
    def __init__(self, code, msg):
        super().__init__(msg)
        self.code, self.msg = code, msg


class H(BaseHTTPRequestHandler):
    server_version = "gaz-api"
    sys_version = ""
    timeout = 15

    def log_message(self, fmt, *a):
        pass

    def ip(self):
        f = self.headers.get("X-Forwarded-For", "")
        return f.split(",")[0].strip() or self.client_address[0]

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n > MAX_BODY:
            raise Fail(413, "Слишком много данных")
        raw = self.rfile.read(n) if n else b"{}"
        try:
            v = json.loads(raw.decode("utf-8") or "{}")
        except Exception:
            raise Fail(400, "Не понял запрос")
        if not isinstance(v, dict):
            raise Fail(400, "Не понял запрос")
        return v

    def send(self, code, obj):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def user(self, c):
        a = self.headers.get("Authorization", "")
        if not a.startswith("Bearer "):
            raise Fail(401, "Нужно войти")
        row = c.execute("select u.* from tokens t join users u on u.id = t.user_id where t.hash = ?", (tok_hash(a[7:].strip()),)).fetchone()
        if row is None:
            raise Fail(401, "Вход устарел, войди снова")
        return row

    def maybe_user(self, c):
        try:
            return self.user(c)
        except Fail:
            return None

    def route(self, method):
        path = urlparse(self.path).path
        if not path.startswith(PREFIX + "/"):
            raise Fail(404, "Нет такого")
        p = path[len(PREFIX):]
        if limited(("all", self.ip()), 600, 60):
            raise Fail(429, "Слишком часто, подожди минуту")
        c = db()
        try:
            with c:
                if method == "GET" and p == "/ping":
                    return {"ok": True, "v": VERSION}
                if method == "POST" and p in ("/register", "/login"):
                    return self.auth(c, p == "/register")
                if method == "POST" and p == "/logout":
                    a = self.headers.get("Authorization", "")
                    c.execute("delete from tokens where hash = ?", (tok_hash(a[7:].strip()),))
                    return {"ok": True}
                if method == "GET" and p == "/save":
                    u = self.user(c)
                    return {"save": json.loads(u["save"]) if u["save"] else None, "rev": u["save_rev"], "login": u["login"]}
                if method == "PUT" and p == "/save":
                    return self.put_save(c)
                if method == "POST" and p == "/result":
                    return self.result(c)
                if method == "GET" and p == "/records":
                    return self.records(c)
                if method == "POST" and p == "/bots":
                    return self.bots(c)
                if method == "GET" and p == "/fighters":
                    rows = c.execute("select login, ko, ko_riders, ko_cops, is_bot as bot from users where ko > 0 order by ko desc, ko_cops desc, id limit ?", (TOP,)).fetchall()
                    out = {"rows": [dict(r) for r in rows]}
                    me = self.maybe_user(c)
                    if me is not None and me["ko"] > 0:
                        out["mine"] = {"rank": 1 + c.execute("select count(*) from users where ko > ?", (me["ko"],)).fetchone()[0], "ko": me["ko"]}
                    return out
        finally:
            c.close()
        raise Fail(404, "Нет такого")

    def auth(self, c, new):
        if limited(("auth", self.ip()), 20, 600):
            raise Fail(429, "Слишком много попыток, подожди 10 минут")
        b = self.body()
        login = " ".join(str(b.get("login", "")).split())
        pw = str(b.get("password", ""))
        if not LOGIN_RE.match(login):
            raise Fail(400, "Логин: от 2 до 20 букв или цифр")
        if not pw or len(pw) > 200:
            raise Fail(400, "Нужен пароль")
        key = login.casefold()
        now = int(time.time())
        if new:
            if c.execute("select 1 from users where login_key = ?", (key,)).fetchone():
                raise Fail(409, "Такой логин уже занят")
            save = b.get("save")
            save_txt = json.dumps(save, ensure_ascii=False) if isinstance(save, dict) else None
            if save_txt and len(save_txt) > MAX_BODY:
                save_txt = None
            cur = c.execute("insert into users(login, login_key, pw, created, save, save_rev) values(?,?,?,?,?,?)",
                            (login, key, hash_pw(pw), now, save_txt, 1 if save_txt else 0))
            uid = cur.lastrowid
        else:
            row = c.execute("select * from users where login_key = ?", (key,)).fetchone()
            if row is None or not check_pw(pw, row["pw"]):
                raise Fail(401, "Неверный логин или пароль")
            uid = row["id"]
        tok = secrets.token_urlsafe(32)
        c.execute("insert into tokens(hash, user_id, created, last) values(?,?,?,?)", (tok_hash(tok), uid, now, now))
        u = c.execute("select * from users where id = ?", (uid,)).fetchone()
        return {"token": tok, "login": u["login"], "save": json.loads(u["save"]) if u["save"] else None, "rev": u["save_rev"]}

    def put_save(self, c):
        u = self.user(c)
        b = self.body()
        save = b.get("save")
        if not isinstance(save, dict):
            raise Fail(400, "Нет сохранения")
        base = int(b.get("rev", -1))
        if base != u["save_rev"] and not b.get("force"):
            # another device saved in between: send back what the server has, the game decides
            return {"conflict": True, "save": json.loads(u["save"]) if u["save"] else None, "rev": u["save_rev"]}
        txt = json.dumps(save, ensure_ascii=False)
        rev = u["save_rev"] + 1
        c.execute("update users set save = ?, save_rev = ? where id = ?", (txt, rev, u["id"]))
        return {"rev": rev}

    def result(self, c):
        u = self.user(c)
        if limited(("res", u["id"]), 120, 3600):
            raise Fail(429, "Слишком много заездов за час")
        b = self.body()
        track = str(b.get("track", ""))
        if not TRACK_RE.match(track):
            raise Fail(400, "Нет такой трассы")
        bike = str(b.get("bike", ""))[:40]
        ko = max(0, min(60, int(b.get("ko", 0))))
        ko_cops = max(0, min(20, int(b.get("ko_cops", 0))))
        finished = bool(b.get("finished"))
        t = int(b.get("time_ms", 0))
        place = int(b.get("place", 0))
        diff = max(0, min(2, int(b.get("diff", 1))))
        now = int(time.time())
        c.execute("insert into results(user_id, track, time_ms, bike, ko, ko_cops, finished, place, at) values(?,?,?,?,?,?,?,?,?)",
                  (u["id"], track, t, bike, ko, ko_cops, int(finished), place, now))
        c.execute("update users set ko = ko + ?, ko_riders = ko_riders + ?, ko_cops = ko_cops + ? where id = ?",
                  (ko + ko_cops, ko, ko_cops, u["id"]))
        best = finished and time_best(c, u["id"], track, t, bike, now, diff)
        ko_new = ko_best(c, u["id"], track, ko, ko_cops, bike, now, diff)
        mine = c.execute("select time_ms from records where user_id = ? and track = ?", (u["id"], track)).fetchone()
        rank = None
        if mine:
            rank = 1 + c.execute("select count(*) from records where track = ? and time_ms < ?", (track, mine["time_ms"])).fetchone()[0]
        kmine = c.execute("select ko from ko_records where user_id = ? and track = ?", (u["id"], track)).fetchone()
        ko_rank = None
        if kmine:
            ko_rank = 1 + c.execute("select count(*) from ko_records where track = ? and ko > ?", (track, kmine["ko"])).fetchone()[0]
        return {"best": best, "rank": rank, "ko_best": ko_new, "ko_rank": ko_rank}

    # The rivals of a race, each kept as a player of his own: his best time and best knockouts on this track
    def bots(self, c):
        u = self.user(c)
        if limited(("bots", u["id"]), 120, 3600):
            raise Fail(429, "Слишком много заездов за час")
        b = self.body()
        track = str(b.get("track", ""))
        if not TRACK_RE.match(track):
            raise Fail(400, "Нет такой трассы")
        lst = b.get("bots")
        if not isinstance(lst, list) or len(lst) > 14:
            raise Fail(400, "Не понял запрос")
        now = int(time.time())
        n = 0
        for x in lst:
            if not isinstance(x, dict):
                continue
            bid = str(x.get("id", ""))
            name = " ".join(str(x.get("name", "")).split())[:20]
            if not BOT_RE.match(bid) or not name:
                continue
            uid = bot_user(c, bid, name)
            bike = str(x.get("bike", ""))[:40]
            ko = max(0, min(20, int(x.get("ko", 0))))
            ko_cops = max(0, min(10, int(x.get("ko_cops", 0))))
            if ko + ko_cops > 0:
                c.execute("update users set ko = ko + ?, ko_riders = ko_riders + ?, ko_cops = ko_cops + ? where id = ?", (ko + ko_cops, ko, ko_cops, uid))
            if x.get("finished"):
                time_best(c, uid, track, int(x.get("time_ms", 0)), bike, now)
            ko_best(c, uid, track, ko, ko_cops, bike, now)
            n += 1
        return {"ok": True, "bots": n}


    def records(self, c):
        me = self.maybe_user(c)
        out = {"time": {}, "ko": {}, "mine": {"time": {}, "ko": {}}}
        sql_t = "select r.track, u.login, u.is_bot as bot, r.bike, r.time_ms, r.at, r.diff from records r join users u on u.id = r.user_id order by r.track, r.time_ms, r.at"
        for r in c.execute(sql_t).fetchall():
            lst = out["time"].setdefault(r["track"], [])
            if len(lst) < TOP:
                lst.append({k: r[k] for k in ("login", "bot", "bike", "time_ms", "diff")})
        sql_k = "select k.track, u.login, u.is_bot as bot, k.bike, k.ko, k.ko_riders, k.ko_cops, k.diff from ko_records k join users u on u.id = k.user_id order by k.track, k.ko desc, k.ko_cops desc, k.at"
        for r in c.execute(sql_k).fetchall():
            lst = out["ko"].setdefault(r["track"], [])
            if len(lst) < TOP:
                lst.append({k: r[k] for k in ("login", "bot", "bike", "ko", "ko_riders", "ko_cops", "diff")})
        if me is not None:
            for r in c.execute("select track, time_ms from records where user_id = ?", (me["id"],)).fetchall():
                rank = 1 + c.execute("select count(*) from records where track = ? and time_ms < ?", (r["track"], r["time_ms"])).fetchone()[0]
                out["mine"]["time"][r["track"]] = {"rank": rank, "time_ms": r["time_ms"]}
            for r in c.execute("select track, ko from ko_records where user_id = ?", (me["id"],)).fetchall():
                rank = 1 + c.execute("select count(*) from ko_records where track = ? and ko > ?", (r["track"], r["ko"])).fetchone()[0]
                out["mine"]["ko"][r["track"]] = {"rank": rank, "ko": r["ko"]}
        out["tracks"] = out["time"]   # for a game page that has not updated yet
        return out

    def handle_any(self, method):
        try:
            self.send(200, self.route(method))
        except Fail as e:
            self.send(e.code, {"error": e.msg})
        except Exception as e:
            print("error:", repr(e), file=sys.stderr)
            self.send(500, {"error": "Ошибка на сервере"})

    def do_GET(self):
        self.handle_any("GET")

    def do_POST(self):
        self.handle_any("POST")

    def do_PUT(self):
        self.handle_any("PUT")


def watch_self():
    me = os.path.abspath(__file__)
    seen = os.path.getmtime(me)
    while True:
        time.sleep(20)
        try:
            if os.path.getmtime(me) != seen:
                print("new version, restarting", file=sys.stderr)
                os._exit(3)
        except OSError:
            pass


def main():
    c = db()
    c.executescript(SCHEMA)
    migrate(c)
    c.close()
    threading.Thread(target=watch_self, daemon=True).start()
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    srv.daemon_threads = True
    print("gaz-api %d on 127.0.0.1:%d, db %s" % (VERSION, PORT, DB), file=sys.stderr)
    srv.serve_forever()


if __name__ == "__main__":
    main()
