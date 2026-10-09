class_name Player extends Character

## 玩家：移动 + 农场状态 + 手持道具。
##
## 手上永远只拿着三样东西之一，用 Q 切换：
##   SEED      种子袋 —— 在耕地上使用 = 播种；在商店使用 = 买种子
##   WATER_CAN 水壶   —— 在作物上使用 = 浇水
##   BASKET    收获篮 —— 在成熟作物上使用 = 收获；在商店使用 = 卖光作物

const WATER_CAPACITY: int = 5

enum Item { SEED, WATER_CAN, BASKET }

const ITEM_NAMES: Array[String] = ["SEED", "WATER_CAN", "BASKET"]

var money: int = 20
var seeds: int = 8
var harvested: int = 0
var water_left: int = 0
var active_item: int = Item.SEED

## 当前重叠的水源数量（站在水源旁自动补水）
var _water_source_count: int = 0

func _unhandled_input(event: InputEvent) -> void:
	InputDirection = Input.get_vector("left", "right", "up", "down")
	UpdateFaceDirection()

func _process(_delta: float) -> void:
	if _water_source_count > 0 and water_left < WATER_CAPACITY:
		water_left = WATER_CAPACITY

func cycle_item() -> void:
	active_item = (active_item + 1) % ITEM_NAMES.size()

func item_name() -> String:
	return ITEM_NAMES[active_item]

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
