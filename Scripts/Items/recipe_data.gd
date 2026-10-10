class_name RecipeData

## 配方表 —— 把「农场」和「矿洞」**真正咬合**起来的那一环。
##
## 之前两条线是各玩各的：农场赚钱只能买种子，矿洞赚钱也只能买种子，
## 两边都不产出**让另一边变强的东西**。所以链条是断的。
##
## 现在矿洞里背回来的矿石，加上农场种出来的作物，能在加工坊打成装备 ——
## 而装备让你打得动更深的矿。**这才是一个越滚越大的循环，而不是两块内容并排放着。**
##
## 配方三样原料：
##   gold   金币（农场那条线的产出）
##   ore    矿石（矿洞那条线的产出）
##   crops  作物（农场那条线，按品种计）

## {id, gold, ore, crops:{作物type:数量}}
const LIST: Array[Dictionary] = [
	{"id": "lucky_charm", "gold": 20, "ore": 1, "crops": {0: 2}},
	{"id": "iron_sword", "gold": 30, "ore": 2, "crops": {}},
	{"id": "iron_plate", "gold": 40, "ore": 3, "crops": {1: 2}},
	{"id": "machine_plate", "gold": 70, "ore": 5, "crops": {}},
	{"id": "heart_pendant", "gold": 80, "ore": 4, "crops": {0: 2, 1: 2}},
	{"id": "core_drill", "gold": 150, "ore": 6, "crops": {2: 2}},
]

## 一条配方要多少某作物
static func crop_need(r: Dictionary, type_id: int) -> int:
	var c: Dictionary = r.get("crops", {})
	return int(c.get(type_id, 0))

## 这条配方一共要多少作物
static func total_crops(r: Dictionary) -> int:
	var sum: int = 0
	for k in (r.get("crops", {}) as Dictionary).keys():
		sum += int((r.get("crops", {}) as Dictionary)[k])
	return sum

static func count() -> int:
	return LIST.size()

static func at(i: int) -> Dictionary:
	if i < 0 or i >= LIST.size():
		return {}
	return LIST[i]

static func find(id: String) -> Dictionary:
	for r in LIST:
		if String(r.get("id", "")) == id:
			return r
	return {}

## 配方产出的名字（就是物品表里的名字）
static func result_name(r: Dictionary) -> String:
	return ItemData.name_of(String(r.get("id", "")))

## 一条配方的可读说明，例如 "2 矿 + 2 胡萝卜 + 30 金 → 铁剑"
static func describe(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	var ore: int = int(r.get("ore", 0))
	if ore > 0:
		parts.append("%d 矿石" % ore)
	var crops: Dictionary = r.get("crops", {})
	for k in crops.keys():
		parts.append("%d %s" % [int(crops[k]), CropData.name_of(int(k))])
	var gold: int = int(r.get("gold", 0))
	if gold > 0:
		parts.append("%d 金" % gold)
	return "%s  →  %s" % [" + ".join(parts), result_name(r)]

## 缺什么？返回缺料的说明；什么都不缺返回空串。
## ⚠️ 判断"能不能做"和"缺什么"必须是**同一段逻辑** ——
##    分成两份写，早晚会出现"按钮是亮的但点了说材料不够"。
static func missing(r: Dictionary, p: Player) -> String:
	if r.is_empty() or p == null:
		return "没有这条配方"
	var lack: PackedStringArray = PackedStringArray()
	var ore: int = int(r.get("ore", 0))
	if ore > p.ore:
		lack.append("矿石 %d/%d" % [p.ore, ore])
	var crops: Dictionary = r.get("crops", {})
	for k in crops.keys():
		var type_id: int = int(k)
		var need: int = int(crops[k])
		var have: int = p.harvested[type_id] if type_id < p.harvested.size() else 0
		if have < need:
			lack.append("%s %d/%d" % [CropData.name_of(type_id), have, need])
	var gold: int = int(r.get("gold", 0))
	if gold > p.money:
		lack.append("金币 %d/%d" % [p.money, gold])
	if lack.size() == 0:
		return ""
	return "缺 " + "、".join(lack)

static func can_craft(r: Dictionary, p: Player) -> bool:
	return not r.is_empty() and missing(r, p) == ""

## 真的做一件。成功返回 true。
## **先验后扣**：用 can_craft 过一遍再动玩家的东西，失败时保证什么都没变。
static func craft(r: Dictionary, p: Player) -> bool:
	if not can_craft(r, p):
		return false
	p.money -= int(r.get("gold", 0))
	p.ore -= int(r.get("ore", 0))
	var crops: Dictionary = r.get("crops", {})
	for k in crops.keys():
		var type_id: int = int(k)
		p.harvested[type_id] = maxi(0, p.harvested[type_id] - int(crops[k]))
	p.add_item(String(r.get("id", "")), 1)
	p.total_crafted += 1
	print("[加工] 做出 ", result_name(r))
	return true

## 当前能做出来的第几条配方（给测试和 UI 找"有没有能做的"）
static func first_craftable(p: Player) -> int:
	for i in range(LIST.size()):
		if can_craft(LIST[i], p):
			return i
	return -1
