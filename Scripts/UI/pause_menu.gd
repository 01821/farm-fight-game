extends CanvasLayer

## 暂停菜单（ESC）。农场和矿洞**共用同一个场景**，两边的节点结构一样。
##
## 关键决定：暂停用 `get_tree().paused = true`，而不是自己写一堆
## "if paused: return" —— 树一停，所有默认 process_mode 的节点**连输入都收不到**，
## 所以开着菜单时按 1-5 不会误种地、按 F 不会误砍树，天然就隔离干净了。
##
## 代价：本节点必须设成 PROCESS_MODE_ALWAYS，否则它自己也收不到输入
## （包括再按一次 ESC 想关掉它）。

signal resumed
signal saved
signal loaded
signal quit_to_title

## 回到标题界面时切到哪个场景。文件不存在就退而求其次直接退出游戏。
@export var title_scene: String = "res://Scenes/Title/title.tscn"

var is_open: bool = false

@onready var backdrop: ColorRect = $Backdrop
@onready var title_label: Label = $Title
@onready var options: Array[Label] = [$Option1, $Option2, $Option3, $Option4]
@onready var status: Label = $Status

func _ready() -> void:
	# 必须 ALWAYS —— 否则暂停之后自己也收不到输入，菜单会关不掉
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_open(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		set_open(not is_open)
		get_viewport().set_input_as_handled()
		return
	if not is_open:
		return
	# 菜单选项复用 1/2/3/4（就是 seed_1..4 那几个物理键）——
	# 农场和矿洞都有这几个动作，所以不用再多加绑定。
	if event.is_action_pressed("seed_1"):
		resume()
	elif event.is_action_pressed("seed_2"):
		save_now()
	elif event.is_action_pressed("seed_3"):
		load_now()
	elif event.is_action_pressed("seed_4"):
		back_to_title()
	else:
		return
	get_viewport().set_input_as_handled()

func set_open(open: bool) -> void:
	is_open = open
	backdrop.visible = open
	title_label.visible = open
	for o in options:
		o.visible = open
	status.visible = open
	get_tree().paused = open
	if open:
		_set_status("")

func resume() -> void:
	set_open(false)
	resumed.emit()
	print("[暂停] 继续")

func save_now() -> void:
	var save := get_tree().get_first_node_in_group("save_system") as SaveSystem
	if save == null:
		_set_status("这里存不了档")
		return
	save.save_game()
	saved.emit()
	_set_status("已存到第 %d 号槽（第 %d 天）" % [save.current_slot, _day()])

func load_now() -> void:
	var save := get_tree().get_first_node_in_group("save_system") as SaveSystem
	if save == null:
		_set_status("这里读不了档")
		return
	if not save.has_save():
		_set_status("第 %d 号槽还没有存档" % save.current_slot)
		return
	# ⚠️ 读档前必须先恢复暂停 —— 否则读完之后整个游戏是停着的，
	#    玩家会以为"读档把游戏读死了"。
	set_open(false)
	save.load_game()
	loaded.emit()
	print("[暂停] 读档完成")

func back_to_title() -> void:
	# 回标题前也要恢复暂停，不然标题界面自己是停的
	set_open(false)
	quit_to_title.emit()
	if ResourceLoader.exists(title_scene):
		get_tree().change_scene_to_file(title_scene)
	else:
		print("[暂停] 没有标题界面，直接退出")
		get_tree().quit()

## 菜单文字（测试直接读）
func option_text(i: int) -> String:
	if i < 0 or i >= options.size():
		return ""
	return options[i].text

func status_text() -> String:
	return status.text

func _set_status(t: String) -> void:
	status.text = t

func _day() -> int:
	var cycle := get_tree().get_first_node_in_group("day_cycle") as DayCycle
	return cycle.day if cycle != null else 0
