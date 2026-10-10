extends Node

## 「胶片」工具：让机器人**真的去玩矿洞**，然后在关键时刻连拍。
##
## 为什么需要它：原来的 screenshot_tour 是"把人瞬移到某个坐标再拍一张"，
## 拿到的是**孤立的状态照片**。所以我能看出"平台贴图错了"，
## 但看不出"跳起来的弧线对不对""挨打那一瞬间什么样""Boss 换招有没有节奏"。
##
## 这个工具拍的是**过程**：机器人一路走过去、打、挨打、跳、见 Boss，
## 我在这些节拍上各拍一张，连起来就是一条胶片。
##
## ⚠️ 必须**非 headless** 跑（headless 没有渲染器，拍出来是空白）。
##
## 用法：
##   Godot_v4.7.2-stable_win64.exe --path . res://Tools/film.tscn

const OUT_DIR: String = "user://film"
## 每个节拍之间等几帧，让画面（粒子、震屏、受击闪烁）稳定下来
const BEAT: int = 10

var _level: Node2D
var _player: MinePlayer
var _shot: int = 0
var _log: PackedStringArray = PackedStringArray()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("[胶片] 输出目录 = ", ProjectSettings.globalize_path(OUT_DIR))
	MineRun.scene_switch_enabled = false
	MineRun.active = false
	MineRun.entry_slot = 1
	MineRun.depth = 1
	MineRun.boss_down = false
	MineRun.start_run()
	MineRun.depth = 1

	_level = (load("res://Scenes/Mine/mine_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	await _step(6)
	_level.build()
	await _step(BEAT)
	_player = _level.get_node("MinePlayer") as MinePlayer

	await _beat("01_spawn", "刚落地")
	await _walk_right(90)
	await _beat("02_walk", "往右走")

	# 找一个怪，走近了砍它 —— 拍"打中火星"那一瞬间
	var foe := _first_enemy_near(240.0)
	if foe != null:
		await _approach(foe, 46.0)
		_player.attack()
		await _step(2)
		await _beat("03_hit", "砍中怪（火星）")
		await _step(4)
		await _beat("04_hit_after", "砍完一下之后")

	# 让怪打我们一下 —— 拍受击边框闪红
	if foe != null and is_instance_valid(foe):
		_player._invuln = 0.0
		_player.hp = _player.max_hp()
		# 把怪挪到身上，它的 _physics_process 里 _touch_player 会自己打过来
		foe.global_position = _player.global_position + Vector2(10, 0)
		for i in range(60):
			await get_tree().physics_frame
			if _player.hp < _player.max_hp():
				break
		await _beat("05_hurt", "挨打（屏幕边缘闪红）")

	# 跳一次，拍空中的姿态
	_player.hp = _player.max_hp()
	await _step(6)
	_tap("jump")
	for i in range(6):
		await get_tree().physics_frame
	await _beat("06_jump", "起跳中")

	# 站到平台上，拍"落在平台上"
	var plat := _find_platform_top()
	if plat != Vector2.INF:
		_player.global_position = plat + Vector2(0, -20)
		_player.velocity = Vector2.ZERO
		await _step(BEAT)
		await _beat("07_on_platform", "站在平台上")

	# 地刺：拍"踩上去持续掉血"
	var spike := _level.get_node_or_null("SpikeA") as Node2D
	if spike != null:
		_player.hp = _player.max_hp()
		_player._invuln = 0.0
		_player.global_position = spike.global_position
		for i in range(30):
			await get_tree().physics_frame
		await _beat("08_spikes", "踩地刺")

	# 落石：站到它下面，拍"预警抖动"
	var rock := _level.get_node_or_null("RockA") as Node2D
	if rock != null:
		_player.hp = _player.max_hp()
		_player.global_position = Vector2(rock.global_position.x, 198)
		await _step(6)
		await _beat("09_rock_armed", "落石下方（预警）")
		for i in range(30):
			await get_tree().physics_frame
			if rock.visible:
				break
		await _beat("10_rock_fall", "落石砸下来")

	# Boss：拍满血、以及打到一半换招
	var boss := _level.get_node_or_null("Boss") as MineEnemy
	if boss != null:
		_player.hp = _player.max_hp()
		_player.global_position = boss.global_position + Vector2(-70, -6)
		await _step(BEAT)
		await _beat("11_boss_full", "Boss 满血")
		boss.hp = int(boss.max_hp / 2) - 1
		await _step(BEAT)
		await _beat("12_boss_phase2", "Boss 半血换招")

	print("[胶片] 完成，共 ", _shot, " 张")
	for ln in _log:
		print("        ", ln)
	get_tree().quit()

# --- 工具函数 ---

func _step(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame

func _beat(tag: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	_shot += 1
	var path: String = "%s/%02d_%s.png" % [OUT_DIR, _shot, tag]
	img.save_png(path)
	var hp: int = _player.hp if _player != null else 0
	_log.append("%02d %s —— %s（血 %d/%d）" % [_shot, tag, note, hp,
		_player.max_hp() if _player != null else 0])
	await _step(BEAT)

func _hold(action: String) -> void:
	if not Input.is_action_pressed(action):
		Input.action_press(action)

func _release(action: String) -> void:
	if Input.is_action_pressed(action):
		Input.action_release(action)

func _tap(action: String) -> void:
	_hold(action)

func _walk_right(frames: int) -> void:
	_hold("right")
	for i in range(frames):
		await get_tree().physics_frame
	# 卡住了就跳一下
	if _player.is_on_wall():
		_tap("jump")
		await _step(10)
	_release("right")
	await _step(4)

func _approach(target: Node2D, dist: float) -> void:
	for i in range(180):
		if not is_instance_valid(target):
			return
		var dx: float = target.global_position.x - _player.global_position.x
		if absf(dx) <= dist:
			break
		if dx > 0.0:
			_hold("right")
		else:
			_hold("left")
		await get_tree().physics_frame
	_release("left")
	_release("right")
	await _step(3)

func _first_enemy_near(max_dist: float) -> MineEnemy:
	var best: MineEnemy = null
	var best_d: float = max_dist
	for n in get_tree().get_nodes_in_group("mine_enemy"):
		var e := n as MineEnemy
		if e == null or not is_instance_valid(e) or e.hp <= 0:
			continue
		var d: float = absf(e.global_position.x - _player.global_position.x)
		if d < best_d:
			best_d = d
			best = e
	return best

## 找一格"上方是空的"的平台，好站上去
func _find_platform_top() -> Vector2:
	var terrain := _level.get_node_or_null("Terrain") as TileMapLayer
	if terrain == null:
		return Vector2.INF
	var used := terrain.get_used_cells()
	for c in used:
		# 平台格的上方一格是空的，就站这儿
		if terrain.get_cell_source_id(c) < 0:
			continue
		if terrain.get_cell_source_id(c + Vector2i(0, -1)) < 0 \
				and terrain.get_cell_source_id(c + Vector2i(0, 1)) < 0:
			return terrain.to_global(terrain.map_to_local(c))
	return Vector2.INF
