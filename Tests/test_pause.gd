extends Node2D

## 端到端自测：ESC 暂停菜单。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_pause.tscn

var _fail: int = 0
var _level: Node2D
var _menu: CanvasLayer
var _player: Player
var _save: SaveSystem

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _step(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame

## 真的投一个按键事件进输入系统。
## Input.action_press 只改状态、不派发事件，_unhandled_input 收不到。
func _tap(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)

func _ready() -> void:
	var ud := "user://farm_save_1.json"
	if FileAccess.file_exists(ud):
		DirAccess.remove_absolute(ud)

	_level = (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	_save = _level.get_node("SaveSystem") as SaveSystem
	_save.auto_load = false
	_save.auto_save_on_dawn = false
	await _step(3)

	_menu = _level.get_node_or_null("PauseMenu") as CanvasLayer
	_player = _level.get_node("level/Player") as Player
	var backdrop := _level.get_node("PauseMenu/Backdrop") as ColorRect

	print("--- 配置 ---")
	_check("农场里挂了暂停菜单", _menu != null)
	_check("ESC 绑上了 pause", InputMap.has_action("pause"))
	if _menu == null:
		print("RESULT fail=", _fail + 1)
		get_tree().quit()
		return
	_check("菜单节点设成了 ALWAYS（否则暂停后自己也收不到输入）",
		_menu.process_mode == Node.PROCESS_MODE_ALWAYS)
	_check("默认是收起的", not _menu.is_open and not backdrop.visible)
	_check("默认没有把游戏暂停", not get_tree().paused)

	print("--- ESC 打开 / 关闭 ---")
	_tap("pause")
	await _step(3)
	_check("按 ESC 打开了", _menu.is_open and backdrop.visible)
	_check("★ 打开的同时把游戏暂停了", get_tree().paused)
	print("  INFO 菜单选项：", _menu.option_text(0), " / ", _menu.option_text(1),
		" / ", _menu.option_text(2), " / ", _menu.option_text(3))
	_check("四个选项都在", _menu.option_text(0) != "" and _menu.option_text(3) != "")
	_check("有『继续游戏』", "继续" in _menu.option_text(0))
	_check("有『存档』", "存" in _menu.option_text(1))
	_check("有『读档』", "读" in _menu.option_text(2))
	_check("有『回到标题』", "标题" in _menu.option_text(3))

	_tap("pause")
	await _step(3)
	_check("再按 ESC 收起了", not _menu.is_open and not backdrop.visible)
	_check("收起时恢复运行", not get_tree().paused)

	print("--- 暂停时游戏真的停住了 ---")
	_tap("pause")
	await _step(3)
	var x0: float = _player.global_position.x
	# 暂停期间按方向键，玩家也不该动 —— 这是把暂停交给 get_tree().paused
	# 而不是手写 if 判断的好处：所有默认 process_mode 的节点连输入都收不到
	Input.action_press("right")
	await _step(20)
	Input.action_release("right")
	print("  INFO 暂停中按了 20 帧方向键，位移 ", snappedf(absf(_player.global_position.x - x0), 0.01), " px")
	_check("暂停时玩家完全不动", is_equal_approx(_player.global_position.x, x0))

	print("--- 用 1 号选项继续 ---")
	_tap("seed_1")
	await _step(3)
	_check("按 1 继续了", not _menu.is_open)
	_check("继续之后恢复运行", not get_tree().paused)

	print("--- 用 2 号选项存档 ---")
	_player.money = 555
	_tap("pause")
	await _step(3)
	_tap("seed_2")
	await _step(4)
	print("  INFO 存档后状态栏：", _menu.status_text())
	# 别把槽号写死 —— current_slot 会记住上次用的是哪个（这是功能，不是 bug）
	_check("存到文件了", _save.has_save())
	_check("状态栏给了反馈", "槽" in _menu.status_text())
	_check("存完还停在菜单里（没有自作主张关掉）", _menu.is_open)

	print("--- 用 3 号选项读档 ---")
	_player.money = 1
	_tap("seed_3")
	await _step(5)
	print("  INFO 读档后金币 = ", _player.money)
	_check("钱被读回来了", _player.money == 555)
	_check("★ 读档后自动取消了暂停（否则玩家会以为游戏读死了）", not get_tree().paused)
	_check("菜单也收起来了", not _menu.is_open)

	print("--- 没有存档时读档要有提示，不能静默失败 ---")
	# ⚠️ 用**同一个**菜单和存档系统。之前这里另建了一个 base_level，
	#    结果菜单里的 get_first_node_in_group("save_system") 拿到的还是**第一个**，
	#    等于根本没测到空槽那条分支。
	var real_path: String = _save.save_path
	_save.save_path = "user://definitely_not_here.json"
	_menu.is_open = true
	_menu.load_now()
	await _step(3)
	print("  INFO 空槽读档提示：", _menu.status_text(), "，paused=", get_tree().paused)
	_check("空槽读档会给出提示", _menu.status_text() != "")
	_save.save_path = real_path
	get_tree().paused = false
	if FileAccess.file_exists("user://farm_save_1.json"):
		DirAccess.remove_absolute("user://farm_save_1.json")

	print("RESULT fail=", _fail)
	get_tree().quit()
