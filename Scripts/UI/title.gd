extends Control

## 标题界面：选存档槽 → 进农场。
##
## ⚠️ 一条硬性约束：**这一版没有改变"直接跑 base_level 能玩"这件事**。
##    标题界面只是**额外的入口**，谁想直接开农场调试、跑测试，都照旧。
##    所以 18 个测试套件不用跟着改，开发流程也没被打断。
##
## 三个槽就是三个按钮：**有存档就继续，没存档就开新档** ——
## 不用先选"新游戏/继续"再选槽，两步并成一步。

const FARM_SCENE: String = "res://Scenes/base_level.tscn"

## 音效开关（用 Master 总线静音实现，不依赖 Sfx 内部怎么写的）
var sfx_on: bool = true
## 设置面板开着没有
var settings_open: bool = false

@onready var slots_root: Node = $Slots
@onready var settings_panel: Control = $Settings
@onready var hint: Label = $Hint

func _ready() -> void:
	sfx_on = not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master"))
	_refresh_slots()
	settings_panel.visible = false

## 把三个槽的摘要刷到界面上。
## ⚠️ 这里**必须用自己的路径查询**，不能去找场景里的 SaveSystem ——
##    标题界面里根本没有那个节点（它长在农场里），找的结果永远是 null，
##    于是三个槽会一律显示"开始新游戏"，明明有存档也看不出来。
func _refresh_slots() -> void:
	for i in range(1, SaveSystem.SLOT_COUNT + 1):
		var label := slots_root.get_node_or_null("Slot%d" % i) as Label
		if label == null:
			continue
		var text: String = "[%d] " % i
		if slot_exists_direct(i):
			var s: Dictionary = slot_summary_direct(i)
			text += "继续 —— 第 %d 天 / %d 金" % [int(s.get("day", 1)), int(s.get("money", 0))]
			if not bool(s.get("ok", true)):
				text += "（版本不符）"
		else:
			text += "开始新游戏"
		label.text = text

## 当前槽的界面文本（测试直接读）
func slot_text(i: int) -> String:
	var label := slots_root.get_node_or_null("Slot%d" % i) as Label
	return label.text if label != null else ""

func settings_text() -> String:
	var l := settings_panel.get_node_or_null("SfxLabel") as Label
	return l.text if l != null else ""

func slot_exists_direct(slot: int) -> bool:
	return FileAccess.file_exists("user://farm_save_%d.json" % slot)

func slot_summary_direct(slot: int) -> Dictionary:
	var p: String = "user://farm_save_%d.json" % slot
	if not FileAccess.file_exists(p):
		return {"exists": false, "day": 0, "money": 0, "ok": false}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {"exists": true, "day": 0, "money": 0, "ok": false}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"exists": true, "day": 0, "money": 0, "ok": false}
	var data: Dictionary = parsed
	var dc: Dictionary = data.get("day_cycle", {})
	var pl: Dictionary = data.get("player", {})
	return {
		"exists": true,
		"day": int(dc.get("day", 1)),
		"money": int(pl.get("money", 0)),
		"ok": int(data.get("version", 0)) == SaveSystem.SAVE_VERSION,
	}

## 选第 slot 个槽进游戏。返回这次是"继续"还是"新游戏"。
func choose_slot(slot: int) -> String:
	if slot < 1 or slot > SaveSystem.SLOT_COUNT:
		return ""
	var existed: bool = slot_exists_direct(slot)
	if not existed:
		# 新档：把这个槽里可能残留的旧文件清掉，避免读到一半的旧数据
		DirAccess.remove_absolute("user://farm_save_%d.json" % slot)
	_write_slot_choice(slot)
	print("[标题] ", "继续" if existed else "开新档", "：第 ", slot, " 号槽")
	get_tree().change_scene_to_file(FARM_SCENE)
	return "continue" if existed else "new"

## 把选中的槽写进配置 —— 农场的 SaveSystem 在 _ready 里会读它
func _write_slot_choice(slot: int) -> void:
	var f := FileAccess.open(SaveSystem.SLOT_CONFIG, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(str(slot))
	f.close()

func toggle_settings() -> void:
	settings_open = not settings_open
	settings_panel.visible = settings_open
	_refresh_settings()

func toggle_sfx() -> void:
	sfx_on = not sfx_on
	var idx: int = AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_mute(idx, not sfx_on)
	_refresh_settings()
	print("[标题] 音效 ", "开" if sfx_on else "关")

func _refresh_settings() -> void:
	var l := settings_panel.get_node_or_null("SfxLabel") as Label
	if l != null:
		l.text = "[1] 音效：%s" % ("开" if sfx_on else "关")

func quit_game() -> void:
	print("[标题] 退出游戏")
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("seed_4"):
		toggle_settings()
		get_viewport().set_input_as_handled()
		return
	if settings_open:
		if event.is_action_pressed("seed_1"):
			toggle_sfx()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("pause"):
			toggle_settings()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("seed_1"):
		choose_slot(1)
	elif event.is_action_pressed("seed_2"):
		choose_slot(2)
	elif event.is_action_pressed("seed_3"):
		choose_slot(3)
	elif event.is_action_pressed("quick_save"):
		# F5 当"退出游戏"：标题界面里没有存/读的含义，别浪费这个键
		quit_game()
	else:
		return
	get_viewport().set_input_as_handled()
