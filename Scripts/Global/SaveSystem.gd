class_name SaveSystem extends Node

## 存档系统：把「天数 / 玩家状态 / 地块与作物 / 目标进度」写成一个 JSON。
##
## 自动读档刻意延后到第一帧的 _process，而不是在 _ready 里做 —— 这样测试脚本
## 可以在 add_child 之后、第一帧之前把 save_path 换成临时文件，既能测到真实读档路径，
## 又不会污染玩家真正的存档。

const SAVE_VERSION: int = 2
const DEFAULT_PATH: String = "user://farm_save.json"

@export var save_path: String = DEFAULT_PATH
@export var auto_load: bool = true
@export var auto_save_on_dawn: bool = true

@onready var player: Player = $"../level/Player"
@onready var land: FarmLand = $"../Land"
@onready var cycle: DayCycle = $"../DayCycle"
@onready var controller: FarmController = $"../FarmController"

var _booted: bool = false

func _ready() -> void:
	add_to_group("save_system")

func _process(_delta: float) -> void:
	if _booted:
		return
	_booted = true
	if auto_save_on_dawn and cycle != null:
		cycle.day_started.connect(_on_day_started)
	if auto_load and has_save():
		load_game()

func _on_day_started(_day: int) -> void:
	save_game()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_save"):
		save_game()
	elif event.is_action_pressed("quick_load"):
		load_game()
	elif event.is_action_pressed("delete_save"):
		delete_save()

func has_save() -> bool:
	return FileAccess.file_exists(save_path)

func save_game() -> bool:
	if player == null or land == null or cycle == null or controller == null:
		push_error("SaveSystem: 依赖节点没找齐，无法存档")
		return false
	var data := {
		"version": SAVE_VERSION,
		"day_cycle": cycle.to_save_data(),
		"player": player.to_save_data(),
		"land": land.to_save_data(),
		"progress": controller.to_save_data(),
	}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_error("存档写入失败：" + error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	print("[存档] 已保存（第 ", cycle.day, " 天）")
	return true

func load_game() -> bool:
	if not has_save():
		print("[存档] 没有存档文件")
		return false
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		push_error("存档读取失败：" + error_string(FileAccess.get_open_error()))
		return false
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("存档内容损坏，已忽略")
		return false
	var data: Dictionary = parsed
	var ver: int = int(data.get("version", 0))
	if ver != SAVE_VERSION:
		print("[存档] 版本不匹配（存档 ", ver, "，当前 ", SAVE_VERSION, "），已忽略")
		return false
	cycle.apply_save_data(data.get("day_cycle", {}))
	land.apply_save_data(data.get("land", {}))
	player.apply_save_data(data.get("player", {}))
	controller.apply_save_data(data.get("progress", {}))
	print("[存档] 已读取（第 ", cycle.day, " 天，", player.money, " 金）")
	return true

func delete_save() -> bool:
	if not has_save():
		print("[存档] 本来就没有存档")
		return false
	var err := DirAccess.remove_absolute(save_path)
	if err != OK:
		push_error("删除存档失败：" + error_string(err))
		return false
	print("[存档] 已删除存档（下次启动就是新游戏）")
	return true
