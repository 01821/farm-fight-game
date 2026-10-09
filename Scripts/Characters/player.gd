class_name Player extends Character

## 玩家：移动 + 农场状态 + 手持道具。
##
## 手上永远只拿着四样东西之一，用 Q 切换：
##   SEED      种子袋 —— 在耕地上使用 = 播种；在商店使用 = 买当前选中的种子
##                      （按 1-5 选择要种 / 要买的作物种类）
##   WATER_CAN 水壶   —— 在作物上使用 = 浇水
##   BASKET    收获篮 —— 在成熟作物上使用 = 收获；在商店使用 = 卖光篮子
##   SWORD     剑     —— 砍附近的野猪
##
## 种子和收获物都是**按作物种类分开计数**的数组，下标就是 CropData 的种类 id。

const WATER_CAPACITY: int = 5
const MAX_HP: int = 5
const ATTACK_COOLDOWN: float = 0.35
const SLASH_TIME: float = 0.12

enum Item { SEED, WATER_CAN, BASKET, SWORD }

const ITEM_NAMES: Array[String] = ["种子袋", "水壶", "收获篮", "长剑"]

signal died

var money: int = 20
## 每种作物的种子数量，下标 = CropData 的种类 id
var seeds: Array[int] = [8, 0, 0, 0, 0]
## 篮子里每种作物的数量
var harvested: Array[int] = [0, 0, 0, 0, 0]
## 当前选中的作物种类（决定播种 / 买种子的种类）
var seed_type: int = 0
var water_left: int = 0
var hp: int = MAX_HP
var active_item: int = Item.SEED

## 当前重叠的水源数量（站在水源旁自动补水）
var _water_source_count: int = 0
var _attack_cd: float = 0.0
var _slash_time: float = 0.0
var _spawn_position: Vector2 = Vector2.ZERO

@onready var slash: Polygon2D = $Slash

func _ready() -> void:
	add_to_group("player")
	_spawn_position = global_position

func _unhandled_input(event: InputEvent) -> void:
	InputDirection = Input.get_vector("left", "right", "up", "down")
	UpdateFaceDirection()

func _process(delta: float) -> void:
	if _water_source_count > 0 and water_left < WATER_CAPACITY:
		water_left = WATER_CAPACITY
	_attack_cd = maxf(0.0, _attack_cd - delta)
	if _slash_time > 0.0:
		_slash_time = maxf(0.0, _slash_time - delta)
		if _slash_time <= 0.0:
			slash.visible = false

# --- 手持道具 ---

func cycle_item() -> void:
	active_item = (active_item + 1) % ITEM_NAMES.size()

func item_name() -> String:
	if active_item == Item.SEED:
		return "种子袋·%s" % crop_name()
	return ITEM_NAMES[active_item]

# --- 作物种类 ---

func crop_name(type_id: int = -1) -> String:
	return CropData.name_of(seed_type if type_id < 0 else type_id)

## 返回是否真的换了种类
func select_seed_type(type_id: int) -> bool:
	if not CropData.is_valid(type_id) or type_id == seed_type:
		return false
	seed_type = type_id
	return true

# --- 种子 ---

func seed_count(type_id: int = -1) -> int:
	var t: int = seed_type if type_id < 0 else type_id
	if not CropData.is_valid(t):
		return 0
	return seeds[t]

func has_seed(type_id: int = -1) -> bool:
	return seed_count(type_id) > 0

func take_seed(type_id: int = -1) -> bool:
	var t: int = seed_type if type_id < 0 else type_id
	if seed_count(t) <= 0:
		return false
	seeds[t] -= 1
	return true

func add_seed(type_id: int, n: int = 1) -> void:
	if not CropData.is_valid(type_id):
		return
	seeds[type_id] = maxi(0, seeds[type_id] + n)

# --- 收获篮 ---

func basket_total() -> int:
	var n: int = 0
	for v in harvested:
		n += v
	return n

func add_harvest(type_id: int, n: int = 1) -> void:
	if not CropData.is_valid(type_id):
		return
	harvested[type_id] = maxi(0, harvested[type_id] + n)

# --- 水 ---

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

# --- 战斗 ---

func can_attack() -> bool:
	return _attack_cd <= 0.0

func begin_attack_cooldown() -> void:
	_attack_cd = ATTACK_COOLDOWN
	# 刀光：复用场景里预建的 Slash 节点，只做开关 + 朝向翻转
	slash.visible = true
	slash.scale.x = -1.0 if sprite_2d.flip_h else 1.0
	_slash_time = SLASH_TIME

func take_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = maxi(0, hp - amount)
	print("[玩家] 掉血 ", amount, "，剩 ", hp, "/", MAX_HP)
	if hp <= 0:
		_die()

## 晕倒：损失一半金币，被抬回出生点，补满血
func _die() -> void:
	var lost: int = money / 2
	money -= lost
	hp = MAX_HP
	water_left = 0
	global_position = _spawn_position
	velocity = Vector2.ZERO
	print("[玩家] 晕倒了！被抬回出生点，损失 ", lost, " 金，剩 ", money)
	died.emit()

# --- 存档 ---

func to_save_data() -> Dictionary:
	return {
		"money": money, "hp": hp, "water_left": water_left,
		"seeds": Array(seeds), "harvested": Array(harvested),
		"seed_type": seed_type, "active_item": active_item,
		"pos_x": global_position.x, "pos_y": global_position.y,
	}

func apply_save_data(d: Dictionary) -> void:
	money = maxi(0, int(d.get("money", 20)))
	hp = clampi(int(d.get("hp", MAX_HP)), 0, MAX_HP)
	water_left = clampi(int(d.get("water_left", 0)), 0, WATER_CAPACITY)
	seed_type = clampi(int(d.get("seed_type", 0)), 0, CropData.count() - 1)
	active_item = clampi(int(d.get("active_item", Item.SEED)), 0, ITEM_NAMES.size() - 1)
	_read_counts(d.get("seeds", null), seeds)
	_read_counts(d.get("harvested", null), harvested)
	global_position = Vector2(
		float(d.get("pos_x", global_position.x)),
		float(d.get("pos_y", global_position.y))
	)
	velocity = Vector2.ZERO

## JSON 读回来的数组是浮点，这里逐个转成非负整数（也顺手挡住越界）
func _read_counts(src: Variant, dst: Array[int]) -> void:
	if typeof(src) != TYPE_ARRAY:
		return
	var arr: Array = src
	for i in range(mini(arr.size(), dst.size())):
		dst[i] = maxi(0, int(arr[i]))
