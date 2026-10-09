extends CanvasLayer

## 左上角状态栏。每帧直接读玩家状态，不做信号同步（状态很少，够用且不容易出错）。
##
## 字体由项目设置 gui/theme/custom_font 指定：
##   Fusion Pixel Font 12px 简体（OFL 协议，见 Assets/fonts/OFL-fusion-pixel-font.txt）
## 字号必须用 12（该字体的设计尺寸），配合窗口的整数倍缩放才是像素对齐的。

@onready var info_label: Label = $InfoLabel
@onready var held_label: Label = $HeldLabel
@onready var player: Player = $"../level/Player"

func _process(_delta: float) -> void:
	info_label.text = "金币 %d   血量 %d/%d   种子 %d   作物 %d   水量 %d/%d" % [
		player.money, player.hp, Player.MAX_HP,
		player.seeds, player.harvested, player.water_left, Player.WATER_CAPACITY
	]
	held_label.text = "[Q] 切换   [F] 使用   手持: %s" % player.item_name()
