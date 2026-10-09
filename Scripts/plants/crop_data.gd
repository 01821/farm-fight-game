class_name CropData

## 作物数据表。种类 id 直接就是图集里的**行号**（kenney_tiny-farm/tilemap_packed.png）。
##
## 图集布局（已 8 倍放大逐格确认）：
##   行 0 = 胡萝卜，行 1 = 紫甘蓝，行 2 = 玉米，行 3 = 番茄，行 4 = 卷心菜
##   每行的列 4..8 是同一种作物的生长序列
##
## ⚠️ 列 7 与列 8 的含义待确认（见 PROJECT_NOTES「待确认」一节）：
##    列 8 看起来是「收获物图标」（比一格还大），列 7 在胡萝卜/番茄/卷心菜行看起来像「一堆土」。
##    如果确实如此，现在 growStage=3 会显示成「作物消失」，应当把 STAGE_COLUMNS 改成 [4, 5, 6, 8]。
##    因为无法从静止图判定，这里保持现状，但把它抽成常量 —— 要改只改这一行。

const STAGE_COLUMNS: Array[int] = [4, 5, 6, 7, 8]

## 从播种到成熟要浇多少次水
const MAX_STAGE: int = 4

## id 就是图集行号；grow_time 是「每升一级」所需秒数
## min_day = 第几天开始能种/能买 —— 开局只给胡萝卜，复杂度随天数摊开，
## 每次解锁都是一次小奖励，而不是一上来就丢给玩家 5 个选择。
const CROPS: Array[Dictionary] = [
	{"id": 0, "name": "胡萝卜", "seed_price": 3, "sell_price": 6, "grow_time": 2.0, "min_day": 1},
	{"id": 1, "name": "紫甘蓝", "seed_price": 5, "sell_price": 11, "grow_time": 2.8, "min_day": 2},
	{"id": 2, "name": "玉米", "seed_price": 8, "sell_price": 19, "grow_time": 3.6, "min_day": 3},
	{"id": 3, "name": "番茄", "seed_price": 12, "sell_price": 30, "grow_time": 4.6, "min_day": 5},
	{"id": 4, "name": "卷心菜", "seed_price": 18, "sell_price": 48, "grow_time": 5.6, "min_day": 7},
]

static func min_day_of(type_id: int) -> int:
	return int(get_crop(type_id).get("min_day", 1))

static func is_unlocked(type_id: int, day: int) -> bool:
	return is_valid(type_id) and day >= min_day_of(type_id)

## 第 day 天已经解锁的种类
static func unlocked_kinds(day: int) -> Array[int]:
	var out: Array[int] = []
	for c in CROPS:
		var id: int = int(c.get("id", 0))
		if day >= int(c.get("min_day", 1)):
			out.append(id)
	return out

## 下一个待解锁的种类（没有就返回 -1），用来给玩家提示「再撑几天有新作物」
static func next_locked(day: int) -> int:
	for c in CROPS:
		if day < int(c.get("min_day", 1)):
			return int(c.get("id", 0))
	return -1

static func count() -> int:
	return CROPS.size()

static func is_valid(type_id: int) -> bool:
	return type_id >= 0 and type_id < CROPS.size()

static func get_crop(type_id: int) -> Dictionary:
	if not is_valid(type_id):
		return CROPS[0]
	return CROPS[type_id]

static func name_of(type_id: int) -> String:
	return String(get_crop(type_id).get("name", "?"))

static func seed_price(type_id: int) -> int:
	return int(get_crop(type_id).get("seed_price", 1))

static func sell_price(type_id: int) -> int:
	return int(get_crop(type_id).get("sell_price", 1))

static func grow_time(type_id: int) -> float:
	return float(get_crop(type_id).get("grow_time", 3.0))

## 生长阶段 -> 图集列号
static func column_for_stage(stage: int) -> int:
	return STAGE_COLUMNS[clampi(stage, 0, STAGE_COLUMNS.size() - 1)]
