extends Node

## 截图巡检工具：把游戏摆到几个关键位置，各截一张 PNG 存下来。
##
## ⚠️ **必须用非 headless 方式跑**：headless 后端没有渲染器，
##    `get_viewport().get_texture()` 拿到的是一张空白图。
##    所以这个工具会真的开一个窗口（屏幕上会闪一下）。
##
## 用法：
##   Godot_v4.7.2-stable_win64.exe --path . res://Tools/screenshot_tour.tscn

const OUT_DIR: String = "user://shots"

## 一张一张来，每张之间留够帧数让画面稳定（粒子、相机平滑都要时间）
const SETTLE: int = 20

var _level: Node2D
var _shot: int = 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("[截图] 输出目录 = ", ProjectSettings.globalize_path(OUT_DIR))
	await _step(SETTLE)
	await _shot_title()
	await _shot_farm()
	await _shot_mine(1)
	await _shot_mine(3)
	print("[截图] 完成，共 ", _shot, " 张")
	get_tree().quit()

func _step(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame

func _grab(name_: String) -> void:
	# 必须等一帧真正画完，否则截到的是上一帧
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("[截图] ", name_, " 拿不到画面")
		return
	_shot += 1
	var path: String = "%s/%02d_%s.png" % [OUT_DIR, _shot, name_]
	var err := img.save_png(path)
	print("[截图] ", name_, " -> ", path, "（", err == OK, "）")

func _shot_title() -> void:
	var t := (load("res://Scenes/Title/title.tscn") as PackedScene).instantiate()
	add_child(t)
	await _step(SETTLE)
	await _grab("title")
	t.queue_free()
	await _step(4)

func _shot_farm() -> void:
	_level = (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	var save := _level.get_node("SaveSystem") as SaveSystem
	save.auto_load = false
	save.auto_save_on_dawn = false
	await _step(6)
	var player := _level.get_node("level/Player") as Player
	# 站到加工坊和农田之间，一屏里能看到：加工坊、农田、矿洞口、商店、HUD
	player.global_position = Vector2(240, 150)
	await _step(SETTLE)
	await _grab("farm")

	# 打开统计面板再拍一张，顺便看 HUD 浮层
	var hud := _level.get_node_or_null("HUD")
	if hud != null:
		hud.stats_open = true
		await _step(SETTLE)
		await _grab("farm_stats")
		hud.stats_open = false
		await _step(4)

	# 配方台：给足料，让六行都亮着 —— 顺便检查有没有哪行文字长到被切掉
	var panel := _level.get_node_or_null("CraftPanel")
	if panel != null:
		player.money = 9999
		player.ore = 99
		player.harvested = [9, 9, 9]
		panel.set_open(true)
		await _step(SETTLE)
		await _grab("craft_panel")
		panel.set_open(false)
		await _step(4)
	_level.queue_free()
	await _step(6)

func _shot_mine(depth: int) -> void:
	MineRun.scene_switch_enabled = false
	MineRun.active = false
	MineRun.depth = depth
	MineRun.boss_down = depth >= 3
	MineRun.start_run()
	MineRun.depth = depth
	var m := (load("res://Scenes/Mine/mine_level.tscn") as PackedScene).instantiate()
	add_child(m)
	await _step(6)
	m.build()
	await _step(SETTLE)
	await _grab("mine_d%d_start" % depth)

	# 挪到关底那段，看 Boss、落石、尖刺球、下潜井口
	var player := m.get_node("MinePlayer") as MinePlayer
	player.global_position = Vector2(780, 170)
	await _step(SETTLE)
	await _grab("mine_d%d_boss" % depth)
	m.queue_free()
	MineRun.active = false
	MineRun.depth = 1
	await _step(6)
