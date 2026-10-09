class_name FarmController extends Node

## 唯一动作键 F 的分发中心：按「手持道具 + 所在位置」决定要干什么。
## Q 切换手持道具。

@onready var player: Player = $"../level/Player"
@onready var land: FarmLand = $"../Land"
@onready var market: Market = $"../level/Static/Market"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_item"):
		player.cycle_item()
		print("[手上] 换成 ", player.item_name())
	elif event.is_action_pressed("use_item"):
		use_held_item()

func use_held_item() -> bool:
	# 站在商店里，交易优先
	if market.is_player_inside():
		match player.active_item:
			Player.Item.SEED:
				return market.buy_seed(player)
			Player.Item.BASKET:
				return market.sell_crops(player)
			_:
				print("[商店] 拿着水壶没法交易")
				return false

	var tile: Vector2i = land.get_player_tile()
	match player.active_item:
		Player.Item.SEED:
			return land.try_plant_at(tile)
		Player.Item.WATER_CAN:
			return land.try_water_at(tile)
		Player.Item.BASKET:
			return land.try_harvest_at(tile)
	return false
