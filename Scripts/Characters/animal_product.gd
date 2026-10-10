class_name AnimalProduct extends Area2D

## 动物产出物（蛋 / 奶）。落在草地上，玩家走过去自动收走。
##
## 蛋的形状用 Polygon2D 画 —— **图集里没有蛋**（Kenney 这套是平台跳跃的地形/道具），
## 和地刺一样的处理：用预建的多边形，不引入任何外部素材。
##
## 收进 `player.animal_goods`，在商店和作物**一起卖**。

## 一个畜产卖多少钱
const PRICE: int = 7
const GOODS_NAME: String = "畜产"

@export var value: int = 1

var _taken: bool = false
var _bob: float = 0.0

@onready var shell: Polygon2D = $Shell

func _ready() -> void:
	add_to_group("animal_product")
	body_entered.connect(_on_body_entered)
	_bob = randf() * TAU

## 轻轻上下浮，一眼能看出"这是可以捡的东西"
func _process(delta: float) -> void:
	_bob += delta * 2.6
	shell.position.y = sin(_bob) * 1.5

func _on_body_entered(body: Node2D) -> void:
	if _taken or not (body is Player):
		return
	_taken = true
	var p := body as Player
	p.add_goods(value)
	Sfx.play("coin")
	queue_free()
