extends Node2D

## 一次性端到端自测：种 → 浇水 → 成熟 → 收获 + 水源补水 + HUD。
## 用法: godot --headless --path . --fixed-fps 60 res://Scenes/_test_farm.tscn

var _fail: int = 0
var _level: Node2D
var _land: TileMapLayer
var _player: Player

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _ready() -> void:
	var ps := load("res://Scenes/base_level.tscn") as PackedScene
	_level = ps.instantiate()
	add_child(_level)
	await get_tree().process_frame
	await get_tree().process_frame

	_land = _level.get_node("Land")
	_player = _level.get_node("level/Player")

	# 测试场景不是主场景，自动加载 Level 拿不到导航区域，这里补上以免动物报错
	var region: NavigationRegion2D = _level.get_node("level/animalRegion2D")
	if Level.animalRegion == null:
		Level.animalRegion = region
	_check("animalRegion2D 在 animalRegion 组里", region.is_in_group("animalRegion"))

	# 内置字体是否覆盖中文（决定 HUD 能不能用中文）
	var f: Font = ThemeDB.fallback_font
	var cjk: bool = f != null and f.has_char("水".unicode_at(0))
	print("  INFO 默认字体支持中文 = ", cjk)

	# --- HUD ---
	var info := _level.get_node_or_null("HUD/InfoLabel") as Label
	_check("HUD/InfoLabel 存在", info != null)
	await get_tree().process_frame
	if info:
		print("  INFO HUD 文本 = ", info.text)

	# --- 找耕地 ---
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

	print("--- 播种 ---")
	_check("初始种子 = 8", _player.seeds == 8)
	if found:
		_check("非耕地播种被拒", _land.try_plant_at(non_farm) == false)
	_check("耕地播种成功", _land.try_plant_at(tile) == true)
	_check("种子扣成 7", _player.seeds == 7)
	_check("同一格重复播种被拒", _land.try_plant_at(tile) == false)
	_check("plants 记录了作物", _land.plants.has(tile))
	if not _land.plants.has(tile):
		_finish()
		return

	var plant: BasePlant = _land.plants[tile]
	plant.timer.wait_time = 0.08

	print("--- 浇水 ---")
	_check("初始水壶为空", _player.water_left == 0)
	_check("没水时浇水被拒", _land.try_water_at(tile) == false)
	_player.water_left = Player.WATER_CAPACITY
	_check("有水后浇水成功", _land.try_water_at(tile) == true)
	_check("水壶扣成 4", _player.water_left == Player.WATER_CAPACITY - 1)
	_check("作物变湿", plant.is_watered == true)
	_check("水分未消耗时重复浇水被拒", _land.try_water_at(tile) == false)

	print("--- 生长到成熟 ---")
	for i in range(4):
		_player.water_left = Player.WATER_CAPACITY
		_land.try_water_at(tile)
		await get_tree().create_timer(0.2).timeout
		print("  INFO 第", i + 1, "轮浇水后 stage = ", plant.growStage)
	_check("长满 4 级", plant.growStage == 4)
	_check("判定为成熟", plant.is_mature())
	_check("成熟后浇水被拒", _land.try_water_at(tile) == false)

	print("--- 收获 ---")
	_check("收获成功", _land.try_harvest_at(tile) == true)
	_check("收成 +1", _player.harvested == 1)
	_check("plants 已清空", _land.plants.is_empty())
	_check("空地上收获被拒", _land.try_harvest_at(tile) == false)

	print("--- 水源补水 ---")
	var bucket: Node2D = _level.get_node("level/Static/waterBucket")
	_player.water_left = 0
	_player.global_position = bucket.global_position
	for i in range(12):
		await get_tree().physics_frame
	print("  INFO 站上水桶后 water_left = ", _player.water_left,
		" 重叠计数 = ", _player._water_source_count)
	_check("站在水源旁自动补满水壶", _player.water_left == Player.WATER_CAPACITY)
	_check("重叠计数 = 1", _player._water_source_count == 1)

	_finish()

func _finish() -> void:
	print("RESULT fail=", _fail)
	get_tree().quit()
