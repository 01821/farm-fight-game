extends Node2D

## 端到端自测：横版矿洞的角色控制（阶段 A）。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_mine.tscn
##
## 手感类的代码最容易"看起来对但一玩就不对"，所以这里不测函数返回值，
## **测的是角色在世界里的实际位置和速度**：真的会掉下去、真的站得住、
## 真的跳得起来、真的会被墙挡住、真的能踩上单向平台。

const TILE: int = 18

## 专用测试地图（比正式关卡更好控制）：
##   x0..8  r9/r10 是地面，地面顶面 y = 162
##   x5..8  r7 是单向木板平台，顶面 y = 126（比地面高 2 格 = 36px）
##   出生点在 (2,8)
## 注意：不能用 const —— PackedStringArray([...]) 不是常量表达式。
var TEST_MAP: PackedStringArray = PackedStringArray([
	"                          ",
	"                          ",
	"                          ",
	"                          ",
	"                          ",
	"                          ",
	"                          ",
	"     ====                 ",
	"  S                       ",
	"#########                 ",
	"#########                 ",
])

const GROUND_TOP: float = 9 * 18.0     # 162
const PLATFORM_TOP: float = 7 * 18.0   # 126

var _fail: int = 0
var _level: MineLevel
var _player: MinePlayer
var _terrain: TileMapLayer

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _step(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame

func _release_all() -> void:
	for a in ["left", "right", "jump"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)

## 把角色放到某处并清零速度，然后等它站稳
func _place(pos: Vector2, settle: int = 4) -> void:
	_release_all()
	_player.global_position = pos
	_player.velocity = Vector2.ZERO
	await _step(settle)

func _ready() -> void:
	_level = (load("res://Scenes/Mine/mine_level.tscn") as PackedScene).instantiate()
	_level.map = TEST_MAP
	add_child(_level)
	await get_tree().physics_frame
	_level.build()
	await _step(2)

	_player = _level.get_node("MinePlayer")
	_terrain = _level.get_node("Terrain")

	# ⚠️ 这个测试只管**移动手感**，先把关卡里的怪清掉。
	#    踩过的坑：往 mine_level.tscn 加了怪之后，这里用的是自定义小地图，
	#    怪在自定义地图上脚下没地面会到处漂，最后蝙蝠飞过来把玩家撞飞，
	#    "落在平台上"这条断言就莫名其妙地红了 —— 而且看起来像是跳跃代码坏了。
	for n in get_tree().get_nodes_in_group("mine_enemy"):
		n.queue_free()
	await _step(2)
	_check("已清场，没有怪干扰", get_tree().get_nodes_in_group("mine_enemy").is_empty())

	print("--- 地形 ---")
	var used := _terrain.get_used_cells()
	print("  INFO 铺了 ", used.size(), " 格")
	_check("地形铺出来了", used.size() > 0)
	_check("实心地面在 (0,9)", _level.is_solid(Vector2i(0, 9)))
	_check("平台在 (5,7)", _level.is_platform(Vector2i(5, 7)))
	_check("(0,0) 是空的", not _level.is_solid(Vector2i(0, 0)))
	_check("地表那层用了带高光的土", _terrain.get_cell_atlas_coords(Vector2i(0, 9)) == MineLevel.ATLAS_SOLID_TOP)
	_check("地表以下用纯土", _terrain.get_cell_atlas_coords(Vector2i(0, 10)) == MineLevel.ATLAS_SOLID_FILL)

	print("--- 重力与落地 ---")
	_player.global_position = Vector2(45, 60)
	_player.velocity = Vector2.ZERO
	await _step(2)
	_check("空中会往下掉", _player.velocity.y > 0.0)
	await _step(90)
	print("  INFO 落地后 feet.y = ", snappedf(_player.global_position.y, 0.1), "（地面顶面 ", GROUND_TOP, "）")

	# 把踩过的坑钉成回归断言：
	#   TileSet.tile_size 必须和 texture_region_size 一致，否则显示对但位置全歪，且不报错。
	#   瓦片物理多边形是相对格子中心的（整格 = -9..9），不是左上角。
	_check("TileSet.tile_size 是 18×18", _terrain.tile_set.tile_size == Vector2i(18, 18))
	_check("地形节点没有额外偏移", _terrain.global_position == Vector2.ZERO)
	var full_poly: PackedVector2Array = _terrain.tile_set.get_source(0).get_tile_data(
		MineLevel.ATLAS_SOLID_TOP, 0).get_collision_polygon_points(0, 0)
	_check("实心瓦片用中心相对的多边形", full_poly.size() == 4 and full_poly[0] == Vector2(-9, -9) and full_poly[2] == Vector2(9, 9))
	var plane_poly: PackedVector2Array = _terrain.tile_set.get_source(0).get_tile_data(
		MineLevel.ATLAS_PLATFORM, 0).get_collision_polygon_points(0, 0)
	_check("平台是薄片而不是整格", plane_poly.size() == 4 and plane_poly[2].y - plane_poly[0].y <= 8.0)
	_check("平台是单向的", _terrain.tile_set.get_source(0).get_tile_data(
		MineLevel.ATLAS_PLATFORM, 0).is_collision_polygon_one_way(0, 0))

	var space := _player.get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(Vector2(45.0, 100.0), Vector2(45.0, 260.0))
	q.exclude = [_player.get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		_check("向下射线能打到地面", false)
	else:
		print("  [dbg] 向下射线打到 y=", snappedf((hit["position"] as Vector2).y, 0.1), "（应为 ", GROUND_TOP, "）")
		_check("向下射线打到的正是地面顶面", absf((hit["position"] as Vector2).y - GROUND_TOP) < 0.6)

	_check("落到地面上站住", _player.is_on_floor())
	_check("没有穿过地面", _player.global_position.y <= GROUND_TOP + 1.0)
	_check("停在离地面 1px 以内", absf(_player.global_position.y - GROUND_TOP) < 1.0)

	print("--- 左右移动 ---")
	await _place(Vector2(45, GROUND_TOP - 1))
	Input.action_press("right")
	await _step(20)
	Input.action_release("right")
	print("  INFO 右走 20 帧后 x = ", snappedf(_player.global_position.x, 0.1))
	_check("按右键会往右走", _player.global_position.x > 60.0)
	_check("朝向右", _player.facing == 1)
	await _step(20)
	_check("松手会停下来", absf(_player.velocity.x) < 1.0)

	await _place(Vector2(120, GROUND_TOP - 1))
	Input.action_press("left")
	await _step(20)
	Input.action_release("left")
	print("  INFO 左走 20 帧后 x = ", snappedf(_player.global_position.x, 0.1))
	_check("按左键会往左走", _player.global_position.x < 105.0)
	_check("朝向左", _player.facing == -1)

	print("--- 跳跃 ---")
	await _place(Vector2(45, GROUND_TOP - 1))
	var start_y: float = _player.global_position.y
	Input.action_press("jump")
	await _step(3)
	_check("按跳会离地", not _player.is_on_floor() and _player.velocity.y < 0.0)
	var apex_hold: float = start_y
	for i in range(60):
		await get_tree().physics_frame
		apex_hold = minf(apex_hold, _player.global_position.y)
	Input.action_release("jump")
	await _step(60)
	var hold_height: float = start_y - apex_hold
	print("  INFO 按住跳：最高上升 ", snappedf(hold_height, 0.1), " px；落回 feet.y = ", snappedf(_player.global_position.y, 0.1))
	_check("按住跳能上升 2 格（36px）以上", hold_height > 36.0)
	_check("跳完会落回地面", _player.is_on_floor())
	_check("落地高度回到原处", absf(_player.global_position.y - start_y) < 1.5)

	# 轻点一下应该明显更矮
	await _place(Vector2(45, GROUND_TOP - 1))
	start_y = _player.global_position.y
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	var apex_tap: float = start_y
	for i in range(60):
		await get_tree().physics_frame
		apex_tap = minf(apex_tap, _player.global_position.y)
	var tap_height: float = start_y - apex_tap
	print("  INFO 轻点跳：最高上升 ", snappedf(tap_height, 0.1), " px")
	_check("轻点跳明显比按住矮（可变跳跃高度）", tap_height < hold_height * 0.8)

	print("--- 单向平台 ---")
	# 站在平台正下方，往上跳，应该穿过平台然后落在它上面
	await _place(Vector2(5 * TILE + 9, GROUND_TOP - 1))
	_check("起跳前在地面上", _player.is_on_floor())
	Input.action_press("jump")
	# 注意：这里必须**一直按住**，中途松手会触发可变跳跃砍半，根本跳不到平台高度
	var passed_through := false
	for i in range(45):
		await get_tree().physics_frame
		if _player.global_position.y < PLATFORM_TOP:
			passed_through = true
	Input.action_release("jump")
	print("  INFO 跳过平台高度？", passed_through, "  最终 feet.y = ", snappedf(_player.global_position.y, 0.1))
	_check("上升时能穿过单向平台", passed_through)
	await _step(60)
	print("  INFO 落下后 feet.y = ", snappedf(_player.global_position.y, 0.1), "（平台顶面 ", PLATFORM_TOP, "）")
	_check("落下来会站在平台上", absf(_player.global_position.y - PLATFORM_TOP) < 1.5)

	print("--- 土狼时间 ---")
	# 从地面右边缘走出去，离地后立刻按跳，靠土狼时间应该还能起跳
	# 地面是 x0..8（世界 0..162），把角色放在最后一格的偏右处
	await _place(Vector2(150, GROUND_TOP - 1), 6)
	_check("站在边缘时在地面上", _player.is_on_floor())
	Input.action_press("right")
	var left_ledge := false
	for i in range(40):
		await get_tree().physics_frame
		if not _player.is_on_floor():
			left_ledge = true
			break
	Input.action_release("right")
	_check("走出边缘后会离地", left_ledge)
	print("  [dbg] 离地瞬间: on_floor=", _player.is_on_floor(),
		" _coyote=", snappedf(_player._coyote, 0.001),
		" x=", snappedf(_player.global_position.x, 0.1))
	# ⚠️ Input.action_press() 到 is_action_just_pressed() 生效**隔一帧**，
	#    所以不能只等 1 帧就断言，要在几帧内观察"有没有跳起来"。
	Input.action_press("jump")
	var jumped := false
	for i in range(4):
		await get_tree().physics_frame
		if _player.velocity.y < 0.0:
			jumped = true
	Input.action_release("jump")
	print("  [dbg] 按跳后 4 帧内起跳？", jumped, " 最后的 velocity.y=", snappedf(_player.velocity.y, 0.1))
	print("  INFO 离地后立刻按跳，4 帧内是否起跳 = ", jumped)
	_check("土狼时间：刚离地仍能起跳", jumped)

	print("--- 视差背景 ---")
	var px := _level.get_node_or_null("Parallax") as ParallaxBackground
	_check("关卡里有视差背景", px != null)
	var backdrop := _level.get_node_or_null("Backdrop") as CanvasLayer
	_check("有垫底的底色层（防止层间露缝）", backdrop != null)
	if px != null:
		var far_layer := px.get_node("FarLayer") as ParallaxLayer
		var near_layer := px.get_node("NearLayer") as ParallaxLayer
		_check("有远层和近层两层", far_layer != null and near_layer != null)
		if far_layer != null and near_layer != null:
			print("  INFO 远层 motion_scale=", far_layer.motion_scale, " 近层=", near_layer.motion_scale)
			_check("两层速度不一样（这才叫视差）", far_layer.motion_scale.x < near_layer.motion_scale.x)
			_check("远层几乎不跟着走", far_layer.motion_scale.x < 0.2)
			_check("两层都设了水平平铺（否则走出画面就空了）",
				far_layer.motion_mirroring.x > 0.0 and near_layer.motion_mirroring.x > 0.0)
			_check("底色在视差层后面（layer 更小）", backdrop.layer < px.layer)

			# ⚠️ 只断言"节点存在 / 参数对"是不够的 —— 那验的是配置文件，不是行为。
			#    真的把摄像机平移一段，量两个层**在屏幕上**滑动的距离：
			#    视差层的屏幕位移 = (1 - motion_scale) × 摄像机位移，
			#    所以远层（scale 小）在屏幕上滑得**更多**。
			var far_sprite := far_layer.get_node("Far") as Sprite2D
			var near_sprite := near_layer.get_node("Near") as Sprite2D
			await _step(4)
			var far_before: Vector2 = far_sprite.get_global_transform_with_canvas().origin
			var near_before: Vector2 = near_sprite.get_global_transform_with_canvas().origin
			# 直接把摄像机挪走，模拟玩家往右跑
			_player.camera.global_position.x += 160.0
			await _step(4)
			var far_moved: float = absf(far_sprite.get_global_transform_with_canvas().origin.x - far_before.x)
			var near_moved: float = absf(near_sprite.get_global_transform_with_canvas().origin.x - near_before.x)
			print("  INFO 摄像机右移 160px 后：远层屏幕上滑了 ", snappedf(far_moved, 0.1),
				" px，近层滑了 ", snappedf(near_moved, 0.1), " px")
			_check("两层在屏幕上的滑动距离确实不同", absf(far_moved - near_moved) > 5.0)
			_check("远层滑得更多（因为它跟着世界走得少）", far_moved > near_moved)

	_release_all()
	print("RESULT fail=", _fail)
	get_tree().quit()
