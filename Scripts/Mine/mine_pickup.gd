class_name MinePickup extends Area2D

## 矿洞里的掉落物（金币）。玩家碰到就自动捡走，钱记在 `MineRun.gold` 上。
##
## 是**预建场景**，怪死掉时 instantiate 一个（不 new 节点）。
## 捡到的钱**不会立刻进农场玩家的钱包** —— 要活着回到农场才结算，
## 在洞里倒下就全丢了。这是"下矿有风险"的核心。

const COIN_CELL := Vector2i(11, 7)   # 地形图集里的金币
const CELL: int = 18

@export var amount: int = 3
## 被弹出来的初速度，让金币有个"蹦一下"的效果
@export var pop_velocity: Vector2 = Vector2(0, -90)

var _velocity: Vector2 = Vector2.ZERO
var _life: float = 0.0
var _taken: bool = false

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("mine_pickup")
	body_entered.connect(_on_body_entered)
	sprite.region_rect = Rect2(COIN_CELL.x * CELL, COIN_CELL.y * CELL, CELL, CELL)
	_velocity = pop_velocity

func _physics_process(delta: float) -> void:
	_life += delta
	# 蹦一下然后落地停住
	if absf(_velocity.y) > 1.0 or absf(_velocity.x) > 1.0:
		_velocity.y += 620.0 * delta
		_velocity.x = move_toward(_velocity.x, 0.0, 200.0 * delta)
		position += _velocity * delta
		if position.y > 0.0:
			position.y = 0.0
			_velocity = Vector2.ZERO
	# 15 秒没人捡就自己消失，免得场景里越积越多
	if _life > 15.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if _taken or not (body is MinePlayer):
		return
	_taken = true
	MineRun.add_gold(amount)
	Sfx.play("coin")
	queue_free()

func take_value() -> int:
	return amount
