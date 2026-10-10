class_name MineGen

## 矿洞地图生成器：**带种子的程序化生成**，产出和手写地图同一种格式
## （`PackedStringArray`），所以 `MineLevel.build()` 一行都不用改。
##
## 为什么要它：之前三张地图是写死的，**第二局和第一局一模一样**，重玩性接近 0。
## 现在同一个存档 + 同一层永远是同一张图（种子可复现），
## 换个存档或者换一层就是一张新图。
##
## ⚠️ 生成器必须保证**玩家够得着**自己造出来的平台。这不是"看起来差不多"就行：
##    跳跃高度 = 初速² / (2×重力) = 238² / (2×760) ≈ 37.3 px ≈ **2 格**。
##    所以平台只能一层一层往上、每层最多隔 2 行。
##    我原来手写的地图把平台摆在第 2/4/6 行，从地面（第 11 行）**一个都跳不上去**——
##    这个 bug 藏了十几轮，因为测试只验过"能站在地面上"。

## 地图尺寸（和手写地图一致，别乱改：相机边界、掉落物位置都按它算）
const W: int = 48
const H: int = 14
## 地面从这一行开始往下全是实心
const GROUND_ROW: int = 11
## 出生点
const SPAWN_X: int = 2
const SPAWN_Y: int = 9
## 平台可以摆的行。**从地面往上每 2 行一层**，正好在 37.3px 的跳跃高度之内。
## （留一点余量：2 行 = 36px，比极限 37.3px 少 1.3px，所以平台要做宽一点才好落。）
const PLATFORM_ROWS: Array[int] = [9, 7, 5, 3]

const SOLID := "#"
const PLATFORM := "="
const SPAWN := "S"

## 生成一张地图。同一个 seed 永远得到同一张图。
static func generate(seed_value: int) -> PackedStringArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var rows: Array[String] = []
	for y in range(H):
		rows.append(" ".repeat(W))

	# 地面：底下三行全实心
	for y in range(GROUND_ROW, H):
		rows[y] = SOLID.repeat(W)

	# 出生点
	rows[SPAWN_Y] = _put(rows[SPAWN_Y], SPAWN_X, SPAWN)

	# 平台：从低到高一层层往上摆，保证每一层都能从下一层跳上来
	for y in PLATFORM_ROWS:
		var count: int = rng.randi_range(2, 4)
		# 起点留出边距，别贴着地图边缘（贴边的话玩家没地方起跳）
		var x: int = rng.randi_range(5, 12)
		for i in range(count):
			var w: int = rng.randi_range(4, 7)
			if x + w > W - 3:
				break
			for k in range(w):
				rows[y] = _put(rows[y], x + k, PLATFORM)
			# 平台之间留一段空，不然连成一整条就没法"跳"了
			x += w + rng.randi_range(4, 9)

	# 出生点正上方别压平台 —— 免得玩家一出生就顶到东西
	rows[SPAWN_Y] = _put(rows[SPAWN_Y], SPAWN_X, SPAWN)

	var out := PackedStringArray()
	for r in rows:
		out.append(r)
	return out

## 把字符串第 x 个字符换成 ch（GDScript 的 String 不能直接按下标改）
static func _put(s: String, x: int, ch: String) -> String:
	if x < 0 or x >= s.length():
		return s
	return s.substr(0, x) + ch + s.substr(x + 1)

## 这一层的随机种子。
## **同一个存档 + 同一层 = 同一张图**（可以复现、可以分享种子），
## 换存档或者换层就是新图。
static func seed_for(slot: int, depth: int) -> int:
	return maxi(1, slot) * 1000 + maxi(1, depth)

## 第 row 行的平台顶面在世界坐标里的 y（给可达性测试用）
static func row_top_y(row: int) -> float:
	return float(row) * 18.0

## 从地面能跳到的最高那一行（用"最多 2 行"这个已知约束算出来）
static func lowest_platform_row() -> int:
	return PLATFORM_ROWS[0]
