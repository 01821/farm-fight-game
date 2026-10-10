extends Node2D

## 端到端自测：NPC（退休矿工「老铁」）。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_npc.tscn
##
## 重点不是"有个节点在那儿"，而是：
##   ① 他会**跟着你的进度换台词**（去过矿洞没有、拆过关底没有）
##   ② 他提的要求**先验后扣** —— 矿石不够时一样东西都不能动
##   ③ 对话框能用鼠标点

var _fail: int = 0
var _level: Node2D
var _player: Player
var _npc: Npc
var _dlg: DialoguePanel
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
	MineRun.total_runs = 0
	MineRun.total_boss = 0

	_level = (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	var save := _level.get_node("SaveSystem") as SaveSystem
	save.auto_load = false
	save.auto_save_on_dawn = false
	await _step(5)
	_player = _level.get_node("level/Player") as Player
	_ctl = _level.get_node("FarmController") as FarmController
	_npc = _level.get_node_or_null("OldIron") as Npc
	_dlg = _level.get_node_or_null("DialoguePanel") as DialoguePanel

	print("--- 他得是个「人」 ---")
	_check("农场里有这个角色", _npc != null)
	_check("农场里有对话框", _dlg != null)
	if _npc == null or _dlg == null:
		print("RESULT fail=", _fail + 2)
		get_tree().quit()
		return
	print("  INFO 他叫：", _npc.npc_name)
	_check("有名字（不是个无名告示牌）", _npc.npc_name != "")
	_check("他站在农田之外（不会挡住种地）",
		not Rect2(248, 136, 64, 48).has_point(_npc.position))
	_check("对话面板是预建的", _level.get_node_or_null("DialoguePanel/Buttons/TradeButton") != null)

	print("--- 台词跟着状态走 ---")
	_player.npc_done.clear()
	var l0: String = _npc.current_line()
	print("  INFO 没见过世面时：", l0)
	_check("第一次见面说的是他自己", "腿" in l0 or "矿" in l0)

	MineRun.total_runs = 1
	var l1: String = _npc.current_line()
	print("  INFO 下过一次矿之后：", l1)
	_check("★ 下过矿之后他换了台词", l1 != l0)
	_check("而且给的是矿洞里的实用提醒", "火把" in l1)

	MineRun.total_runs = 0
	_player.ore = 0
	print("  INFO 矿石不够时：", _npc.current_line())
	_check("没矿石时他不会谈交易", "石头" not in _npc.current_line())

	print("--- 提要求：先验后扣 ---")
	_check("他确实有要求", not _npc.gift_given())
	_check("矿石不够时交不了", not _npc.can_trade())
	_check("矿石不够时他说缺多少", "0" in _npc.request_text())
	var ore_snap: int = _player.ore
	var inv_snap: int = _player.inventory.size()
	_check("硬交也返回 false", not _npc.trade())
	_check("矿石没动", _player.ore == ore_snap)
	_check("背包没动", _player.inventory.size() == inv_snap)
	_check("标记也没写上", not _npc.gift_given())

	print("--- 料够了：真给东西 ---")
	_player.ore = 5
	_check("现在可以交了", _npc.can_trade())
	print("  INFO 他现在的台词：", _npc.current_line())
	_check("★ 够料时台词变成谈交易", "石头" in _npc.current_line())
	print("  INFO 按钮文字：", _npc.request_text())
	_check("按钮文字写明了换什么", ItemData.name_of(Npc.GIFT) in _npc.request_text())

	var line_after: String = _npc.interact()
	await _step(2)
	print("  INFO 交易后他说的：", line_after)
	_check("拿到护身符了", _player.has_item(Npc.GIFT))
	_check("扣掉了矿石", _player.ore == 5 - Npc.WANT_ORE)
	_check("记下了「给过了」", _npc.gift_given())
	_check("★ 交过之后他换台词了", line_after != l0)
	_check("再想交就交不了了", not _npc.can_trade())
	var inv_after: int = _player.item_count(Npc.GIFT)
	_npc.trade()
	_check("重复交易不会白给", _player.item_count(Npc.GIFT) == inv_after)

	MineRun.total_boss = 1
	var l2: String = _npc.current_line()
	print("  INFO 拆过关底之后：", l2)
	_check("★ 你拆掉关底他会提到这件事", "采掘机械" in l2)

	print("--- 鼠标能点 ---")
	_player.npc_done.clear()
	_player.ore = 0
	_dlg.talk_to(_npc)
	await _step(3)
	_check("对话框打开了", _dlg.is_open)
	_check("暂停了游戏（说话时就该停下来）", get_tree().paused)
	print("  INFO 名字行：", _dlg.name_text(), "；台词：", _dlg.line_text())
	_check("显示了名字", _dlg.name_text() == _npc.npc_name)
	_check("显示了台词", _dlg.line_text() != "")
	_check("料不够时按钮是暗的", not _dlg.trade_enabled())
	# ⚠️ 别断言"没有护身符" —— 前面那轮交易**已经给过一个了**，
	#    "有没有"恒为真。要比的是**数量有没有变**。
	var charm_before: int = _player.item_count(Npc.GIFT)
	_dlg.click_trade()
	await _step(2)
	_check("点了也不给东西（数量没变）", _player.item_count(Npc.GIFT) == charm_before)

	_player.ore = 9
	_dlg.set_open(true)
	await _step(3)
	_check("料够了按钮就亮了", _dlg.trade_enabled())
	_dlg.click_trade()
	await _step(3)
	print("  INFO 点完之后：", _dlg.line_text())
	_check("★ 鼠标点一下就真的成交了", _player.has_item(Npc.GIFT))
	_check("矿石扣了", _player.ore == 9 - Npc.WANT_ORE)
	_dlg.set_open(false)
	await _step(2)
	_check("关掉之后游戏恢复", not get_tree().paused)

	print("--- 站在他旁边按 F 会开口 ---")
	_player.global_position = _npc.global_position
	await _step(5)
	_check("检测到玩家在附近", _npc.is_player_inside())
	var opened: bool = _ctl.use_held_item()
	await _step(3)
	print("  INFO use_held_item 返回 ", opened, "，对话框开着=", _dlg.is_open)
	_check("★ 站他旁边按 F 打开了对话", _dlg.is_open)
	_dlg.set_open(false)
	await _step(2)

	print("--- 进度要能存档 ---")
	_player.npc_done.clear()
	_player.npc_done[Npc.FLAG] = true
	var snap: Dictionary = _player.to_save_data()
	_player.npc_done.clear()
	_check("清空之后他当作没给过", not _npc.gift_given())
	_player.apply_save_data(snap)
	_check("★ 读档之后他还记得给过了", _npc.gift_given())
	_player.apply_save_data({"money": 1})
	_check("旧档没有 npc_done 字段也不会崩", _player.npc_done.size() == 0)

	print("RESULT fail=", _fail)
	get_tree().quit()
