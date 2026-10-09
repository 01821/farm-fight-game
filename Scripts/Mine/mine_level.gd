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

## 掉落物场景，在场景文件里预先接好
@export var pickup_scene: PackedScene

@onready var terrain: TileMapLayer = $Terrain
@onready var player: MinePlayer = $MinePlayer

func _ready() -> void:
	build()
	_hook_player()
	# ⚠️ 这里**不要**自动 MineRun.start_run()。
	#    踩过的坑：自动开局之后，测试里玩家一死就会触发 MineRun.finish()，
	#    而 finish() 会真的 change_scene_to_file —— 测试场景当场被换掉，
	#    后面所有断言全部失效，报的错还完全看不出跟矿洞有关。
	#    现在只有真的从矿洞口进来（MineRun.active 已经是 true）才有火把倒计时。
	if MineRun.active:
		print("[矿洞] 火把 ", int(MineRun.torch_left), " 秒，烧完自动回农场")

func _hook_player() -> void:
	if player == null:
		return
	if not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)

## 每只怪死掉都掉一份金币，并计入这趟的战绩
func _hook_enemies() -> void:
	for n in get_tree().get_nodes_in_group("mine_enemy"):
		var e := n as MineEnemy
		if e != null and not e.died.is_connected(_on_enemy_died):
			e.died.connect(_on_enemy_died)

func _on_enemy_died(enemy: MineEnemy) -> void:
	MineRun.add_kill()
	if pickup_scene == null or not is_instance_valid(enemy):
		return
	var from: Vector2 = enemy.global_position + Vector2(0, -12)
	_spawn_drop(MinePickup.Kind.COIN, 1 + enemy.max_hp, from)
	# 25% 概率额外掉一块矿石 —— 稀有才值得高兴
	if randf() < 0.25:
		_spawn_drop(MinePickup.Kind.ORE, -1, from)
		print("[矿洞] ", enemy.display_name(), " 还掉了一块矿石！")

func _spawn_drop(kind: int, value: int, at: Vector2) -> MinePickup:
	if pickup_scene == null:
		return null
	var drop := pickup_scene.instantiate() as MinePickup
	if drop == null:
		return null
	# kind / amount 要在 add_child **之前**设好 —— _ready 会拿它们初始化贴图和数值
	drop.kind = kind
	drop.amount = value
	add_child(drop)
	drop.global_position = at
	drop.mark_spawn()
	return drop

## 这一趟结束：在洞里倒下就是失败，丢掉这趟收获
func _on_player_died() -> void:
	MineRun.finish(false)

func _process(delta: float) -> void:
	_hook_player()
	_hook_enemies()
	if not MineRun.active:
		return
	MineRun.torch_left = maxf(0.0, MineRun.torch_left - delta)
	if MineRun.torch_left <= 0.0:
		print("[矿洞] 火把烧完了，被送回农场")
		MineRun.finish(true)

## 火把剩余比例（HUD 用）
func torch_ratio() -> float:
	if MineRun.TORCH_TIME <= 0.0:
		return 0.0
	return clampf(MineRun.torch_left / MineRun.TORCH_TIME, 0.0, 1.0)

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
