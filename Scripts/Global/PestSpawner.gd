class_name PestSpawner extends Node2D

## 野猪刷新器：**只在夜晚**放野猪，白天不放；天亮时场上的野猪全部撤退。
##
## 每夜按「波」刷新：间隔 wave_interval 秒一波，每波 wave_size（随天数增长）只，场上上限 max_pests。
## 之所以是 Node2D：自身的 global_position 可以当刷新锚点（拿不到玩家时用）。
##
## 找不到 DayCycle 时会退回 always_active 的行为（给单元测试用）。

@export var boar_scene: PackedScene
@export var spawn_distance: float = 165.0
@export var max_pests: int = 6
@export var wave_interval: float = 8.0
@export var always_active: bool = false

var _cycle: DayCycle
var _wave_timer: float = 0.0
var _active: bool = false

func _ready() -> void:
	add_to_group("pest_spawner")
	_try_resolve()

## DayCycle 若排在后面，_ready 时它的分组还没注册 —— 所以允许之后再补查一次。
## 不依赖场景里的节点顺序，免得以后挪一下节点就静默失效。
func _try_resolve() -> void:
	if _cycle != null:
		return
	_cycle = get_tree().get_first_node_in_group("day_cycle")
	if _cycle == null:
		return
	_cycle.night_started.connect(_on_night_started)
	_cycle.day_started.connect(_on_day_started)
	_active = _cycle.is_night

func is_active() -> bool:
	return _active

func _on_night_started(_day: int) -> void:
	_active = true
	_wave_timer = wave_interval  # 入夜立刻来第一波，不用等一个间隔

func _on_day_started(_day: int) -> void:
	_active = false
	retreat_all()

## 天亮：场上野猪全部撤退
func retreat_all() -> int:
	var pests := get_tree().get_nodes_in_group("pest")
	var n: int = pests.size()
	if n > 0:
		print("[战斗] 天亮了，", n, " 只野猪撤退了")
	for node in pests:
		var boar := node as Boar
		if boar != null and is_instance_valid(boar):
			boar.queue_free()
	return n

func _process(delta: float) -> void:
	if _cycle == null:
		_try_resolve()
		if _cycle == null:
			_active = always_active
	else:
		# 每帧与昼夜状态对齐：读档会直接改 DayCycle 状态，只靠信号同步会漏掉
		_active = _cycle.is_night
	if not _active:
		return
	_wave_timer += delta
	if _wave_timer < wave_interval:
		return
	_wave_timer = 0.0
	spawn_wave()

## 放一整波，返回实际放出的数量
func spawn_wave() -> int:
	var want: int = _cycle.wave_size() if _cycle != null else 1
	var spawned: int = 0
	for i in range(want):
		if get_tree().get_nodes_in_group("pest").size() >= max_pests:
			break
		if spawn_one() != null:
			spawned += 1
	return spawned

## 立刻放一只，返回实例（测试直接调这个）
func spawn_one() -> Boar:
	if boar_scene == null:
		push_error("PestSpawner: boar_scene 没有设置")
		return null
	var anchor: Vector2 = global_position
	var player := get_tree().get_first_node_in_group("player") as Player
	if player != null and is_instance_valid(player):
		anchor = player.global_position
	var angle: float = randf() * TAU
	var boar: Boar = boar_scene.instantiate()
	get_parent().add_child(boar)
	boar.global_position = anchor + Vector2.RIGHT.rotated(angle) * spawn_distance
	print("[战斗] 一只野猪闯进农场了（场上 ", get_tree().get_nodes_in_group("pest").size(), " 只）")
	return boar
