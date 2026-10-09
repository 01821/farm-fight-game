extends CanvasLayer

## 左上角状态栏，四行。
##
## 字体由项目设置 gui/theme/custom_font 指定：
##   Fusion Pixel Font 12px 简体（OFL，见 Assets/fonts/OFL-fusion-pixel-font.txt）
## 字号必须用 12（该字体的设计尺寸），配合窗口整数倍缩放才像素对齐。
##
## HUD 挂在 CanvasLayer 上，是独立画布，所以**不会被夜晚的 NightTint 压暗**，始终清晰。

@onready var info_label: Label = $InfoLabel
@onready var farm_label: Label = $FarmLabel
@onready var held_label: Label = $HeldLabel
@onready var key_label: Label = $KeyLabel
@onready var player: Player = $"../level/Player"
@onready var cycle: DayCycle = $"../DayCycle"
@onready var controller: FarmController = $"../FarmController"

func _process(_delta: float) -> void:
	var phase := "%s %d 秒" % [cycle.phase_name(), ceili(cycle.phase_time_left())]
	if controller.goal_reached:
		info_label.text = "第 %d 天   %s   目标已达成！" % [cycle.day, phase]
	else:
		info_label.text = "第 %d 天   %s   目标 %d/%d" % [
			cycle.day, phase,
			mini(player.money, FarmController.GOLD_GOAL), FarmController.GOLD_GOAL
		]
	farm_label.text = "金币 %d   血量 %d/%d   水量 %d/%d" % [
		player.money, player.hp, Player.MAX_HP, player.water_left, Player.WATER_CAPACITY
	]
	held_label.text = "手持: %s   种子 %d   作物 %d" % [
		player.item_name(), player.seed_count(), player.basket_total()
	]
	key_label.text = "[1-5]选作物 [Q]切换 [F]使用 [F5]存 [F9]读"
