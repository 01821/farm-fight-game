class_name MineCart extends AnimatableBody2D

## 矿车：在两点之间来回跑，**玩家站上去会被自动带着走**。
##
## 靠的是 Godot 自带的移动平台机制，而不是手动搬运玩家：
## `AnimatableBody2D` 会把自身的速度报给踩在它上面的 `CharacterBody2D`，
## 对方的 `move_and_slide()` 就会跟着走。省掉一堆容易写错的父子关系代码。
##
## 注意：它要放在**地形层（layer 1）**，玩家的 collision_mask 才会把它当"地面"。

## 单程距离（以出生点为中心，左右各走 travel/2）
@export var travel: float = 150.0
@export var speed: float = 145.0
## 初始方向，1 = 右
@export var start_dir: int = 1
## 到站停多久再往回走（给玩家上下车的时间）
@export var stop_time: float = 0.45

var _origin: Vector2
var _dir: int = 1
var _stop_left: float = 0.0
var _rider: Node2D

## 乘客检测用的是一个**预建的 Area2D 子节点** ——
## AnimatableBody2D 自己没有 body_entered 信号（那是 Area2D 的）。
@onready var rider_area: Area2D = $RiderArea

func _ready() -> void:
	add_to_group("mine_cart")
	_origin = global_position
	_dir = 1 if start_dir >= 0 else -1
	rider_area.body_entered.connect(_on_body_entered)
	rider_area.body_exited.connect(_on_body_exited)

func _physics_process(delta: float) -> void:
	if _stop_left > 0.0:
		_stop_left = maxf(0.0, _stop_left - delta)
		return
	var next: float = global_position.x + float(_dir) * speed * delta
	var left: float = _origin.x - travel * 0.5
	var right: float = _origin.x + travel * 0.5
	if next <= left:
		next = left
		_dir = 1
		_stop_left = stop_time
	elif next >= right:
		next = right
		_dir = -1
		_stop_left = stop_time
	global_position = Vector2(next, global_position.y)

## 现在车上有没有人
func has_rider() -> bool:
	return _rider != null and is_instance_valid(_rider)

func rider() -> Node2D:
	return _rider if has_rider() else null

func is_at_end() -> bool:
	return _stop_left > 0.0

func _on_body_entered(body: Node2D) -> void:
	if body is MinePlayer:
		_rider = body
		print("[矿洞] 跳上矿车（", "往右" if _dir > 0 else "往左", "开）")

func _on_body_exited(body: Node2D) -> void:
	if body == _rider:
		_rider = null
