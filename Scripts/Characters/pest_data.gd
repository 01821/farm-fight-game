class_name PestData

## 害兽数据表。贴图取自 kenney_tiny-dungeon/Tilemap/tilemap_packed.png，
## `cell` 是「图集列, 图集行」，坐标已用 8 倍放大逐格确认过。
##
## ⚠️ 图集行 9 = y144，行 10 = y160。之前把「行9 列2」误记成恶魔，实际是红色螃蟹，
##    所以这张表里不再用它。

const CELL_SIZE: int = 16

const PESTS: Array[Dictionary] = [
	{
		"id": 0, "name": "野猪", "cell": Vector2i(3, 10),
		"hp": 2, "speed": 38.0, "reward": 2, "max_eats": 1,
		"min_day": 1, "weight": 10,
	},
	{
		"id": 1, "name": "蝙蝠", "cell": Vector2i(0, 10),
		"hp": 1, "speed": 66.0, "reward": 2, "max_eats": 1,
		"min_day": 2, "weight": 7,
	},
	{
		"id": 2, "name": "蜘蛛", "cell": Vector2i(2, 10),
		"hp": 3, "speed": 30.0, "reward": 5, "max_eats": 3,
		"min_day": 3, "weight": 5,
	},
]

static func count() -> int:
	return PESTS.size()

static func is_valid(id: int) -> bool:
	return id >= 0 and id < PESTS.size()

static func get_pest(id: int) -> Dictionary:
	if not is_valid(id):
		return PESTS[0]
	return PESTS[id]

static func name_of(id: int) -> String:
	return String(get_pest(id).get("name", "?"))

static func hp_of(id: int) -> int:
	return int(get_pest(id).get("hp", 1))

static func speed_of(id: int) -> float:
	return float(get_pest(id).get("speed", 38.0))

static func reward_of(id: int) -> int:
	return int(get_pest(id).get("reward", 0))

## 啃掉几株才罢休（1 = 啃一株就走）
static func max_eats_of(id: int) -> int:
	return int(get_pest(id).get("max_eats", 1))

static func min_day_of(id: int) -> int:
	return int(get_pest(id).get("min_day", 1))

static func region_of(id: int) -> Rect2:
	var cell: Vector2i = get_pest(id).get("cell", Vector2i.ZERO)
	return Rect2(cell.x * CELL_SIZE, cell.y * CELL_SIZE, CELL_SIZE, CELL_SIZE)

## 从第 day 天开始会出现的种类
static func kinds_for_day(day: int) -> Array[int]:
	var out: Array[int] = []
	for p in PESTS:
		if day >= int(p.get("min_day", 1)):
			out.append(int(p.get("id", 0)))
	return out

## 按天数抽一种（权重池，越往后池子里越容易出现强的）
static func pick_kind(day: int) -> int:
	var pool: Array[int] = []
	for p in PESTS:
		if day < int(p.get("min_day", 1)):
			continue
		var id: int = int(p.get("id", 0))
		for i in range(maxi(1, int(p.get("weight", 1)))):
			pool.append(id)
	if pool.is_empty():
		return 0
	return pool[randi() % pool.size()]
