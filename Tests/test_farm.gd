extends Node2D

## 端到端自测：手持道具分发 → 农场循环 → 商店经济 → 水源补水 → HUD。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_farm.tscn
##
## 全程尽量走 FarmController.use_held_item()，也就是玩家真正会走的那条路径。

var _fail: int = 0
var _level: Node2D
var _land: FarmLand
var _player: Player
var _market: Market
var _ctl: FarmController

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _move_to(pos: Vector2) -> void:
	_player.global_position = pos
	_player.velocity = Vector2.ZERO

func _move_to_tile(tile: Vector2i) -> void:
	_move_to(_land.to_global(_land.map_to_local(tile)))

func _ready() -> void:
	var ps := load("res://Scenes/base_level.tscn") as PackedScene
	_level = ps.instantiate()
	add_child(_level)
	# 测试绝不能碰玩家真正的存档
	var save_sys := _level.get_node("SaveSystem") as SaveSystem
	save_sys.auto_load = false
	save_sys.auto_save_on_dawn = false
	await get_tree().process_frame
	await get_tree().process_frame

	_land = _level.get_node("Land")
	_player = _level.get_node("level/Player")
	_market = _level.get_node("level/Static/Market")
	_ctl = _level.get_node("FarmController")

	# 测试场景不是主场景，自动加载 Level 拿不到导航区域，这里补上以免动物报错
	var region: NavigationRegion2D = _level.get_node("level/animalRegion2D")
	if Level.animalRegion == null:
		Level.animalRegion = region
	_check("animalRegion2D 在 animalRegion 组里", region.is_in_group("animalRegion"))

	var fallback: Font = ThemeDB.fallback_font
	print("  INFO 内置默认字体支持中文 = ", fallback != null and fallback.has_char("水".unicode_at(0)))

	var info := _level.get_node_or_null("HUD/InfoLabel") as Label
	_check("HUD/InfoLabel 存在", info != null)
	var held := _level.get_node_or_null("HUD/HeldLabel") as Label
	_check("HUD/HeldLabel 存在", held != null)
	await get_tree().process_frame

	# 真正决定渲染的是 Label 实际取到的字体，所以验证它，而不是内置字体
	if info:
		var lf: Font = info.get_theme_font("font")
		_check("HUD 取到字体", lf != null)
		_check("HUD 字体能画「金」", lf != null and lf.has_char("金".unicode_at(0)))
		_check("HUD 字体能画「水」", lf != null and lf.has_char("水".unicode_at(0)))
		if lf:
			print("  INFO HUD 字体 = ", lf.get_font_name())
			print("  INFO 抗锯齿=", lf.get("antialiasing"), " 微调=", lf.get("hinting"),
				" 次像素=", lf.get("subpixel_positioning"))
		print("  INFO HUD 文本 = ", info.text)
	if held:
		print("  INFO 手持提示 = ", held.text)

	print("--- 手持道具 ---")
	_check("初始手持种子", _player.active_item == Player.Item.SEED)
	_player.cycle_item()
	_check("切换一次 -> 水壶", _player.active_item == Player.Item.WATER_CAN)
	_player.cycle_item()
	_check("再切一次 -> 收获篮", _player.active_item == Player.Item.BASKET)
	_player.cycle_item()
	_check("再切一次 -> 剑", _player.active_item == Player.Item.SWORD)
	_player.cycle_item()
	_check("切四下回到种子", _player.active_item == Player.Item.SEED)

	print("--- 找耕地 ---")
	var farm_tiles: Array[Vector2i] = []
	for c in _land.get_used_cells():
		if _land.is_farmland(c):
			farm_tiles.append(c)
	print("  INFO 耕地格数 = ", farm_tiles.size())
	_check("至少有一格耕地", farm_tiles.size() > 0)
	if farm_tiles.is_empty():
		_finish()
		return
	var tile: Vector2i = farm_tiles[0]

	var grass: TileMapLayer = _level.get_node("Grass")
	var non_farm := Vector2i(-999, -999)
	var found := false
	for c in grass.get_used_cells():
		if not _land.is_farmland(c):
			non_farm = c
			found = true
			break
	_check("找到非耕地（草地）做反例", found)

	print("--- 播种（手持种子 + F）---")
	_check("有 5 种作物数据", CropData.count() == 5)
	_check("默认选中胡萝卜", _player.seed_type == 0)
	_check("初始胡萝卜种子 = 8", _player.seed_count(0) == 8)
	_check("初始金币 = 20", _player.money == 20)
	if found:
		_move_to_tile(non_farm)
		_check("非耕地播种被拒", _use_as(Player.Item.SEED) == false)
	_move_to_tile(tile)
	_check("耕地播种成功", _use_as(Player.Item.SEED) == true)
	_check("种子扣成 7", _player.seed_count(0) == 7)
	_check("同一格重复播种被拒", _use_as(Player.Item.SEED) == false)
	_check("手持水壶对空地使用被拒", _use_as(Player.Item.WATER_CAN) == false)
	_check("plants 记录了作物", _land.plants.has(tile))
	if not _land.plants.has(tile):
		_finish()
		return

	var plant: BasePlant = _land.plants[tile]
	plant.timer.wait_time = 0.08

	print("--- 浇水（手持水壶 + F）---")
	_check("初始水壶为空", _player.water_left == 0)
	_check("没水时浇水被拒", _use_as(Player.Item.WATER_CAN) == false)
	_player.water_left = Player.WATER_CAPACITY
	_check("有水后浇水成功", _use_as(Player.Item.WATER_CAN) == true)
	_check("水壶扣成 4", _player.water_left == Player.WATER_CAPACITY - 1)
	_check("作物变湿", plant.is_watered == true)
	_check("水分未消耗时重复浇水被拒", _use_as(Player.Item.WATER_CAN) == false)

	print("--- 生长到成熟 ---")
	for i in range(4):
		_player.water_left = Player.WATER_CAPACITY
		_use_as(Player.Item.WATER_CAN)
		await get_tree().create_timer(0.2).timeout
		print("  INFO 第", i + 1, "轮浇水后 stage = ", plant.growStage)
	_check("长满 4 级", plant.growStage == 4)
	_check("判定为成熟", plant.is_mature())
	_check("成熟后浇水被拒", _use_as(Player.Item.WATER_CAN) == false)

	print("--- 收获（手持收获篮 + F）---")
	_check("收获成功", _use_as(Player.Item.BASKET) == true)
	_check("篮子有 1 个胡萝卜", _player.basket_total() == 1 and _player.harvested[0] == 1)
	_check("plants 已清空", _land.plants.is_empty())
	_check("空地上收获被拒", _use_as(Player.Item.BASKET) == false)

	print("--- 商店 ---")
	_check("不在商店范围内", _market.is_player_inside() == false)
	_move_to(_market.global_position)
	for i in range(12):
		await get_tree().physics_frame
	_check("站进商店范围", _market.is_player_inside() == true)

	_check("手持水壶在商店使用被拒", _use_as(Player.Item.WATER_CAN) == false)
	_check("卖光作物成功", _use_as(Player.Item.BASKET) == true)
	_check("金币 20+6 = 26（胡萝卜收购价 6）", _player.money == 26)
	_check("篮子已清空", _player.basket_total() == 0)
	_check("空篮子再卖被拒", _use_as(Player.Item.BASKET) == false)
	_check("买种子成功", _use_as(Player.Item.SEED) == true)
	_check("金币 26-3 = 23（胡萝卜种子 3 金）", _player.money == 23)
	_check("种子回到 8", _player.seed_count(0) == 8)

	_player.money = 1
	_check("钱不够时买种子被拒", _use_as(Player.Item.SEED) == false)
	_check("钱没变", _player.money == 1)
	_player.money = 22

	print("--- 多种作物 ---")
	_check("切到玉米（id 2）", _player.select_seed_type(2) == true)
	_check("当前作物名 = 玉米", _player.crop_name() == "玉米")
	_check("重复选同一种返回 false", _player.select_seed_type(2) == false)
	_check("越界种类被拒", _player.select_seed_type(99) == false)
	_check("玉米种子价 8 金", CropData.seed_price(2) == 8)
	_check("玉米收购价 19 金", CropData.sell_price(2) == 19)
	_check("玉米每级 3.6 秒", is_equal_approx(CropData.grow_time(2), 3.6))
	_check("玉米种子初始为 0", _player.seed_count() == 0)

	_player.money = 100
	_move_to(_market.global_position)
	for i in range(12):
		await get_tree().physics_frame
	_check("在商店买到玉米种子", _use_as(Player.Item.SEED) == true)
	_check("金币 100-8 = 92", _player.money == 92)
	_check("玉米种子 = 1", _player.seed_count(2) == 1)

	# 种玉米：先离开商店范围，否则 F 会被商店分支抢走
	var tile2: Vector2i = farm_tiles[1] if farm_tiles.size() > 1 else tile
	_move_to_tile(tile2)
	for i in range(12):
		await get_tree().physics_frame
	_check("已离开商店范围", _market.is_player_inside() == false)
	_check("种下玉米", _use_as(Player.Item.SEED) == true)
	_check("玉米种子用完", _player.seed_count(2) == 0)
	var corn: BasePlant = _land.plants.get(tile2)
	_check("作物的 plantType = 2", corn != null and corn.plantType == 2)
	_check("生长时间写进了 Timer（3.6 秒）", corn != null and is_equal_approx(corn.timer.wait_time, 3.6))
	if corn != null:
		print("  INFO 玉米 stage0 region = ", corn.sprite_2d.region_rect)
		corn.queue_free()
		_land.plants.erase(tile2)

	print("--- 水源补水 ---")
	var bucket: Node2D = _level.get_node("level/Static/waterBucket")
	_player.water_left = 0
	_move_to(bucket.global_position)
	for i in range(12):
		await get_tree().physics_frame
	print("  INFO 站上水桶后 water_left = ", _player.water_left,
		" 重叠计数 = ", _player._water_source_count)
	_check("站在水源旁自动补满水壶", _player.water_left == Player.WATER_CAPACITY)
	_check("重叠计数 = 1", _player._water_source_count == 1)

	_finish()

func _use_as(item: int) -> bool:
	_player.active_item = item
	return _ctl.use_held_item()

func _finish() -> void:
	print("RESULT fail=", _fail)
	get_tree().quit()
