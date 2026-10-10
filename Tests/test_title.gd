extends Node2D

## 端到端自测：标题界面。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_title.tscn
##
## ⚠️ 这里**不测 choose_slot 真的切场景** —— 一切场景测试节点就没了。
##    那条路径靠"跑一次 base_level 仍然能玩"来间接保证（全量回归里有 18 个套件）。

var _fail: int = 0
var _title: Control

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _step(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame

func _tap(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)

func _slot_path(i: int) -> String:
	return "user://farm_save_%d.json" % i

func _clean() -> void:
	for i in range(1, SaveSystem.SLOT_COUNT + 1):
		if FileAccess.file_exists(_slot_path(i)):
			DirAccess.remove_absolute(_slot_path(i))

func _ready() -> void:
	_clean()
	await _step(2)

	_title = (load("res://Scenes/Title/title.tscn") as PackedScene).instantiate()
	add_child(_title)
	await _step(3)

	print("--- 基本结构 ---")
	_check("标题界面加载了", _title != null)
	_check("有三个存档槽", SaveSystem.SLOT_COUNT == 3)
	var hint := _title.get_node("Hint") as Label
	print("  INFO 提示行：", hint.text)
	_check("提示行告诉玩家鼠标能点", "鼠标" in hint.text)

	print("--- 没有存档时三个槽都是「新游戏」 ---")
	for i in range(1, 4):
		print("  INFO 槽", i, "：", _title.slot_text(i))
		_check("槽 %d 显示开始新游戏" % i, "新游戏" in _title.slot_text(i))

	print("--- 鼠标交互（这一版新加的）---")
	var btns: Array[Button] = [_title.get_node("Slots/Slot1"), _title.get_node("Slots/Slot2"), _title.get_node("Slots/Slot3")]
	var settings_btn := _title.get_node("Bottom/SettingsButton") as Button
	var quit_btn := _title.get_node("Bottom/QuitButton") as Button
	for i in range(btns.size()):
		var b: Button = btns[i]
		_check("槽 %d 是真正的 Button（不是 Label）" % (i + 1), b != null)
		_check("槽 %d 鼠标点得中（mouse_filter 不是 IGNORE）" % (i + 1),
			b.mouse_filter != Control.MOUSE_FILTER_IGNORE)
		_check("槽 %d 的按下事件有人接" % (i + 1), b.pressed.get_connections().size() > 0)
		_check("槽 %d 有悬停变色反馈" % (i + 1),
			b.get_theme_color("font_hover_color") != b.get_theme_color("font_color"))
	print("  INFO 设置按钮：", settings_btn.text, "；退出按钮：", quit_btn.text)
	_check("设置也是可点的 Button", settings_btn != null and settings_btn.mouse_filter != Control.MOUSE_FILTER_IGNORE)
	_check("退出也是可点的 Button", quit_btn != null and quit_btn.mouse_filter != Control.MOUSE_FILTER_IGNORE)
	_check("设置按钮接了处理函数", settings_btn.pressed.get_connections().size() > 0)

	# 真按一下（不触发切场景的那条路，免得测试节点被销毁）
	var before_open: bool = _title.settings_open
	settings_btn.emit_signal("pressed")
	await _step(3)
	print("  INFO 点设置按钮之后 settings_open = ", _title.settings_open)
	_check("点设置按钮真的打开了设置", _title.settings_open != before_open)
	settings_btn.emit_signal("pressed")
	await _step(3)
	_check("再点一下收起", _title.settings_open == before_open)

	print("--- 标题是动的 ---")
	# 不去数 Tween 对象（Tween 不是 Node，不在 children 里），
	# 直接验**行为**：盯着它的 y 看一段时间，有没有在变。
	var title_label := _title.get_node("GameTitle") as Label
	var y_min: float = title_label.position.y
	var y_max: float = title_label.position.y
	for i in range(90):
		await get_tree().process_frame
		y_min = minf(y_min, title_label.position.y)
		y_max = maxf(y_max, title_label.position.y)
	print("  INFO 标题 y 在 ", snappedf(y_min, 0.1), " ~ ", snappedf(y_max, 0.1), " 之间浮动")
	_check("标题会上下浮动（界面是活的）", y_max - y_min > 1.0)

	print("--- 背景不再是纯黑 ---")
	var backdrop := _title.get_node_or_null("Backdrop") as TextureRect
	_check("标题界面有背景图", backdrop != null and backdrop.texture != null)
	var shade := _title.get_node_or_null("Shade") as ColorRect
	_check("压了一层暗色让白字读得清", shade != null and shade.color.a > 0.0)

	print("--- 有存档时显示「继续」+ 摘要 ---")
	# 手写一份最小存档，模拟玩家玩过
	var data := {
		"version": SaveSystem.SAVE_VERSION,
		"day_cycle": {"day": 6},
		"player": {"money": 321},
	}
	var f := FileAccess.open(_slot_path(2), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	_title._refresh_slots()
	await _step(2)
	print("  INFO 槽1：", _title.slot_text(1))
	print("  INFO 槽2：", _title.slot_text(2))
	print("  INFO 槽3：", _title.slot_text(3))
	_check("空槽还是「新游戏」", "新游戏" in _title.slot_text(1))
	_check("★ 有存档的槽变成「继续」", "继续" in _title.slot_text(2))
	_check("摘要里有天数", "6" in _title.slot_text(2))
	_check("摘要里有金币", "321" in _title.slot_text(2))
	_check("另一个空槽不受影响", "新游戏" in _title.slot_text(3))

	print("--- 版本不符要标出来 ---")
	var bad := {"version": 0, "day_cycle": {"day": 2}, "player": {"money": 5}}
	var f2 := FileAccess.open(_slot_path(3), FileAccess.WRITE)
	f2.store_string(JSON.stringify(bad))
	f2.close()
	_title._refresh_slots()
	await _step(2)
	print("  INFO 槽3：", _title.slot_text(3))
	_check("旧版本存档仍然算「继续」", "继续" in _title.slot_text(3))
	_check("并且标出「版本不符」", "版本不符" in _title.slot_text(3))
	print("--- 设置面板 ---")
	_check("默认关着", not _title.settings_open)
	_tap("seed_4")
	await _step(3)
	_check("按 4 打开了设置", _title.settings_open)
	print("  INFO 设置内容：", _title.settings_text())
	_check("设置里有音效开关", "音效" in _title.settings_text())
	var before: bool = _title.sfx_on
	_tap("seed_1")
	await _step(3)
	print("  INFO 音效 ", before, " → ", _title.sfx_on, "，提示：", _title.settings_text())
	_check("按 1 能切换音效", _title.sfx_on != before)
	_check("设置文字跟着变", ("开" if _title.sfx_on else "关") in _title.settings_text())
	# 切回去，别把后续测试搞成静音
	_tap("seed_1")
	await _step(2)
	_tap("pause")
	await _step(3)
	_check("按 ESC 收起设置", not _title.settings_open)

	print("--- 直接跑 base_level 仍然能玩（标题界面只是额外入口）---")
	var farm := (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(farm)
	var save := farm.get_node("SaveSystem") as SaveSystem
	save.auto_load = false
	save.auto_save_on_dawn = false
	await _step(3)
	_check("农场能独立加载", farm.get_node_or_null("level/Player") != null)
	_check("农场里有暂停菜单", farm.get_node_or_null("PauseMenu") != null)
	_check("农场里有商店", farm.get_node_or_null("level/Static/Market") != null)
	farm.queue_free()
	await _step(2)

	_clean()
	print("RESULT fail=", _fail)
	get_tree().quit()
