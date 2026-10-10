class_name ItemData

## 物品表。
##
## 为什么要有它：这游戏原来是"2 把武器 + 3 种药 + 4 个技能"，全部开局就定好，
## **没有任何"捡到一件更好的东西"的时刻** —— 而泰拉瑞亚一半的驱动力就来自那一瞬间。
##
## 三件装备槽各管一个数：
##   WEAPON  加攻击力
##   ARMOR   减伤
##   TRINKET 加最大生命
## 这三条都能被测试直接量出来（"装上之后伤害真的变了吗"），
## 不是只写个数字摆在那里。

enum Slot { WEAPON, ARMOR, TRINKET }

const SLOT_NAMES: Array[String] = ["武器", "护甲", "饰品"]

## id -> {name, slot, desc, dmg, def, hp}
## dmg = 加的伤害；def = 每次挨打减掉几点；hp = 加的最大生命
const TABLE: Dictionary = {
	"bronze_sword": {
		"name": "青铜短剑", "slot": Slot.WEAPON, "dmg": 0, "def": 0, "hp": 0,
		"desc": "开局就有的那把，没什么好说的",
	},
	"iron_sword": {
		"name": "铁剑", "slot": Slot.WEAPON, "dmg": 1, "def": 0, "hp": 0,
		"desc": "在加工坊打出来的，砍起来实在多了",
	},
	"core_drill": {
		"name": "钻头核心", "slot": Slot.WEAPON, "dmg": 3, "def": 0, "hp": 0,
		"desc": "从采掘机械身上拆下来的。它还在转",
	},
	"leather_vest": {
		"name": "皮甲", "slot": Slot.ARMOR, "dmg": 0, "def": 1, "hp": 0,
		"desc": "挡一点是一点",
	},
	"iron_plate": {
		"name": "铁板甲", "slot": Slot.ARMOR, "dmg": 0, "def": 2, "hp": 0,
		"desc": "沉，但挨打不疼了",
	},
	"machine_plate": {
		"name": "机械装甲", "slot": Slot.ARMOR, "dmg": 0, "def": 2, "hp": 1,
		"desc": "采掘机械的外壳。还能再挨一下",
	},
	"lucky_charm": {
		"name": "护身符", "slot": Slot.TRINKET, "dmg": 0, "def": 0, "hp": 1,
		"desc": "多一条命的意思",
	},
	"heart_pendant": {
		"name": "心之坠", "slot": Slot.TRINKET, "dmg": 0, "def": 0, "hp": 2,
		"desc": "深处那种机械的能量核心，挂着挺暖",
	},
}

## 关底 Boss 的独特掉落：第几层掉什么。
## **只在第一次拆掉那一层时给** —— 所以它是个"时刻"，不是刷钱。
const BOSS_DROPS: Dictionary = {
	1: "iron_sword",
	2: "machine_plate",
	3: "core_drill",
}

static func exists(id: String) -> bool:
	return TABLE.has(id)

static func get_item(id: String) -> Dictionary:
	return TABLE.get(id, {})

static func name_of(id: String) -> String:
	return String(get_item(id).get("name", id))

static func slot_of(id: String) -> int:
	return int(get_item(id).get("slot", -1))

static func slot_name(slot: int) -> String:
	if slot < 0 or slot >= SLOT_NAMES.size():
		return "?"
	return SLOT_NAMES[slot]

static func desc_of(id: String) -> String:
	return String(get_item(id).get("desc", ""))

static func damage_of(id: String) -> int:
	return int(get_item(id).get("dmg", 0))

static func defense_of(id: String) -> int:
	return int(get_item(id).get("def", 0))

static func hp_of(id: String) -> int:
	return int(get_item(id).get("hp", 0))

## 某一层的独特掉落（没有就返回空串）
static func boss_drop(depth: int) -> String:
	return String(BOSS_DROPS.get(depth, ""))

static func count() -> int:
	return TABLE.size()

## 全表 id，顺序稳定（存档/测试用）
static func all_ids() -> Array[String]:
	var out: Array[String] = []
	for k in TABLE.keys():
		out.append(String(k))
	out.sort()
	return out
