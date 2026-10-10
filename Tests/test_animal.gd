extends Node2D

## 端到端自测：动物产出（蛋/奶）这条农场第二收入线。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_animal.tscn

var _fail: int = 0
var _level: Node2D
var _animal: Node2D          # base_animal（脚本没有 class_name）
var _player: Player
var _market: Market
var _cycle: DayCycle

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _step(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame

func _products() -> Array:
	return get_tree().get_nodes_in_group("animal_product")

func _ready() -> void:
	_level = (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	var save := _level.get_node("SaveSystem") as SaveSystem
	save.auto_load = false
	save.auto_save_on_dawn = false
	await _step(3)

	_animal = _level.get_node_or_null("level/Animals/base_animal")
	_player = _level.get_node("level/Player") as Player
	_market = _level.get_node("level/Static/Market") as Market
	_cycle = _level.get_node("DayCycle") as DayCycle

	print("--- 配置 ---")
	_check("农场里有动物", _animal != null)
	if _animal == null:
		print("RESULT fail=", _fail + 1)
		get_tree().quit()
		return
	print("  INFO 动物产出单价 ", AnimalProduct.PRICE, " 金，每只最多同时留 ",
		_animal.MAX_PENDING, " 个")
	_check("畜产有价钱", AnimalProduct.PRICE > 0)
	_check("设了产出物场景（预建，不是运行时 new 的）", _animal.product_scene != null)
	_check("一开始地上没有畜产", _products().is_empty())
	_check("一开始产出计数是 0", _animal.produced_total() == 0)

	print("--- 每天早上产一个 ---")
	# 直接触发"新的一天"，等价于天亮
	_cycle.day_started.emit(_cycle.day)
	await _step(3)
	print("  INFO 过了一天：地上 ", _products().size(), " 个，累计产出 ", _animal.produced_total())
	_check("天亮后产出了一个", _animal.produced_total() == 1)
	_check("地上出现了一个畜产", _products().size() == 1)
	_check("pending 记账对得上", _animal.pending_products() == 1)
	_check("产出物落在动物附近",
		_products()[0].global_position.distance_to(_animal.global_position) < 30.0)

	print("--- 收走：路过就捡 ---")
	var before_goods: int = _player.goods_total()
	_player.global_position = (_products()[0] as Node2D).global_position
	await _step(6)
	print("  INFO 捡完：手里 ", _player.goods_total(), " 个，地上还剩 ", _products().size())
	_check("走过去自动收走", _player.goods_total() == before_goods + 1)
	_check("捡完地上就没了", _products().is_empty())
	_check("累计收过 1 个", _player.total_goods == 1)
	await _step(3)
	_check("收走之后 pending 也减回去了", _animal.pending_products() == 0)

	print("--- 不设上限的话地上会堆满，所以有个上限 ---")
	# ⚠️ 先把玩家挪远。上一节他正站在动物旁边，
	#    新产的蛋一落地就被他捡走，地上永远是 0 —— 又是"前置状态没收拾干净"。
	_player.global_position = Vector2(40, 40)
	await _step(4)
	# 累计产出是**跨节累加**的（前面那节已经产过 1 个并被收走），所以按增量断言
	var produced_before: int = _animal.produced_total()
	for i in range(_animal.MAX_PENDING + 2):
		_cycle.day_started.emit(_cycle.day + i)
		await _step(2)
	print("  INFO 连过 ", _animal.MAX_PENDING + 2, " 天：地上 ", _products().size(),
		" 个，累计产出 ", produced_before, " → ", _animal.produced_total())
	_check("地上最多只留 MAX_PENDING 个", _products().size() == _animal.MAX_PENDING)
	_check("堆满之后就不再产了（只多产了 MAX_PENDING 个）",
		_animal.produced_total() == produced_before + _animal.MAX_PENDING)

	print("--- 畜产和作物一起在商店卖 ---")
	# 先把地上的都收掉
	for i in range(_animal.MAX_PENDING + 2):
		var left := _products()
		if left.is_empty():
			break
		_player.global_position = (left[0] as Node2D).global_position
		await _step(4)
	print("  INFO 手里畜产 ", _player.goods_total(), " 个")
	_check("手里有畜产了", _player.goods_total() > 0)

	var goods_n: int = _player.goods_total()
	var money0: int = _player.money
	# 篮子里也放一株作物，验证两者能一起卖
	_player.harvested[0] = 2
	var crop_worth: int = 2 * CropData.sell_price(0)
	var expect_base: int = crop_worth + goods_n * AnimalProduct.PRICE
	_player.global_position = _market.global_position
	await _step(4)
	var ok: bool = _market.sell_crops(_player)
	await _step(2)
	print("  INFO 卖之前 ", money0, " 金 → 卖之后 ", _player.money,
		"（作物 ", crop_worth, " + 畜产 ", goods_n * AnimalProduct.PRICE, "）")
	_check("卖成功了", ok)
	_check("畜产卖掉了（手里清空）", _player.goods_total() == 0)
	_check("作物也一起卖掉了", _player.harvested[0] == 0)
	_check("★ 钱真的进账了（畜产也算了钱）", _player.money >= money0 + expect_base)

	print("--- 只有畜产、没有作物时也能卖 ---")
	_player.money = 0
	_player.add_goods(1)
	var ok2: bool = _market.sell_crops(_player)
	await _step(2)
	print("  INFO 只卖畜产：", ok2, "，现在 ", _player.money, " 金")
	_check("篮子里只有畜产也卖得掉", ok2)
	_check("拿到了畜产的钱", _player.money > 0)
	_check("手里的畜产清空了", _player.goods_total() == 0)

	print("--- 畜产要能存档 ---")
	_player.animal_goods = 3
	_player.total_goods = 9
	var pd: Dictionary = _player.to_save_data()
	_check("存档里记了手里的畜产", int(pd.get("animal_goods", -1)) == 3)
	_check("存档里记了累计畜产", int(pd.get("total_goods", -1)) == 9)
	_player.animal_goods = 0
	_player.total_goods = 0
	_player.apply_save_data(pd)
	_check("读档读回手里的畜产", _player.animal_goods == 3)
	_check("读档读回累计畜产", _player.total_goods == 9)
	_check("收获篮总数把畜产也算进去了", _player.basket_total() >= 3)

	print("RESULT fail=", _fail)
	get_tree().quit()
