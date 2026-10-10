extends Node2D

## 端到端自测：物品栏 + 装备槽 + 关底独特掉落。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_items.tscn
##
## 重点不是"装备表里有几个字段"，而是**装上去之后数值真的变了**：
## 伤害变高、最大生命变大、挨打没那么疼。这三条都能直接量出来。

var _fail: int = 0
var _level: Node2D
var _mine: Node2D
var _player: Player
var _mp: MinePlayer

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

	print("--- 物品表本身 ---")
	print("  INFO 一共 ", ItemData.count(), " 件物品")
	_check("表不是空的", ItemData.count() >= 8)
	var bad := 0
	for id in ItemData.all_ids():
		var it := ItemData.get_item(id)
		if String(it.get("name", "")) == "":
			bad += 1
		var s: int = ItemData.slot_of(id)
		if s < 0 or s >= ItemData.SLOT_NAMES.size():
			bad += 1
	_check("每件都有名字和合法槽位", bad == 0)
	_check("三种槽都有名字", ItemData.slot_name(0) == "武器" and ItemData.slot_name(2) == "饰品")

	_level = (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	var save := _level.get_node("SaveSystem") as SaveSystem
	save.auto_load = false
	save.auto_save_on_dawn = false
	await _step(4)
	_player = _level.get_node("level/Player") as Player

	print("--- 背包 ---")
	_check("一开始背包是空的", _player.inventory.size() == 0)
	_check("没有那件东西", not _player.has_item("iron_sword"))
	_check("拿到一件装备", _player.add_item("iron_sword", 1))
	_check("背包里有了", _player.has_item("iron_sword") and _player.item_count("iron_sword") == 1)
	_check("拿到不存在的物品会被拒", not _player.add_item("no_such_thing"))
	_check("★ 第一次拿到就自动穿上空槽（不用玩家自己想起来去装）",
		_player.equipped_id(ItemData.Slot.WEAPON) == "iron_sword")
	print("  INFO 装备栏：", _player.equipment_line())
	_check("装备栏摘要里有它", "铁剑" in _player.equipment_line())

	print("--- 加成真的算出来了 ---")
	_check("武器加伤害 1", _player.total_damage_bonus() == 1)
	_check("还没穿护甲，减伤 0", _player.total_defense() == 0)
	_player.add_item("iron_plate")
	_check("穿上铁板甲后减伤 2", _player.total_defense() == 2)
	_player.add_item("heart_pendant")
	_check("戴上心之坠后加血 2", _player.total_hp_bonus() == 2)
	print("  INFO 合计：伤害+", _player.total_damage_bonus(),
		" 减伤", _player.total_defense(), " 加血+", _player.total_hp_bonus())

	print("--- 换装备 ---")
	_player.add_item("core_drill")
	_check("换上钻头核心", _player.equip("core_drill"))
	_check("槽里现在是钻头核心", _player.equipped_id(ItemData.Slot.WEAPON) == "core_drill")
	_check("伤害加成跟着涨到 3", _player.total_damage_bonus() == 3)
	_player.unequip(ItemData.Slot.WEAPON)
	_check("脱下来之后加成清零", _player.total_damage_bonus() == 0)
	_player.equip("core_drill")

	print("--- 装到矿洞玩家身上 ---")
	_mine = (load("res://Scenes/Mine/mine_level.tscn") as PackedScene).instantiate()
	add_child(_mine)
	await _step(4)
	_mp = _mine.get_node("MinePlayer") as MinePlayer
	await _step(3)
	print("  INFO MinePlayer 伤害 = ", _mp.attack_damage(), "，最大生命 = ", _mp.max_hp())
	_check("矿洞看到的是基础最大生命 + 饰品加成",
		_mp.max_hp() == MinePlayer.MAX_HP + 2)
	# 基础武器是青铜短剑（+0），所以这里的伤害应该正好等于装备加成
	var bare: int = MineCombatData.get_weapon(_mp.weapon_id).get("damage", 1)
	_check("★ 装备的伤害加成真的算进了攻击力",
		_mp.attack_damage() == bare + _player.total_damage_bonus())

	print("--- 护甲真的减伤，但不会减到无敌 ---")
	_player.unequip(ItemData.Slot.ARMOR)
	_mp.hp = _mp.max_hp()
	_mp._invuln = 0.0
	var full_before: int = _mp.hp
	_mp.take_damage(3, Vector2.ZERO)
	var took_bare: int = full_before - _mp.hp
	print("  INFO 不穿甲挨 3 点，实际掉 ", took_bare)
	_check("不穿甲就实打实掉 3 点", took_bare == 3)

	_player.equip("iron_plate")
	_mp.hp = _mp.max_hp()
	_mp._invuln = 0.0
	full_before = _mp.hp
	_mp.take_damage(3, Vector2.ZERO)
	var took_armored: int = full_before - _mp.hp
	print("  INFO 穿铁板甲（减伤2）挨 3 点，实际掉 ", took_armored)
	_check("★ 穿甲之后掉得少了", took_armored < took_bare)
	_check("正好少掉 2 点", took_armored == 1)

	# 堆够减伤也不能无敌：至少掉 1
	_player.add_item("machine_plate")
	_player.equip("machine_plate")
	_mp.hp = _mp.max_hp()
	_mp._invuln = 0.0
	full_before = _mp.hp
	_mp.take_damage(1, Vector2.ZERO)
	print("  INFO 减伤 2 挨 1 点，实际掉 ", full_before - _mp.hp)
	_check("★ 减伤再高也至少掉 1 点（否则躲不躲都一样，比挨打疼更糟）",
		full_before - _mp.hp == 1)

	print("--- 关底独特掉落 ---")
	_check("第 1 层关底掉铁剑", ItemData.boss_drop(1) == "iron_sword")
	_check("第 3 层关底掉钻头核心", ItemData.boss_drop(3) == "core_drill")
	_check("没定义的层返回空", ItemData.boss_drop(99) == "")

	# 清空背包，模拟"第一次打这层"
	_player.inventory.clear()
	_player.equipped.clear()
	MineRun.depth = 2
	MineRun.pending_unique = ""
	_mine._award_boss_unique()
	await _step(2)
	print("  INFO 第 2 层关底给了：", MineRun.pending_unique, "，背包=", _player.inventory)
	_check("★ 拆掉关底拿到了一件独特装备", _player.has_item("machine_plate"))
	_check("而且自动穿上了", _player.equipped_id(ItemData.Slot.ARMOR) == "machine_plate")
	_check("记下了这趟拆到的是什么", MineRun.pending_unique == "machine_plate")

	# 再拆一次不该重复给
	_player.take_item("machine_plate")
	_player.inventory.erase("machine_plate")
	MineRun.pending_unique = ""
	_mine._award_boss_unique()   # 第一次清掉之后又给了一份
	var count_after_first: int = _player.item_count("machine_plate")
	_mine._award_boss_unique()
	await _step(2)
	print("  INFO 又拆一次之后 machine_plate 数量 = ", _player.item_count("machine_plate"),
		"（第一次之后是 ", count_after_first, "）")
	_check("★ 同一层再拆不会重复给", _player.item_count("machine_plate") == count_after_first)

	print("--- 背包和装备要能存档 ---")
	_player.inventory.clear()
	_player.equipped.clear()
	_player.add_item("core_drill")
	_player.add_item("iron_plate")
	_player.add_item("heart_pendant")
	_player.add_item("lucky_charm", 3)
	var dmg_before: int = _player.total_damage_bonus()
	var hp_before: int = _player.total_hp_bonus()
	var cnt_before: int = _player.item_count("lucky_charm")
	var snap: Dictionary = _player.to_save_data()
	_player.inventory.clear()
	_player.equipped.clear()
	_check("清空之后确实空了", _player.inventory.size() == 0 and _player.total_damage_bonus() == 0)
	_player.apply_save_data(snap)
	print("  INFO 读回来之后的装备栏：", _player.equipment_line())
	_check("读回背包", _player.has_item("core_drill") and _player.has_item("iron_plate"))
	_check("读回数量", _player.item_count("lucky_charm") == cnt_before)
	_check("读回装备", _player.total_damage_bonus() == dmg_before)
	_check("读回饰品加成", _player.total_hp_bonus() == hp_before)

	# 旧档没有这两个字段也不能炸
	_player.apply_save_data({"money": 5})
	_check("旧档读进来不会崩，背包是空的", _player.inventory.size() == 0)

	print("RESULT fail=", _fail)
	get_tree().quit()
