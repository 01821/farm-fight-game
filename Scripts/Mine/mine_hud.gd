class_name MineHud extends CanvasLayer

## 矿洞里的 HUD：左上角一排心形血量。
##
## 心形直接取自地形图集里的三档（满 / 半 / 空），不用自己画：
##   满 (4,2)  半 (5,2)  空 (6,2)，格子 18×18
##
## 心是**预建的 Sprite2D 子节点**，脚本只改它们的 region_rect，
## 不在运行时创建任何节点。

const CELL: int = 18
const HEART_FULL := Vector2i(4, 2)
const HEART_HALF := Vector2i(5, 2)
const HEART_EMPTY := Vector2i(6, 2)
## 相邻两颗心之间的水平间距
const STEP: float = 17.0

@onready var hearts_root: Node2D = $Hearts
@onready var hint: Label = $HintLabel

var _player: MinePlayer

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("mine_player") as MinePlayer

func hearts() -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	for c in hearts_root.get_children():
		if c is Sprite2D:
			out.append(c)
	return out

func heart_count() -> int:
	return hearts().size()

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("mine_player") as MinePlayer
		if _player == null:
			return
	_refresh_hearts(_player.hp, _player.MAX_HP)

## 按当前血量刷新每一颗心：满 / 半 / 空。**一颗心 = 2 点血。**
func _refresh_hearts(hp: int, max_hp: int) -> void:
	var needed: int = ceili(float(max_hp) / 2.0)
	var list := hearts()
	for i in range(list.size()):
		var h: Sprite2D = list[i]
		if i >= needed:
			h.visible = false
			continue
		h.visible = true
		var cell: Vector2i
		if hp >= (i + 1) * 2:
			cell = HEART_FULL
		elif hp >= i * 2 + 1:
			cell = HEART_HALF
		else:
			cell = HEART_EMPTY
		h.region_rect = Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL)

func set_hint(text: String) -> void:
	hint.text = text
