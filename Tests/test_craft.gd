extends Node2D

## 端到端自测：合成系统（加工坊配方台）。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_craft.tscn
##
## 重点是**"能不能做"和真做一次的结果必须一致**：
## 缺料时按钮要暗、点了什么都不能变；够料时点一下东西真的到手。

var _fail: int = 0
var _level: Node2D
var _player: Player
var _panel: CanvasLayer
var _ctl: FarmController

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

	print("--- 配方表 ---")
	print("  INFO 一共 ", RecipeData.count(), " 条配方")
	_check("有配方", RecipeData.count() >= 4)
	var bad := 0
	for i in range(RecipeData.count()):
		var r := RecipeData.at(i)
		var id: String = String(r.get("id", ""))
		if not ItemData.exists(id):
			bad += 1          # 产出必须是物品表里真有的东西
		if RecipeData.total_crops(r) == 0 and int(r.get("ore", 0)) == 0:
			bad += 1          # 一条配方总得要点实物，不能纯金币
	_check("★ 每条配方的产出都在物品表里，而且都要实物", bad == 0)
	for i in range(RecipeData.count()):
		print("  INFO ", RecipeData.describe(RecipeData.at(i)))
	# 必须是"矿洞的产出 + 农场的产出"混着用，否则两条线还是没咬合
	var uses_ore := false
	var uses_crops := false
	for i in range(RecipeData.count()):
		var r := RecipeData.at(i)
		if int(r.get("ore", 0)) > 0:
			uses_ore = true
		if RecipeData.total_crops(r) > 0:
			uses_crops = true
	_check("★ 配方同时吃矿石和作物（两条线真的咬上了）", uses_ore and uses_crops)

	_level = (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	var save := _level.get_node("SaveSystem") as SaveSystem
	save.auto_load = false
	save.auto_save_on_dawn = false
	await _step(4)
	_player = _level.get_node("level/Player") as Player
	_ctl = _level.get_node("FarmController") as FarmController
	_panel = _level.get_node_or_null("CraftPanel") as CanvasLayer
	_check("农场里挂了配方台", _panel != null)
	if _panel == null:
		print("RESULT fail=", _fail + 1)
		get_tree().quit()
		return
	_check("配方台是预建的（不是运行时造的）", _level.get_node_or_null("CraftPanel/Rows/Row5") != null)

	print("--- 缺料：按钮该是暗的、点了什么都不能变 ---")
	_player.money = 0
	_player.ore = 0
	_player.harvested = [0, 0, 0]
	_panel.set_open(true)
	await _step(3)
	_check("面板打开了", _panel.is_open)
	var r0 := RecipeData.at(0)
	print("  INFO 第 1 行：", _panel.row_text(0))
	print("  INFO 缺料说明：", RecipeData.missing(r0, _player))
	_check("缺料时那一行是点不动的", not _panel.row_enabled(0))
	_check("文字里说明了缺什么", "缺" in _panel.row_text(0))
	var money_before: int = _player.money
	var inv_before: int = _player.inventory.size()
	_panel.click_row(0)
	await _step(3)
	_check("点了也不扣钱", _player.money == money_before)
	_check("点了也不给东西", _player.inventory.size() == inv_before)
	_check("没有能做的配方时 first_craftable 返回 -1", RecipeData.first_craftable(_player) == -1)

	print("--- 只缺一样 ---")
	_player.ore = 99
	_player.money = 9999
	_player.harvested = [0, 0, 0]
	# 第 0 条要 2 个 0 号作物，现在一个都没有
	print("  INFO 缺料说明：", RecipeData.missing(r0, _player))
	_check("只缺作物时也做不了", not RecipeData.can_craft(r0, _player))
	_check("说明里点名了作物", CropData.name_of(0) in RecipeData.missing(r0, _player))

	print("--- 料够了：鼠标点一下就真做出来 ---")
	_player.harvested[0] = 2
	var ore_before: int = _player.ore
	var gold_before: int = _player.money
	var crop_before: int = _player.harvested[0]
	_panel.set_open(true)
	await _step(3)
	_check("这一行现在点得动了", _panel.row_enabled(0))
	print("  INFO 第 1 行：", _panel.row_text(0))
	_panel.click_row(0)
	await _step(3)
	print("  INFO 状态栏：", _panel.status_text())
	_check("★ 拿到成品了", _player.has_item(String(r0.get("id", ""))))
	_check("扣了矿石", _player.ore == ore_before - int(r0.get("ore", 0)))
	_check("扣了金币", _player.money == gold_before - int(r0.get("gold", 0)))
	_check("扣了作物", _player.harvested[0] == crop_before - RecipeData.crop_need(r0, 0))
	_check("累计加工数 +1", _player.total_crafted >= 1)
	_check("状态栏给了反馈", _panel.status_text() != "")

	print("--- 失败时必须是「什么都没发生」 ---")
	_player.harvested = [0, 0, 0]
	var gold_snap: int = _player.money
	var ore_snap: int = _player.ore
	var inv_snap: int = _player.inventory.size()
	_check("can_craft 说不行", not RecipeData.can_craft(r0, _player))
	_check("craft 也返回 false", not RecipeData.craft(r0, _player))
	_check("钱没动", _player.money == gold_snap)
	_check("矿石没动", _player.ore == ore_snap)
	_check("背包没动", _player.inventory.size() == inv_snap)

	print("--- 能做的行会自己亮起来 ---")
	_player.ore = 99
	_player.money = 9999
	_player.harvested = [9, 9, 9]
	_panel.set_open(true)
	await _step(3)
	var lit := 0
	for i in range(RecipeData.count()):
		if _panel.row_enabled(i):
			lit += 1
	print("  INFO 料全够时亮着的行数 = ", lit, "/", RecipeData.count())
	_check("料够了每一条都亮", lit == RecipeData.count())

	print("--- 在加工坊按 F 会打开配方台 ---")
	_panel.set_open(false)
	await _step(2)
	var mill := _level.get_node("level/Static/Mill") as Node2D
	_player.global_position = mill.global_position
	await _step(4)
	_check("玩家站在加工坊范围内", (_level.get_node("level/Static/Mill") as Mill).is_player_inside())
	var opened: bool = _ctl.use_held_item()
	await _step(3)
	print("  INFO use_held_item 返回 ", opened, "，面板开着=", _panel.is_open)
	_check("★ 在加工坊按 F 打开了配方台", _panel.is_open)
	_check("而且算用过了（返回 true）", opened)
	_panel.set_open(false)

	print("--- 矿石要能存档 ---")
	_player.ore = 17
	_player.total_crafted = 5
	var snap: Dictionary = _player.to_save_data()
	_player.ore = 0
	_player.total_crafted = 0
	_player.apply_save_data(snap)
	_check("矿石读回来了", _player.ore == 17)
	_check("加工次数读回来了", _player.total_crafted == 5)
	_player.apply_save_data({"money": 1})
	_check("旧档没有 ore 字段也不会崩", _player.ore == 0)

	print("RESULT fail=", _fail)
	get_tree().quit()
