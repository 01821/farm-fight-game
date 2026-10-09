class_name Player extends Character

## 玩家：负责移动 + 携带农场状态（水壶 / 种子 / 收成 / 金币）。

const WATER_CAPACITY: int = 5

var money: int = 20
var seeds: int = 8
var harvested: int = 0
var water_left: int = 0

## 当前重叠的水源数量（站在水源旁自动补水）
var _water_source_count: int = 0

func _unhandled_input(event: InputEvent) -> void:
	InputDirection = Input.get_vector("left", "right", "up", "down")
	UpdateFaceDirection()

func _process(_delta: float) -> void:
	if _water_source_count > 0 and water_left < WATER_CAPACITY:
		water_left = WATER_CAPACITY

func has_water() -> bool:
	return water_left > 0

func consume_water() -> bool:
	if water_left <= 0:
		return false
	water_left -= 1
	return true

func add_water_source() -> void:
	_water_source_count += 1

func remove_water_source() -> void:
	_water_source_count = maxi(0, _water_source_count - 1)
