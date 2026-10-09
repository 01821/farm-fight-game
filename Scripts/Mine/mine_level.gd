class_name MineLevel extends Node2D

## 矿洞关卡：把脚本里那张 ASCII 图铺成 TileMapLayer，顺便给玩家找出生点。
##
## 为什么要用 ASCII 图而不是在编辑器里一格一格画：
##   关卡改一行字就能改，diff 看得见，AI 也能安全地改（不用碰二进制 tile_map_data）。
##   只用 `set_cell()` 写数据，**没有动态创建任何节点**，符合项目约定。
##
## 图例：
##   `#` 实心土块（有碰撞）
##   `=` 木板平台（只有上表面有碰撞，可以从下面跳上去）
##   `S` 出生点（本身不放瓦片）
##   空格 空

const TILE_SIZE: int = 18

## 图集格子（18×18，已画网格确认过）
const ATLAS_SOLID_TOP := Vector2i(0, 2)   # 带高光的土层表面
const ATLAS_SOLID_FILL := Vector2i(4, 0)  # 纯土，用于地表以下
const ATLAS_PLATFORM := Vector2i(12, 0)   # 木板平台

const SOLID := "#"
const PLATFORM := "="
const SPAWN := "S"

@export var map: PackedStringArray = PackedStringArray([
	"                                                ",
	"                                                ",
	"            ====                                ",
	"                                                ",
	"                      ====                      ",
	"                                                ",
	"        ====                    ====            ",
	"                                                ",
	"                                                ",
	"  S                                             ",
	"                                                ",
	"################################################",
	"################################################",
	"################################################",
])

@onready var terrain: TileMapLayer = $Terrain
@onready var player: MinePlayer = $MinePlayer

func _ready() -> void:
	build()

## 把 map 铺成瓦片。返回出生点的格子坐标。
func build() -> Vector2i:
	terrain.clear()
	var spawn := Vector2i(2, 9)
	for y in range(map.size()):
		var row: String = map[y]
		for x in range(row.length()):
			var ch: String = row[x]
			match ch:
				SOLID:
					# 地表那层用带高光的，下面用纯土，看起来才有"地面"的感觉
					var tile: Vector2i = ATLAS_SOLID_TOP if _char_at(x, y - 1) != SOLID else ATLAS_SOLID_FILL
					terrain.set_cell(Vector2i(x, y), 0, tile)
				PLATFORM:
					terrain.set_cell(Vector2i(x, y), 0, ATLAS_PLATFORM)
				SPAWN:
					spawn = Vector2i(x, y)
	if player != null:
		player.global_position = terrain.to_global(terrain.map_to_local(spawn))
	return spawn

func _char_at(x: int, y: int) -> String:
	if y < 0 or y >= map.size():
		return " "
	var row: String = map[y]
	if x < 0 or x >= row.length():
		return " "
	return row[x]

## 关卡在全局坐标下的矩形（给摄像机做边界用）
func world_rect() -> Rect2:
	var cols: int = 0
	for row in map:
		cols = maxi(cols, row.length())
	return Rect2(Vector2.ZERO, Vector2(cols * TILE_SIZE, map.size() * TILE_SIZE))

## 某个格子是不是实心的（测试用）
func is_solid(cell: Vector2i) -> bool:
	return _char_at(cell.x, cell.y) == SOLID

func is_platform(cell: Vector2i) -> bool:
	return _char_at(cell.x, cell.y) == PLATFORM
