extends Node

## 矿洞「这一趟」的状态（自动加载单例，全局名字 MineRun）。
##
## **进出矿洞是靠切换场景实现的**，而农场的状态（地块、每株作物、金币…）全都活在
## base_level 场景里，一切场景就没了。解决办法是**复用已有的存档系统**：
## 进洞前先用 SaveSystem 存一次，回来时它的「启动自动读档」会把农场原样恢复。
##
## 这样不用把农场塞进 autoload，也不会丢状态 —— 而且"死在洞里丢掉这趟收获"
## 天然成立：存档是在**进洞之前**拍的。

signal run_started
signal run_finished(success: bool, gold: int, kills: int)

const FARM_SCENE: String = "res://Scenes/base_level.tscn"
const MINE_SCENE: String = "res://Scenes/Mine/mine_level.tscn"
## 一趟的火把时间（秒）。烧完自动被送回农场，**收获保留**。
const TORCH_TIME: float = 75.0

var active: bool = false
## 这一趟捡到的金币
var gold: int = 0
## 这一趟挖到的矿石块数（价值已经算进 gold 里了，这个只是给结算显示用）
var ore: int = 0
## 这一趟赶跑的怪
var kills: int = 0
var torch_left: float = 0.0
## 测试用的开关：headless 测试里不能真的切场景（一切后面就没法继续跑断言了）。
## 关掉之后 finish() 只改状态、不切场景。
var scene_switch_enabled: bool = true

var _pending: Dictionary = {}

func start_run() -> void:
	active = true
	gold = 0
	ore = 0
	kills = 0
	torch_left = TORCH_TIME
	run_started.emit()
	print("[矿洞] 进洞，火把 ", int(TORCH_TIME), " 秒")

func add_gold(n: int) -> void:
	if n <= 0:
		return
	gold += n
	print("[矿洞] 捡到 ", n, " 金（这趟共 ", gold, "）")

## 矿石：价值直接算进 gold，另外记一个块数给结算显示
func add_ore(n: int) -> void:
	if n <= 0:
		return
	ore += 1
	gold += n
	print("[矿洞] 挖到矿石 x1（值 ", n, " 金，这趟共 ", gold, " 金 / ", ore, " 块）")

func add_kill() -> void:
	kills += 1

## success = true 保留这趟收获；false = 丢掉（在洞里倒下了）
func finish(success: bool) -> void:
	if not active:
		return
	active = false
	_pending = {"success": success, "gold": gold, "kills": kills, "ore": ore}
	print("[矿洞] 出洞 - ", "带回" if success else "丢掉",
		"这趟收获：", gold, " 金 / ", ore, " 块矿石，赶跑 ", kills, " 只")
	run_finished.emit(success, gold, kills)
	if scene_switch_enabled:
		get_tree().change_scene_to_file(FARM_SCENE)

## 回到农场后由矿洞口读取一次，然后清空（保证只结算一次）
func consume_result() -> Dictionary:
	var r := _pending
	_pending = {}
	return r

func has_result() -> bool:
	return not _pending.is_empty()
