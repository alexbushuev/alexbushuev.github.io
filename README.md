# Газ и цепь 3D

Мотогонки с дракой и полицией. Движок Godot 4.7, рендер Compatibility, чтобы шло на телефонах и в браузере.

## Что от движка не зависит

- `data/` — все цифры игры в JSON: байки, экипировка, оружие, лиги, трассы, соперники, темы, правила.
- `tools/make_models.py` и `models/` — все 3D-модели строятся кодом в Blender и лежат в glTF.
  Цвета хранятся в вершинах, у гонщика настоящий скелет. Такие файлы открывает любой движок.
- `tests/` — бот, который проходит гонки без экрана.

## Что привязано к Godot

`src/` (логика `sim.gd`, `road.gd` сама по себе без графики; графика, интерфейс и звук в остальных файлах), `main.tscn`, `project.godot`, `export_presets.cfg`, `web/shell.html`.

## Как собрать

    # модели (нужен модуль bpy)
    PYTHONPATH=<bpy> python3 tools/make_models.py -- models
    # импорт и бот
    godot --headless --path . --import
    godot --headless --path . res://tests/bot_test.tscn -- all x human
    godot --headless --path . res://tests/rules_test.tscn     # копы, деньги, сохранение
    godot --headless --path . res://tests/traffic_test.tscn   # трафик против байка
    godot --headless --path . res://tests/steer_test.tscn     # замеры руля
    godot --headless --path . res://tests/settings_test.tscn  # уровни мотора, кнопки, раскладка телефона
    godot --headless --path . res://tests/hill_test.tscn      # подъёмы и спуски, трамплины, скорость байков на уклоне
    godot --headless --path . res://tests/foot_test.tscn      # пешеходы, сбить бегущего к байку, сложность

Реальный звук: `AUDIO_MARKS=/tmp/m.txt xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 320x180 --write-movie /tmp/a.avi res://tests/audio_probe.tscn`, потом `python3 tools/audio_measure.py /tmp/a.avi /tmp/m.txt`.

Рёв мотора и баланс звуков настраиваются в `data/sound.json`, без правки кода.

Голоса заранее записаны в `audio/voices/` инструментом `tools/make_voices.py` (Piper, эффект рации на numpy/scipy). Новая реплика: добавить текст в `data/rivals.json` или `data/sound.json` и запустить инструмент. Голоса denis и dmitri под CC0; ruslan под CC BY-NC-SA, у irina лицензия не указана: перед продажей игры их надо заменить.

В браузере зацикленные звуки (мотор, сирена, визг) играет страница, `gazLoops` в `web/shell.html`: у Godot в вебе цикл перезапускается вручную и щёлкает. Разовые звуки и сборка для ПК идут через Godot.
    # кадры без экрана
    xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x590 -- shot 4 sapsan /tmp/a 10,20
    xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x590 -- ui /tmp/u   # все экраны
    # браузерная сборка в dist/
    tools/build_web.sh godot
    # выкладка: dist/ в ветку gaz3d, сервер забирает её сам
    tools/publish.sh

## Единицы и договорённости

Метры и секунды. Дорога: `s` вдоль, `d` поперёк, `+d` вправо. Наши полосы +1.8 и +5.4, встречные -1.8 и -5.4.
В glTF вперёд это -Z, вверх +Y.

## План

1. Езда, соперники, удары, падения, полиция, трафик, звук. Готово.
2. Гараж, магазин, деньги, экипировка, сохранение, бар с досье, экран перед стартом. Готово.
3. Настройки звука и кнопок, автогаз на телефоне. Готово.
4. Длинные трассы с тоннелями, путепроводами, развилками и срезками; живучесть и забег к байку; приборы и зеркала; аккаунты, рекорды, бойцы. Готово. Дальше: шлифовка, совместные заезды.
4. Больше деталей на трассах, анимации, лучшие модели.
5. Сборка для ПК (.exe), потом Android и iPhone.


## Сервер аккаунтов и рекордов

`server/gaz_api.py`: один файл, только стандартная библиотека Python и SQLite. Логин и пароль (scrypt), сохранение на аккаунт с защитой от перезаписи с другого устройства, результаты заездов. Таблицы, топ-10: на каждой трассе лучшее время и лучший заезд по нокаутам (одна строка на игрока), плюс нокауты за всё время. Соперники считаются отдельными игроками: после твоего финиша игра досчитывает их гонку и отправляет их время и нокауты (только с заездов на средней сложности). У каждого рекорда записана сложность, на которой он поставлен. Проверка: `python3 server/test_api.py`.

Установка на сервер один раз, от root: `curl -fsSL https://raw.githubusercontent.com/alexbushuev/alexbushuev.github.io/gaz-api/setup.sh | bash`. Служба работает от пользователя gaz, база в `/var/lib/gaz-api/data`, Caddy передаёт ей `/gaz-api/`. Новые версии приходят сами каждые 5 минут из ветки `gaz-api` (sha256 из манифеста), выкладка: `tools/publish_api.sh`. Отключить автообновление: удалить `/etc/cron.d/gaz-api-update`.

Проверка на своей машине: `GAZ_DB=/tmp/t.db GAZ_PORT=8788 python3 server/gaz_api.py`, `python3 tools/dev_server.py 8123 http://127.0.0.1:8788` (сайт из dist/ плюс API, как Caddy), `GAZ_API=http://127.0.0.1:8788/gaz-api godot --headless --path . res://tests/net_test.tscn`.

Другие тесты: `tests/branch_test` (развилки и выигрыш срезки по времени), `tests/build_time` (сколько строится трасса), `tests/geo_dump` (точки трассы для картинки), режим снимков `-- shot <трасса> <байк> <папка> 1 tour` (тоннели, мосты, развилки) и `-- shot <трасса> <байк> <папка> 0 b10` (прыжок, знаки уклона, переход с пешеходами).
