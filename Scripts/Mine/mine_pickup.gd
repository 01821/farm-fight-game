class_name MinePickup extends Area2D

## 矿洞里的掉落物：金币 / 矿石。玩家碰到就自动捡走，记在 `MineRun` 上。
##
## 是**预建场景**，怪死掉或宝箱打开时 instantiate 一个（不 new 节点）。
## 捡到的钱**不会立刻进农场玩家的钱包** —— 要活着回到农场才结算，
## 在洞里倒下就全丢了。这是"下矿有风险"的核心。

## ⚠️ 加新种类时注意：**涂色是靠 modulate，不换图集格**。
##    因为图集格选错不会报错、只会渲染成别的东西（平台那一格我就踩过三次）。
##    复用已经确认能渲染的格子 + 上色，是这里最稳的做法。
enum Kind { COIN, ORE, GEM, RELIC }

const CELL: int = 18

## kind → {图集格, 默认价值, 名字, 颜色}
const KINDS: Array[Dictionary] = [
	{"cell": Vector2i(11, 7), "value": 3, "name": "金币", "tint": Color.WHITE},
	{"cell": Vector2i(7, 3), "value": 9, "name": "矿石", "tint": Color.WHITE},
	# 宝石：值钱得多。普通怪小概率掉、精英怪必掉 —— 这一下就把"打怪"从
	# "走过场"变成"有盼头"。
	{"cell": Vector2i(7, 3), "value": 40, "name": "宝石", "tint": Color(1.8, 1.45, 0.5)},
	# 遗物：不掉钱，**带一件装备回农场**。捡到它的感觉和捡钱完全不一样。
	{"cell": Vector2i(4, 2), "value": 0, "name": "遗物", "tint": Color(1.6, 1.15, 0.55)},
]

@export var kind: int = Kind.COIN
## -1 = 用这种掉落物的默认价值
@export var amount: int = -1
## 遗物带的装备 id（只有 Kind.RELIC 用）
@export var item_id: String = ""
## 被弹出来的初速度，让掉落物有"蹦一下"的效果
@export var pop_velocity: Vector2 = Vector2(0, -90)

var _velocity: Vector2 = Vector2.ZERO
var _life: float = 0.0
var _taken: bool = false
## 出生点（**局部坐标**）。落回这里就停，不要用 y > 0 判断 ——
## 踩过的坑：position 是相对关卡的，掉在地上的金币 position.y 本来就是 190 多，
## 用 `position.y > 0` 会把它们全部瞬移到关卡顶部 y=0。
var _spawn_pos: Vector2 = Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("mine_pickup")
	body_entered.connect(_on_body_entered)
	var d: Dictionary = KINDS[clampi(kind, 0, KINDS.size() - 1)]
	var cell: Vector2i = d["cell"]
	sprite.region_rect = Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL)
	sprite.modulate = d.get("tint", Color.WHITE)
	# 贵的东西要大一点、闪一点 —— 玩家在一堆金币里得一眼看见它
	if kind == Kind.GEM or kind == Kind.RELIC:
		sprite.scale = Vector2(1.35, 1.35)
	if amount < 0:
		amount = int(d["value"])
	_velocity = pop_velocity
	_spawn_pos = position

func display_name() -> String:
	return String(KINDS[clampi(kind, 0, KINDS.size() - 1)]["name"])

func _physics_process(delta: float) -> void:
	_life += delta
	# 蹦一下然后落回出生高度
	if absf(_velocity.y) > 1.0 or absf(_velocity.x) > 1.0:
		_velocity.y += 620.0 * delta
		_velocity.x = move_toward(_velocity.x, 0.0, 200.0 * delta)
		position += _velocity * delta
		if position.y >= _spawn_pos.y:
			position = _spawn_pos
			_velocity = Vector2.ZERO
	# 20 秒没人捡就自己消失，免得场景里越积越多
	if _life > 20.0:
		queue_free()

## 由生成方在设置好 global_position 之后调一次，记下出生点
func mark_spawn() -> void:
	_spawn_pos = position

func _on_body_entered(body: Node2D) -> void:
	if _taken or not (body is MinePlayer):
		return
	_taken = true
	match kind:
		Kind.ORE:
			MineRun.add_ore(amount)
		Kind.GEM:
			MineRun.add_gold(amount)
			print("[矿洞] ★ 捡到宝石，", amount, " 金")
		Kind.RELIC:
			MineRun.add_item(item_id)
			print("[矿洞] ★★ 捡到遗物：", ItemData.name_of(item_id))
		_:
			MineRun.add_gold(amount)
	Sfx.play("coin")
	queue_free()
