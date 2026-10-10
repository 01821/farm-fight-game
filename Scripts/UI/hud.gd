extends CanvasLayer

## 左上角状态栏（四行）+ 三个浮层：目标横幅、成就提示条、升级二选一面板。
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
@onready var banner: Label = $Banner
@onready var banner_backdrop: ColorRect = $BannerBackdrop
@onready var toast: Label = $Toast
@onready var toast_backdrop: ColorRect = $ToastBackdrop
@onready var stat_backdrop: ColorRect = $StatBackdrop
@onready var stat_title: Label = $StatTitle
@onready var stat_body: Label = $StatBody
@onready var goal_label: Label = $GoalLabel
@onready var equip_label: Label = $EquipLabel
@onready var perk_backdrop: ColorRect = $PerkBackdrop
@onready var perk_title: Label = $PerkTitle
@onready var perk_option1: Label = $PerkOption1
@onready var perk_option2: Label = $PerkOption2
@onready var player: Player = $"../level/Player"
@onready var cycle: DayCycle = $"../DayCycle"
@onready var controller: FarmController = $"../FarmController"
@onready var weather: Weather = get_node_or_null("../Weather") as Weather
@onready var achievements: Achievements = get_node_or_null("../Achievements") as Achievements

## Y 键生涯统计面板。
## 数据全部来自**已有的生涯计数**，没有为了这个面板另开一套统计 ——
## 玩家经历过的每一件事本来就被记着，这只是把它们摊开给他看。
var stats_open: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("stats_toggle"):
		stats_open = not stats_open
		get_viewport().set_input_as_handled()

func _update_stats_panel() -> void:
	stat_backdrop.visible = stats_open
	stat_title.visible = stats_open
	stat_body.visible = stats_open
	if not stats_open:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("—— 农场 ——")
	lines.append("玩了 %d 天" % cycle.day)
	lines.append("累计赚到 %d 金（身上 %d）" % [player.total_earned, player.money])
	lines.append("收获作物 %d 个" % player.total_harvested)
	lines.append("赶跑害兽 %d 只" % player.total_kills)
	lines.append("收畜产 %d 个" % player.total_goods)
	lines.append("加工价值 %d 金" % player.total_processed)
	lines.append("")
	lines.append("—— 矿洞 ——")
	lines.append("下矿 %d 趟" % MineRun.total_runs)
	lines.append("赶跑矿怪 %d 只" % MineRun.total_mine_kills)
	lines.append("拆掉关底 %d 台" % MineRun.total_boss)
	lines.append("到过最深第 %d 层" % MineRun.deepest)
	lines.append("单趟最多带回 %d 金" % MineRun.best_run_gold)
	lines.append("一命通关 %d 次" % MineRun.flawless_runs)
	lines.append("")
	var lv: String = ""
	for i in range(Upgrades.INFO.size()):
		if i > 0:
			lv += "  "
		lv += "%s%d" % [Upgrades.name_of(i), Upgrades.level_of(i)]
	lines.append("土地升级 " + lv)
	stat_body.text = "\n".join(lines)

## 统计面板当前正文（测试直接读）
func stats_text() -> String:
	return stat_body.text

## 当前目标。**常驻显示**，做完了自动换下一条 —— 这就是"一环接一环"。
func _update_goal() -> void:
	if Guide.is_all_done():
		goal_label.text = "目标：全部完成！(%d/%d)" % [Guide.count_done(), Guide.total()]
		goal_label.add_theme_color_override("font_color", Color(0.7, 1, 0.75))
		return
	var hint: String = Guide.current_hint()
	goal_label.text = "目标(%d/%d)：%s" % [Guide.count_done() + 1, Guide.total(), Guide.current_text()]
	goal_label.add_theme_color_override("font_color", Color(1, 0.93, 0.62))
	if hint != "":
		goal_label.tooltip_text = hint

## 目标文本（测试直接读）
func goal_text() -> String:
	return goal_label.text

func _process(_delta: float) -> void:
	# 所有浮层节点都是预建的，这里只切可见性和文本
	var won: bool = controller.goal_reached
	banner.visible = won
	banner_backdrop.visible = won

	var show_toast: bool = achievements != null and achievements.toast_visible()
	toast.visible = show_toast
	toast_backdrop.visible = show_toast
	if show_toast:
		toast.text = achievements.toast_text()

	_update_perk_panel()
	_update_stats_panel()
	_update_goal()

	var phase := "%s %d 秒" % [cycle.phase_name(), ceili(cycle.phase_time_left())]
	var sky: String = weather.sky_name() if weather != null else "晴天"
	if won:
		info_label.text = "第 %d 天   %s   %s   目标已达成！" % [cycle.day, phase, sky]
	else:
		info_label.text = "第 %d 天   %s   %s   目标 %d/%d" % [
			cycle.day, phase, sky,
			mini(player.money, FarmController.GOLD_GOAL), FarmController.GOLD_GOAL
		]
	farm_label.text = "金币 %d   血量 %d/%d   水量 %d/%d   成就 %d/%d" % [
		player.money, player.hp, player.max_hp, player.water_left, Player.WATER_CAPACITY,
		achievements.count() if achievements != null else 0,
		achievements.total() if achievements != null else 0
	]
	held_label.text = "手持: %s   种子 %d   作物 %d   农耕%d 战斗%d 经营%d" % [
		player.item_name(), player.seed_count(), player.basket_total(),
		Progression.level_of(Progression.Skill.FARM),
		Progression.level_of(Progression.Skill.COMBAT),
		Progression.level_of(Progression.Skill.TRADE)
	]
	# ⚠️ 装备**必须单独一行**。塞进 held_label 的尾巴上会被屏幕右边切掉
	#    （"装备:" 三个字之后什么都没了）—— 这是截图看出来的，测试量不出来。
	equip_label.text = "装备: %s   伤害+%d 减伤%d 血+%d" % [
		player.equipment_line(), player.total_damage_bonus(),
		player.total_defense(), player.total_hp_bonus()
	]
	key_label.text = "[1-5]选作物 [Q]切换 [F]使用 [F5]存 [F9]读 [Y]统计"

## 升级二选一面板。注意：面板亮着的时候 1 / 2 是「选专精」，
## 路由在 FarmController._unhandled_input 里。
func _update_perk_panel() -> void:
	var pending: bool = Progression.pending_choice >= 0
	perk_backdrop.visible = pending
	perk_title.visible = pending
	perk_option1.visible = pending
	perk_option2.visible = pending
	if not pending:
		return
	var options := Progression.pending_options()
	perk_title.text = "%s 升级！选一项专精（不可更改）" % Progression.pending_skill_name()
	if options.size() > 0:
		var p0: Dictionary = options[0]
		perk_option1.text = "[1] %s —— %s" % [p0.get("name", "?"), p0.get("desc", "")]
	else:
		perk_option1.text = ""
	if options.size() > 1:
		var p1: Dictionary = options[1]
		perk_option2.text = "[2] %s —— %s" % [p1.get("name", "?"), p1.get("desc", "")]
	else:
		perk_option2.text = ""
