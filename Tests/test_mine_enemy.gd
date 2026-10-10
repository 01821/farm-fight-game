extends Node2D

## 端到端自测：矿洞怪的 AI + 玩家的受伤与无敌帧 + 心形血条（阶段 C）。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_mine_enemy.tscn

var _fail: int = 0
var _level: MineLevel
var _player: MinePlayer
var _enemy: MineEnemy
var _bat: MineEnemy
var _hud: MineHud
var _died_signal: bool = false

func _on_player_died() -> void:
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

## 把玩家放到敌人左边 distance 处（同一水平线上），站稳
func _place_near(enemy: MineEnemy, distance: float, settle: int = 6) -> void:
	_release_all()
	_player.global_position = Vector2(enemy.global_position.x - distance, enemy.global_position.y - 2)
	_player.velocity = Vector2.ZERO
	await _step(settle)

func _flat_map() -> PackedStringArray:
	## 一张只有地面、没有任何平台的空地图。飞行怪的测试要在开阔空气里做。
	var out := PackedStringArray()
	for y in range(MineGen.H):
		out.append("#".repeat(MineGen.W) if y >= MineGen.GROUND_ROW else " ".repeat(MineGen.W))
	out[MineGen.SPAWN_Y] = MineGen._put(out[MineGen.SPAWN_Y], MineGen.SPAWN_X, "S")
	return out

func _ready() -> void:
	_level = (load("res://Scenes/Mine/mine_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	await _step(2)
	_level.build()
	await _step(6)

	_player = _level.get_node("MinePlayer")
	_enemy = _level.get_node("EnemyA")
	_bat = _level.get_node("EnemyBat")
	_hud = _level.get_node("MineHud")
	_player.died.connect(_on_player_died)

	print("--- HUD 心形血条 ---")
	_check("HUD 预建了 6 颗心的槽位", _hud.heart_count() == 6)
	var full := Rect2(4 * 18, 2 * 18, 18, 18)
	var half := Rect2(5 * 18, 2 * 18, 18, 18)
	var empty := Rect2(6 * 18, 2 * 18, 18, 18)

	_player.hp = MinePlayer.MAX_HP
	await _step(2)
	var hearts := _hud.hearts()
	print("  INFO 满血时前 3 颗 = ", hearts[0].region_rect, hearts[1].region_rect, hearts[2].region_rect)
	_check("满血（6）时 3 颗全满", hearts[0].region_rect == full and hearts[1].region_rect == full and hearts[2].region_rect == full)
	_check("用不到的槽位隐藏了", hearts[3].visible == false and hearts[5].visible == false)

	_player.hp = 5
	await _step(2)
	_check("掉到 5 血：两颗满 + 一颗半", hearts[0].region_rect == full and hearts[1].region_rect == full and hearts[2].region_rect == half)

	_player.hp = 3
	await _step(2)
	_check("掉到 3 血：一颗满 + 一颗半 + 一颗空", hearts[0].region_rect == full and hearts[1].region_rect == half and hearts[2].region_rect == empty)

	_player.hp = 1
	await _step(2)
	_check("掉到 1 血：半颗 + 两颗空", hearts[0].region_rect == half and hearts[1].region_rect == empty and hearts[2].region_rect == empty)

	print("--- 受伤与无敌帧 ---")
	_player.hp = MinePlayer.MAX_HP
	_player.global_position = Vector2(60, 198)
	await _step(4)
	var ok1: bool = _player.take_damage(1, Vector2(200, 198))
	_check("受伤返回 true", ok1)
	_check("掉 1 点血", _player.hp == MinePlayer.MAX_HP - 1)
	_check("受伤后进入无敌", _player.is_invulnerable())
	_check("被撞飞（有向上速度）", _player.velocity.y < 0.0)

	var ok2: bool = _player.take_damage(1, Vector2(200, 198))
	_check("无敌期间再打无效", ok2 == false)
	_check("无敌期间不掉血", _player.hp == MinePlayer.MAX_HP - 1)

	await get_tree().create_timer(MinePlayer.INVULN_TIME + 0.1).timeout
	_check("无敌结束后解除", not _player.is_invulnerable())
	_check("解除后又能受伤", _player.take_damage(1, Vector2(200, 198)) == true)
	_check("这次真的掉了血", _player.hp == MinePlayer.MAX_HP - 2)

	print("--- 死亡 ---")
	# ⚠️ 必须等上一刀的无敌帧过掉，否则下面这一下会被无敌挡掉（我第一次就写错了）
	await get_tree().create_timer(MinePlayer.INVULN_TIME + 0.1).timeout
	_player.hp = 1
	_check("血尽这一下能打进去", _player.take_damage(1, Vector2(200, 198)) == true)
	_check("血尽发 died 信号", _died_signal)
	_check("血量不会变成负数", _player.hp == 0)

	print("--- 怪的巡逻与追击 ---")
	# 先把玩家挪远，让怪回到巡逻
	_release_all()
	_player.global_position = Vector2(60, 198)
	_player.velocity = Vector2.ZERO
	await _step(30)
	print("  INFO 玩家在远处时，EnemyA 状态 = ", _enemy.state_name())
	_check("离得远时不追", not _enemy.is_chasing())

	# 走进侦测范围
	var near_x: float = _enemy.global_position.x - 70.0
	_player.global_position = Vector2(near_x, 198)
	_player.velocity = Vector2.ZERO
	await _step(4)
	print("  INFO 玩家距离 ", snappedf(absf(_enemy.global_position.x - _player.global_position.x), 0.1),
		" 时，状态 = ", _enemy.state_name())
	_check("走进范围就开始追", _enemy.is_chasing())

	# 追击时应该朝玩家方向移动
	var dist_before: float = absf(_enemy.global_position.x - _player.global_position.x)
	await _step(20)
	var dist_after: float = absf(_enemy.global_position.x - _player.global_position.x)
	print("  INFO 追击中距离 ", snappedf(dist_before, 0.1), " → ", snappedf(dist_after, 0.1))
	_check("追击时确实在靠近", dist_after < dist_before)

	print("--- 接触伤害（端到端） ---")
	_player.hp = MinePlayer.MAX_HP
	# 直接把玩家塞到怪身边，等无敌帧过去后让它撞
	_player.global_position = Vector2(_enemy.global_position.x - 8.0, _enemy.global_position.y - 2)
	_player.velocity = Vector2.ZERO
	var hp_before: int = _player.hp
	await get_tree().create_timer(MinePlayer.INVULN_TIME + 0.6).timeout
	print("  INFO 贴着怪 ", MinePlayer.INVULN_TIME + 0.6, " 秒后：", hp_before, " → ", _player.hp)
	_check("贴着怪会被撞掉血", _player.hp < hp_before)

	print("--- 蝙蝠 ---")
	_check("蝙蝠是飞行怪", _bat.is_flying())
	await _step(40)
	_check("飞行怪不会掉到地上", _bat.global_position.y < 190.0)

	# ⚠️ 换成一张**没有平台**的平地地图再测。
	#    新地图是程序化生成的，蝙蝠头顶可能正好压着一块平台，
	#    它往下降时会撞上去、velocity.y 被 move_and_slide 清零，
	#    于是下面那条断言就失败了 —— 而失败原因跟蝙蝠的 AI 毫无关系。
	_level.map = _flat_map()
	_level.build()
	await _step(4)

	# ⚠️ 关键：把玩家**水平拉开到接触范围之外**（70 > CONTACT_RANGE 15），
	#    否则玩家会被反复撞飞、一直在空中弹，"他在上还是在下"就说不清了。
	#    （第一版就是栽在这里：断言方向反了，还以为蝙蝠有 bug。）
	_release_all()
	_player.hp = MinePlayer.MAX_HP
	_player.global_position = Vector2(_bat.global_position.x - 70.0, 198)
	_player.velocity = Vector2.ZERO
	await _step(3)
	print("  [dbg] 玩家在下方：蝙蝠 y=", snappedf(_bat.global_position.y, 0.1),
		" 玩家 y=", snappedf(_player.global_position.y, 0.1),
		" 蝙蝠 velocity.y=", snappedf(_bat.velocity.y, 0.1),
		" 状态=", _bat.state_name())
	_check("玩家在下方时，蝙蝠往下压（velocity.y > 0）", _bat.velocity.y > 0.0)

	# 反过来：把玩家瞬移到蝙蝠上方，它应该往上追
	_player.global_position = Vector2(_bat.global_position.x - 70.0, _bat.global_position.y - 60.0)
	_player.velocity = Vector2.ZERO
	await _step(3)
	print("  [dbg] 玩家在上方：蝙蝠 velocity.y=", snappedf(_bat.velocity.y, 0.1))
	_check("玩家在上方时，蝙蝠往上追（velocity.y < 0）", _bat.velocity.y < 0.0)

	# 离开侦测范围就不再追
	_player.global_position = Vector2(_bat.global_position.x - 300.0, 198)
	_player.velocity = Vector2.ZERO
	await _step(3)
	_check("拉远之后不再追", not _bat.is_chasing())

	print("--- 尖刺球（重单位：打不动、僵不住） ---")
	_check("怪的种类表有 5 种（含尖刺球）", MineEnemy.KINDS.size() == 5)
	var spike := _level.get_node_or_null("EnemySpike") as MineEnemy
	_check("关卡里摆了尖刺球", spike != null)
	if spike != null:
		print("  INFO ", spike.display_name(), " hp=", spike.hp, " 重=", spike.heavy)
		_check("名字是尖刺球", spike.display_name() == "尖刺球")
		_check("贴图用图集第 0 行最后一格", spike.sprite.region_rect == Rect2(8 * 24, 0, 24, 24))
		_check("被标成了『重』单位", spike.heavy)
		_check("硬直抗性很高", spike.stun_scale < 0.5)

		# 对照实验：同样的击退，机器人会被推走，尖刺球几乎不动。
		# 这才叫"验证了免疫"，只打一下看它没动是不够的 —— 也可能是我击退写坏了。
		spike.global_position = Vector2(600, 189)
		spike.velocity = Vector2.ZERO
		await _step(3)
		var spike_x0: float = spike.global_position.x
		spike.take_damage(1, spike.global_position - Vector2(40, 0), 300.0)
		await _step(4)
		var spike_moved: float = absf(spike.global_position.x - spike_x0)

		var robot := _level.get_node("EnemyA") as MineEnemy
		robot.global_position = Vector2(600, 189)
		robot.velocity = Vector2.ZERO
		await _step(3)
		var robot_x0: float = robot.global_position.x
		robot.take_damage(1, robot.global_position - Vector2(40, 0), 300.0)
		await _step(4)
		var robot_moved: float = absf(robot.global_position.x - robot_x0)

		print("  INFO 同样一脚 300 击退：尖刺球动了 ", snappedf(spike_moved, 0.1),
			" px，机器人动了 ", snappedf(robot_moved, 0.1), " px")
		# 用**相对比较**而不是写死阈值：击退是逐帧衰减的，4 帧只积累十几像素，
		# 写死一个数会变成"测的是衰减曲线"而不是"测的免疫"。
		_check("尖刺球吃不到击退（几乎原地不动）", spike_moved < 4.0)
		_check("机器人照常被推飞（对照组，动得明显更多）",
			robot_moved > 8.0 and robot_moved > spike_moved * 3.0)

	print("--- 打死怪不会报错 ---")
	var hp_b: int = _bat.hp
	for i in range(hp_b):
		if not is_instance_valid(_bat):
			break
		_bat.take_damage(1, _player.global_position)
		await _step(2)
	_check("蝙蝠被打死了", not is_instance_valid(_bat))

	print("--- 受击反馈：屏幕边缘闪红 + 低血量心跳 ---")
	var hud := _level.get_node("MineHud") as MineHud
	var bars := hud.hurt_bars()
	_check("受击边框有 4 条边", bars.size() == 4)
	_player.hp = MinePlayer.MAX_HP
	await _step(35)
	print("  INFO 满血时边框亮度 ", snappedf(hud.hurt_alpha(), 0.001))
	_check("满血时边框是看不见的", hud.hurt_alpha() < 0.01)

	# 挨一下，边框应该立刻冲上去
	_player.hp = MinePlayer.MAX_HP
	_player.take_damage(1, Vector2(_player.global_position.x - 40, _player.global_position.y))
	await _step(2)
	var peak: float = hud.hurt_alpha()
	print("  INFO 挨打后边框亮度 ", snappedf(peak, 0.001))
	_check("挨打后边框亮起来了", peak > 0.2)
	_check("亮度不超过上限", peak <= MineHud.HURT_PEAK + 0.001)
	_check("四条边一起亮", bars[0].color.a == bars[3].color.a)

	# 淡出
	await _step(int(MineHud.HURT_FADE * 60) + 8)
	print("  INFO 淡出后亮度 ", snappedf(hud.hurt_alpha(), 0.001))
	_check("会自己淡下去", hud.hurt_alpha() < 0.01)

	# 低血量心跳：**不给它新的伤害**，边框也应该自己一下一下地跳
	_player.hp = 1
	var lo: float = 1.0
	var hi: float = 0.0
	for i in range(int(MineHud.BEAT_PERIOD * 60) + 6):
		await get_tree().physics_frame
		var a: float = hud.hurt_alpha()
		lo = minf(lo, a)
		hi = maxf(hi, a)
	print("  INFO 低血量一个心跳周期内：最暗 ", snappedf(lo, 0.001), " 最亮 ", snappedf(hi, 0.001))
	_check("低血量时边框会自己亮起来（心跳）", hi > 0.1)
	_check("心跳是起伏的，不是常亮", lo < hi * 0.5)

	# 血量回到安全线以上，心跳该停
	_player.hp = MinePlayer.MAX_HP
	await _step(int(MineHud.BEAT_PERIOD * 60) + 8)
	_check("血量恢复后心跳停止", hud.hurt_alpha() < 0.01)

	_release_all()
	print("RESULT fail=", _fail)
	get_tree().quit()
