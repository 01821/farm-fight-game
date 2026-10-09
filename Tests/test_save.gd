extends Node2D

## 端到端自测：存档系统。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_save.tscn
##
## 全程用临时存档路径 user://test_save.json，不碰玩家真正的存档。

const TEST_PATH := "user://test_save.json"

var _fail: int = 0
var _level: Node2D
var _save: SaveSystem
var _player: Player
var _land: FarmLand
var _cycle: DayCycle
var _controller: FarmController

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _wipe() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)

func _action_key(action: String) -> int:
	if not InputMap.has_action(action):
		return -1
	for e in InputMap.action_get_events(action):
		var k := e as InputEventKey
		if k != null:
			return k.physical_keycode
	return -1

func _farm_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in _land.get_used_cells():
		if _land.is_farmland(c):
			out.append(c)
	return out

func _ready() -> void:
	_wipe()

	print("--- 输入动作（核对硬编码的功能键码） ---")
	_check("有 quick_save 动作", InputMap.has_action("quick_save"))
	_check("F5 的键码 = 引擎常量 KEY_F5", _action_key("quick_save") == KEY_F5)
	_check("F9 的键码 = 引擎常量 KEY_F9", _action_key("quick_load") == KEY_F9)
	_check("F10 的键码 = 引擎常量 KEY_F10", _action_key("delete_save") == KEY_F10)

	_level = (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	# 必须在第一帧之前改路径：自动读档被刻意延后到 _process 首帧
	_save = _level.get_node("SaveSystem")
	_save.save_path = TEST_PATH
	await get_tree().process_frame
	await get_tree().process_frame

	_player = _level.get_node("level/Player")
	_land = _level.get_node("Land")
	_cycle = _level.get_node("DayCycle")
	_controller = _level.get_node("FarmController")
	_cycle.running = false

	var region: NavigationRegion2D = _level.get_node("level/animalRegion2D")
	if Level.animalRegion == null:
		Level.animalRegion = region

	print("--- 初始没有存档 ---")
	_check("测试路径上没有存档", _save.has_save() == false)

	print("--- 改状态后存档 ---")
	_cycle.day = 4
	_cycle.elapsed = 30.0            # > 27 秒，属于夜晚
	_player.money = 137
	_player.hp = 3
	_player.seeds = 5
	_player.harvested = 2
	_player.water_left = 4
	_player.active_item = Player.Item.SWORD
	_controller.goal_reached = true

	var tiles := _farm_tiles()
	_check("有耕地", tiles.size() > 0)
	var tile: Vector2i = tiles[0]
	var plant: BasePlant = _land.spawn_plant(tile, 0)
	plant.apply_save_data({"type": 0, "stage": 2, "watered": true})
	_check("种下并设置到 2 级", plant.growStage == 2 and plant.is_watered)

	_check("存档写入成功", _save.save_game() == true)
	_check("存档文件已生成", _save.has_save() == true)

	print("--- 破坏状态后读档 ---")
	_player.money = 0
	_player.hp = Player.MAX_HP
	_player.seeds = 0
	_player.harvested = 0
	_player.water_left = 0
	_player.active_item = Player.Item.SEED
	_controller.goal_reached = false
	_cycle.day = 1
	_cycle.elapsed = 0.0
	_cycle.is_night = false
	_land.clear_all_plants()
	await get_tree().process_frame
	_check("状态确实被破坏了", _land.plants.is_empty() and _player.money == 0 and _cycle.day == 1)

	_check("读档成功", _save.load_game() == true)
	await get_tree().process_frame
	_check("天数恢复 = 4", _cycle.day == 4)
	_check("时段由 elapsed 重算为夜晚", _cycle.is_night == true)
	_check("金币恢复 = 137", _player.money == 137)
	_check("血量恢复 = 3", _player.hp == 3)
	_check("种子恢复 = 5", _player.seeds == 5)
	_check("篮子恢复 = 2", _player.harvested == 2)
	_check("水量恢复 = 4", _player.water_left == 4)
	_check("手持物恢复 = 长剑", _player.active_item == Player.Item.SWORD)
	_check("目标进度恢复", _controller.goal_reached == true)
	_check("作物数量恢复", _land.plants.size() == 1)
	var restored: BasePlant = _land.plants.get(tile)
	_check("作物实例回来了", restored != null)
	if restored != null:
		_check("生长阶段恢复 = 2", restored.growStage == 2)
		_check("浇水状态恢复", restored.is_watered == true)

	print("--- 坏存档要能优雅拒绝 ---")
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 999}))
	f.close()
	_check("版本不符时拒绝读取", _save.load_game() == false)

	f = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("这不是 JSON {{{")
	f.close()
	_check("内容损坏时拒绝读取", _save.load_game() == false)

	print("--- 删除存档 ---")
	_check("删除成功", _save.delete_save() == true)
	_check("删完就没有了", _save.has_save() == false)
	_check("没有存档时再删返回 false", _save.delete_save() == false)

	print("--- 启动自动读档（真实启动路径） ---")
	_check("重新写一份存档", _save.save_game() == true)
	# 让第一份实例安静下来，避免两个实例同时刷野猪
	_cycle.elapsed = 5.0
	_cycle.is_night = false

	var level2 := (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(level2)
	var save2 := level2.get_node("SaveSystem") as SaveSystem
	save2.save_path = TEST_PATH
	var player2 := level2.get_node("level/Player") as Player
	var cycle2 := level2.get_node("DayCycle") as DayCycle
	cycle2.running = false
	_check("新实例开局是默认值", player2.money == 20 and cycle2.day == 1)

	await get_tree().process_frame
	await get_tree().process_frame
	_check("启动时自动读了金币 = 137", player2.money == 137)
	_check("启动时自动读了天数 = 4", cycle2.day == 4)
	_check("启动时自动读了地块上的作物", (level2.get_node("Land") as FarmLand).plants.size() == 1)

	_wipe()
	_finish()

func _finish() -> void:
	print("RESULT fail=", _fail)
	get_tree().quit()
