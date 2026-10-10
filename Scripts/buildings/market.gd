class_name Market extends Node2D

## 商店（挂在 house.tscn 上）：站进 InteractionArea 后，用手持道具按 F 交易。
##   手持种子袋 -> 买 1 粒**当前选中种类**的种子（价格见 CropData）
##   手持收获篮 -> 卖掉篮子里**所有种类**的作物
##
## 站在商店里按 1-5 可以切换要买卖的作物种类（分发在 FarmController 里）。

@onready var area: Area2D = $InteractionArea

var _player_inside: int = 0
var _cycle: DayCycle

func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func is_player_inside() -> bool:
	return _player_inside > 0

## 作物按天数解锁，商店只卖已经解锁的
func current_day() -> int:
	if _cycle == null:
		_cycle = get_tree().get_first_node_in_group("day_cycle") as DayCycle
	return _cycle.day if _cycle != null else 1

## 当前种子实际要花多少钱（商人专精打折）
func seed_price_now(type_id: int) -> int:
	return int(round(float(CropData.seed_price(type_id)) * Progression.seed_price_multiplier()))

func buy_seed(player: Player) -> bool:
	var type_id: int = player.seed_type
	if not CropData.is_unlocked(type_id, current_day()):
		print("[商店] ", CropData.name_of(type_id), " 还没解锁（第 ",
			CropData.min_day_of(type_id), " 天开始有）")
		return false
	var price: int = seed_price_now(type_id)
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
	var base_total: int = 0
	var count: int = 0
	var detail: String = ""
	for type_id in range(player.harvested.size()):
		var n: int = player.harvested[type_id]
		if n <= 0:
			continue
		base_total += n * CropData.sell_price(type_id)
		count += n
		if detail != "":
			detail += "、"
		detail += "%s x%d" % [CropData.name_of(type_id), n]
		player.harvested[type_id] = 0
	# 动物产出和作物一起卖。玩家不用记"蛋该去哪卖"。
	var goods: int = player.goods_total()
	if goods > 0:
		base_total += goods * AnimalProduct.PRICE
		count += goods
		if detail != "":
			detail += "、"
		detail += "%s x%d" % [AnimalProduct.GOODS_NAME, goods]
		player.animal_goods = 0
	if count <= 0:
		print("[商店] 篮子是空的，先去收获作物或者收畜产")
		return false
	var total: int = int(round(float(base_total) * Progression.sell_multiplier()))
	player.money += total
	# 经营经验：每卖一次至少 +1，之后每 10 金再 +1
	Progression.add_xp(Progression.Skill.TRADE, maxi(1, total / 10))
	Sfx.play("coin")
	var bonus: String = "" if total == base_total else "（原价 %d，专精加成后 %d）" % [base_total, total]
	print("[商店] 卖出 ", detail, "，+", total, " 金", bonus, "，共 ", player.money)
	return true

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player_inside += 1

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_player_inside = maxi(0, _player_inside - 1)
