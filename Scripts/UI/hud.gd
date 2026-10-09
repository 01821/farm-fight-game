extends CanvasLayer

## 左上角状态栏。每帧直接读玩家状态，不做信号同步（状态很少，够用且不容易出错）。
## 注：Godot 内置字体不含中文字形，这里用英文以免渲染成方块。

@onready var info_label: Label = $InfoLabel
@onready var held_label: Label = $HeldLabel
@onready var player: Player = $"../level/Player"

func _process(_delta: float) -> void:
	info_label.text = "Gold %d   Seeds %d   Crops %d   Water %d/%d" % [
		player.money, player.seeds, player.harvested, player.water_left, Player.WATER_CAPACITY
	]
	held_label.text = "[Q] switch   [F] use   holding: %s" % player.item_name()
