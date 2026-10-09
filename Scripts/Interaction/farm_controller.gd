class_name FarmController extends Node

## 唯一动作键 F 的分发中心：按「手持道具 + 所在位置」决定要干什么。
## Q 切换手持道具。

const ATTACK_RANGE: float = 26.0
const ATTACK_DAMAGE: int = 1

## 目标：攒够这么多金币就算「建成谷仓」
const GOLD_GOAL: int = 300

@onready var player: Player = $"../level/Player"
@onready var land: FarmLand = $"../Land"
@onready var market: Market = $"../level/Static/Market"

var goal_reached: bool = false

func _process(_delta: float) -> void:
	if goal_reached:
		return
	if player.money >= GOLD_GOAL:
		goal_reached = true
		Sfx.play("goal")
		print("[目标] 攒够 ", GOLD_GOAL, " 金，谷仓建成了！")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_item"):
		player.cycle_item()
		print("[手上] 换成 ", player.item_name())
		return
	if event.is_action_pressed("use_item"):
		use_held_item()
		return
	# 1-5 选择作物种类（播种和买种子都用它）
	for i in range(CropData.count()):
		if event.is_action_pressed("seed_%d" % (i + 1)):
			if player.select_seed_type(i):
				print("[种子] 选中 ", player.crop_name(), "（有 ", player.seed_count(i), " 粒，种子价 ",
					CropData.seed_price(i), "，收购价 ", CropData.sell_price(i), "）")
			else:
				print("[种子] 已经是 ", player.crop_name(), " 了")
			return

func use_held_item() -> bool:
	# 站在商店里，交易优先
	if market.is_player_inside():
		match player.active_item:
			Player.Item.SEED:
				return market.buy_seed(player)
			Player.Item.BASKET:
				return market.sell_crops(player)
			_:
				print("[商店] 拿着 ", player.item_name(), " 没法交易")
				return false

	if player.active_item == Player.Item.SWORD:
		return attack()

	var tile: Vector2i = land.get_player_tile()
	match player.active_item:
		Player.Item.SEED:
			return land.try_plant_at(tile)
		Player.Item.WATER_CAN:
			return land.try_water_at(tile)
		Player.Item.BASKET:
			return land.try_harvest_at(tile)
	return false

## 砍一圈：范围内所有野猪各掉 ATTACK_DAMAGE 点血
func attack() -> bool:
	if not player.can_attack():
		print("[战斗] 挥太快了，喘口气")
		return false
	player.begin_attack_cooldown()
	var hit: int = 0
	for node in get_tree().get_nodes_in_group("pest"):
		var boar := node as Boar
		if boar == null or not is_instance_valid(boar):
			continue
		if player.global_position.distance_to(boar.global_position) <= ATTACK_RANGE:
			boar.take_damage(ATTACK_DAMAGE)
			hit += 1
	if hit == 0:
		print("[战斗] 挥空了，附近没有野猪")
		return false
	print("[战斗] 砍中 ", hit, " 只野猪")
	Sfx.play("hit")
	return true

func to_save_data() -> Dictionary:
	return {"goal_reached": goal_reached}

func apply_save_data(d: Dictionary) -> void:
	goal_reached = bool(d.get("goal_reached", false))
