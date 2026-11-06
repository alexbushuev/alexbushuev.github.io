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
3. Настройки звука и кнопок, автогаз на телефоне. Готово. Шлифовка: управление, физика, ощущение скорости, звук, эффекты.
4. Больше деталей на трассах, анимации, лучшие модели.
5. Сборка для ПК (.exe), потом Android и iPhone.
