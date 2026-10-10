class_name MineEntrance extends Node2D

## 农场这边的矿洞口：走进去按 F 就下矿。
##
## 交互方式照抄现有的水源 / 商店：预建的 InteractionArea + body_entered/exited。
## 进洞前**先存一次档**（切场景会丢掉 base_level 的一切），
## 从洞里回来时再结算这趟的收获。

@export var mine_scene: String = "res://Scenes/Mine/mine_level.tscn"

var _player_inside: bool = false
var _save: SaveSystem

@onready var area: Area2D = $InteractionArea
@onready var active_sprite: Sprite2D = $ActiveSprite

func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	_save = get_tree().get_first_node_in_group("save_system") as SaveSystem
	_deferred_settle()

## ⚠️ 结算必须等**自动读档之后**再做。
##
## 踩过的坑（藏了很久的真 bug）：SaveSystem 是在**第一帧 `_process`** 里自动读档的，
## 而 `_ready` 比它早。在 `_ready` 里给玩家发钱，紧接着 `apply_save_data()` 就按存档
## 把钱包覆盖回去了 —— **"带回金币"在真实游戏里其实一直是不生效的**。
## 之前的测试只验了 `consume_result()` 的内容，没验玩家钱包，所以一直没抓到。
func _deferred_settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_settle_previous_run()

## 从矿洞回到农场后：把这趟的收获结算给玩家。
## 存档是在**进洞之前**拍的，所以失败时什么都不用做 —— 收获自然就没了。
func _settle_previous_run() -> void:
	if not MineRun.has_result():
		return
	var r := MineRun.consume_result()
	var player := get_tree().get_first_node_in_group("player") as Player
	var success: bool = bool(r.get("success", false))
	var gold: int = int(r.get("gold", 0))
	var kills: int = int(r.get("kills", 0))
	var ore: int = int(r.get("ore", 0))
	var before: int = player.money if player != null else 0
	if success and player != null:
		if gold > 0:
			player.earn(gold)
			Sfx.play("coin")
		# 矿石也带回农场 —— 它是"矿洞 → 加工坊 → 装备 → 打更深的矿"
		# 这条循环里唯一的实物，光带钱回来是不够的。
		if ore > 0:
			player.ore += ore
			print("[矿洞] 矿石入袋：", player.ore, " 块")
		# 遗物：在洞里捡到的装备。**只有活着回来才到手**
		# （finish(false) 的时候这批是空的，所以这里不用再判一次）。
		for id_v in r.get("items", []):
			var id: String = String(id_v)
			if ItemData.exists(id):
				player.add_item(id, 1)
				print("[矿洞] 遗物到手：", ItemData.name_of(id))
		# 每日首通：今天第一次拆掉关底，额外再给一笔
		var bonus: int = MineRun.claim_daily()
		if bonus > 0:
			player.earn(bonus)
	print("[矿洞] 结算：", "带回 " if success else "丢掉 ", gold,
		" 金 / ", ore, " 块矿石（赶跑 ", kills, " 只），钱包 ", before, " → ",
		player.money if player != null else 0)

func is_player_inside() -> bool:
	return _player_inside

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player_inside = true
		if active_sprite != null:
			active_sprite.visible = true
		print("[矿洞] 按 F 下矿（火把 ", int(MineRun.TORCH_TIME), " 秒）")

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_player_inside = false
		if active_sprite != null:
			active_sprite.visible = false

## 由 FarmController 在按 F 时调用
func enter_mine() -> bool:
	if not _player_inside or MineRun.active:
		return false
	if _save == null:
		_save = get_tree().get_first_node_in_group("save_system") as SaveSystem
	if _save != null:
		_save.save_game()
		print("[矿洞] 进洞前已存档（切场景靠它恢复农场）")
	# 记下"今天是第几天" —— 回来结算时要靠它判断这趟算不算每日首通
	var cycle := get_tree().get_first_node_in_group("day_cycle") as DayCycle
	MineRun.start_run()
	MineRun.entry_day = cycle.day if cycle != null else 0
	# 记下是哪个槽 —— 地图种子由 槽号+层数 决定，这样"同一个存档每次一样、
	# 换个存档就是新地图"
	MineRun.entry_slot = _save.current_slot if _save != null else 1
	print("[矿洞] 第 ", MineRun.entry_day, " 天下矿（", MineRun.entry_slot, " 号槽，种子 ",
		MineRun.level_seed(), "）")
	get_tree().change_scene_to_file(mine_scene)
	return true
