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

## 图集格子（18×18）。**这几格是放大图集逐个看过的，不是猜的。**
const ATLAS_SOLID_TOP := Vector2i(0, 2)   # 带高光的土层表面
const ATLAS_SOLID_FILL := Vector2i(4, 0)  # 纯土，用于地表以下
## ⚠️ 平台这一格是**试出来的**，两次踩坑记在这里：
##    ① 原来用 (12,0) —— 那其实是**红白警戒带**，渲染出来是一条红橙条纹，不是木板。
##    ② 改用 (11,1) —— 放大图集看那块"木板"，结果**那一格是透明的**，平台整个消失。
##    最后用 (4,0)：地下纯土。它**已经被我亲眼确认过渲染正常**（矿洞地表以下就是它），
##    读作"土台子"，而且和地表那层浅色高光区分得开。
##    结论：挑图集格子，**看不清就放大看，改完一定截图确认**，别靠描述猜。
const ATLAS_PLATFORM := Vector2i(4, 0)

const SOLID := "#"
const PLATFORM := "="
const SPAWN := "S"

## 外部显式指定的地图。**留空就用当前层数对应的地图** ——
## 测试会把它设成自己的小地图（那种情况下不该被分层覆盖掉）。
@export var map: PackedStringArray = PackedStringArray()

## 每层的地图（下标 = depth - 1）。
## 用 var 而不是 const —— `PackedStringArray([...])` **不是常量表达式**，const 会编译失败。
var MAPS: Array[PackedStringArray] = [
	# 第 1 层：最宽松，平台少、间隔大
	PackedStringArray([
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
	]),
	# 第 2 层：平台变多、抬高，掉下去的风险变大
	PackedStringArray([
		"                                                ",
		"        ====                                    ",
		"                                                ",
		"                  ====                          ",
		"                              ====              ",
		"                                                ",
		"      ====            ====            ====      ",
		"                                                ",
		"                                                ",
		"  S                                             ",
		"                                                ",
		"################################################",
		"################################################",
		"################################################",
	]),
	# 第 3 层：层层叠叠，落脚点碎，逼你一路跳
	PackedStringArray([
		"                                                ",
		"      ====        ====        ====              ",
		"                                                ",
		"    ====        ====        ====        ====    ",
		"                                                ",
		"      ====        ====        ====              ",
		"                                                ",
		"    ====        ====        ====        ====    ",
		"                                                ",
		"  S                                             ",
		"                                                ",
		"################################################",
		"################################################",
		"################################################",
	]),
]

## 掉落物场景，在场景文件里预先接好
@export var pickup_scene: PackedScene
## 关底被拆掉时掉几份金币 / 几块矿石
@export var boss_coin_drops: int = 5
@export var boss_coin_value: int = 8
@export var boss_ore_drops: int = 3

@onready var terrain: TileMapLayer = $Terrain
@onready var player: MinePlayer = $MinePlayer

func _ready() -> void:
	build()
	_hook_player()
	_scale_enemies_by_depth()
	_apply_hazard_depth()
	# ⚠️ 这里**不要**自动 MineRun.start_run()。
	#    踩过的坑：自动开局之后，测试里玩家一死就会触发 MineRun.finish()，
	#    而 finish() 会真的 change_scene_to_file —— 测试场景当场被换掉，
	#    后面所有断言全部失效，报的错还完全看不出跟矿洞有关。
	#    现在只有真的从矿洞口进来（MineRun.active 已经是 true）才有火把倒计时。
	if MineRun.active:
		print("[矿洞] 第 ", MineRun.depth, " 层，火把 ", int(MineRun.torch_left), " 秒")

## 陷阱只在**第 2 层及以下**生效，第 1 层是干净的新手层。
##
## 这条一石二鸟：玩法上是"越深越凶"的递进（第 1 层教你打怪、认路），
## 工程上顺带把陷阱和"只关心移动/战斗的老测试"隔离开了 ——
## 之前往共享关卡里加东西，把不相关的测试打红过两次。
func _apply_hazard_depth() -> void:
	var on: bool = MineRun.depth >= 2
	var n_haz: int = 0
	for n in get_tree().get_nodes_in_group("mine_hazard"):
		var h := n as Node2D
		if h == null:
			continue
		n_haz += 1
		h.visible = on
		# 关掉整个处理 —— 只把 visible 设 false 的话，地刺照样会扎人
		h.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		var a := h as Area2D
		if a != null:
			a.monitoring = on
	if n_haz > 0:
		print("[矿洞] 第 ", MineRun.depth, " 层：陷阱 ", "开启" if on else "关闭", "（", n_haz, " 处）")

## 越深怪越强。血量和伤害一起涨 —— 只涨血的话，玩家会觉得"变肉了"而不是"变难了"。
func _scale_enemies_by_depth() -> void:
	var mult: float = MineRun.enemy_multiplier()
	if is_equal_approx(mult, 1.0):
		return
	for n in get_tree().get_nodes_in_group("mine_enemy"):
		var e := n as MineEnemy
		if e == null:
			continue
		e.max_hp = maxi(1, int(round(float(e.max_hp) * mult)))
		e.hp = e.max_hp
		e.set("_damage", maxi(1, int(round(float(e.get("_damage")) * minf(mult, 1.6)))))
	for n in get_tree().get_nodes_in_group("mine_boss"):
		var b := n as MineEnemy
		if b == null:
			continue
		b.max_hp = maxi(1, int(round(float(b.max_hp) * mult)))
		b.hp = b.max_hp
	print("[矿洞] 第 ", MineRun.depth, " 层：敌人强度 x", mult)

func _hook_player() -> void:
	if player == null:
		return
	if not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)

## 每只怪死掉都掉一份金币，并计入这趟的战绩。
## Boss 不在 "mine_enemy" 分组里（它是另一类东西），所以要单独 hook 一次。
func _hook_enemies() -> void:
	for n in get_tree().get_nodes_in_group("mine_enemy"):
		var e := n as MineEnemy
		if e != null and not e.died.is_connected(_on_enemy_died):
			e.died.connect(_on_enemy_died)
	for n in get_tree().get_nodes_in_group("mine_boss"):
		var b := n as MineEnemy
		if b != null and not b.died.is_connected(_on_enemy_died):
			b.died.connect(_on_enemy_died)

func _on_enemy_died(enemy: MineEnemy) -> void:
	if enemy.is_boss():
		_on_boss_died(enemy)
		return
	MineRun.add_kill()
	if pickup_scene == null or not is_instance_valid(enemy):
		return
	var from: Vector2 = enemy.global_position + Vector2(0, -12)
	_spawn_drop(MinePickup.Kind.COIN, 1 + enemy.max_hp, from)
	# 25% 概率额外掉一块矿石 —— 稀有才值得高兴
	if randf() < 0.25:
		_spawn_drop(MinePickup.Kind.ORE, -1, from)
		print("[矿洞] ", enemy.display_name(), " 还掉了一块矿石！")

## 关底被拆：掉一大笔，并记进这趟战绩
func _on_boss_died(boss: MineEnemy) -> void:
	MineRun.add_kill()
	MineRun.boss_down = true
	print("[矿洞] ", boss.display_name(), " 被拆了！矿洞清净了")
	if pickup_scene == null or not is_instance_valid(boss):
		return
	var origin: Vector2 = boss.global_position + Vector2(0, -20)
	# 撒开一点，不然五份金币会叠成一份的样子
	for i in range(boss_coin_drops):
		var off: float = float(i) - float(boss_coin_drops - 1) * 0.5
		_spawn_drop(MinePickup.Kind.COIN, boss_coin_value, origin + Vector2(off * 18.0, 0))
	for i in range(boss_ore_drops):
		var off2: float = float(i) - float(boss_ore_drops - 1) * 0.5
		_spawn_drop(MinePickup.Kind.ORE, -1, origin + Vector2(off2 * 24.0, 8.0))
	Sfx.play("goal")

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
	MineRun.mark_died()
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

## 用**程序化生成**的地图（关掉就退回下面手写的那几张，方便对照调试）
@export var use_generated_map: bool = true

## 当前实际用的地图，优先级：
##   1. 显式设过 `map`（测试用自定义小地图时走这条）
##   2. 程序化生成（种子 = 存档槽号 + 层数）
##   3. 手写的兜底地图
func active_map() -> PackedStringArray:
	if map.size() > 0:
		return map
	if use_generated_map:
		return MineGen.generate(MineRun.level_seed())
	return MAPS[clampi(MineRun.depth - 1, 0, MAPS.size() - 1)]

## 把 active_map() 铺成瓦片。返回出生点的格子坐标。
func build() -> Vector2i:
	var m := active_map()
	terrain.clear()
	var spawn := Vector2i(2, 9)
	for y in range(m.size()):
		var row: String = m[y]
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
	var m := active_map()
	if y < 0 or y >= m.size():
		return " "
	var row: String = m[y]
	if x < 0 or x >= row.length():
		return " "
	return row[x]

## 关卡在全局坐标下的矩形（给摄像机做边界用）
func world_rect() -> Rect2:
	var m := active_map()
	var cols: int = 0
	for row in m:
		cols = maxi(cols, row.length())
	return Rect2(Vector2.ZERO, Vector2(cols * TILE_SIZE, m.size() * TILE_SIZE))

## 某个格子是不是实心的（测试用）
func is_solid(cell: Vector2i) -> bool:
	return _char_at(cell.x, cell.y) == SOLID

func is_platform(cell: Vector2i) -> bool:
	return _char_at(cell.x, cell.y) == PLATFORM
