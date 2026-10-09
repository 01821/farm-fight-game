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
	_check("刷新器拿到了 boar_scene", _spawner.boar_scene != null)
	_check("白天刷新器不活跃", _spawner.is_active() == false)
	_check("场上初始没有野猪", _count_pests() == 0)
	var boar: Boar = _spawner.spawn_one()
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
	var boar2: Boar = _spawner.spawn_one()
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
	var boar3: Boar = _spawner.spawn_one()
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

	_finish()

func _finish() -> void:
	print("RESULT fail=", _fail)
	get_tree().quit()
