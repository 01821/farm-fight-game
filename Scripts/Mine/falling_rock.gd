class_name FallingRock extends Area2D

## 落石：挂在顶上，玩家走到下面才掉。
##
## 和地刺的区别是**它是可以躲开的** —— 前提是玩家看得见预兆。
## 所以下落之前有一小段"抖一抖"的预警（`SHAKE_TIME`）：
## 不预告的陷阱不叫陷阱，叫坑人。

enum State { HANG, SHAKE, FALL, BROKEN }

## 玩家进入这个水平距离就触发
const TRIGGER_X: float = 26.0
## 玩家必须在它下面（不能站在上面就触发）
const TRIGGER_ABOVE_Y: float = 8.0
## 抖动预警时长
const SHAKE_TIME: float = 0.45
const FALL_GRAVITY: float = 900.0
const MAX_FALL: float = 520.0
## 掉到这个世界高度就算砸到地，碎掉
@export var ground_y: float = 198.0
@export var damage: int = 2

var _state: int = State.HANG
var _t: float = 0.0
var _vy: float = 0.0
var _origin: Vector2

@onready var sprite: Sprite2D = $Sprite2D
@onready var shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("mine_hazard")
	_origin = global_position

func state_name() -> String:
	match _state:
		State.HANG: return "挂着"
		State.SHAKE: return "预警"
		State.FALL: return "下落"
		State.BROKEN: return "碎了"
	return "?"

func is_dangerous() -> bool:
	return _state == State.FALL

func _physics_process(delta: float) -> void:
	match _state:
		State.HANG:
			_check_trigger()
		State.SHAKE:
			_t += delta
			# 左右小幅抖动当预警
			sprite.position.x = sin(_t * 60.0) * 1.6
			if _t >= SHAKE_TIME:
				_start_fall()
		State.FALL:
			_vy = minf(_vy + FALL_GRAVITY * delta, MAX_FALL)
			position.y += _vy * delta
			_hit_player()
			if global_position.y >= ground_y:
				_break()
		State.BROKEN:
			pass

## 触发用**距离判断**，不是靠 Area2D 重叠。
##
## 踩过的坑：一开始写成 `for b in get_overlapping_bodies()` 再比距离 ——
## 但判定盒只有 16×16、挂在 y=120，站在地面（y=198）的玩家**根本碰不到它**，
## 于是永远不触发。判定盒只该用来算"砸到了没有"，不该用来算"走到下面了没有"。
func _check_trigger() -> void:
	var p := get_tree().get_first_node_in_group("mine_player") as MinePlayer
	if p == null or not is_instance_valid(p):
		return
	if absf(p.global_position.x - global_position.x) <= TRIGGER_X \
			and p.global_position.y > global_position.y + TRIGGER_ABOVE_Y:
		_t = 0.0
		_state = State.SHAKE
		print("[矿洞] 头顶的石头松了……")

func _start_fall() -> void:
	_state = State.FALL
	_vy = 0.0
	sprite.position.x = 0.0
	print("[矿洞] 落石！")

func _hit_player() -> void:
	for b in get_overlapping_bodies():
		var p := b as MinePlayer
		if p != null:
			p.take_damage(damage, global_position + Vector2(0, -10))

## 砸到地面：碎掉，不再有伤害
func _break() -> void:
	_state = State.BROKEN
	global_position.y = ground_y
	monitoring = false
	shape.disabled = true
	# 碎掉的样子：压扁 + 变暗，不用换贴图
	sprite.scale = Vector2(1.35, 0.4)
	sprite.modulate = Color(0.6, 0.55, 0.5, 0.85)
	print("[矿洞] 石头砸碎了")
