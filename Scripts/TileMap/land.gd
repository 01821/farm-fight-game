extends TileMapLayer

## 耕地层：负责播种 / 浇水 / 收获。
## 键盘操作在 _unhandled_input 里转成格子坐标，具体规则都在 try_*_at() 里，方便直接调用测试。

const BASE_PLANT = preload("uid://orgflfd17epj")

@onready var player: Player = $"../level/Player"
@onready var plants_node: Node2D = $"../level/Static/Plants"

## 格子坐标 -> 作物实例
var plants: Dictionary = {}
var current_crop_type: int = 0

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("plant"):
		try_plant_at(get_player_tile())
	elif event.is_action_pressed("water"):
		try_water_at(get_player_tile())
	elif event.is_action_pressed("harvest"):
		try_harvest_at(get_player_tile())

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
	if player.seeds <= 0:
		print("[农场] 没有种子了")
		return false
	player.seeds -= 1
	var plant: BasePlant = BASE_PLANT.instantiate()
	plant.plantType = current_crop_type
	plants_node.add_child(plant)
	plant.global_position = to_global(map_to_local(tile_pos))
	plants[tile_pos] = plant
	print("[农场] 播种成功，剩余种子 ", player.seeds)
	return true

func try_water_at(tile_pos: Vector2i) -> bool:
	var plant: BasePlant = plants.get(tile_pos)
	if plant == null:
		print("[农场] 这格没有作物")
		return false
	if plant.is_mature():
		print("[农场] 已经成熟了，按 E 收获")
		return false
	if not player.has_water():
		print("[农场] 水壶空了，去水桶 / 水缸旁补水")
		return false
	if not plant.water():
		print("[农场] 这株刚浇过，等它长一级")
		return false
	player.consume_water()
	return true

func try_harvest_at(tile_pos: Vector2i) -> bool:
	var plant: BasePlant = plants.get(tile_pos)
	if plant == null:
		print("[农场] 这格没有作物")
		return false
	if not plant.is_mature():
		print("[农场] 还没成熟")
		return false
	plants.erase(tile_pos)
	plant.queue_free()
	player.harvested += 1
	print("[农场] 收获成功！累计收成 ", player.harvested)
	return true
