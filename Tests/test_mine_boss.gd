extends Node2D

## 端到端自测：矿洞关底 Boss（采掘机械）。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_mine_boss.tscn
##
## 重点验两件事：
##   1) Boss 的动作**可预判** —— 必须走完 蓄力(闪红) → 冲撞 的预告循环，
##      不能一声不响就冲过来。不预告的攻击不叫难度，叫不讲理。
##   2) 打死之后的奖励和战绩要真的记上。

var _fail: int = 0
var _level: MineLevel
var _player: MinePlayer
var _boss: MineBoss
var _hud: MineHud
var _engaged_signal: bool = false

func _on_boss_engaged() -> void:
	_engaged_signal = true

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
	for a in ["left", "right", "jump", "use_item", "switch_weapon"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)

func _pickup_count() -> int:
	return get_tree().get_nodes_in_group("mine_pickup").size()

func _ready() -> void:
	# 测试里不能真的切场景（Boss 一死会触发结算）
	MineRun.scene_switch_enabled = false
	MineRun.active = false

	_level = (load("res://Scenes/Mine/mine_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	await _step(2)
	_level.build()
	await _step(4)

	_player = _level.get_node("MinePlayer")
	_boss = _level.get_node("Boss")
	_hud = _level.get_node("MineHud")
	var bar := _level.get_node("MineHud/BossBackdrop") as ColorRect
	var fill := _level.get_node("MineHud/BossFill") as ColorRect
	var boss_label := _level.get_node("MineHud/BossLabel") as Label

	print("--- 关底 ---")
	_check("关卡右深处摆了 Boss", _boss != null)
	if _boss == null:
		print("RESULT fail=", _fail + 1)
		get_tree().quit()
		return
	_boss.engaged.connect(_on_boss_engaged)
	_check("它是 Boss（不是小怪）", _boss.is_boss())
	_check("Boss 不该被算进小怪池", not _boss.is_chasing())
	print("  INFO 血量 ", _boss.hp, "/", _boss.max_hp, "，名字 ", _boss.display_name())
	_check("血量远高于小怪（24 对 2~4）", _boss.max_hp >= 20)
	_check("贴图用的是图集里的大型机械", _boss.sprite.region_rect == Rect2(4 * 24, 2 * 24, 24, 24))
	_check("放大 2 倍显得更大", is_equal_approx(_boss.sprite.scale.x, 2.0))

	print("--- 待机：不惊动它 ---")
	var mobs := get_tree().get_nodes_in_group("mine_enemy").size()
	print("  INFO 场上怪总数（含 Boss）= ", mobs)
	_check("没靠近时不进入战斗", not _boss.is_engaged())
	_check("没靠近时是待机", _boss.phase_name() == "待机")
	await _step(4)
	_check("HUD 血条平时是隐藏的", bar.visible == false)
	_check("血条填充也是隐藏的", fill.visible == false)

	print("--- 走近 → 开战 ---")
	_release_all()
	_player.global_position = Vector2(_boss.global_position.x - 120.0, 198)
	_player.velocity = Vector2.ZERO
	await _step(6)
	print("  INFO 距离 ", snappedf(absf(_boss.global_position.x - _player.global_position.x), 0.1),
		" 时：engaged=", _boss.is_engaged(), " 相位=", _boss.phase_name())
	_check("走进范围就把 Boss 惊动了", _boss.is_engaged())
	_check("发了 engaged 信号（给音乐 / 演出留的钩子）", _engaged_signal)
	await _step(3)
	_check("HUD 血条出现了", bar.visible and fill.visible)
	print("  INFO 血条文字：", boss_label.text)
	_check("血条上写了名字和血量", _boss.display_name() in boss_label.text and "24" in boss_label.text)
	_check("满血时血条是满的", is_equal_approx(fill.size.x, MineHud.BOSS_BAR_WIDTH))

	print("--- 挨打：血量与血条一起掉 ---")
	var hp0: int = _boss.hp
	_boss.take_damage(6, _player.global_position)
	await _step(3)
	print("  INFO 挨了 6 点：", hp0, " → ", _boss.hp, "，血条宽 ", snappedf(fill.size.x, 0.1))
	_check("掉了 6 点血", _boss.hp == hp0 - 6)
	_check("血条跟着变短", fill.size.x < MineHud.BOSS_BAR_WIDTH)
	_check("硬直抗性：僵直倍率很小（不会被连击锁死）", _boss.stun_scale < 0.5)

	print("--- 预告：蓄力 → 冲撞 ---")
	var seen: Dictionary = {}
	var saw_warn_color := false
	for i in range(420):
		await get_tree().physics_frame
		if not is_instance_valid(_boss):
			break
		seen[_boss.phase_name()] = true
		# 蓄力时应该闪成预警色，玩家一眼能看出来"要冲了"
		if _boss.phase_name() == "蓄力" and _boss.sprite.modulate.r > 1.8:
			saw_warn_color = true
		# 跟着它跑，别让它跑出范围
		if absf(_boss.global_position.x - _player.global_position.x) > 150.0:
			_player.global_position.x = _boss.global_position.x - 100.0
	print("  INFO 观察到的相位：", seen.keys())
	_check("会逼近玩家", seen.has("逼近"))
	_check("会先蓄力（有预告）", seen.has("蓄力"))
	_check("蓄力之后才冲撞", seen.has("冲撞"))
	_check("冲撞完会喘息（给玩家反击窗口）", seen.has("喘息"))
	_check("蓄力时会闪成预警色", saw_warn_color)

	print("--- 拆掉它 ---")
	var coin_drops: int = _level.boss_coin_drops
	var ore_drops: int = _level.boss_ore_drops
	# ⚠️ 先走开再打 —— Boss 会一路追到玩家身边，贴脸打死的话
	#    掉落会**在玩家脚下生成、当场被捡走**，就数不到"地上有几份"了。
	_release_all()
	_player.global_position = Vector2(_boss.global_position.x - 220.0, 198)
	_player.velocity = Vector2.ZERO
	await _step(3)
	var lying_before: int = _pickup_count()
	_boss.hp = 1
	_boss.take_damage(1, _player.global_position)
	await _step(4)
	_check("血量归零后消失", not is_instance_valid(_boss))
	_check("这趟战绩记为『关底已拆』", MineRun.boss_down)
	print("  INFO 掉落 ", lying_before, " → ", _pickup_count(),
		"（预期 +", coin_drops + ore_drops, "）")
	_check("掉了一大笔（比小怪多得多）", _pickup_count() == lying_before + coin_drops + ore_drops)
	await _step(3)
	_check("Boss 没了之后血条也收起来", bar.visible == false)

	print("--- 结算里会带上『关底已拆』 ---")
	MineRun.start_run()
	MineRun.boss_down = true
	MineRun.add_gold(10)
	MineRun.finish(true)
	var r := MineRun.consume_result()
	_check("结算结果里有 boss_down", bool(r.get("boss_down", false)))
	MineRun.boss_down = false

	_release_all()
	print("RESULT fail=", _fail)
	get_tree().quit()
