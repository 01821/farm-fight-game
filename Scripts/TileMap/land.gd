class_name FarmLand extends TileMapLayer

## 耕地层：播种 / 浇水 / 收获的具体规则。
## 键盘输入不在这里 —— 由 FarmController 按「手持道具 + 所在位置」统一分发。
## 自己加入 "farm_land" 组，好让野猪能找到作物。

const BASE_PLANT = preload("uid://orgflfd17epj")

@onready var player: Player = $"../level/Player"
@onready var plants_node: Node2D = $"../level/Static/Plants"

## 格子坐标 -> 作物实例
var plants: Dictionary = {}
## 有没有接上 DayCycle 的信号
var _cycle_hooked: bool = false

func _ready() -> void:
	add_to_group("farm_land")
	_hook_cycle()

## 洒水器升级：每天早上自动浇几株。
## DayCycle 可能排在后面，_ready 时分组还没注册，所以允许之后再补查。
func _hook_cycle() -> void:
	if _cycle_hooked:
		return
	var cycle := get_tree().get_first_node_in_group("day_cycle") as DayCycle
	if cycle == null:
		return
	cycle.day_started.connect(_on_day_started)
	_cycle_hooked = true

func _process(_delta: float) -> void:
	_hook_cycle()

func _on_day_started(_day: int) -> void:
	water_by_sprinkler()

## 洒水器自动浇水。返回浇了几株。
## 它浇的是"当前还缺水的那些"，所以和玩家手动浇水不会互相浪费。
func water_by_sprinkler() -> int:
	var quota: int = Upgrades.sprinkler_count()
	if quota <= 0:
		return 0
	var done: int = 0
	for tile in plants.keys():
		if done >= quota:
			break
		if water_plant_at(tile):
			done += 1
	if done > 0:
		print("[升级] 洒水器早上自动浇了 ", done, " 株")
	return done

func get_player_tile() -> Vector2i:
	return local_to_map(to_local(player.global_position))

func is_farmland(tile_pos: Vector2i) -> bool:
	var tile_data := get_cell_tile_data(tile_pos)
	if tile_data == null:
		return false
	return tile_data.get_terrain_set() == 0 and tile_data.get_terrain() == 0

func try_plant_at(tile_pos: Vector2i) -> bool:
	if not is_farmland(tile_pos):
		print("[农场] 这里不是耕地，种不了")
		return false
	if plants.has(tile_pos):
		print("[农场] 这格已经种过了")
		return false
	if not player.has_seed():
		print("[农场] 没有 ", player.crop_name(), " 种子了，去商店买")
		return false
	var type_id: int = player.seed_type
	player.take_seed()
	spawn_plant(tile_pos, type_id)
	player.register_plant()
	Sfx.play("plant")
	print("[农场] 种下 ", CropData.name_of(type_id), "，还剩 ", player.seed_count(type_id), " 粒")
	return true

## 在指定格子实例化一株作物。播种和读档共用这一条路径。
## extra 非空时当作存档数据应用到新作物上（这样读档出来的作物会带着原来的生长阶段）。
func spawn_plant(tile_pos: Vector2i, type_id: int, extra: Dictionary = {}) -> BasePlant:
	var plant: BasePlant = BASE_PLANT.instantiate()
	plant.plantType = type_id
	# growTime 必须在 add_child 之前设：_ready 会拿它去设 Timer
	# 育种家专精会缩短生长时间
	plant.growTime = CropData.grow_time(type_id) * Progression.grow_time_multiplier()
	plants_node.add_child(plant)
	plant.global_position = to_global(map_to_local(tile_pos))
	if not extra.is_empty():
		plant.apply_save_data(extra)
	plants[tile_pos] = plant
	return plant

func try_water_at(tile_pos: Vector2i) -> bool:
	var plant: BasePlant = plants.get(tile_pos)
	if plant == null:
		print("[农场] 这格没有作物")
		return false
	if plant.is_mature():
		print("[农场] 已经成熟了，换收获篮收走")
		return false
	if not player.has_water():
		print("[农场] 水壶空了，去水桶 / 水缸旁补水")
		return false
	if not plant.water():
		print("[农场] 这株刚浇过，等它长一级")
		return false
	player.consume_water()
	# 园丁：顺手把周围一格也浇了（不额外扣水）
	var r: int = Progression.water_radius()
	var extra: int = 0
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if dx == 0 and dy == 0:
				continue
			if water_plant_at(tile_pos + Vector2i(dx, dy)):
				extra += 1
	if extra > 0:
		print("[农场] 园丁顺手浇了周围 ", extra, " 株")
	Sfx.play("water")
	return true

## 只给某格作物浇水，不扣玩家的水壶。返回是否浇上了。
func water_plant_at(tile_pos: Vector2i) -> bool:
	var p: BasePlant = plants.get(tile_pos)
	if p == null or not is_instance_valid(p):
		return false
	var ok: bool = p.water()
	# 浇上了就记一笔（干旱天第一遍也算"浇过了"，它确实是一次浇水动作）
	if ok:
		player.register_water()
	return ok

func try_harvest_at(tile_pos: Vector2i) -> bool:
	var plant: BasePlant = plants.get(tile_pos)
	if plant == null:
		print("[农场] 这格没有作物")
		return false
	if not plant.is_mature():
		print("[农场] 还没成熟")
		return false
	var type_id: int = plant.plantType
	plants.erase(tile_pos)
	plant.queue_free()
	player.add_harvest(type_id)
	var got: int = 1
	# 囤积者：有概率多收一株
	if randf() < Progression.harvest_bonus_chance():
		player.add_harvest(type_id)
		got = 2
	# 温室升级：每级稳多收 1 个（**不看运气**，所以和上面那条专精叠加得起来）
	var green: int = Upgrades.greenhouse_bonus()
	if green > 0:
		for i in range(green):
			player.add_harvest(type_id)
		got += green
	Progression.add_xp(Progression.Skill.FARM, 1)
	Sfx.play("harvest")
	print("[农场] 收获 ", CropData.name_of(type_id), " x", got, "！篮子里共 ", player.basket_total(), " 个")
	return true

## 作物被野猪啃掉（或其它方式损毁）
func destroy_plant_at(tile_pos: Vector2i) -> bool:
	var plant: BasePlant = plants.get(tile_pos)
	if plant == null:
		return false
	plants.erase(tile_pos)
	if is_instance_valid(plant):
		plant.queue_free()
	return true

## 雨天：给所有还没浇过水的作物免费浇一遍（不消耗玩家的水壶）。
## 返回实际浇了几株。成熟的和刚浇过的会被 BasePlant.water() 自己挡掉。
func water_all() -> int:
	var n: int = 0
	for tile in plants.keys():
		if water_plant_at(tile):
			n += 1
	return n

func clear_all_plants() -> int:
	var n: int = plants.size()
	for tile in plants.keys():
		var p: BasePlant = plants[tile]
		if p != null and is_instance_valid(p):
			p.queue_free()
	plants.clear()
	return n

func to_save_data() -> Dictionary:
	var list: Array = []
	for tile in plants.keys():
		var p: BasePlant = plants[tile]
		if p == null or not is_instance_valid(p):
			continue
		var d: Dictionary = p.to_save_data()
		d["tile_x"] = tile.x
		d["tile_y"] = tile.y
		list.append(d)
	return {"plants": list}

func apply_save_data(data: Dictionary) -> void:
	clear_all_plants()
	for entry in data.get("plants", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var tile := Vector2i(int(entry.get("tile_x", 0)), int(entry.get("tile_y", 0)))
		spawn_plant(tile, int(entry.get("type", 0)), entry)
