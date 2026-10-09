extends Node2D

## 端到端自测：矿洞战斗（阶段 B）。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_mine_combat.tscn
##
## 打击感这类东西最怕"看起来对、打上去没感觉"，所以这里测的是**敌人的实际状态变化**：
## 掉了多少血、有没有被推开、有没有硬直、有没有飘字、死了没有。

var _fail: int = 0
var _level: MineLevel
var _player: MinePlayer
var _enemy: MineEnemy
## ⚠️ 用成员变量而不是局部变量接收信号：
## GDScript 的 lambda **按值捕获局部变量**，`func(_e): flag = true` 改的是副本，外面看不到。
var _died_signal: bool = false

func _on_enemy_died(_e: MineEnemy) -> void:
	_died_signal = true

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _step(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame

func _release_all() -> void:
	for a in ["left", "right", "jump", "use_item"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)

## 把玩家摆到敌人左边 distance 像素处，面朝敌人并站稳
func _face_enemy(distance: float, settle: int = 6) -> void:
	_release_all()
	_player.global_position = Vector2(_enemy.global_position.x - distance, _enemy.global_position.y - 2)
	_player.velocity = Vector2.ZERO
	await _step(settle)
	_player.facing = 1

func _damage_numbers() -> int:
	var n: int = 0
	for c in _player.get_parent().get_children():
		if c is DamageNumber:
			n += 1
	return n

func _ready() -> void:
	_level = (load("res://Scenes/Mine/mine_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	await _step(2)
	_level.build()
	await _step(4)

	_player = _level.get_node("MinePlayer")
	_enemy = _level.get_node("EnemyA")

	print("--- 敌人 ---")
	var all := get_tree().get_nodes_in_group("mine_enemy")
	print("  INFO 关卡里有 ", all.size(), " 只怪")
	_check("关卡里预建了敌人", all.size() == 3)
	_check("默认种类是绿机兵（3 血）", _enemy.hp == 3 and _enemy.max_hp == 3)
	_check("敌人贴图用 24×24 网格（0,0）", _enemy.sprite.region_rect == Rect2(0, 0, 24, 24))
	_check("蝙蝠是另一种贴图", (_level.get_node("EnemyBat") as MineEnemy).sprite.region_rect == Rect2(168, 48, 24, 24))

	print("--- 攻击判定 ---")
	# 离得远：砍不到
	await _face_enemy(80.0)
	var hp_before: int = _enemy.hp
	_check("离太远砍不到", _player.can_attack() and _player.attack() == 0)
	_check("没打中就不掉血", _enemy.hp == hp_before)
	await _step(30)

	# 贴上去：能砍到
	await _face_enemy(12.0)
	_check("靠近后可以攻击", _player.can_attack())
	var hit: int = _player.attack()
	print("  INFO 这一刀打中 ", hit, " 只")
	_check("近身能砍中", hit == 1)
	_check("敌人掉 1 点血", _enemy.hp == hp_before - 1)
	_check("立刻生成飘字", _damage_numbers() == 1)
	_check("攻击进入冷却", not _player.can_attack())
	_check("冷却中再砍被拒（不会重复结算）", _player.attack() == 0)
	_check("敌人进入硬直", _enemy.is_stunned())

	print("--- 击退 ---")
	# 刚被打完应该正在被推开
	print("  INFO 击退强度 = ", snappedf(_enemy.knockback_len(), 0.1))
	_check("被打会往远离玩家的方向飞", _enemy.knockback_len() > 0.0)
	var x_after_hit: float = _enemy.global_position.x
	await _step(10)
	print("  INFO 敌人 x：", snappedf(x_after_hit, 0.1), " → ", snappedf(_enemy.global_position.x, 0.1))
	_check("击退真的把它推远了", _enemy.global_position.x > x_after_hit)
	await _step(40)
	_check("击退会衰减停下来", _enemy.knockback_len() < 2.0)
	_check("硬直也会结束", not _enemy.is_stunned())

	print("--- 打死 ---")
	# ⚠️ 打死之后 enemy 会被 queue_free，**不能再读它的属性**，所以先记下来。
	var hp_before_kill: int = _enemy.hp
	_enemy.died.connect(_on_enemy_died)
	print("  INFO 最后一刀前剩血 ", hp_before_kill)
	for i in range(hp_before_kill):
		if not is_instance_valid(_enemy):
			break
		await _face_enemy(12.0)
		_player.attack()
		await _step(25)
	_check("砍够刀数就死了", not is_instance_valid(_enemy))
	_check("发出 died 信号", _died_signal)
	await _step(3)
	_check("死掉的敌人离开场景", not is_instance_valid(_enemy))
	_check("场上还剩 2 只怪", get_tree().get_nodes_in_group("mine_enemy").size() == 2)

	print("--- 飘字会自己消失 ---")
	print("  INFO 当前场上飘字数量 = ", _damage_numbers())
	_check("飘字确实生成过", _damage_numbers() > 0)
	await get_tree().create_timer(0.9).timeout
	_check("飘字播完自动回收", _damage_numbers() == 0)

	print("--- 别的怪不受影响 ---")
	var other := _level.get_node("EnemyB") as MineEnemy
	_check("旁边的怪满血", other.hp == other.max_hp)
	# 换个方向砍：面朝左，判定框也要跟着摆到左边
	_release_all()
	_player.global_position = Vector2(other.global_position.x + 12.0, other.global_position.y - 2)
	_player.velocity = Vector2.ZERO
	await _step(6)
	_player.facing = -1
	await _step(2)
	print("  INFO 判定框位置 x = ", snappedf(_player.attack_box.position.x, 0.1))
	_check("朝左时判定框摆到左边", _player.attack_box.position.x < 0.0)
	var hit2: int = _player.attack()
	_check("朝左也能砍中", hit2 == 1)
	_check("打到的是旁边那只", other.hp == other.max_hp - 1)

	_release_all()
	print("RESULT fail=", _fail)
	get_tree().quit()
