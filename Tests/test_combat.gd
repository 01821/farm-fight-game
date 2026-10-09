extends Node2D

## 端到端自测：战斗系统。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_combat.tscn

var _fail: int = 0
var _level: Node2D
var _land: FarmLand
var _player: Player
var _ctl: FarmController
var _spawner: PestSpawner
var _cycle: DayCycle
var _spawn_pos: Vector2
var _slash: Polygon2D

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _count_pests() -> int:
	return get_tree().get_nodes_in_group("pest").size()

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
	_ctl = _level.get_node("FarmController")
	_spawner = _level.get_node("PestSpawner")
	_cycle = _level.get_node("DayCycle")
	# 冻结时间：本测试关心的是战斗本身，不想在跑测试时入夜自动刷野猪
	_cycle.running = false
	_spawn_pos = _player.global_position
	_slash = _player.get_node("Slash")

	var region: NavigationRegion2D = _level.get_node("level/animalRegion2D")
	if Level.animalRegion == null:
		Level.animalRegion = region

	print("--- 刷新器 ---")
	_check("刷新器拿到了 pest_scene", _spawner.pest_scene != null)
	_check("白天刷新器不活跃", _spawner.is_active() == false)
	_check("场上初始没有害兽", _count_pests() == 0)
	var boar: Pest = _spawner.spawn_one()
	_check("spawn_one 返回实例", boar != null)
	_check("场上 1 只野猪", _count_pests() == 1)
	if boar == null:
		_finish()
		return
	_check("野猪在 pest 组里", boar.is_in_group("pest"))
	_check("野猪初始 2 点血", boar.hp == 2)

	print("--- 野猪会朝作物走 ---")
	var farm_tiles: Array[Vector2i] = []
	for c in _land.get_used_cells():
		if _land.is_farmland(c):
			farm_tiles.append(c)
	_check("有耕地", farm_tiles.size() > 0)
	if farm_tiles.is_empty():
		_finish()
		return
	var tile: Vector2i = farm_tiles[0]
	_player.global_position = _land.to_global(_land.map_to_local(tile))
	_player.active_item = Player.Item.SEED
	_check("种下作物", _ctl.use_held_item() == true)
	if not _land.plants.has(tile):
		_finish()
		return
	var plant: BasePlant = _land.plants[tile]

	boar.global_position = plant.global_position + Vector2(120.0, 0.0)
	var d0: float = boar.global_position.distance_to(plant.global_position)
	for i in range(45):
		await get_tree().physics_frame
	var d1: float = boar.global_position.distance_to(plant.global_position)
	print("  INFO 与作物距离 ", snappedf(d0, 0.1), " -> ", snappedf(d1, 0.1))
	_check("野猪朝作物靠近了", d1 < d0 - 8.0)

	print("--- 玩家攻击 ---")
	var arena := Vector2(100.0, 260.0)
	_player.global_position = arena
	boar.global_position = arena + Vector2(10.0, 0.0)
	await get_tree().physics_frame

	_player.active_item = Player.Item.SWORD
	_check("可以攻击", _player.can_attack() == true)
	_check("攻击前刀光隐藏", _slash.visible == false)
	var dist_before: float = _player.global_position.distance_to(boar.global_position)
	_check("砍中野猪", _ctl.use_held_item() == true)
	await get_tree().physics_frame
	var dist_after: float = _player.global_position.distance_to(boar.global_position)
	print("  INFO 与野猪距离 ", snappedf(dist_before, 0.1), " -> ", snappedf(dist_after, 0.1))
	_check("砍中会把野猪击退", dist_after > dist_before)
	_check("刀光出现", _slash.visible == true)
	_check("野猪剩 1 点血", boar.hp == 1)
	_check("攻击后进入冷却", _player.can_attack() == false)
	_check("冷却中再砍被拒", _ctl.use_held_item() == false)
	await get_tree().create_timer(0.45).timeout
	_check("刀光已自动隐藏", _slash.visible == false)
	_check("冷却结束", _player.can_attack() == true)
	# 追上去补刀（模拟玩家贴身追击，避免测试受野猪走位影响而抖动）
	boar.global_position = _player.global_position + Vector2(8.0, 0.0)
	_check("再砍一下击杀", _ctl.use_held_item() == true)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("野猪已被移除", _count_pests() == 0)

	print("--- 挥空 ---")
	_player.global_position = arena
	await get_tree().create_timer(0.45).timeout
	_check("附近没野猪时砍空返回 false", _ctl.use_held_item() == false)

	print("--- 野猪啃作物 ---")
	var boar2: Pest = _spawner.spawn_one()
	_check("又来一只", _count_pests() == 1)
	# 重新种一株（上一株还在）
	if not _land.plants.has(tile):
		_player.global_position = _land.to_global(_land.map_to_local(tile))
		_player.active_item = Player.Item.SEED
		_ctl.use_held_item()
	_check("田里有作物", _land.plants.size() > 0)
	var target: BasePlant = _land.plants.values()[0]
	boar2.global_position = target.global_position + Vector2(6.0, 0.0)
	for i in range(20):
		await get_tree().physics_frame
	_check("作物被啃掉了", _land.plants.size() == 0)
	await get_tree().process_frame
	_check("啃完野猪离场", _count_pests() == 0)

	print("--- 野猪顶玩家 ---")
	_player.hp = Player.MAX_HP
	var boar3: Pest = _spawner.spawn_one()
	boar3.global_position = _player.global_position
	for i in range(10):
		await get_tree().physics_frame
	print("  INFO 玩家血量 = ", _player.hp, "/", Player.MAX_HP)
	_check("贴身被野猪顶掉血", _player.hp < Player.MAX_HP)

	print("--- 晕倒惩罚 ---")
	_player.money = 20
	_player.hp = 1
	_player.take_damage(1)
	_check("血量补满", _player.hp == Player.MAX_HP)
	_check("损失一半金币 20 -> 10", _player.money == 10)
	_check("被抬回出生点", _player.global_position.is_equal_approx(_spawn_pos))

	# 清场：前面留了一只没打死的，会干扰后面的计数
	for n in get_tree().get_nodes_in_group("pest"):
		(n as Pest).queue_free()
	await get_tree().process_frame
	_check("清场后场上没有害兽", _count_pests() == 0)

	print("--- 害兽种类 ---")
	_check("数据表有 3 种", PestData.count() == 3)
	_check("第 1 天只有野猪", PestData.kinds_for_day(1) == [0])
	_check("第 2 天加入蝙蝠", PestData.kinds_for_day(2) == [0, 1])
	_check("第 3 天加入蜘蛛", PestData.kinds_for_day(3) == [0, 1, 2])
	_check("野猪 2 血 / 赏金 2", PestData.hp_of(0) == 2 and PestData.reward_of(0) == 2)
	_check("蝙蝠 1 血 / 66 速 / 更快", PestData.hp_of(1) == 1 and is_equal_approx(PestData.speed_of(1), 66.0))
	_check("蜘蛛 3 血 / 要啃 3 株", PestData.hp_of(2) == 3 and PestData.max_eats_of(2) == 3)
	_check("野猪贴图在 (48,160)", PestData.region_of(0) == Rect2(48, 160, 16, 16))
	_check("蝙蝠贴图在 (0,160)", PestData.region_of(1) == Rect2(0, 160, 16, 16))
	_check("蜘蛛贴图在 (32,160)", PestData.region_of(2) == Rect2(32, 160, 16, 16))

	var only_boar := true
	for i in range(50):
		if PestData.pick_kind(1) != 0:
			only_boar = false
	_check("第 1 天怎么抽都是野猪", only_boar)
	var seen := {}
	for i in range(300):
		seen[PestData.pick_kind(3)] = true
	_check("第 3 天三种都抽得到", seen.size() == 3)

	var bat: Pest = _spawner.spawn_one(1)
	_check("可以指定种类生成", bat != null and bat.kind == 1)
	if bat == null:
		_finish()
		return
	_check("蝙蝠血量来自数据表", bat.hp == 1)
	_check("蝙蝠贴图跟着换", bat.sprite_2d.region_rect == Rect2(0, 160, 16, 16))

	print("--- 击杀赏金 ---")
	_player.money = 0
	_player.active_item = Player.Item.SWORD
	# 先等冷却结束，**再**瞬移到蝙蝠身上 —— 蝙蝠速度 66，先站过去等 0.5 秒它早跑出范围了
	await get_tree().create_timer(0.5).timeout
	_player.global_position = bat.global_position
	_check("蝙蝠 1 血一刀带走", _ctl.use_held_item() == true)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("击杀拿到赏金 2 金", _player.money == 2)
	_check("蝙蝠已消失", _count_pests() == 0)

	# 清场，免得上一段有残留影响后面的计数
	for n in get_tree().get_nodes_in_group("pest"):
		(n as Pest).queue_free()
	await get_tree().process_frame

	print("--- 刀光动画 ---")
	_player.global_position = arena
	_player.active_item = Player.Item.SWORD
	await get_tree().create_timer(0.5).timeout
	_ctl.use_held_item()
	var grow0: float = absf(_slash.scale.x)
	_check("挥砍瞬间刀光可见且很小", _slash.visible == true and grow0 < 0.7)
	await get_tree().create_timer(0.06).timeout
	var grow1: float = absf(_slash.scale.x)
	print("  INFO 刀光 scale ", snappedf(grow0, 0.01), " -> ", snappedf(grow1, 0.01))
	_check("刀光在放大（有挥砍感）", grow1 > grow0 + 0.15)
	await get_tree().create_timer(0.15).timeout
	_check("刀光播完自动隐藏", _slash.visible == false)

	print("--- 蜘蛛啃一株不罢休 ---")
	_land.clear_all_plants()
	_player.seeds[0] = 5
	var planted: int = 0
	for i in range(3):
		_move_to_tile(farm_tiles[i])
		_player.active_item = Player.Item.SEED
		if _ctl.use_held_item():
			planted += 1
	_check("种下三株", planted == 3)
	var spider: Pest = _spawner.spawn_one(2)
	spider.global_position = _land.to_global(_land.map_to_local(farm_tiles[0]))
	for i in range(12):
		await get_tree().physics_frame
	print("  INFO 蜘蛛已啃 ", spider._eaten, " 株，场上 ", _count_pests(), " 只")
	_check("蜘蛛啃掉了作物", _land.plants.size() < planted)
	_check("蜘蛛啃一株后仍在场上", _count_pests() == 1 and is_instance_valid(spider))
	_check("蜘蛛还没吃饱（3 株上限）", spider._eaten < 3)

	_finish()

func _finish() -> void:
	print("RESULT fail=", _fail)
	get_tree().quit()
