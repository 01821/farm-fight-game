extends Node

## 成长系统。这是一个**自动加载单例**，全局名字就叫 `Progression`。
##
## 三个系各自攒经验、升级，升级时**二选一**拿专精。经验全部来自玩家已经在做的事，
## 不需要额外学新操作：
##   农耕：每收获 1 个作物 +1
##   战斗：每赶跑 1 只害兽 +1
##   经营：每卖出 10 金 +1
##
## 专精效果**不写成一堆散落的 if**，而是集中成下面那一组查询函数
## （sell_multiplier / water_radius / ...），各系统问一句就行。
## 加新专精时：在 PERKS 里加一条 + 在查询函数里加一行。

signal level_changed(skill: int, level: int)
signal choice_offered(skill: int)
signal perk_taken(skill: int, perk_id: String, perk_name: String)

enum Skill { FARM, COMBAT, TRADE }

const SKILL_NAMES: Array[String] = ["农耕", "战斗", "经营"]

## 每级需要的累计经验（下标 = 已升级数）。长度决定一共能升几级。
const LEVEL_STEPS: Array[int] = [3, 8]

## PERKS[系][第几次选择][选项]
const PERKS: Array = [
	[
		[
			{"id": "farmer", "name": "农夫", "desc": "作物售价 +20%"},
			{"id": "gardener", "name": "园丁", "desc": "浇水一次覆盖周围 3x3"},
		],
		[
			{"id": "breeder", "name": "育种家", "desc": "作物生长时间 -25%"},
			{"id": "hoarder", "name": "囤积者", "desc": "收获时 25% 概率多得一株"},
		],
	],
	[
		[
			{"id": "swordsman", "name": "剑客", "desc": "攻击范围 +40%"},
			{"id": "bulwark", "name": "铁壁", "desc": "最大生命 +3"},
		],
		[
			{"id": "executioner", "name": "处决者", "desc": "对满血敌人伤害翻倍"},
			{"id": "hunter", "name": "猎手", "desc": "击杀赏金翻倍"},
		],
	],
	[
		[
			{"id": "merchant", "name": "商人", "desc": "种子便宜 30%"},
			{"id": "saver", "name": "储户", "desc": "每天天亮 +5 金利息"},
		],
		[
			{"id": "wholesale", "name": "批发", "desc": "卖光作物时额外 +15%"},
			{"id": "insurance", "name": "保险", "desc": "晕倒不再损失金币"},
		],
	],
]

var xp: Array[int] = [0, 0, 0]
var level: Array[int] = [0, 0, 0]
## 每个系已经选过几次专精
var chosen: Array[int] = [0, 0, 0]
var perks: Dictionary = {}
## 正在等玩家二选一的系；-1 表示没有
var pending_choice: int = -1
## 关掉就不再弹选择（测试里可以静音）
var enabled: bool = true

func _ready() -> void:
	add_to_group("progression")

# --- 基础查询 ---

func skill_name(skill: int) -> String:
	if skill < 0 or skill >= SKILL_NAMES.size():
		return "?"
	return SKILL_NAMES[skill]

func xp_of(skill: int) -> int:
	if skill < 0 or skill >= xp.size():
		return 0
	return xp[skill]

func level_of(skill: int) -> int:
	if skill < 0 or skill >= level.size():
		return 0
	return level[skill]

func has_perk(id: String) -> bool:
	return perks.has(id)

func perk_count() -> int:
	return perks.size()

# --- 经验与升级 ---

func add_xp(skill: int, amount: int) -> void:
	if amount <= 0 or skill < 0 or skill >= SKILL_NAMES.size():
		return
	xp[skill] += amount
	_check_level_up(skill)

func _check_level_up(skill: int) -> void:
	var leveled: bool = false
	while level[skill] < LEVEL_STEPS.size() and xp[skill] >= LEVEL_STEPS[level[skill]]:
		level[skill] += 1
		leveled = true
		print("[成长] ", SKILL_NAMES[skill], " 升到 ", level[skill], " 级（经验 ", xp[skill], "）")
		level_changed.emit(skill, level[skill])
	if leveled:
		_schedule_next_offer()

func _schedule_next_offer() -> void:
	if not enabled or pending_choice >= 0:
		return
	for s in range(SKILL_NAMES.size()):
		if chosen[s] < level[s] and chosen[s] < PERKS[s].size():
			pending_choice = s
			print("[成长] 请选择 ", SKILL_NAMES[s], " 专精（按 1 或 2）")
			choice_offered.emit(s)
			return

## 当前待选的两个选项；没有待选就返回空数组
func pending_options() -> Array:
	if pending_choice < 0:
		return []
	var tier: int = chosen[pending_choice]
	if tier < 0 or tier >= PERKS[pending_choice].size():
		return []
	return PERKS[pending_choice][tier]

func pending_skill_name() -> String:
	return skill_name(pending_choice)

func choose(index: int) -> bool:
	if pending_choice < 0:
		return false
	var options := pending_options()
	if index < 0 or index >= options.size():
		return false
	var skill: int = pending_choice
	var perk: Dictionary = options[index]
	perks[String(perk["id"])] = true
	chosen[skill] += 1
	pending_choice = -1
	print("[成长] 选择了 ", perk["name"], " —— ", perk["desc"])
	perk_taken.emit(skill, String(perk["id"]), String(perk["name"]))
	# 可能一次升了不止一级，选完接着弹下一个
	_schedule_next_offer()
	return true

## 直接给一个专精（调试 / 测试用）
func force_perk(id: String) -> bool:
	if has_perk(id):
		return false
	for s in range(PERKS.size()):
		for tier in PERKS[s]:
			for perk in tier:
				if String(perk["id"]) == id:
					perks[id] = true
					chosen[s] += 1
					return true
	return false

func reset() -> void:
	xp = [0, 0, 0]
	level = [0, 0, 0]
	chosen = [0, 0, 0]
	perks.clear()
	pending_choice = -1

# --- 专精效果（各系统问这里） ---

## 卖作物的价格倍率
func sell_multiplier() -> float:
	var m: float = 1.0
	if has_perk("farmer"):
		m += 0.20
	if has_perk("wholesale"):
		m += 0.15
	return m

## 买种子的价格倍率
func seed_price_multiplier() -> float:
	return 0.7 if has_perk("merchant") else 1.0

## 作物生长时间倍率
func grow_time_multiplier() -> float:
	return 0.75 if has_perk("breeder") else 1.0

## 收获时多得一株的概率
func harvest_bonus_chance() -> float:
	return 0.25 if has_perk("hoarder") else 0.0

## 浇水额外覆盖的半径（0 = 只浇一格）
func water_radius() -> int:
	return 1 if has_perk("gardener") else 0

func max_hp_bonus() -> int:
	return 3 if has_perk("bulwark") else 0

func attack_range_multiplier() -> float:
	return 1.4 if has_perk("swordsman") else 1.0

func bounty_multiplier() -> float:
	return 2.0 if has_perk("hunter") else 1.0

## 处决者：对满血敌人伤害翻倍
func executes_full_hp() -> bool:
	return has_perk("executioner")

## 晕倒是否还扣金币
func death_penalty_enabled() -> bool:
	return not has_perk("insurance")

func daily_interest() -> int:
	return 5 if has_perk("saver") else 0

# --- 存档 ---

func to_save_data() -> Dictionary:
	return {
		"xp": Array(xp), "level": Array(level), "chosen": Array(chosen),
		"perks": perks.keys(),
	}

func apply_save_data(d: Dictionary) -> void:
	reset()
	_read_ints(d.get("xp", null), xp)
	_read_ints(d.get("level", null), level)
	_read_ints(d.get("chosen", null), chosen)
	for id in d.get("perks", []):
		perks[String(id)] = true

func _read_ints(src: Variant, dst: Array[int]) -> void:
	if typeof(src) != TYPE_ARRAY:
		return
	var arr: Array = src
	for i in range(mini(arr.size(), dst.size())):
		dst[i] = maxi(0, int(arr[i]))
