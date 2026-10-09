extends Node

## 一次性分析工具：判定作物生长阶段的列映射。
## 用法: godot --headless --path . res://Tools/analyze_crops.tscn
##
## 要回答的问题：图集列 7 到底是「成株」还是「收获后的空地/土堆」？
##
## 判据（很硬）：
##   如果某一列在 5 种作物之间**几乎一模一样**，那它就是各种作物**共用**的一张图
##   （空地/土堆）；如果它是「各自的成熟植株」，跨作物的差异必然很大。
##
## 另外把每一格跟图集里的参考土块比一次，看谁最像土。

const ATLAS := "res://Assets/kenney_tiny-farm/Tilemap/tilemap_packed.png"
const CELL: int = 16
const COLS: Array[int] = [4, 5, 6, 7, 8]
const ROWS: Array[int] = [0, 1, 2, 3, 4]
## 图集里明显的空地/土块，拿来当「像不像土」的参照
const SOIL_REFS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 2), Vector2i(1, 2)]

func _ready() -> void:
	var tex := load(ATLAS) as Texture2D
	if tex == null:
		push_error("图集加载失败")
		get_tree().quit()
		return
	var img: Image = tex.get_image()
	if img == null:
		push_error("取不到像素（可能被压缩了）")
		get_tree().quit()
		return
	if img.is_compressed():
		img.decompress()
	print("图集 ", img.get_width(), " x ", img.get_height(), "（", img.get_format(), "）")

	var soil: Array = []
	for p in SOIL_REFS:
		soil.append(_cell(img, p.x, p.y))

	print("")
	print("列 | 跨作物平均差 | 与土块平均差 | 结论")
	print("---+--------------+--------------+------")
	var report: Array[Dictionary] = []
	for c in COLS:
		var cells: Array = []
		for r in ROWS:
			cells.append(_cell(img, c, r))

		var pair_sum: float = 0.0
		var pair_n: int = 0
		for i in range(cells.size()):
			for j in range(i + 1, cells.size()):
				pair_sum += _diff(cells[i], cells[j])
				pair_n += 1
		var cross: float = pair_sum / float(pair_n)

		var soil_sum: float = 0.0
		for cell in cells:
			var best := INF
			for s in soil:
				best = minf(best, _diff(cell, s))
			soil_sum += best
		var to_soil: float = soil_sum / float(cells.size())

		report.append({"col": c, "cross": cross, "soil": to_soil})
		print("%2d | %12.2f | %12.2f |" % [c, cross, to_soil])

	# 判定：跨作物差异最小的那一列，就是各种作物共用的图
	var min_cross: float = INF
	var min_col: int = -1
	for e in report:
		if float(e["cross"]) < min_cross:
			min_cross = float(e["cross"])
			min_col = int(e["col"])
	var max_cross: float = 0.0
	for e in report:
		max_cross = maxf(max_cross, float(e["cross"]))

	print("")
	print("跨作物差异最小的列 = ", min_col, "（", "%.2f" % min_cross, "）")
	print("跨作物差异最大的列 = ", "%.2f" % max_cross)
	print("")
	if min_col == 7 and max_cross > min_cross * 3.0:
		print(">>> 判定：列 7 是**各作物共用**的图（空地 / 土堆），不是成熟植株。")
		print(">>> 应当把 CropData.STAGE_COLUMNS 改成 [4, 5, 6, 8]，MAX_STAGE 改成 3。")
	else:
		print(">>> 判定：没有哪一列明显「共用」。")
		print(">>> 说明列 7 也是随作物变化的（成株/枯株），当前的 [4,5,6,7,8] 可以保留。")

	get_tree().quit()

func _cell(img: Image, col: int, row: int) -> PackedColorArray:
	var out := PackedColorArray()
	for y in range(CELL):
		for x in range(CELL):
			out.append(img.get_pixel(col * CELL + x, row * CELL + y))
	return out

## 平均每像素的 RGBA 绝对差，放大 100 倍方便看
func _diff(a: PackedColorArray, b: PackedColorArray) -> float:
	var s: float = 0.0
	for i in range(a.size()):
		s += absf(a[i].r - b[i].r) + absf(a[i].g - b[i].g) + absf(a[i].b - b[i].b) + absf(a[i].a - b[i].a)
	return s / float(a.size()) * 100.0
