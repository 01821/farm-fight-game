extends Node2D

## 端到端自测：稀有掉落 + 金色精英怪 + 遗物带回农场。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_elite.tscn
##
## 这一套是为了让矿洞**不再完全可预测**：
##   打完一只怪掉什么，以前是能算出来的；现在有宝石、有遗物、有金色精英。

var _fail: int = 0
var _level: Node2D
var _mine: Node2D
var _player: Player

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
	MineRun.scene_switch_enabled = false
	MineRun.active = false
	MineRun.depth = 1

	_level = (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	var save := _level.get_node("SaveSystem") as SaveSystem
	save.auto_load = false
	save.auto_save_on_dawn = false
	await _step(4)
	_player = _level.get_node("level/Player") as Player

	print("--- 掉落物表 ---")
	print("  INFO 一共 ", MinePickup.KINDS.size(), " 种")
	_check("至少 4 种", MinePickup.KINDS.size() >= 4)
	_check("宝石的定义在", MinePickup.Kind.GEM < MinePickup.KINDS.size())
	_check("遗物的定义在", MinePickup.Kind.RELIC < MinePickup.KINDS.size())
	var gem: Dictionary = MinePickup.KINDS[MinePickup.Kind.GEM]
	var ore: Dictionary = MinePickup.KINDS[MinePickup.Kind.ORE]
	print("  INFO 宝石值 ", gem.get("value"), "，矿石值 ", ore.get("value"))
	_check("★ 宝石比矿石值钱得多", int(gem.get("value", 0)) > int(ore.get("value", 0)) * 2)
	_check("宝石和矿石是不同颜色（不然分不出来）",
		gem.get("tint", Color.WHITE) != ore.get("tint", Color.WHITE))

	print("--- 金色精英 ---")
	MineRun.start_run()
	MineRun.depth = 1
	_mine = (load("res://Scenes/Mine/mine_level.tscn") as PackedScene).instantiate()
	add_child(_mine)
	await _step(4)
	_mine.build()
	await _step(8)

	var elites: Array[MineEnemy] = []
	var normals: Array[MineEnemy] = []
	for n in get_tree().get_nodes_in_group("mine_enemy"):
		var e := n as MineEnemy
		if e == null or not is_instance_valid(e) or e.is_boss():
			continue
		if e.is_elite:
			elites.append(e)
		else:
			normals.append(e)
	print("  INFO 第 1 层：精英 ", elites.size(), " 只，普通 ", normals.size(), " 只")
	_check("★ 第 1 层会点出精英", elites.size() >= 1)
	_check("不是所有怪都变精英（不然就不稀罕了）", normals.size() >= 1)

	if elites.size() > 0:
		var el: MineEnemy = elites[0]
		print("  INFO 精英叫「", el.display_name(), "」血 ", el.hp, "/", el.max_hp,
			" 颜色 ", el.sprite.modulate)
		_check("精英血比基础值多", el.max_hp > 2)
		_check("精英名字前有「金色」", "金色" in el.display_name())
		_check("★ 精英是金色的", el.sprite.modulate.r > el.sprite.modulate.b)
		_check("精英个头更大", el.sprite.scale.x > 1.0)

		# ⚠️ 闪白结束之后必须**回到金色**，不能变成白的
		el.take_damage(1, Vector2.ZERO)
		await _step(20)
		print("  INFO 挨打闪白之后颜色 ", el.sprite.modulate)
		_check("★ 挨打闪白结束后变回金色（不是白）", el.sprite.modulate.r > el.sprite.modulate.b)

		print("--- 精英死了必掉好东西 ---")
		# ⚠️ 怪死掉时节点会被 queue_free。所以**该读的值要在杀它之前读出来** ——
		#    杀完之后再碰它就是 "previously freed"（这里踩了两次）。
		var elite_max_hp: int = el.max_hp
		el.take_damage(999, Vector2.ZERO)
		await _step(6)
		var kinds: Array[int] = []
		for n in get_tree().get_nodes_in_group("mine_pickup"):
			var p := n as MinePickup
			if p != null and is_instance_valid(p):
				kinds.append(p.kind)
		print("  INFO 掉了 ", kinds.size(), " 个东西，种类 ", kinds)
		_check("★ 精英掉东西了", kinds.size() > 0)
		_check("★ 精英必掉宝石", kinds.has(MinePickup.Kind.GEM))
		_check("精英的 max_hp 确实被加成过（死前记下来的）", elite_max_hp > 2)

	print("--- 遗物：捡到的是装备，不是钱 ---")
	# 清空战场上的掉落物，免得干扰
	for n in get_tree().get_nodes_in_group("mine_pickup"):
		n.queue_free()
	await _step(3)
	MineRun.pending_items.clear()
	var from := Vector2(200, 180)
	_mine._spawn_relic(from)
	await _step(4)
	var relic: MinePickup = null
	for n in get_tree().get_nodes_in_group("mine_pickup"):
		var p := n as MinePickup
		if p != null and p.kind == MinePickup.Kind.RELIC:
			relic = p
	_check("★ 生成出了遗物掉落物", relic != null)
	if relic != null:
		# ⚠️ 捡走之后掉落物就 queue_free 了 —— **先把 id 记下来**再用。
		var relic_id: String = relic.item_id
		print("  INFO 遗物带的是：", relic_id, "（", ItemData.name_of(relic_id), "）")
		_check("遗物带着一个真的物品 id", ItemData.exists(relic_id))
		# 让矿洞玩家去碰它
		var mp := _mine.get_node("MinePlayer") as MinePlayer
		mp.global_position = relic.global_position
		await _step(6)
		print("  INFO 捡完之后 MineRun.pending_items = ", MineRun.pending_items)
		_check("★ 捡到之后记进了这趟的收获", MineRun.pending_items.has(relic_id))

	print("--- 死了就丢掉（包括遗物）---")
	MineRun.finish(false)
	var lost: Dictionary = MineRun.consume_result()
	print("  INFO 倒下出洞的结算 items = ", lost.get("items", []))
	_check("★ 在洞里倒下时遗物一件都带不回去", (lost.get("items", []) as Array).is_empty())

	print("--- 活着回去才到手 ---")
	MineRun.start_run()
	MineRun.add_item("heart_pendant")
	MineRun.finish(true)
	var won: Dictionary = MineRun.consume_result()
	print("  INFO 活着出洞的结算 items = ", won.get("items", []))
	_check("★ 活着回去时遗物在结算里", (won.get("items", []) as Array).has("heart_pendant"))

	# 走一遍真实的结算路径，看装备有没有真的进玩家背包
	_player.inventory.clear()
	_player.equipped.clear()
	_player.ore = 0
	MineRun.start_run()
	MineRun.add_item("iron_plate")
	MineRun.finish(true)
	var entrance := _level.get_node("level/Static/MineEntrance") as MineEntrance
	entrance._settle_previous_run()
	await _step(3)
	print("  INFO 结算之后背包 = ", _player.inventory)
	_check("★★ 遗物真的进了玩家背包", _player.has_item("iron_plate"))

	print("RESULT fail=", _fail)
	get_tree().quit()
