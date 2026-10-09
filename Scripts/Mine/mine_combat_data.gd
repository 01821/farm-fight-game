class_name MineCombatData

## 矿洞的战斗数值表：武器 + 技能。
##
## 沿用项目一贯的「数据表驱动」做法（照 CropData / PestData / Progression.PERKS 的样子）：
## **加一把武器或一个技能 = 表里加一条**，不用去改逻辑。

# --- 武器 ---
# id 就是下标。攻击判定的宽度直接用 reach 设，所以换武器能真的改变手感。
const WEAPONS: Array[Dictionary] = [
	{
		"id": 0, "name": "短剑",
		"damage": 1, "reach": 24.0, "box_height": 20.0,
		"cooldown": 0.34, "knock": 130.0,
		"color": Color(1, 1, 1, 0.8),
	},
	{
		"id": 1, "name": "巨剑",
		"damage": 2, "reach": 32.0, "box_height": 26.0,
		"cooldown": 0.62, "knock": 210.0,
		"color": Color(1.0, 0.72, 0.45, 0.85),
	},
]

# --- 技能 ---
# kind 决定这个技能怎么结算，逻辑在 MinePlayer.cast_skill() 里分派。
const SKILLS: Array[Dictionary] = [
	{
		"id": 0, "name": "重斩", "key": "H",
		"kind": "heavy", "cost": 4, "cooldown": 4.0,
		"damage": 3, "reach": 44.0, "box_height": 34.0,
		"desc": "向前一记大范围重砍，伤害高",
	},
	{
		"id": 1, "name": "旋风斩", "key": "U",
		"kind": "spin", "cost": 6, "cooldown": 6.0,
		"damage": 2, "radius": 34.0,
		"desc": "原地转一圈，打中身周所有敌人",
	},
	{
		"id": 2, "name": "冲刺", "key": "I",
		"kind": "dash", "cost": 3, "cooldown": 2.0,
		"speed": 300.0, "duration": 0.18, "damage": 1,
		"desc": "向前突进，突进期间无敌",
	},
	{
		"id": 3, "name": "治疗", "key": "O",
		"kind": "heal", "cost": 8, "cooldown": 10.0,
		"heal": 3,
		"desc": "回复 3 点生命",
	},
]

const ENERGY_MAX: int = 20
## 每秒回能
const ENERGY_REGEN: float = 2.2

static func weapon_count() -> int:
	return WEAPONS.size()

static func is_valid_weapon(id: int) -> bool:
	return id >= 0 and id < WEAPONS.size()

static func get_weapon(id: int) -> Dictionary:
	if not is_valid_weapon(id):
		return WEAPONS[0]
	return WEAPONS[id]

static func weapon_name(id: int) -> String:
	return String(get_weapon(id).get("name", "?"))

static func weapon_field(id: int, key: String, fallback: Variant) -> Variant:
	return get_weapon(id).get(key, fallback)

static func skill_count() -> int:
	return SKILLS.size()

static func is_valid_skill(id: int) -> bool:
	return id >= 0 and id < SKILLS.size()

static func get_skill(id: int) -> Dictionary:
	if not is_valid_skill(id):
		return SKILLS[0]
	return SKILLS[id]

static func skill_name(id: int) -> String:
	return String(get_skill(id).get("name", "?"))

static func skill_desc(id: int) -> String:
	return String(get_skill(id).get("desc", ""))

static func skill_field(id: int, key: String, fallback: Variant) -> Variant:
	return get_skill(id).get(key, fallback)
