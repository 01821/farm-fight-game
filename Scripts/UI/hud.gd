extends CanvasLayer

## 左上角状态栏，三行。
##
## 字体由项目设置 gui/theme/custom_font 指定：
##   Fusion Pixel Font 12px 简体（OFL，见 Assets/fonts/OFL-fusion-pixel-font.txt）
## 字号必须用 12（该字体的设计尺寸），配合窗口整数倍缩放才像素对齐。
##
## HUD 挂在 CanvasLayer 上，是独立画布，所以**不会被夜晚的 NightTint 压暗**，始终清晰。

@onready var info_label: Label = $InfoLabel
@onready var farm_label: Label = $FarmLabel
@onready var held_label: Label = $HeldLabel
@onready var player: Player = $"../level/Player"
@onready var cycle: DayCycle = $"../DayCycle"
@onready var controller: FarmController = $"../FarmController"

func _process(_delta: float) -> void:
	info_label.text = "第 %d 天   %s   金币 %d   血量 %d/%d" % [
		cycle.day, cycle.phase_name(), player.money, player.hp, Player.MAX_HP
	]
	if controller.goal_reached:
		farm_label.text = "种子 %d   作物 %d   水量 %d/%d   目标已达成！" % [
			player.seeds, player.harvested, player.water_left, Player.WATER_CAPACITY
		]
	else:
		farm_label.text = "种子 %d   作物 %d   水量 %d/%d   目标 %d/%d" % [
			player.seeds, player.harvested, player.water_left, Player.WATER_CAPACITY,
			mini(player.money, FarmController.GOLD_GOAL), FarmController.GOLD_GOAL
		]
	held_label.text = "[Q] 切换   [F] 使用   手持: %s" % player.item_name()
