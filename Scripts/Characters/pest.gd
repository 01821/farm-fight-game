class_name Pest extends CharacterBody2D

## 害兽（Pest）：闯进农场啃作物的敌人。
##
## 行为差异全部由 PestData 驱动，同一个场景换 kind 就换了一种敌人：
##   野猪：慢、2 血，啃一株就走
##   蝙蝠：快、1 血，偷一株立刻飞走（考反应）
##   蜘蛛：慢、3 血，啃完不走，要连啃三株才罢休
##
## 直线冲向最近的作物（地图上几乎没阻挡）→ 啃 → 按 max_eats 决定走还是继续。
## 顺路会顶玩家一下；被打会掉血并短暂硬直 + 击退；血尽被赶跑并给赏金。
## 找不到作物、或者卡住太久，也会自己离开，不会赖在地图上。

const EAT_RANGE: float = 10.0
const CONTACT_RANGE: float = 12.0
const CONTACT_DAMAGE: int = 1
const CONTACT_COOLDOWN: float = 1.5
const HIT_STUN: float = 0.25
const KNOCKBACK_SPEED: float = 140.0
const KNOCKBACK_DECAY: float = 9.0
const GIVE_UP_TIME: float = 6.0
const STUCK_TIME: float = 3.0
const STUCK_EPSILON: float = 1.0
const DIGEST_TIME: float = 0.5
const INVALID_TILE := Vector2i(-999999, -999999)

## 种类 id（见 PestData）。**必须在 add_child 之前设好** —— _ready 会拿它配置一切。
@export var kind: int = 0

var hp: int = 1
var speed: float = 38.0

@onready var sprite_2d: Sprite2D = $Sprite2D

var _reward: int = 0
var _max_eats: int = 1
var _eaten: int = 0
var _land: FarmLand
var _player: Player
var _contact_cd: float = 0.0
var _flash: float = 0.0
var _stun: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _idle_time: float = 0.0
var _stuck_time: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("pest")
	hp = PestData.hp_of(kind)
	speed = PestData.speed_of(kind)
	_reward = PestData.reward_of(kind)
	_max_eats = maxi(1, PestData.max_eats_of(kind))
	sprite_2d.region_rect = PestData.region_of(kind)
	_last_pos = global_position
	_land = get_tree().get_first_node_in_group("farm_land")
	_player = get_tree().get_first_node_in_group("player")

func display_name() -> String:
	return PestData.name_of(kind)

## from 是攻击者的位置，用来决定往哪个方向飞（给 Vector2.INF 就不击退）
func take_damage(amount: int, from: Vector2 = Vector2.INF) -> void:
	if hp <= 0:
		return
	hp -= amount
	print("[战斗] ", display_name(), " 挨了一下，剩 ", hp, " 点血")
	if hp <= 0:
		_die()
		return
	_flash = 0.12
	_stun = HIT_STUN
	if from.is_finite():
		var away: Vector2 = global_position - from
		if away.length() > 0.01:
			_knockback = away.normalized() * KNOCKBACK_SPEED

func _die() -> void:
	print("[战斗] ", display_name(), " 被赶跑了")
	if _reward > 0 and _player != null and is_instance_valid(_player):
		_player.earn(_reward)
		Sfx.play("coin")
		print("[战斗] 赏金 +", _reward, " 金")
	queue_free()

func _physics_process(delta: float) -> void:
	_update_flash(delta)
	_contact_cd = maxf(0.0, _contact_cd - delta)
	_touch_player()

	# 击退优先：被打飞的这段时间不寻路、也不受硬直影响
	if _knockback.length() > 2.0:
		velocity = _knockback
		move_and_slide()
		_knockback = _knockback.lerp(Vector2.ZERO, minf(1.0, KNOCKBACK_DECAY * delta))
		_last_pos = global_position
		return

	# 受击硬直：短暂站住不动，否则玩家刚砍中它就已经跑出攻击范围了
	if _stun > 0.0:
		_stun = maxf(0.0, _stun - delta)
		velocity = Vector2.ZERO
		return

	var tile := _find_target_tile()
	if tile == INVALID_TILE:
		velocity = Vector2.ZERO
		_idle_time += delta
		if _idle_time > GIVE_UP_TIME:
			print("[战斗] 农场里没作物，", display_name(), " 走了")
			queue_free()
		return

	var plant: BasePlant = _land.plants.get(tile)
	if plant == null or not is_instance_valid(plant):
		return

	var to: Vector2 = plant.global_position - global_position
	if to.length() <= EAT_RANGE:
		_eat(tile)
		return

	velocity = to.normalized() * speed
	move_and_slide()
	if absf(velocity.x) > 0.01:
		sprite_2d.flip_h = velocity.x < 0.0
	_track_stuck(delta)

func _touch_player() -> void:
	if _contact_cd > 0.0:
		return
	if _player == null or not is_instance_valid(_player):
		return
	if global_position.distance_to(_player.global_position) <= CONTACT_RANGE:
		_player.take_damage(CONTACT_DAMAGE)
		_contact_cd = CONTACT_COOLDOWN

func _track_stuck(delta: float) -> void:
	if global_position.distance_to(_last_pos) < STUCK_EPSILON:
		_stuck_time += delta
		if _stuck_time > STUCK_TIME:
			print("[战斗] ", display_name(), " 被挡住了，自己走了")
			queue_free()
	else:
		_stuck_time = 0.0
		_last_pos = global_position

func _update_flash(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		sprite_2d.modulate = Color(2.0, 0.5, 0.5) if _flash > 0.0 else Color.WHITE

## 找最近的作物格子；没有作物返回 INVALID_TILE
func _find_target_tile() -> Vector2i:
	if _land == null or not is_instance_valid(_land):
		return INVALID_TILE
	var best := INVALID_TILE
	var best_dist := INF
	for tile in _land.plants.keys():
		var p: BasePlant = _land.plants[tile]
		if p == null or not is_instance_valid(p):
			continue
		var d: float = global_position.distance_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = tile
	return best

func _eat(tile: Vector2i) -> void:
	_land.destroy_plant_at(tile)
	_eaten += 1
	print("[战斗] ", display_name(), " 啃掉一株作物（", _eaten, "/", _max_eats, "）")
	if _eaten >= _max_eats:
		if _max_eats > 1:
			print("[战斗] ", display_name(), " 吃饱了，溜了")
		queue_free()
		return
	# 还没吃饱：愣一下再去找下一株
	_stun = DIGEST_TIME
