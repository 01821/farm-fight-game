class_name MineChest extends Area2D

## 矿洞里的宝箱：玩家碰到就打开，掉出一堆金币和矿石。
##
## 图集里宝箱是**三帧**的（关 / 半开 / 全开），这里只用第一帧和最后一帧。
## 掉落物走的是**预建的 MinePickup 场景**（instantiate，不 new 节点）。

const CELL: int = 18
const CELL_CLOSED := Vector2i(9, 1)
const CELL_OPEN := Vector2i(11, 1)

@export var coin_count: int = 3
@export var ore_count: int = 1
## 掉落物场景，在场景文件里预先接好
@export var pickup_scene: PackedScene

var _opened: bool = false

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("mine_chest")
	body_entered.connect(_on_body_entered)
	_set_cell(CELL_CLOSED)

func _set_cell(c: Vector2i) -> void:
	sprite.region_rect = Rect2(c.x * CELL, c.y * CELL, CELL, CELL)

func is_opened() -> bool:
	return _opened

func _on_body_entered(body: Node2D) -> void:
	if _opened or not (body is MinePlayer):
		return
	open()

## 开箱。返回掉了几份东西；已经开过就返回 0。
func open() -> int:
	if _opened:
		return 0
	_opened = true
	_set_cell(CELL_OPEN)
	monitoring = false
	Sfx.play("buy")
	var n: int = 0
	for i in range(coin_count):
		if _spawn(MinePickup.Kind.COIN, i, coin_count):
			n += 1
	for i in range(ore_count):
		if _spawn(MinePickup.Kind.ORE, i, ore_count):
			n += 1
	print("[矿洞] 开宝箱，掉出 ", n, " 份东西")
	return n

## 把掉落物往两边撒开，免得全叠在一个点上
func _spawn(kind: int, index: int, total: int) -> bool:
	if pickup_scene == null:
		return false
	var p := pickup_scene.instantiate() as MinePickup
	if p == null:
		return false
	var spread: float = float(index) - float(total - 1) * 0.5
	# kind / pop_velocity 必须在 add_child **之前**设好 —— _ready 会拿它们初始化
	p.kind = kind
	p.pop_velocity = Vector2(spread * 30.0, -110.0 - absf(spread) * 10.0)
	get_parent().add_child(p)
	p.global_position = global_position + Vector2(0, -6)
	p.mark_spawn()
	return true
