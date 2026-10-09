class_name Market extends Node2D

## 商店（挂在 house.tscn 上）：站进 InteractionArea 后，用手持道具按 F 交易。
##   手持种子袋 -> 买 1 粒种子（花钱）
##   手持收获篮 -> 卖掉篮子里全部作物（赚钱）

const SEED_PRICE: int = 3
const CROP_PRICE: int = 5

@onready var area: Area2D = $InteractionArea

var _player_inside: int = 0

func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func is_player_inside() -> bool:
	return _player_inside > 0

func buy_seed(player: Player) -> bool:
	if player.money < SEED_PRICE:
		print("[商店] 金币不够（需要 ", SEED_PRICE, "，只有 ", player.money, "）")
		return false
	player.money -= SEED_PRICE
	player.seeds += 1
	print("[商店] 买下 1 粒种子，-", SEED_PRICE, " 金，剩 ", player.money)
	return true

func sell_crops(player: Player) -> bool:
	if player.harvested <= 0:
		print("[商店] 篮子是空的，先收获作物")
		return false
	var count: int = player.harvested
	var income: int = count * CROP_PRICE
	player.harvested = 0
	player.money += income
	print("[商店] 卖出 ", count, " 个作物，+", income, " 金，共 ", player.money)
	return true

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player_inside += 1

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_player_inside = maxi(0, _player_inside - 1)
