class_name MineEntrance extends Node2D

## 农场这边的矿洞口：走进去按 F 就下矿。
##
## 交互方式照抄现有的水源 / 商店：预建的 InteractionArea + body_entered/exited。
## 进洞前**先存一次档**（切场景会丢掉 base_level 的一切），
## 从洞里回来时再结算这趟的收获。

@export var mine_scene: String = "res://Scenes/Mine/mine_level.tscn"

var _player_inside: bool = false
var _save: SaveSystem

@onready var area: Area2D = $InteractionArea
@onready var active_sprite: Sprite2D = $ActiveSprite

func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	_save = get_tree().get_first_node_in_group("save_system") as SaveSystem
	_settle_previous_run()

## 从矿洞回到农场的这一帧：把这趟的收获结算给玩家。
## 存档是在**进洞之前**拍的，所以失败时什么都不用做 —— 收获自然就没了。
func _settle_previous_run() -> void:
	if not MineRun.has_result():
		return
	var r := MineRun.consume_result()
	var player := get_tree().get_first_node_in_group("player") as Player
	var success: bool = bool(r.get("success", false))
	var gold: int = int(r.get("gold", 0))
	var kills: int = int(r.get("kills", 0))
	var ore: int = int(r.get("ore", 0))
	if success and gold > 0 and player != null:
		player.earn(gold)
		Sfx.play("coin")
	print("[矿洞] 结算：", "带回 " if success else "丢掉 ", gold,
		" 金 / ", ore, " 块矿石（赶跑 ", kills, " 只），现在有 ", player.money if player != null else 0)

func is_player_inside() -> bool:
	return _player_inside

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player_inside = true
		if active_sprite != null:
			active_sprite.visible = true
		print("[矿洞] 按 F 下矿（火把 ", int(MineRun.TORCH_TIME), " 秒）")

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_player_inside = false
		if active_sprite != null:
			active_sprite.visible = false

## 由 FarmController 在按 F 时调用
func enter_mine() -> bool:
	if not _player_inside or MineRun.active:
		return false
	if _save == null:
		_save = get_tree().get_first_node_in_group("save_system") as SaveSystem
	if _save != null:
		_save.save_game()
		print("[矿洞] 进洞前已存档（切场景靠它恢复农场）")
	MineRun.start_run()
	get_tree().change_scene_to_file(mine_scene)
	return true
