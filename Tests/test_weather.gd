extends Node2D

## 端到端自测：天气系统（雨天自动浇灌 + 画面偏冷 + HUD 显示）。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_weather.tscn

var _fail: int = 0
var _level: Node2D
var _weather: Weather
var _cycle: DayCycle
var _tint: CanvasModulate
var _land: FarmLand
var _player: Player
var _ctl: FarmController

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _step(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame

func _move_to_tile(tile: Vector2i) -> void:
	_player.global_position = _land.to_global(_land.map_to_local(tile))
	_player.velocity = Vector2.ZERO

func _farm_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in _land.get_used_cells():
		if _land.is_farmland(c):
			out.append(c)
	return out

func _ready() -> void:
	var ps := load("res://Scenes/base_level.tscn") as PackedScene
	_level = ps.instantiate()
	add_child(_level)
	var save_sys := _level.get_node("SaveSystem") as SaveSystem
	save_sys.auto_load = false
	save_sys.auto_save_on_dawn = false
	await get_tree().process_frame
	await get_tree().process_frame

	_weather = _level.get_node("Weather")
	_cycle = _level.get_node("DayCycle")
	_tint = _level.get_node("NightTint")
	_land = _level.get_node("Land")
	_player = _level.get_node("level/Player")
	_ctl = _level.get_node("FarmController")
	_cycle.running = false
	_cycle.elapsed = 0.0
	_cycle.is_night = false

	var region: NavigationRegion2D = _level.get_node("level/animalRegion2D")
	if Level.animalRegion == null:
		Level.animalRegion = region

	var info := _level.get_node("HUD/InfoLabel") as Label

	print("--- 初始 ---")
	_check("Weather 节点存在", _weather != null)
	_check("开局是晴天", _weather.is_rainy == false and _weather.sky_name() == "晴天")
	await _step(3)
	_check("HUD 显示晴天", "晴天" in info.text)
	print("  INFO ", info.text)

	print("--- 掷骰子 ---")
	_weather.rain_chance = 1.0
	_check("必然下雨时函数返回 true", _weather.roll_for_day(1) == true)
	_check("状态变成雨天", _weather.is_rainy == true)
	_weather.rain_chance = 0.0
	_check("必然晴天时函数返回 false", _weather.roll_for_day(2) == false)
	_check("状态变回晴天", _weather.is_rainy == false)
	_check("默认下雨概率在合理区间", Weather.new().rain_chance > 0.0 and Weather.new().rain_chance < 1.0)

	print("--- 画面偏冷 ---")
	_weather.set_rainy(false)
	await _step(5)
	var dry: Color = _tint.color
	_weather.set_rainy(true)
	await _step(3)
	var wet: Color = _tint.color
	print("  INFO 晴天色 ", dry, "   雨天色 ", wet)
	_check("雨天画面整体压暗", wet.r < dry.r - 0.05)
	_check("雨天偏蓝（b > r）", wet.b > wet.r)
	_weather.set_rainy(false)
	await _step(3)
	_check("转晴后画面恢复", _tint.color.r > 0.99)

	print("--- 雨天自动浇水 ---")
	var tiles := _farm_tiles()
	_check("有耕地", tiles.size() > 0)
	if tiles.is_empty():
		_finish()
		return
	_land.clear_all_plants()
	_player.seeds[0] = 5
	var planted: int = 0
	for i in range(2):
		_move_to_tile(tiles[i])
		_player.active_item = Player.Item.SEED
		if _ctl.use_held_item():
			planted += 1
	_check("种下两株", planted == 2)

	# 先把它们弄湿（water_all 只浇没浇过的）
	_check("water_all 浇了 2 株", _land.water_all() == 2)
	_check("再浇一次返回 0（都已湿）", _land.water_all() == 0)

	# 清空重来，验证「雨水会自己浇」
	_land.clear_all_plants()
	for i in range(2):
		_move_to_tile(tiles[i])
		_player.active_item = Player.Item.SEED
		_ctl.use_held_item()
	var p0: BasePlant = _land.plants.get(tiles[0])
	_check("刚种下是干的", p0 != null and p0.is_watered == false)

	_weather.set_rainy(true)
	await get_tree().create_timer(Weather.RAIN_TICK + 0.3).timeout
	print("  INFO 下雨 1.3 秒后: watered=", p0.is_watered, " stage=", p0.growStage)
	_check("雨水把作物浇湿了", p0.is_watered == true or p0.growStage > 0)

	print("--- HUD ---")
	await _step(2)
	_check("HUD 显示雨天", "雨天" in info.text)
	print("  INFO ", info.text)
	_weather.set_rainy(false)
	await _step(2)
	_check("HUD 显示晴天", "晴天" in info.text)

	_finish()

func _finish() -> void:
	print("RESULT fail=", _fail)
	get_tree().quit()
