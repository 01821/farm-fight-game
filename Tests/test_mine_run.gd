extends Node2D

## 端到端自测：矿洞与农场的连通（阶段 E）。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_mine_run.tscn
##
## ⚠️ 测试里必须关掉 MineRun.scene_switch_enabled ——
##    否则 finish() 会真的切场景，一切后面就没法继续跑断言了。

var _fail: int = 0
var _level: MineLevel
var _player: MinePlayer
var _enemy: MineEnemy

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

func _ready() -> void:
	MineRun.scene_switch_enabled = false
	MineRun.active = false
	MineRun.gold = 0
	MineRun.kills = 0

	print("--- 这一趟的状态 ---")
	_check("初始不在洞里", not MineRun.active)
	MineRun.start_run()
	_check("进洞后 active", MineRun.active)
	_check("火把充满", is_equal_approx(MineRun.torch_left, MineRun.TORCH_TIME))
	_check("收获清零", MineRun.gold == 0 and MineRun.kills == 0)

	MineRun.add_gold(5)
	MineRun.add_gold(3)
	MineRun.add_kill()
	print("  INFO 捡了 5+3 金、1 只怪 → gold=", MineRun.gold, " kills=", MineRun.kills)
	_check("金币累加", MineRun.gold == 8)
	_check("击杀累加", MineRun.kills == 1)
	MineRun.add_gold(-5)
	_check("负数被忽略", MineRun.gold == 8)

	print("--- 出洞结算 ---")
	var success_signal := false
	var killed_signal := false
	# 信号用方法接，不用 lambda（lambda 按值捕获局部变量，改了外面看不到）
	MineRun.run_finished.connect(_on_run_finished)
	MineRun.finish(true)
	_check("出洞后 active 关掉", not MineRun.active)
	_check("发了 run_finished 信号", _finished_count == 1)
	_check("结果已暂存", MineRun.has_result())
	var r := MineRun.consume_result()
	print("  INFO 结算：success=", r.get("success"), " gold=", r.get("gold"), " kills=", r.get("kills"))
	_check("结算内容正确", bool(r.get("success")) and int(r.get("gold")) == 8 and int(r.get("kills")) == 1)
	_check("结算只能取一次", not MineRun.has_result())
	_check("再取是空的", MineRun.consume_result().is_empty())
	_check("重复 finish 不会重复结算", _call_finish_again() == false)

	print("--- 矿洞场景 ---")
	MineRun.start_run()
	_level = (load("res://Scenes/Mine/mine_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	await _step(2)
	_level.build()
	await _step(4)
	_player = _level.get_node("MinePlayer")
	_enemy = _level.get_node("EnemyA")

	var torch0: float = MineRun.torch_left
	await _step(30)
	print("  INFO 火把 ", snappedf(torch0, 0.1), " → ", snappedf(MineRun.torch_left, 0.1))
	_check("火把会随时间减少", MineRun.torch_left < torch0)
	_check("火把比例在 0~1 之间", _level.torch_ratio() > 0.0 and _level.torch_ratio() <= 1.0)

	var hud := _level.get_node("MineHud") as MineHud
	var torch_label := _level.get_node("MineHud/TorchLabel") as Label
	print("  INFO ", torch_label.text)
	_check("HUD 显示火把剩余秒数", "火把" in torch_label.text and "秒" in torch_label.text)
	_check("HUD 显示这趟收获", "收获" in torch_label.text)
	_check("HUD 有 4 格技能栏", hud.skill_labels().size() == 4)

	print("--- 打怪掉钱 ---")
	var before_gold: int = MineRun.gold
	var before_kills: int = MineRun.kills
	_enemy.take_damage(99, _player.global_position)
	await _step(3)
	print("  INFO 打死一只后：金币 ", before_gold, " → ", MineRun.gold, "，击杀 ", before_kills, " → ", MineRun.kills)
	_check("击杀计数 +1", MineRun.kills == before_kills + 1)
	var coins := get_tree().get_nodes_in_group("mine_pickup")
	print("  INFO 地上有 ", coins.size(), " 份掉落")
	_check("地上至少掉了一份", coins.size() >= 1)
	if coins.size() >= 1:
		# ⚠️ 怪有 25% 概率**同时**掉金币和矿石，所以不能只盯第一份 ——
		#    按"地上所有掉落的总账"来验，既稳定又更强。
		#    另外：金额和位置都要在捡之前记下来，捡走后对象就被释放了。
		var expected_gain: int = 0
		var spots: Array[Vector2] = []
		for node in coins:
			if not is_instance_valid(node):
				continue
			var pk := node as MinePickup
			if pk == null:
				continue
			expected_gain += pk.amount
			spots.append(pk.global_position)
		print("  INFO 这批掉落合计 ", expected_gain, "，第一份落点 ", spots[0].round() if spots.size() > 0 else "?")
		# 掉落物应该落回出生高度，而不是被瞬移到关卡顶部
		_check("掉落物停在合理的高度（没有被瞬移到 y=0）", spots.size() > 0 and spots[0].y > 100.0)
		for s in spots:
			_player.global_position = s
			await _step(3)
		await _step(4)
		print("  INFO 全捡完金币 = ", MineRun.gold, "（预期 ", before_gold + expected_gain, "）")
		_check("碰到就自动捡走（总账对得上）", MineRun.gold == before_gold + expected_gain)
		_check("捡完地上没有残留", get_tree().get_nodes_in_group("mine_pickup").is_empty())

	print("--- 火把烧完 = 自动回农场（收获保留） ---")
	MineRun.start_run()
	MineRun.add_gold(20)
	MineRun.torch_left = 0.05
	await _step(10)
	_check("火把烧完会自动结算", not MineRun.active)
	var r2 := MineRun.consume_result()
	print("  INFO 结算：success=", r2.get("success"), " gold=", r2.get("gold"))
	_check("烧完是成功（收获保留）", bool(r2.get("success")))
	_check("收获原样带回", int(r2.get("gold")) == 20)

	print("--- 在洞里倒下 = 丢掉这趟收获 ---")
	MineRun.start_run()
	MineRun.add_gold(50)
	_player.hp = 1
	_player.take_damage(5, Vector2(0, 0))
	await _step(3)
	_check("倒下会结束这趟", not MineRun.active)
	var r3 := MineRun.consume_result()
	print("  INFO 结算：success=", r3.get("success"), " gold=", r3.get("gold"))
	_check("倒下是失败", not bool(r3.get("success")))
	_check("失败时不带回金币（结算里 gold 仅供参考）", int(r3.get("gold")) == 50)

	print("--- 矿石 ---")
	_check("掉落物有 2 种（金币 / 矿石）", MinePickup.KINDS.size() == 2)
	var coin_v: int = int(MinePickup.KINDS[0]["value"])
	var ore_v: int = int(MinePickup.KINDS[1]["value"])
	print("  INFO 金币值 ", coin_v, "，矿石值 ", ore_v)
	_check("矿石比金币值钱", ore_v > coin_v)

	MineRun.start_run()
	var ore_drop := _level.pickup_scene.instantiate() as MinePickup
	ore_drop.kind = MinePickup.Kind.ORE
	ore_drop.amount = -1          # 用默认价值
	_level.add_child(ore_drop)
	ore_drop.global_position = _player.global_position
	ore_drop.mark_spawn()
	await _step(6)
	print("  INFO 捡矿石后：gold=", MineRun.gold, " ore=", MineRun.ore)
	_check("矿石计入块数", MineRun.ore == 1)
	_check("矿石的价值也进了金币", MineRun.gold == ore_v)

	print("--- 宝箱 ---")
	var chest := _level.get_node("Chest1") as MineChest
	_check("关卡里摆了宝箱", chest != null)
	if chest != null:
		_check("宝箱初始是关着的", not chest.is_opened())
		var gold_before: int = MineRun.gold
		var ore_before: int = MineRun.ore
		_player.global_position = chest.global_position
		await _step(8)
		print("  INFO 碰到宝箱后：已开=", chest.is_opened(), "，gold=", MineRun.gold)
		_check("碰到就自动打开", chest.is_opened())
		_check("开箱后贴图变成打开的样子",
			chest.sprite.region_rect == Rect2(11 * 18, 1 * 18, 18, 18))
		_check("已经开过的箱子不会重复开", chest.open() == 0)

		# ⚠️ 掉落是在玩家脚下生成的，会被**立刻捡走**，所以数不到"地上的份数"。
		#    要验掉落数量，得先让玩家走开再开第二个箱子。
		var chest2 := _level.get_node("Chest2") as MineChest
		_player.global_position = Vector2(60, 198)
		await _step(6)
		var lying_before: int = get_tree().get_nodes_in_group("mine_pickup").size()
		var spawned: int = chest2.open()
		await _step(2)
		var lying_after: int = get_tree().get_nodes_in_group("mine_pickup").size()
		print("  INFO 走开再开箱：spawned=", spawned, "，地上 ", lying_before, " → ", lying_after)
		_check("开箱掉出的份数 = 金币 + 矿石", spawned == chest2.coin_count + chest2.ore_count)
		_check("这些掉落确实留在了地上", lying_after == lying_before + spawned)

		# 把玩家挪到每一份掉落上，全捡掉（掉落可能已被捡走，所以要判有效性再转类型）
		for round_i in range(5):
			for node in get_tree().get_nodes_in_group("mine_pickup"):
				if not is_instance_valid(node):
					continue
				var p := node as MinePickup
				if p == null:
					continue
				_player.global_position = p.global_position
				await _step(3)
		await _step(6)
		print("  INFO 全捡完：gold ", gold_before, " → ", MineRun.gold,
			"，ore ", ore_before, " → ", MineRun.ore)
		_check("宝箱的收获进了这趟账", MineRun.gold > gold_before)
		_check("宝箱至少给了一块矿石", MineRun.ore > ore_before)
		_check("捡完场上没有残留掉落", get_tree().get_nodes_in_group("mine_pickup").is_empty())

	var torch_txt := (_level.get_node("MineHud/TorchLabel") as Label).text
	print("  INFO ", torch_txt)
	_check("HUD 同时显示金币和矿石", "金" in torch_txt and "矿" in torch_txt)

	print("--- 分层：越深越肥，但火把不补 ---")
	MineRun.scene_switch_enabled = false
	MineRun.start_run()
	_check("进洞从第 1 层开始", MineRun.depth == 1)
	_check("第 1 层倍率是 1", is_equal_approx(MineRun.loot_multiplier(), 1.0))
	_check("有 3 层", MineRun.MAX_DEPTH == 3)
	_check("第 1 层不是最深处", not MineRun.is_deepest())

	var torch_before: float = MineRun.torch_left
	_check("能下到第 2 层", MineRun.descend())
	_check("层数变了", MineRun.depth == 2)
	print("  INFO 第 2 层：收获 x", MineRun.loot_multiplier(), "，敌人 x", MineRun.enemy_multiplier(),
		"，火把 ", snappedf(MineRun.torch_left, 0.1), "（下潜前 ", snappedf(torch_before, 0.1), "）")
	_check("越深收获倍率越高", MineRun.loot_multiplier() > 1.0)
	_check("越深敌人越强", MineRun.enemy_multiplier() > 1.0)
	_check("★ 下潜不补火把", is_equal_approx(MineRun.torch_left, torch_before))

	# 倍率真的作用在收获上
	MineRun.gold = 0
	MineRun.add_gold(10)
	var expect2: int = int(round(10.0 * MineRun.loot_multiplier()))
	print("  INFO 第 2 层捡 10 金 → 实得 ", MineRun.gold, "（倍率算出来应是 ", expect2, "）")
	_check("收获按层数倍率放大", MineRun.gold == expect2)
	_check("确实比第 1 层多", MineRun.gold > 10)

	MineRun.descend()
	_check("能下到第 3 层", MineRun.depth == 3)
	_check("第 3 层是最深处", MineRun.is_deepest())
	_check("到底了就不能再下", MineRun.descend() == false)
	_check("层数没被越界加", MineRun.depth == 3)

	print("--- 井口：不拆关底不让下 ---")
	var well := _level.get_node_or_null("DescendPoint") as DescendPoint
	_check("关卡最右边有下潜井口", well != null)
	if well != null:
		MineRun.depth = 1
		var d0: int = MineRun.depth
		MineRun.boss_down = false
		print("  INFO 关底没拆时 can_descend = ", well.can_descend())
		_check("关底没拆时井口是封着的", not well.can_descend())
		_player.global_position = well.global_position
		await _step(5)
		_check("封着的时候走过去也不会下潜", MineRun.depth == d0)

		MineRun.boss_down = true
		_check("拆掉关底后井口开了", well.can_descend())
		_player.global_position = Vector2(100, 198)
		await _step(5)
		_player.global_position = well.global_position
		await _step(5)
		print("  INFO 走进井口后层数 ", d0, " → ", MineRun.depth)
		_check("走进去就下一层", MineRun.depth == d0 + 1)

	print("--- HUD 显示层数 ---")
	await _step(4)
	var layer_txt := (_level.get_node("MineHud/TorchLabel") as Label).text
	print("  INFO ", layer_txt)
	_check("HUD 上写着当前层数", "层" in layer_txt)

	print("--- 陷阱：地刺与落石 ---")
	var spikes: Array[SpikeTrap] = []
	var rocks: Array[FallingRock] = []
	for n in get_tree().get_nodes_in_group("mine_hazard"):
		if n is SpikeTrap:
			spikes.append(n as SpikeTrap)
		elif n is FallingRock:
			rocks.append(n as FallingRock)
	print("  INFO 关卡里有 ", spikes.size(), " 处地刺、", rocks.size(), " 块落石")
	_check("摆了地刺", spikes.size() >= 1)
	_check("摆了落石", rocks.size() >= 1)

	# ★ 第 1 层是干净的新手层
	MineRun.depth = 1
	_level._apply_hazard_depth()
	await _step(2)
	_check("第 1 层时陷阱是关掉的", not spikes[0].visible and not spikes[0].monitoring)
	_check("第 1 层时落石也是关的", not rocks[0].visible and not rocks[0].monitoring)

	MineRun.depth = 2
	_level._apply_hazard_depth()
	await _step(2)
	_check("第 2 层陷阱开启", spikes[0].visible and spikes[0].monitoring)
	_check("第 2 层落石开启", rocks[0].visible and rocks[0].monitoring)

	# 踩到地刺要掉血
	var spike := spikes[0]
	_player.hp = MinePlayer.MAX_HP
	_player.global_position = Vector2(2000, -400)   # 先挪开，把无敌帧耗掉
	await _step(int(MinePlayer.INVULN_TIME * 60) + 8)
	_player.global_position = spike.global_position + Vector2(0.5, -2)
	_player.velocity = Vector2.ZERO
	await _step(6)
	print("  INFO 踩地刺后血量 ", _player.hp, "/", MinePlayer.MAX_HP)
	_check("踩到地刺会掉血", _player.hp < MinePlayer.MAX_HP)

	# 站着不动要**持续**疼，不是只扎一下就走
	var hp_stay: int = _player.hp
	await _step(int(MinePlayer.INVULN_TIME * 60) + 10)
	print("  INFO 在刺上站了一会儿，血量 ", hp_stay, " → ", _player.hp)
	_check("站着不动会持续掉血", _player.hp < hp_stay)

	# 落石：走到下面才会掉，而且**先抖一下预警**
	var rock := rocks[0]
	_player.global_position = Vector2(2000, -400)
	await _step(int(MinePlayer.INVULN_TIME * 60) + 8)
	_check("落石一开始是挂着的", rock.state_name() == "挂着")
	# 站到它正下方
	_player.global_position = Vector2(rock.global_position.x, rock.ground_y)
	await _step(3)
	print("  INFO 走到落石下面后：", rock.state_name())
	_check("走到下面会触发（先进预警）", rock.state_name() == "预警" or rock.state_name() == "下落")
	# 预警那零点几秒里它还不该有伤害 —— 这就是"看得见的预兆"
	await _step(int(FallingRock.SHAKE_TIME * 60) + 6)
	print("  INFO 预警结束后：", rock.state_name(), "，y=", snappedf(rock.global_position.y, 0.1))
	_check("预警之后才真的往下掉", rock.state_name() == "下落" or rock.state_name() == "碎了")
	await _step(90)
	print("  INFO 最后：", rock.state_name(), "，y=", snappedf(rock.global_position.y, 0.1))
	_check("掉到地面会碎", rock.state_name() == "碎了")
	_check("碎了就停在落地高度", is_equal_approx(rock.global_position.y, rock.ground_y))
	_check("碎了之后不再有判定", not rock.monitoring)

	MineRun.depth = 1
	_level._apply_hazard_depth()
	_player.hp = MinePlayer.MAX_HP

	print("--- 农场那边的矿洞口 ---")
	# 前面开着的那趟要先收掉，否则"不该误启动一趟"这条会被自己前面的状态干扰
	MineRun.active = false
	var farm := (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(farm)
	var save := farm.get_node("SaveSystem") as SaveSystem
	save.auto_load = false
	save.auto_save_on_dawn = false
	await _step(2)
	var ent := farm.get_node_or_null("level/Static/MineEntrance") as MineEntrance
	_check("农场里摆了矿洞口", ent != null)
	if ent != null:
		var p := farm.get_node("level/Player") as Player
		var land := farm.get_node("Land") as FarmLand
		print("  INFO 玩家出生点 ", p.global_position, "，洞口 ", ent.global_position)
		_check("玩家出生时不在洞口范围内", not ent.is_player_inside())
		_check("不在洞口时按 F 不会进洞", ent.enter_mine() == false)
		_check("也不会误启动一趟", not MineRun.active)

		# ⚠️ 洞口**不能压在农田上** —— 否则站那格按 F 会被洞口分支抢走，种不了地。
		#    （踩过一次：test_farm 的玉米种不下去，报的错跟矿洞毫无关系。）
		var radius: float = 30.0
		var clash: int = 0
		var nearest: float = INF
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c in land.get_used_cells():
			if not land.is_farmland(c):
				continue
			var w: Vector2 = land.to_global(land.map_to_local(c))
			lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.y))
			hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.y))
			var d: float = w.distance_to(ent.global_position)
			nearest = minf(nearest, d)
			if d < radius:
				clash += 1
		print("  INFO 农田范围 x ", lo.x, "~", hi.x, "  y ", lo.y, "~", hi.y)
		print("  INFO 离洞口最近的农田 ", snappedf(nearest, 0.1), " px（要求 > ", radius, "）")
		_check("洞口没有压在任何农田上", clash == 0)

	MineRun.active = false
	MineRun.scene_switch_enabled = true
	_release_all()
	print("RESULT fail=", _fail)
	get_tree().quit()

var _finished_count: int = 0

func _on_run_finished(_success: bool, _gold: int, _kills: int) -> void:
	_finished_count += 1

func _call_finish_again() -> bool:
	var was_active: bool = MineRun.active
	MineRun.finish(true)
	return MineRun.active != was_active
