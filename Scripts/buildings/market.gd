class_name Market extends Node2D

## 商店（挂在 house.tscn 上）：站进 InteractionArea 后，用手持道具按 F 交易。
##   手持种子袋 -> 买 1 粒**当前选中种类**的种子（价格见 CropData）
##   手持收获篮 -> 卖掉篮子里**所有种类**的作物
##
## 站在商店里按 1-5 可以切换要买卖的作物种类（分发在 FarmController 里）。

@onready var area: Area2D = $InteractionArea

var _player_inside: int = 0

func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func is_player_inside() -> bool:
	return _player_inside > 0

func buy_seed(player: Player) -> bool:
	var type_id: int = player.seed_type
	var price: int = CropData.seed_price(type_id)
	if player.money < price:
		print("[商店] 金币不够（", CropData.name_of(type_id), " 种子要 ", price, "，只有 ", player.money, "）")
		return false
	player.money -= price
	player.add_seed(type_id, 1)
	Sfx.play("buy")
	print("[商店] 买下 1 粒 ", CropData.name_of(type_id), " 种子，-", price,
		" 金，剩 ", player.money, "，该种子共 ", player.seed_count(type_id), " 粒")
	return true

func sell_crops(player: Player) -> bool:
	var total: int = 0
	var count: int = 0
	var detail: String = ""
	for type_id in range(player.harvested.size()):
		var n: int = player.harvested[type_id]
		if n <= 0:
			continue
		total += n * CropData.sell_price(type_id)
		count += n
		if detail != "":
			detail += "、"
		detail += "%s x%d" % [CropData.name_of(type_id), n]
		player.harvested[type_id] = 0
	if count <= 0:
		print("[商店] 篮子是空的，先去收获作物")
		return false
	player.money += total
	Sfx.play("coin")
	print("[商店] 卖出 ", detail, "，+", total, " 金，共 ", player.money)
	return true

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player_inside += 1

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_player_inside = maxi(0, _player_inside - 1)
