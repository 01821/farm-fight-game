extends Node2D

## 端到端自测：成就系统（解锁条件、提示条、存档）。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_achievements.tscn

const TEST_PATH := "user://test_ach_save.json"

var _fail: int = 0
var _level: Node2D
var _ach: Achievements
var _player: Player
var _cycle: DayCycle
var _controller: FarmController
var _save: SaveSystem

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _step(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame

func _wipe() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)

func _ready() -> void:
	_wipe()
	_level = (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	_save = _level.get_node("SaveSystem") as SaveSystem
	_save.save_path = TEST_PATH
	_save.auto_load = false
	_save.auto_save_on_dawn = false
	await _step(2)

	_ach = _level.get_node("Achievements")
	_player = _level.get_node("level/Player")
	_cycle = _level.get_node("DayCycle")
	_controller = _level.get_node("FarmController")
	_cycle.running = false

	var region: NavigationRegion2D = _level.get_node("level/animalRegion2D")
	if Level.animalRegion == null:
		Level.animalRegion = region

	var toast := _level.get_node("HUD/Toast") as Label
	var farm := _level.get_node("HUD/FarmLabel") as Label

	print("--- 初始 ---")
	_check("成就节点存在", _ach != null)
	_check("共有 6 个成就", _ach.total() == 6)
	_check("一个都没解锁", _ach.count() == 0)
	_check("提示条隐藏", toast.visible == false and _ach.toast_visible() == false)
	_check("HUD 显示成就进度 0/6", "0/6" in farm.text)

	print("--- 逐个解锁 ---")
	_player.total_harvested = 1
	await _step(2)
	_check("收获一个 -> 初次丰收", _ach.has("first_harvest"))
	_check("提示条亮起", toast.visible == true)
	_check("提示文本正确", toast.text == "成就达成：初次丰收")
	print("  INFO 提示文本 = ", toast.text)
	_check("HUD 进度变成 1/6", "1/6" in farm.text)

	_player.total_kills = 1
	await _step(2)
	_check("赶跑一只 -> 初次交锋", _ach.has("first_kill"))

	_player.total_harvested = 10
	await _step(2)
	_check("累计收获 10 -> 绿手指", _ach.has("harvest_10"))

	_player.total_kills = 25
	await _step(2)
	_check("累计 25 只 -> 农场卫士", _ach.has("kill_25"))

	_cycle.day = 4
	await _step(2)
	_check("活到第 4 天 -> 熬过三夜", _ach.has("day_3"))

	print("--- 提示条会自己消失 ---")
	# 上一条提示是「熬过三夜」，等它超时
	await get_tree().create_timer(Achievements.TOAST_TIME + 0.3).timeout
	_check("超时后提示条隐藏", toast.visible == false and _ach.toast_visible() == false)

	_controller.goal_reached = true
	await _step(2)
	_check("攒够 300 金 -> 谷仓建成", _ach.has("barn"))
	_check("全部 6 个都解锁了", _ach.count() == 6)

	print("--- 重复解锁不重复触发 ---")
	_check("已解锁的再解锁返回 false", _ach.force_unlock("barn") == false)
	_check("解锁数没变", _ach.count() == 6)
	_check("不存在的 id 返回 false", _ach.force_unlock("没有这个成就") == false)

	print("--- 存档 ---")
	_check("存档写入成功", _save.save_game() == true)

	# 先把一切压回「什么都没达成」，否则下一帧会被条件重新推导出来
	_player.total_harvested = 0
	_player.total_kills = 0
	_cycle.day = 1
	_controller.goal_reached = false
	_ach.apply_save_data({})
	await _step(3)
	_check("条件不满足 + 空集合 -> 一个都没有", _ach.count() == 0)

	# 载入一个「条件并不支持」的集合 —— 这样才能证明是「载入」而不是「重新推导」
	_ach.apply_save_data({"unlocked": ["first_harvest", "barn"]})
	_check("apply_save_data 载入了指定集合", _ach.count() == 2 and _ach.has("barn"))
	await _step(3)
	_check("已载入的成就不会因条件不满足而消失", _ach.count() == 2)

	_check("读档成功", _save.load_game() == true)
	await _step(2)
	_check("读档后 6 个成就都在", _ach.count() == 6 and _ach.has("barn"))
	_check("玩家生涯计数也恢复了", _player.total_harvested == 10 and _player.total_kills == 25)

	_wipe()
	_finish()

func _finish() -> void:
	print("RESULT fail=", _fail)
	get_tree().quit()
