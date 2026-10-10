extends Control

## 标题界面：选存档槽 → 进农场。
##
## ⚠️ 一条硬性约束：**这一版没有改变"直接跑 base_level 能玩"这件事**。
##    标题界面只是**额外的入口**，谁想直接开农场调试、跑测试，都照旧。
##
## 交互上**鼠标和键盘并存**：三个槽是真 Button（能点、有悬停变色），
## 1/2/3 也照旧能用 —— 键鼠两条路都通，玩家爱用哪个用哪个。

const FARM_SCENE: String = "res://Scenes/base_level.tscn"

## 音效开关（用 Master 总线静音实现，不依赖 Sfx 内部怎么写的）
var sfx_on: bool = true
## 设置面板开着没有
var settings_open: bool = false
## 三个槽的点击次数（测试用：鼠标点一下会 +1）
var slot_click_count: Array[int] = [0, 0, 0]

@onready var slots_root: Node = $Slots
@onready var slot_buttons: Array[Button] = [$Slots/Slot1, $Slots/Slot2, $Slots/Slot3]
@onready var settings_button: Button = $Bottom/SettingsButton
@onready var quit_button: Button = $Bottom/QuitButton
@onready var settings_panel: Control = $Settings
@onready var sfx_button: Button = $Settings/SfxButton
@onready var back_button: Button = $Settings/BackButton
@onready var game_title: Label = $GameTitle
@onready var hint: Label = $Hint

func _ready() -> void:
	sfx_on = not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master"))
	# 鼠标这条路：真按钮，按下就触发。键盘那条走 _unhandled_input。
	for i in range(slot_buttons.size()):
		slot_buttons[i].pressed.connect(_on_slot_pressed.bind(i + 1))
	settings_button.pressed.connect(toggle_settings)
	quit_button.pressed.connect(quit_game)
	sfx_button.pressed.connect(toggle_sfx)
	back_button.pressed.connect(toggle_settings)
	_refresh_slots()
	_refresh_settings()
	settings_panel.visible = false
	_start_title_bob()

## 标题轻轻上下浮动。
## **静止的一屏字和会动的界面，给人的感觉完全是两回事** ——
## 这是我这一版最想补的东西：之前的标题界面就是一块黑底加几行不动的字。
func _start_title_bob() -> void:
	var base_y: float = game_title.position.y
	var tw := create_tween().set_loops()
	tw.tween_property(game_title, "position:y", base_y + 4.0, 1.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(game_title, "position:y", base_y, 1.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_slot_pressed(slot: int) -> void:
	if slot >= 1 and slot <= slot_click_count.size():
		slot_click_count[slot - 1] += 1
	choose_slot(slot)

## 把三个槽的摘要刷到界面上。
## ⚠️ 必须用自己的路径查询，不能去找场景里的 SaveSystem ——
##    标题界面里根本没有那个节点（它长在农场里），找的结果永远是 null。
func _refresh_slots() -> void:
	for i in range(1, SaveSystem.SLOT_COUNT + 1):
		var btn := slots_root.get_node_or_null("Slot%d" % i) as Button
		if btn == null:
			continue
		var text: String = "%d 号存档 —— " % i
		if slot_exists_direct(i):
			var s: Dictionary = slot_summary_direct(i)
			text += "继续（第 %d 天 / %d 金）" % [int(s.get("day", 1)), int(s.get("money", 0))]
			if not bool(s.get("ok", true)):
				text += " ⚠版本不符"
		else:
			text += "开始新游戏"
		btn.text = text

## 当前槽的界面文本（测试直接读）
func slot_text(i: int) -> String:
	if i < 1 or i > slot_buttons.size():
		return ""
	return slot_buttons[i - 1].text

func settings_text() -> String:
	return sfx_button.text if sfx_button != null else ""

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
	if sfx_button != null:
		sfx_button.text = "[1] 音效：%s" % ("开" if sfx_on else "关")

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
		quit_game()
	else:
		return
	get_viewport().set_input_as_handled()
