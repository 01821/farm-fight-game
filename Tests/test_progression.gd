extends Node2D

## 端到端自测：成长与专精系统。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_progression.tscn
##
## 分两层测：
##   1) 纯数据层 —— 经验/升级/二选一/各个查询函数
##   2) 真实接入 —— 专精是不是真的改变了游戏行为（售价、浇水范围、生长时间、最大生命、晕倒惩罚）

const TEST_PATH := "user://test_prog_save.json"

var _fail: int = 0
var _level: Node2D
var _player: Player
var _cycle: DayCycle
var _land: FarmLand
var _market: Market
var _ctl: FarmController
var _save: SaveSystem

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _step(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame

func _move_to_tile(tile: Vector2i) -> void:
	_player.global_position = _land.to_global(_land.map_to_local(tile))
	_player.velocity = Vector2.ZERO

func _farm_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in _land.get_used_cells():
		if _land.is_farmland(c):
			out.append(c)
	return out

func _ready() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	Progression.reset()
	Progression.enabled = true

	_level = (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	_save = _level.get_node("SaveSystem") as SaveSystem
	_save.save_path = TEST_PATH
	_save.auto_load = false
	_save.auto_save_on_dawn = false
	await _step(2)

	_player = _level.get_node("level/Player")
	_cycle = _level.get_node("DayCycle")
	_land = _level.get_node("Land")
	_market = _level.get_node("level/Static/Market")
	_ctl = _level.get_node("FarmController")
	_cycle.running = false
	_cycle.day = 7            # 全部作物都解锁，免得干扰

	var region: NavigationRegion2D = _level.get_node("level/animalRegion2D")
	if Level.animalRegion == null:
		Level.animalRegion = region

	var perk_backdrop := _level.get_node("HUD/PerkBackdrop") as ColorRect

	print("--- 数据层 ---")
	_check("Progression 单例存在", Progression != null)
	_check("三个系都从 0 级 0 经验开始", Progression.level_of(0) == 0 and Progression.xp_of(0) == 0)
	_check("初始没有待选专精", Progression.pending_choice == -1)
	_check("初始没有任何专精", Progression.perk_count() == 0)

	Progression.add_xp(Progression.Skill.FARM, 2)
	_check("经验累加", Progression.xp_of(Progression.Skill.FARM) == 2)
	_check("没到阈值不升级", Progression.level_of(Progression.Skill.FARM) == 0)

	Progression.add_xp(Progression.Skill.FARM, 1)
	_check("到 3 点经验升到 1 级", Progression.level_of(Progression.Skill.FARM) == 1)
	_check("升级后弹出二选一", Progression.pending_choice == Progression.Skill.FARM)
	_check("待选项有 2 个", Progression.pending_options().size() == 2)
	_check("待选的是农耕", Progression.pending_skill_name() == "农耕")

	await _step(2)
	_check("升级面板亮起", perk_backdrop.visible == true)
	var opt1 := _level.get_node("HUD/PerkOption1") as Label
	var opt2 := _level.get_node("HUD/PerkOption2") as Label
	print("  INFO ", opt1.text)
	print("  INFO ", opt2.text)
	_check("选项 1 是农夫", "农夫" in opt1.text)
	_check("选项 2 是园丁", "园丁" in opt2.text)

	_check("越界选择被拒", Progression.choose(5) == false)
	_check("选了农夫", Progression.choose(0) == true)
	_check("拿到 farmer 专精", Progression.has_perk("farmer"))
	_check("面板收起", Progression.pending_choice == -1)
	await _step(2)
	_check("升级面板隐藏", perk_backdrop.visible == false)
	_check("重复拿同一个返回 false", Progression.force_perk("farmer") == false)

	Progression.add_xp(Progression.Skill.FARM, 10)
	_check("到 8 点经验升到 2 级", Progression.level_of(Progression.Skill.FARM) == 2)
	_check("第二次也弹二选一", Progression.pending_choice == Progression.Skill.FARM)
	Progression.choose(0)
	_check("第二层拿到育种家", Progression.has_perk("breeder"))

	print("--- 查询函数 ---")
	for perk in ["gardener", "hoarder", "swordsman", "bulwark", "executioner",
			"hunter", "merchant", "saver", "wholesale", "insurance"]:
		Progression.force_perk(perk)
	_check("农夫 + 批发 = 售价 1.35 倍", is_equal_approx(Progression.sell_multiplier(), 1.35))
	_check("商人 = 种子 0.7 倍", is_equal_approx(Progression.seed_price_multiplier(), 0.7))
	_check("育种家 = 生长 0.75 倍", is_equal_approx(Progression.grow_time_multiplier(), 0.75))
	_check("囤积者 = 25% 概率", is_equal_approx(Progression.harvest_bonus_chance(), 0.25))
	_check("园丁 = 半径 1", Progression.water_radius() == 1)
	_check("铁壁 = +3 生命", Progression.max_hp_bonus() == 3)
	_check("剑客 = 范围 1.4 倍", is_equal_approx(Progression.attack_range_multiplier(), 1.4))
	_check("猎手 = 赏金 2 倍", is_equal_approx(Progression.bounty_multiplier(), 2.0))
	_check("处决者生效", Progression.executes_full_hp() == true)
	_check("保险 = 不扣钱", Progression.death_penalty_enabled() == false)
	_check("储户 = 每天 5 金", Progression.daily_interest() == 5)

	print("--- 真实接入 ---")
	# 铁壁：最大生命应当被顶上去，而且顺手补满
	await _step(3)
	print("  INFO 玩家最大生命 = ", _player.max_hp, " 当前 ", _player.hp)
	_check("铁壁把最大生命顶到 8", _player.max_hp == 8)
	_check("上限提高时补了血", _player.hp == 8)

	# 保险：晕倒不掉钱
	_player.money = 100
	_player.take_damage(99)
	_check("有保险时晕倒不掉钱", _player.money == 100)
	_check("晕倒后满血", _player.hp == 8)
	Progression.perks.erase("insurance")
	_player.money = 100
	_player.hp = 1
	_player.take_damage(1)
	_check("没保险时晕倒掉一半", _player.money == 50)
	Progression.force_perk("insurance")

	# 农夫 + 批发：卖价真的变高
	var tiles := _farm_tiles()
	_check("有耕地", tiles.size() > 0)
	if tiles.is_empty():
		_finish()
		return
	_land.clear_all_plants()
	_player.seeds[0] = 5
	_move_to_tile(tiles[0])
	_player.active_item = Player.Item.SEED
	_ctl.use_held_item()
	var plant: BasePlant = _land.plants.get(tiles[0])
	_check("育种家把生长时间缩短到 1.5 秒", plant != null and is_equal_approx(plant.timer.wait_time, 1.5))

	plant.apply_save_data({"type": 0, "stage": 4, "watered": false})
	_check("把它催熟", plant.is_mature())
	_player.active_item = Player.Item.BASKET
	_ctl.use_held_item()
	_move_to(_market.global_position)
	for i in range(12):
		await get_tree().physics_frame
	_player.money = 0
	# ⚠️ 不能硬写「6 金变 8 金」：这一段把**囤积者也解锁了**（25% 概率多收一株），
	#    篮子里是 1 个还是 2 个胡萝卜是随机的，售价自然跟着变。
	#    所以按实际收获数量算期望值，这样测的仍然是"售价倍率有没有生效"。
	var basket_before: int = _player.basket_total()
	_ctl.use_held_item()      # 手持收获篮 = 卖
	var base_price: int = basket_before * CropData.sell_price(0)
	var expected: int = int(round(float(base_price) * 1.35))
	print("  INFO 篮子里 ", basket_before, " 个胡萝卜；原价 ", base_price,
		" 金 → 农夫+批发后应为 ", expected, "，实际 ", _player.money)
	_check("篮子里装了 1~2 个（囤积者可能多送一个）", basket_before >= 1 and basket_before <= 2)
	_check("农夫+批发的售价倍率真的生效了", _player.money == expected)
	_check("确实比原价高", _player.money > base_price)

	# 园丁：浇水覆盖相邻格
	_land.clear_all_plants()
	var pair := _find_adjacent_pair(tiles)
	if pair.size() == 2:
		# 必须先离开商店范围并等物理帧更新，否则 F 会被商店分支抢走（踩过一次了）
		_move_to_tile(pair[0])
		for i in range(12):
			await get_tree().physics_frame
		_check("已离开商店范围", _market.is_player_inside() == false)
		_player.seeds[0] = 5
		for t in pair:
			_move_to_tile(t)
			_player.active_item = Player.Item.SEED
			_ctl.use_held_item()
		var p_a: BasePlant = _land.plants.get(pair[0])
		var p_b: BasePlant = _land.plants.get(pair[1])
		_check("相邻两格都种上了", p_a != null and p_b != null)
		if p_a != null and p_b != null:
			_player.water_left = 5
			_move_to_tile(pair[0])
			_player.active_item = Player.Item.WATER_CAN
			_ctl.use_held_item()
			print("  INFO 浇一格后：A watered=", p_a.is_watered, "  B watered=", p_b.is_watered)
			_check("园丁把相邻那格也浇了", p_a.is_watered and p_b.is_watered)
			_check("只扣了 1 点水", _player.water_left == 4)
	else:
		print("  INFO 没找到相邻耕地，跳过园丁范围测试")

	print("--- 存档 ---")
	var xp_before: int = Progression.xp_of(Progression.Skill.FARM)
	var perks_before: int = Progression.perk_count()
	_save.save_game()
	Progression.reset()
	_check("清空后没有专精", Progression.perk_count() == 0)
	_save.load_game()
	_check("读档后专精回来了", Progression.has_perk("farmer") and Progression.has_perk("insurance"))
	_check("读档后专精数量一致", Progression.perk_count() == perks_before)
	_check("读档后等级回来了", Progression.level_of(Progression.Skill.FARM) == 2)
	print("  INFO 存档前农耕经验 = ", xp_before, "，读档后 = ", Progression.xp_of(Progression.Skill.FARM))
	_check("读档后经验回来了", Progression.xp_of(Progression.Skill.FARM) == xp_before)

	Progression.reset()
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	_finish()

func _find_adjacent_pair(tiles: Array[Vector2i]) -> Array[Vector2i]:
	for t in tiles:
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			if tiles.has(t + d):
				return [t, t + d]
	return []

func _move_to(pos: Vector2) -> void:
	_player.global_position = pos
	_player.velocity = Vector2.ZERO

func _finish() -> void:
	print("RESULT fail=", _fail)
	get_tree().quit()
