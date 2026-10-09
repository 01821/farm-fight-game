extends Node2D

## 端到端自测：昼夜循环 + 夜晚成群来袭 + 天亮撤退 + 难度爬坡 + 目标。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_daynight.tscn

var _fail: int = 0
var _level: Node2D
var _cycle: DayCycle
var _spawner: PestSpawner
var _tint: CanvasModulate
var _player: Player
var _controller: FarmController

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _count_pests() -> int:
	return get_tree().get_nodes_in_group("pest").size()

func _step(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame

func _ready() -> void:
	var ps := load("res://Scenes/base_level.tscn") as PackedScene
	_level = ps.instantiate()
	add_child(_level)
	# 本测试会触发「天亮自动存档」，必须掐掉，否则会覆盖玩家真正的存档
	var save_sys := _level.get_node("SaveSystem") as SaveSystem
	save_sys.auto_load = false
	save_sys.auto_save_on_dawn = false
	await get_tree().process_frame
	await get_tree().process_frame

	_cycle = _level.get_node("DayCycle")
	_spawner = _level.get_node("PestSpawner")
	_tint = _level.get_node("NightTint")
	_player = _level.get_node("level/Player")
	_controller = _level.get_node("FarmController")

	var region: NavigationRegion2D = _level.get_node("level/animalRegion2D")
	if Level.animalRegion == null:
		Level.animalRegion = region

	print("--- 开局（白天） ---")
	_cycle.running = false
	_check("第 1 天", _cycle.day == 1)
	_check("开局是白天", _cycle.is_night == false)
	_check("时段名 = 白天", _cycle.phase_name() == "白天")
	_check("白天画面不压暗", _tint.color.is_equal_approx(Color(1, 1, 1, 1)))
	_check("白天刷新器不活跃", _spawner.is_active() == false)
	_check("第 1 天波次 = 2", _cycle.wave_size() == 2)

	print("--- 入夜 ---")
	_cycle.running = true
	_cycle.elapsed = _cycle.day_length * _cycle.day_ratio + 0.01
	await _step(3)
	_check("判定为夜晚", _cycle.is_night == true)
	_check("时段名 = 夜晚", _cycle.phase_name() == "夜晚")
	_check("入夜后刷新器活跃", _spawner.is_active() == true)

	await _step(40)
	print("  INFO 入夜 0.7 秒后画面色 = ", _tint.color)
	_check("夜晚画面被压暗", _tint.color.r < 0.99 and _tint.color.b > _tint.color.r)

	print("--- 夜晚成群来袭 ---")
	await _step(3)
	print("  INFO 入夜瞬间场上 = ", _count_pests())
	_check("入夜立刻自动来了第一波（2 只）", _count_pests() == 2)

	var extra: int = _spawner.spawn_wave()
	print("  INFO 手动再放一波 = ", extra, " 只")
	_check("一波 = 波次规模 2 只", extra == 2)
	_check("场上累计 4 只", _count_pests() == 4)

	for i in range(5):
		_spawner.spawn_wave()
	print("  INFO 连放 5 波后场上 = ", _count_pests())
	_check("不会超过上限", _count_pests() <= _spawner.max_pests)

	print("--- 天亮 ---")
	_cycle.elapsed = _cycle.day_length - 0.01
	await _step(3)
	_check("进入第 2 天", _cycle.day == 2)
	_check("回到白天", _cycle.is_night == false)
	_check("白天刷新器停手", _spawner.is_active() == false)
	await _step(3)
	_check("天亮野猪全部撤退", _count_pests() == 0)
	_check("第 2 天波次涨到 3", _cycle.wave_size() == 3)

	_cycle.running = true
	_cycle.elapsed = 0.0
	# 明暗是渐变，需要 FADE_TIME 秒才到位，别只等 1 秒
	await get_tree().create_timer(DayCycle.FADE_TIME + 0.5).timeout
	print("  INFO 天亮后画面色 = ", _tint.color)
	_check("白天画面重新变亮", _tint.color.r > 0.99)

	print("--- 目标 ---")
	_check("初始未达成", _controller.goal_reached == false)
	_player.money = FarmController.GOLD_GOAL - 1
	await _step(2)
	_check("差 1 金时未达成", _controller.goal_reached == false)
	_player.money = FarmController.GOLD_GOAL
	await _step(2)
	_check("达标后标记为达成", _controller.goal_reached == true)

	var info := _level.get_node("HUD/InfoLabel") as Label
	var farm := _level.get_node("HUD/FarmLabel") as Label
	var held := _level.get_node("HUD/HeldLabel") as Label
	print("  INFO ", info.text)
	print("  INFO ", farm.text)
	print("  INFO ", held.text)
	_check("HUD 显示天数", "天" in info.text)
	_check("HUD 显示时段", "白天" in info.text or "夜晚" in info.text)
	_check("HUD 显示目标已达成", "已达成" in info.text)

	_finish()

func _finish() -> void:
	print("RESULT fail=", _fail)
	get_tree().quit()
