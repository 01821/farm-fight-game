extends Node2D

## 端到端自测：多存档槽（3 个）。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_slots.tscn
##
## 这里刻意**不**用真的 base_level 存档内容做断言，而是直接验"路径 / 摘要 / 删除"
## 这套槽位 API —— 存档内容本身在 test_save 里已经覆盖过了。

var _fail: int = 0
var _level: Node2D
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

func _ready() -> void:
	_level = (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	_save = _level.get_node("SaveSystem") as SaveSystem
	_save.auto_load = false
	_save.auto_save_on_dawn = false
	await _step(3)

	print("--- 槽位基础 ---")
	_check("有 3 个存档槽", SaveSystem.SLOT_COUNT == 3)
	_check("每个槽一个文件",
		_save.slot_path(1) != _save.slot_path(2) and _save.slot_path(2) != _save.slot_path(3))
	print("  INFO 槽 1 = ", _save.slot_path(1))
	print("  INFO 槽 2 = ", _save.slot_path(2))
	print("  INFO 槽 3 = ", _save.slot_path(3))
	_check("槽路径带槽号", "1" in _save.slot_path(1) and "3" in _save.slot_path(3))

	print("--- 切槽 ---")
	_check("能切到 2 号", _save.set_slot(2))
	_check("当前槽是 2", _save.current_slot == 2)
	_check("save_path 跟着变了", _save.save_path == _save.slot_path(2))
	_check("越界的槽号被拒", not _save.set_slot(0) and not _save.set_slot(4))
	_check("被拒之后槽号没变", _save.current_slot == 2)

	print("--- 各槽互不干扰 ---")
	# 清场：先把三个槽都删掉
	for s in range(1, SaveSystem.SLOT_COUNT + 1):
		if _save.slot_exists(s):
			_save.delete_slot(s)
	await _step(2)
	for s in range(1, SaveSystem.SLOT_COUNT + 1):
		_check("清场后 %d 号槽是空的" % s, not _save.slot_exists(s))

	# 往 1 号槽存一份
	_save.set_slot(1)
	var player := _level.get_node("level/Player") as Player
	var cycle := _level.get_node("DayCycle") as DayCycle
	player.money = 111
	cycle.day = 5
	_check("存到 1 号槽", _save.save_game())
	await _step(2)
	_check("1 号槽有东西了", _save.slot_exists(1))
	_check("2 号槽还是空的（没被串味）", not _save.slot_exists(2))

	print("--- 标题界面要的摘要，不用真载入就能读 ---")
	var sum1: Dictionary = _save.slot_summary(1)
	print("  INFO 1 号槽摘要 ", sum1)
	_check("摘要说存在", bool(sum1.get("exists")))
	_check("摘要能读到第几天", int(sum1.get("day", 0)) == 5)
	_check("摘要能读到金币", int(sum1.get("money", 0)) == 111)
	_check("摘要说版本匹配", bool(sum1.get("ok")))

	var sum2: Dictionary = _save.slot_summary(2)
	_check("空槽的摘要说不存在", not bool(sum2.get("exists")))
	_check("空槽摘要不会崩", sum2.has("day") and sum2.has("money"))

	print("--- 存到另一个槽不会覆盖第一个 ---")
	_save.set_slot(2)
	player.money = 222
	cycle.day = 9
	_check("存到 2 号槽", _save.save_game())
	await _step(2)
	var s1b: Dictionary = _save.slot_summary(1)
	var s2b: Dictionary = _save.slot_summary(2)
	print("  INFO 槽1 第", int(s1b.get("day", 0)), "天 /", int(s1b.get("money", 0)),
		" 金；槽2 第", int(s2b.get("day", 0)), "天 /", int(s2b.get("money", 0)), " 金")
	_check("1 号槽没被覆盖", int(s1b.get("money", 0)) == 111 and int(s1b.get("day", 0)) == 5)
	_check("2 号槽是新的那份", int(s2b.get("money", 0)) == 222 and int(s2b.get("day", 0)) == 9)

	print("--- 读档只读当前槽 ---")
	_save.set_slot(1)
	player.money = 0
	cycle.day = 1
	_check("从 1 号槽读档", _save.load_game())
	await _step(2)
	print("  INFO 从 1 号槽读回来：第 ", cycle.day, " 天 / ", player.money, " 金")
	_check("读回的是 1 号槽的内容", player.money == 111 and cycle.day == 5)

	print("--- 删档 ---")
	_check("删 2 号槽", _save.delete_slot(2))
	await _step(2)
	_check("2 号槽没了", not _save.slot_exists(2))
	_check("1 号槽还在", _save.slot_exists(1))
	_check("删不存在的槽返回 false", not _save.delete_slot(3))

	print("--- 记住上次用的槽 ---")
	_save.set_slot(3)
	await _step(2)
	var level2 := (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(level2)
	var save2 := level2.get_node("SaveSystem") as SaveSystem
	save2.auto_load = false
	save2.auto_save_on_dawn = false
	await _step(3)
	print("  INFO 重新开一局之后的槽号 = ", save2.current_slot)
	_check("新开的 SaveSystem 记得上次用的是 3 号槽", save2.current_slot == 3)
	_check("并且 save_path 也对上了", save2.save_path == save2.slot_path(3))

	# 收尾：别把测试槽留给玩家
	for s in range(1, SaveSystem.SLOT_COUNT + 1):
		if _save.slot_exists(s):
			_save.delete_slot(s)

	print("RESULT fail=", _fail)
	get_tree().quit()
