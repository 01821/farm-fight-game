class_name Player extends Character

## 玩家：移动 + 农场状态 + 手持道具。
##
## 手上永远只拿着四样东西之一，用 Q 切换：
##   SEED      种子袋 —— 在耕地上使用 = 播种；在商店使用 = 买种子
##   WATER_CAN 水壶   —— 在作物上使用 = 浇水
##   BASKET    收获篮 —— 在成熟作物上使用 = 收获；在商店使用 = 卖光作物
##   SWORD     剑     —— 砍附近的野猪

const WATER_CAPACITY: int = 5
const MAX_HP: int = 5
const ATTACK_COOLDOWN: float = 0.35
const SLASH_TIME: float = 0.12

enum Item { SEED, WATER_CAN, BASKET, SWORD }

const ITEM_NAMES: Array[String] = ["种子袋", "水壶", "收获篮", "长剑"]

signal died

var money: int = 20
var seeds: int = 8
var harvested: int = 0
var water_left: int = 0
var hp: int = MAX_HP
var active_item: int = Item.SEED

## 当前重叠的水源数量（站在水源旁自动补水）
var _water_source_count: int = 0
var _attack_cd: float = 0.0
var _slash_time: float = 0.0
var _spawn_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("player")
	_spawn_position = global_position

func _unhandled_input(event: InputEvent) -> void:
	InputDirection = Input.get_vector("left", "right", "up", "down")
	UpdateFaceDirection()

@onready var slash: Polygon2D = $Slash

func _process(delta: float) -> void:
	if _water_source_count > 0 and water_left < WATER_CAPACITY:
		water_left = WATER_CAPACITY
	_attack_cd = maxf(0.0, _attack_cd - delta)
	if _slash_time > 0.0:
		_slash_time = maxf(0.0, _slash_time - delta)
		if _slash_time <= 0.0:
			slash.visible = false

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

func add_water_source() -> void:
	_water_source_count += 1

func remove_water_source() -> void:
	_water_source_count = maxi(0, _water_source_count - 1)
