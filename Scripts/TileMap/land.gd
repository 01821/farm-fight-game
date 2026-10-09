extends TileMapLayer

const BASE_PLANT = preload("uid://orgflfd17epj")

@onready var player: CharacterBody2D = $"../level/Player"
@onready var plants_node: Node2D = $"../level/Static/Plants"

var planted_tiles: Array[Vector2i] = []
var current_crop_type: int = 0

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("plant"):
		_try_plant()

func _try_plant() -> void:
	var tile_pos := local_to_map(to_local(player.global_position))
	var tile_data := get_cell_tile_data(tile_pos)

	if tile_data == null:
		print("当前位置没有 Land tile，不可种植")
		return
	if tile_data.get_terrain_set() != 0 or tile_data.get_terrain() != 0:
		print("不是耕地，不可种植")
		return
	if tile_pos in planted_tiles:
		print("该位置已种过作物，不可重复种植")
		return

	# 种植
	planted_tiles.append(tile_pos)
	var plant: BasePlant = BASE_PLANT.instantiate()
	plant.plantType = current_crop_type
	plant.position = map_to_local(tile_pos)
	plants_node.add_child(plant)

	print("种植成功！类型: ", current_crop_type, " 已种植: ", planted_tiles.size())
