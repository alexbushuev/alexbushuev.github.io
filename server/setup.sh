#!/bin/bash
# Газ и цепь: one-time setup of the accounts and records server. Run as root:
#   curl -fsSL https://raw.githubusercontent.com/alexbushuev/alexbushuev.github.io/gaz-api/setup.sh | bash
# What it does: a small Python service as the unprivileged user gaz, its database in /var/lib/gaz-api/data,
# an updater that pulls new versions of the service from GitHub every 5 minutes (checked against sha256),
# and one line in Caddy that forwards /gaz-api/ to it. Safe to run again.
set -euo pipefail
BASE=https://raw.githubusercontent.com/alexbushuev/alexbushuev.github.io/gaz-api
SITE=cybertoilet.duckdns.org
CF=${CADDYFILE:-/etc/caddy/Caddyfile}
say() { printf '\n== %s\n' "$*"; }
[ "$(id -u)" = 0 ] || { echo "Запусти от root"; exit 1; }

say "Проверяю Python"
command -v python3 >/dev/null || { apt-get update -qq && apt-get install -y -qq python3; }
python3 -c 'import sqlite3, hashlib; hashlib.scrypt(b"a", salt=b"b", n=16, r=8, p=1)'

say "Пользователь gaz и папки"
id gaz >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin gaz
mkdir -p /var/lib/gaz-api/app /var/lib/gaz-api/data
chown -R gaz:gaz /var/lib/gaz-api
chmod 750 /var/lib/gaz-api/data

say "Обновлялка"
cat > /usr/local/bin/gaz-api-update <<'UPD'
#!/bin/bash
# Pulls the service from GitHub when it changes. Only gaz_api.py, only if its sha256 matches the manifest.
set -e
BASE=https://raw.githubusercontent.com/alexbushuev/alexbushuev.github.io/gaz-api
DIR=/var/lib/gaz-api/app
WORK=$(mktemp -d "$DIR/.incoming.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
curl -fsSL --max-time 30 "$BASE/manifest.txt" -o "$WORK/manifest.txt"
cmp -s "$WORK/manifest.txt" "$DIR/manifest.txt" && exit 0
line=$(grep ' gaz_api.py$' "$WORK/manifest.txt")
sum=${line%% *}
curl -fsSL --max-time 60 "$BASE/gaz_api.py" -o "$WORK/gaz_api.py"
echo "$sum  $WORK/gaz_api.py" | sha256sum -c --status
python3 -m py_compile "$WORK/gaz_api.py"
chmod 644 "$WORK/gaz_api.py"
mv "$WORK/gaz_api.py" "$DIR/gaz_api.py"
mv "$WORK/manifest.txt" "$DIR/manifest.txt"
UPD
chmod 755 /usr/local/bin/gaz-api-update
runuser -u gaz -- /usr/local/bin/gaz-api-update
test -s /var/lib/gaz-api/app/gaz_api.py

say "Служба"
cat > /etc/systemd/system/gaz-api.service <<'UNIT'
[Unit]
Description=Gaz i cep: accounts and records
After=network.target

[Service]
User=gaz
Group=gaz
Environment=GAZ_DB=/var/lib/gaz-api/data/gaz.db
Environment=GAZ_PORT=8787
ExecStart=/usr/bin/python3 /var/lib/gaz-api/app/gaz_api.py
Restart=always
RestartSec=2
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
ReadWritePaths=/var/lib/gaz-api/data
MemoryMax=200M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable gaz-api >/dev/null 2>&1
systemctl restart gaz-api
echo '*/5 * * * * root /usr/sbin/runuser -u gaz -- /usr/local/bin/gaz-api-update >/dev/null 2>&1' > /etc/cron.d/gaz-api-update
for i in 1 2 3 4 5 6 7 8 9 10; do curl -fsS http://127.0.0.1:8787/gaz-api/ping >/dev/null 2>&1 && break; sleep 1; done
curl -fsS http://127.0.0.1:8787/gaz-api/ping >/dev/null || { echo "Служба не отвечает:"; journalctl -u gaz-api -n 20 --no-pager; exit 1; }

say "Caddy"
if grep -q 'gaz-api' "$CF"; then
  echo "Уже настроен"
else
  cp "$CF" "$CF.bak-gaz-api"
  python3 - "$CF" "$SITE" <<'PY'
import re, sys
path, site = sys.argv[1], sys.argv[2]
lines = open(path).read().split("\n")
for i, l in enumerate(lines):
    if site in l and l.rstrip().endswith("{") and not l.lstrip().startswith("#"):
        ind = re.match(r"\s*", lines[i + 1] if i + 1 < len(lines) else "").group(0) or "    "
        lines.insert(i + 1, ind + "reverse_proxy /gaz-api/* 127.0.0.1:8787")
        open(path, "w").write("\n".join(lines))
        sys.exit(0)
print("Не нашёл блок сайта " + site + " в " + path)
sys.exit(1)
PY
  if ! caddy validate --config "$CF" --adapter caddyfile >/dev/null 2>&1; then
    cp "$CF.bak-gaz-api" "$CF"
    echo "Caddy не принял настройку, вернул как было"; exit 1
  fi
  systemctl reload caddy
fi

say "Проверка снаружи"
sleep 2
if curl -fsS "https://$SITE/gaz-api/ping"; then
  printf '\n\nГОТОВО. Аккаунты и рекорды работают.\n'
else
  echo "Снаружи не отвечает. Пришли этот вывод Claude."; exit 1
fi
