extends Character

## 农场里的动物。除了到处走，**每天早上会下一个蛋**。
##
## 这是农场的第二条收入线：作物要买种子、浇水、等生长；
## 动物是一次性投入、之后每天白拿。两条线的节奏不一样，玩家可以选。
##
## 蛋落地后不会自己消失（上限 MAX_PENDING 个），玩家走过去就收走。

## 一只动物最多同时在地上留几个蛋 —— 不设上限的话，
## 玩家几天不收，地上会堆满蛋，既卡画面又破坏"每天去收"的节奏。
const MAX_PENDING: int = 3

@onready var move_timer: Timer = $MoveTimer

## 产出物场景，在场景文件里预先接好
@export var product_scene: PackedScene

var _cycle: DayCycle
var _resolved: bool = false
var _pending: int = 0
var _produced_total: int = 0

func _ready() -> void:
	add_to_group("animal")
	_try_resolve()

## DayCycle 可能排在后面，_ready 时分组还没注册，所以允许之后再补查
func _try_resolve() -> bool:
	if _resolved:
		return true
	_cycle = get_tree().get_first_node_in_group("day_cycle") as DayCycle
	if _cycle == null:
		return false
	_cycle.day_started.connect(_on_day_started)
	_resolved = true
	print("[农场] 动物开始产出了（每早一个，最多同时留 ", MAX_PENDING, " 个）")
	return true

func _process(_delta: float) -> void:
	if not _resolved:
		_try_resolve()

func _on_day_started(day: int) -> void:
	produce(day)

## 产出一个。返回有没有真的产（已经堆满就返回 false）。
func produce(day: int = 0) -> bool:
	if product_scene == null:
		return false
	if _pending >= MAX_PENDING:
		print("[农场] 地上已经堆了 ", _pending, " 个畜产，先收一收")
		return false
	var p := product_scene.instantiate() as AnimalProduct
	if p == null:
		return false
	get_parent().add_child(p)
	# 落在脚边、稍微散开一点，免得几个蛋叠成一个
	p.global_position = global_position + Vector2(randf_range(-8.0, 8.0), 4.0)
	p.tree_exited.connect(_on_product_gone)
	_pending += 1
	_produced_total += 1
	print("[农场] 第 ", day, " 天：", name, " 产出了一个畜产（地上 ", _pending, " 个）")
	return true

func _on_product_gone() -> void:
	_pending = maxi(0, _pending - 1)

## 地上还有几个没被收走
func pending_products() -> int:
	return _pending

## 这只动物一共产出过多少
func produced_total() -> int:
	return _produced_total
