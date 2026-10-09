class_name PestSpawner extends Node2D

## 野猪刷新器：每隔 spawn_interval 秒，在玩家周围的环上放一只野猪，场上最多 max_pests 只。
## boar_scene 是预先做好的场景（在编辑器 / .tscn 里指定），运行时只做 instantiate。
## 之所以是 Node2D：自身的 global_position 可以当刷新锚点（拿不到玩家时用）。

@export var boar_scene: PackedScene
@export var spawn_interval: float = 14.0
@export var max_pests: int = 3
@export var spawn_distance: float = 165.0
@export var auto_start: bool = true

var _elapsed: float = 0.0
var _player: Player

func _ready() -> void:
	add_to_group("pest_spawner")
	_player = get_tree().get_first_node_in_group("player")

func _process(delta: float) -> void:
	if not auto_start:
		return
	_elapsed += delta
	if _elapsed < spawn_interval:
		return
	_elapsed = 0.0
	if get_tree().get_nodes_in_group("pest").size() >= max_pests:
		return
	spawn_one()

## 立刻放一只，返回实例（测试直接调这个）
func spawn_one() -> Boar:
	if boar_scene == null:
		push_error("PestSpawner: boar_scene 没有设置")
		return null
	var anchor: Vector2 = global_position
	if _player != null and is_instance_valid(_player):
		anchor = _player.global_position
	var angle: float = randf() * TAU
	var boar: Boar = boar_scene.instantiate()
	get_parent().add_child(boar)
	boar.global_position = anchor + Vector2.RIGHT.rotated(angle) * spawn_distance
	print("[战斗] 一只野猪闯进农场了（场上 ", get_tree().get_nodes_in_group("pest").size(), " 只）")
	return boar
