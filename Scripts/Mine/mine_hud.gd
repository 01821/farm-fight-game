class_name MineHud extends CanvasLayer

## 矿洞里的 HUD：心形血量 + 技能栏 + 能量/武器状态。
##
## 全部是**预建节点**，脚本只改文本和颜色，不在运行时创建任何东西。
##   心形  —— 取自地形图集的三档（满 (4,2) / 半 (5,2) / 空 (6,2)），**一颗心 = 2 点血**
##   技能栏 —— 4 个 Label，冷却中变灰并显示剩余秒数

const CELL: int = 18
const HEART_FULL := Vector2i(4, 2)
const HEART_HALF := Vector2i(5, 2)
const HEART_EMPTY := Vector2i(6, 2)

const COLOR_READY := Color(1, 0.95, 0.6)
const COLOR_COOLDOWN := Color(0.55, 0.55, 0.6)
const COLOR_NO_ENERGY := Color(0.75, 0.5, 0.5)

@onready var hearts_root: Node2D = $Hearts
@onready var status_label: Label = $StatusLabel
@onready var torch_label: Label = $TorchLabel
@onready var potion_label: Label = $PotionLabel
@onready var skill_list_backdrop: ColorRect = $SkillListBackdrop
@onready var skill_list_title: Label = $SkillListTitle
@onready var skill_list_body: Label = $SkillListBody
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

func skill_label(i: int) -> Label:
	return get_node_or_null("Skill%d" % (i + 1)) as Label

func skill_labels() -> Array[Label]:
	var out: Array[Label] = []
	for i in range(MineCombatData.skill_count()):
		var l := skill_label(i)
		if l != null:
			out.append(l)
	return out

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("mine_player") as MinePlayer
		if _player == null:
			return
	_refresh_hearts(_player.hp, _player.MAX_HP)
	_refresh_skills()
	_refresh_status()
	_refresh_skill_list()

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

## 技能栏：可用时亮黄，冷却中变灰并在名字后面标剩余秒数，能量不够则偏红
func _refresh_skills() -> void:
	for i in range(MineCombatData.skill_count()):
		var l := skill_label(i)
		if l == null:
			continue
		var key: String = String(MineCombatData.skill_field(i, "key", "?"))
		var name: String = MineCombatData.skill_name(i)
		var cd: float = _player.skill_cd[i]
		if cd > 0.05:
			l.text = "[%s]%s %.1f" % [key, name, cd]
			l.add_theme_color_override("font_color", COLOR_COOLDOWN)
		elif _player.energy < float(MineCombatData.skill_field(i, "cost", 0)):
			l.text = "[%s]%s" % [key, name]
			l.add_theme_color_override("font_color", COLOR_NO_ENERGY)
		else:
			l.text = "[%s]%s" % [key, name]
			l.add_theme_color_override("font_color", COLOR_READY)

func _refresh_status() -> void:
	var cost_txt: String = ""
	if _player.is_dashing():
		cost_txt = "   冲刺中"
	status_label.text = "能量 %d/%d    武器 %s [L]切换%s" % [
		int(_player.energy), MineCombatData.ENERGY_MAX, _player.weapon_name(), cost_txt
	]
	# 火把 + 这趟的收获
	var torch: float = MineRun.torch_left
	torch_label.text = "火把 %d 秒   收获 %d 金" % [ceili(torch), MineRun.gold]
	if torch <= 10.0:
		torch_label.add_theme_color_override("font_color", Color(1, 0.4, 0.3))
	else:
		torch_label.add_theme_color_override("font_color", Color(1, 0.86, 0.5))
	# 消耗品（和技能是分开的两套资源）
	potion_label.text = "[1] 回血药 x%d（回 %d 点）    [P] 技能表" % [_player.potions, MinePlayer.POTION_HEAL]
	if _player.potions <= 0:
		potion_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	else:
		potion_label.add_theme_color_override("font_color", Color(0.75, 1, 0.8))

## P 键技能表：列出每个技能的按键、消耗、冷却和说明
func _refresh_skill_list() -> void:
	var open: bool = _player.skill_list_open
	skill_list_backdrop.visible = open
	skill_list_title.visible = open
	skill_list_body.visible = open
	if not open:
		return
	skill_list_title.text = "技能表（按 P 收起）"
	var lines: PackedStringArray = PackedStringArray()
	for i in range(MineCombatData.skill_count()):
		lines.append("[%s] %s   消耗%d  冷却%ds" % [
			String(MineCombatData.skill_field(i, "key", "?")),
			MineCombatData.skill_name(i),
			int(MineCombatData.skill_field(i, "cost", 0)),
			int(MineCombatData.skill_field(i, "cooldown", 0)),
		])
		lines.append("      " + MineCombatData.skill_desc(i))
	skill_list_body.text = "\n".join(lines)

func set_hint(text: String) -> void:
	hint.text = text
