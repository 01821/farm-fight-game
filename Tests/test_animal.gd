extends Node2D

## 端到端自测：动物产出（蛋/奶）这条农场第二收入线。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_animal.tscn

var _fail: int = 0
var _level: Node2D
var _animal: Node2D          # base_animal（脚本没有 class_name）
var _player: Player
var _market: Market
var _cycle: DayCycle
var _land: FarmLand
var _weather: Weather
var _ctl: FarmController

func _farm_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in _land.get_used_cells():
		if _land.is_farmland(c):
			out.append(c)
	return out

## 把玩家挪到某一格农田上（种地 / 浇水都要先站过去）
func _move_to_tile(tile: Vector2i) -> void:
	_player.global_position = _land.to_global(_land.map_to_local(tile))

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

## 模拟"按一下某个动作键"。
## 必须走 parse_input_event —— Input.action_press 只改状态，不会派发事件。
func _tap_action(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)

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
	_land = _level.get_node("Land") as FarmLand
	_weather = _level.get_node_or_null("Weather") as Weather
	_ctl = _level.get_node("FarmController") as FarmController

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

	print("--- 加工坊：生的做成成品，价值翻倍 ---")
	var mill := _level.get_node_or_null("level/Static/Mill") as Mill
	_check("农场里摆了加工坊", mill != null)

	# ★ 和矿洞口一样的守门断言：建筑不能压在农田上，
	#   否则站在那格按 F 会被建筑分支抢走、种不了地（真踩过）。
	var land := _level.get_node("Land") as FarmLand
	var clash: int = 0
	var nearest: float = INF
	for c in land.get_used_cells():
		if not land.is_farmland(c):
			continue
		var w: Vector2 = land.to_global(land.map_to_local(c))
		var dd: float = w.distance_to(mill.global_position)
		nearest = minf(nearest, dd)
		if dd < 30.0:
			clash += 1
	print("  INFO 加工坊离最近的农田 ", snappedf(nearest, 0.1), " px")
	_check("加工坊没有压在任何农田上", clash == 0)

	if mill != null:
		var p3 := _player
		p3.harvested = [0, 0, 0, 0, 0]
		p3.processed_value = 0
		_check("篮子空的时候加工不了", mill.process_crops(p3) == 0)

		# 放两株 0 号作物进去
		p3.harvested[0] = 2
		var raw: int = 2 * CropData.sell_price(0)
		var gain_preview: int = mill.preview_gain(p3)
		print("  INFO 2 株 ", CropData.name_of(0), " 生卖 ", raw, " 金，加工后多赚 ", gain_preview)
		_check("预览能算出多赚多少", gain_preview == int(round(float(raw) * Mill.MULTIPLIER)) - raw)

		var made: int = mill.process_crops(p3)
		print("  INFO 加工产出价值 ", made, "（生卖只有 ", raw, "）")
		_check("加工产出比生卖多", made > raw)
		_check("正好是倍率关系", made == int(round(float(raw) * Mill.MULTIPLIER)))
		_check("生作物被消耗掉了", p3.harvested[0] == 0)
		_check("成品的价值记在玩家身上", p3.processed_value == made)
		_check("加工完就不能再加工一次了", mill.process_crops(p3) == 0)

		print("--- 加工品也在商店卖 ---")
		var money1: int = p3.money
		var pv: int = p3.processed_value
		p3.global_position = _market.global_position
		await _step(4)
		var ok3: bool = _market.sell_crops(p3)
		await _step(2)
		print("  INFO 卖加工品：", money1, " → ", p3.money, "（成品值 ", pv, "）")
		_check("加工品卖得掉", ok3)
		_check("加工品清空了", p3.processed_value == 0)
		_check("★ 钱真的进账了", p3.money >= money1 + pv)

	print("--- 三条收入线一起卖 ---")
	_player.money = 0
	_player.harvested = [0, 0, 0, 0, 0]
	_player.harvested[0] = 1              # 作物
	_player.animal_goods = 1              # 畜产
	_player.processed_value = 20          # 加工品
	var expected: int = CropData.sell_price(0) + AnimalProduct.PRICE + 20
	_player.global_position = _market.global_position
	await _step(4)
	var ok4: bool = _market.sell_crops(_player)
	await _step(2)
	print("  INFO 一次卖出三条线的货，进账 ", _player.money, "（预期至少 ", expected, "）")
	_check("一次全卖掉", ok4)
	_check("三条线的钱都算上了", _player.money >= expected)
	_check("三样都清空了",
		_player.harvested[0] == 0 and _player.goods_total() == 0 and _player.processed_value == 0)

	print("--- 加工品要能存档 ---")
	_player.processed_value = 33
	_player.total_processed = 77
	var pd2: Dictionary = _player.to_save_data()
	_check("存档里记了成品的价值", int(pd2.get("processed_value", -1)) == 33)
	_check("存档里记了累计加工值", int(pd2.get("total_processed", -1)) == 77)
	_player.processed_value = 0
	_player.total_processed = 0
	_player.apply_save_data(pd2)
	_check("读档读回成品价值", _player.processed_value == 33)
	_check("读档读回累计加工值", _player.total_processed == 77)

	print("--- 土地升级：洒水器 / 肥料 / 温室 ---")
	_check("有三项土地升级", Upgrades.INFO.size() == 3)
	_check("升级名对得上",
		Upgrades.name_of(0) == "洒水器" and Upgrades.name_of(1) == "肥料" and Upgrades.name_of(2) == "温室")

	# 从零开始，免得被前面的状态干扰
	Upgrades.levels = [0, 0, 0]
	_check("没买时洒水器浇 0 株", Upgrades.sprinkler_count() == 0)
	_check("没买时生长倍率是 1", is_equal_approx(Upgrades.grow_time_multiplier(), 1.0))
	_check("没买时收获没有加成", Upgrades.greenhouse_bonus() == 0)
	_check("没买时 any 是 false", not Upgrades.has_any())

	print("  INFO 洒水器 ", Upgrades.next_price(0), " 金 / 肥料 ", Upgrades.next_price(1),
		" 金 / 温室 ", Upgrades.next_price(2), " 金")

	print("--- 买升级：钱不够买不了 ---")
	_check("钱不够时买不了", not Upgrades.buy(0, 0))
	_check("没买成就不该升级", Upgrades.level_of(0) == 0)
	_check("钱不够时 can_afford 是 false", not Upgrades.can_afford(0, 0))

	print("--- 洒水器：每天早上自动浇水 ---")
	var p0: int = Upgrades.next_price(0)
	_check("钱够就能买", Upgrades.buy(0, p0))
	_check("等级变成 1", Upgrades.level_of(0) == 1)
	print("  INFO 一级洒水器：", Upgrades.effect_text(0))
	_check("一级洒水器浇 2 株", Upgrades.sprinkler_count() == 2)

	# 真的种几株干的，过一夜看它浇没浇
	_land.clear_all_plants()
	await _step(2)
	_weather.set_rainy(false)
	var tiles3 := _farm_tiles()
	var planted: int = 0
	for t in tiles3:
		if planted >= 3:
			break
		_move_to_tile(t)
		_ctl.use_held_item()
		await _step(1)
		if _land.plants.has(t):
			planted += 1
	print("  INFO 种下了 ", planted, " 株，都是干的")
	_check("种下了足够多的作物", planted >= 3)
	var dry_before: int = 0
	for t in _land.plants.keys():
		if not (_land.plants[t] as BasePlant).is_watered:
			dry_before += 1
	_check("种下去的时候都是干的", dry_before >= 3)

	_cycle.day_started.emit(_cycle.day + 1)
	await _step(4)
	var wet_now: int = 0
	for t in _land.plants.keys():
		if (_land.plants[t] as BasePlant).is_watered:
			wet_now += 1
	print("  INFO 过了一夜：湿了 ", wet_now, " 株（洒水器配额 ", Upgrades.sprinkler_count(), "）")
	_check("★ 洒水器早上自动浇了水", wet_now > 0)
	_check("浇的数量不超过配额", wet_now <= Upgrades.sprinkler_count())
	_check("没有把所有作物都浇了（否则就不叫配额了）", wet_now < dry_before)

	print("--- 肥料：作物长得更快 ---")
	var base_mult: float = Upgrades.grow_time_multiplier()
	Upgrades.buy(1, Upgrades.next_price(1))
	var fast_mult: float = Upgrades.grow_time_multiplier()
	print("  INFO 肥料一级后生长倍率 ", base_mult, " → ", fast_mult)
	_check("买了肥料倍率变小", fast_mult < base_mult)
	_check("倍率在合理区间", fast_mult > 0.2 and fast_mult < 1.0)
	# 真的作用在新种的作物上
	_land.clear_all_plants()
	await _step(2)
	_move_to_tile(tiles3[0])
	_ctl.use_held_item()
	await _step(2)
	var fp: BasePlant = _land.plants.get(tiles3[0])
	if fp != null:
		print("  INFO 新种的作物生长时间 ", snappedf(fp.timer.wait_time, 0.01),
			"（原始 ", fp.growTime, "）")
		_check("新作物确实享受了肥料加成", fp.timer.wait_time < fp.growTime)
		_check("缩短比例和倍率一致",
			is_equal_approx(fp.timer.wait_time, fp.growTime * fast_mult))

	print("--- 温室：每次收获多拿 ---")
	Upgrades.buy(2, Upgrades.next_price(2))
	_check("温室一级", Upgrades.greenhouse_bonus() == 1)
	_check("现在至少买过东西了", Upgrades.has_any())

	print("--- 满级就买不了了 ---")
	Upgrades.levels = [Upgrades.MAX_LEVEL, Upgrades.MAX_LEVEL, Upgrades.MAX_LEVEL]
	_check("满级后 is_maxed", Upgrades.is_maxed(0) and Upgrades.is_maxed(2))
	_check("满级后没有下一级价格", Upgrades.next_price(0) == -1)
	_check("满级后买不了", not Upgrades.buy(0, 999999))

	print("--- 升级要能存档 ---")
	Upgrades.levels = [2, 1, 3]
	var ud: Dictionary = Upgrades.to_save_data()
	Upgrades.levels = [0, 0, 0]
	Upgrades.apply_save_data(ud)
	print("  INFO 读档后的等级 ", Upgrades.levels)
	_check("读档读回三项等级", Upgrades.levels == [2, 1, 3])
	Upgrades.apply_save_data({})
	_check("存档里没这一段时退回全 0", Upgrades.levels == [0, 0, 0])

	print("--- 拿着工具箱在商店买升级 ---")
	Upgrades.levels = [0, 0, 0]
	_player.money = 9999
	_player.active_item = Player.Item.TOOLBOX
	_player.global_position = _market.global_position
	await _step(4)
	_check("商店认得工具箱这个道具", _player.item_name() == "工具箱")
	var buy_ok: bool = _market.buy_upgrade(_player)
	await _step(2)
	print("  INFO 买升级：", buy_ok, "，等级 ", Upgrades.levels, "，余额 ", _player.money)
	_check("拿着工具箱按 F 能买升级", buy_ok)
	_check("确实升了一级", Upgrades.has_any())
	_check("钱被扣了", _player.money < 9999)

	var money_before: int = _player.money
	_player.money = 0
	_check("没钱的时候买不了", not _market.buy_upgrade(_player))
	_check("没买成不扣钱（本来就是 0）", _player.money == 0)
	_player.money = money_before

	print("--- 统计面板（Y 键） ---")
	var hud := _level.get_node_or_null("HUD")
	_check("农场里有 HUD", hud != null)
	if hud != null:
		var backdrop := _level.get_node("HUD/StatBackdrop") as ColorRect
		var body := _level.get_node("HUD/StatBody") as Label
		_check("统计面板是预建节点", backdrop != null and body != null)

		hud.stats_open = false
		await _step(3)
		_check("默认是收起的", not backdrop.visible and not body.visible)

		# 按键开关
		_check("Y 键绑上了 stats_toggle", InputMap.has_action("stats_toggle"))
		# ⚠️ `Input.action_press()` **只改内部状态，不派发事件** ——
		#    `_unhandled_input` 根本收不到。要真的投一个事件进输入系统，
		#    得用 `Input.parse_input_event()`。（踩过：断言"按一下 Y 打开了"一直红。）
		_tap_action("stats_toggle")
		await _step(3)
		_check("按一下 Y 打开了", hud.stats_open and backdrop.visible)
		_tap_action("stats_toggle")
		await _step(3)
		_check("再按一下收起了", not hud.stats_open and not backdrop.visible)

		# 塞进一些可辨认的数字，看它有没有如实显示
		_player.total_earned = 1234
		_player.total_harvested = 56
		_player.total_kills = 7
		_player.total_goods = 8
		_player.total_processed = 90
		MineRun.total_runs = 3
		MineRun.total_mine_kills = 21
		MineRun.total_boss = 2
		MineRun.deepest = 3
		MineRun.best_run_gold = 145
		MineRun.flawless_runs = 1
		hud.stats_open = true
		await _step(3)
		var txt: String = hud.stats_text()
		print("  INFO 统计面板：")
		for ln in txt.split("\n"):
			print("        ", ln)
		_check("有农场段", "农场" in txt)
		_check("有矿洞段", "矿洞" in txt)
		_check("显示了累计赚到的钱", "1234" in txt)
		_check("显示了收获作物数", "56" in txt)
		_check("显示了害兽数", "7" in txt)
		_check("显示了畜产数", "8" in txt)
		_check("显示了加工价值", "90" in txt)
		_check("显示了矿洞趟数", "3 趟" in txt)
		_check("显示了矿怪数", "21" in txt)
		_check("显示了拆关底数", "2 台" in txt)
		_check("显示了最深层次", "3 层" in txt)
		_check("显示了单趟最佳", "145" in txt)
		_check("显示了土地升级等级", "洒水器" in txt)
		hud.stats_open = false
		await _step(2)

	print("--- 累计赚到的钱只增不减 ---")
	_player.total_earned = 0
	_player.money = 100
	_player.earn(50)
	_check("赚了就累加", _player.total_earned == 50 and _player.money == 150)
	_player.money -= 120          # 花钱买东西
	_check("花掉钱之后身上变少", _player.money == 30)
	_check("但生涯累计不受影响", _player.total_earned == 50)
	_player.earn(10)
	_check("再赚继续累加", _player.total_earned == 60)

	print("--- 累计赚到的钱要能存档 ---")
	_player.total_earned = 4321
	var ed: Dictionary = _player.to_save_data()
	_player.total_earned = 0
	_player.apply_save_data(ed)
	_check("读档读回累计收入", _player.total_earned == 4321)

	print("--- 目标引导链（一环接一环）---")
	# 从零开始，别被前面的状态干扰
	Guide.apply_save_data({})
	Guide.player = null
	Guide.controller = null
	_player.total_planted = 0
	_player.total_watered = 0
	_player.total_harvested = 0
	_player.total_earned = 0
	_player.total_goods = 0
	_player.total_processed = 0
	MineRun.total_runs = 0
	MineRun.total_boss = 0
	Upgrades.levels = [0, 0, 0]
	_ctl.goal_reached = false
	await _step(3)

	_check("引导链有 10 环", Guide.total() == 10)
	_check("一开始一环都没完成", Guide.count_done() == 0)
	_check("没全部完成", not Guide.is_all_done())
	print("  INFO 当前目标：", Guide.current_text())
	print("  INFO 提示：", Guide.current_hint())
	_check("第一个目标是种 3 株作物", "种" in Guide.current_text())
	_check("每一条都带提示（玩家不会卡住）", Guide.current_hint() != "")
	_check("★ 自动加载单例也能找到玩家（不是靠相对路径）", Guide._try_resolve())

	print("--- HUD 常驻显示当前目标 ---")
	var hud2 := _level.get_node("HUD")
	await _step(3)
	print("  INFO ", hud2.goal_text())
	_check("HUD 上显示目标", "目标" in hud2.goal_text())
	_check("HUD 上写了进度 1/10", "1/10" in hud2.goal_text())

	print("--- 一环接一环：按顺序推进 ---")
	# 只把第 1 条做够，第 2 条不该跳过去
	_player.total_planted = 2
	await _step(3)
	_check("差一点就不算完成", Guide.count_done() == 0)
	# ⚠️ 临到关键断言之前**再清一次后面的条件** —— 否则别的系统在这一帧里
	#    把 total_watered / total_harvested 拱上去了，链子会一次连推两环，
	#    这条断言就偶发失败（三遍里挂过一次）。
	_player.total_watered = 0
	_player.total_harvested = 0
	_player.total_planted = 3
	await get_tree().physics_frame
	print("  INFO 种够 3 株之后：完成 ", Guide.count_done(), " 环，当前 ", Guide.current_text())
	_check("做够了就完成第 1 环", Guide.has("plant_3"))
	# ⚠️ 别断言 "浇水" —— 文案是"给作物**浇一次**水"，中间夹了字，
	#    连续的"浇水"根本不存在。断言子串时要盯着真实文案。（踩过）
	_check("自动换到第 2 环", "浇" in Guide.current_text())
	_check("弹了提示", Guide.toast_visible())
	print("  INFO 提示文字：", Guide.toast_text())
	_check("提示里有『下一个』", "下一个" in Guide.toast_text())

	# 第 2 环没做完，第 3 环的达成条件满足了也不该跳
	_player.total_harvested = 99
	# ⚠️ 只等**一帧**。Guide 是"一帧最多推一环"，等 3 帧的话
	#    water_1 和 harvest_1 可能连着推完，下面这条断言就偶发变红。
	await get_tree().physics_frame
	_check("★ 上一环没做完，后面的不会跳着完成", not Guide.has("harvest_1"))
	_check("仍然卡在第 2 环", "浇" in Guide.current_text())

	_player.total_watered = 1
	await get_tree().physics_frame
	_check("浇了水就过第 2 环", Guide.has("water_1"))
	_check("并且立刻推进到第 3 环", "收获" in Guide.current_text())
	await _step(3)
	_check("第 3 环的收获条件已经满足了，这一帧补上", Guide.has("harvest_1"))

	print("--- 链子把农场和矿洞串起来了 ---")
	var ids: Array[String] = []
	for e in Guide.LIST:
		ids.append(String(e.get("id", "")))
	print("  INFO 整条链：", " → ".join(ids))
	_check("链子里有农场的事", ids.has("plant_3") and ids.has("sell_1"))
	_check("链子里有矿洞的事", ids.has("mine_1") and ids.has("boss_1"))
	_check("链子里有畜产", ids.has("goods_1"))
	_check("链子里有加工", ids.has("process_1"))
	_check("链子里有升级", ids.has("upgrade_1"))

	print("--- 把整条链走完 ---")
	_player.total_planted = 3
	_player.total_watered = 1
	_player.total_harvested = 1
	_player.total_earned = 1
	_ctl.goal_reached = true
	MineRun.total_runs = 1
	MineRun.total_boss = 1
	_player.total_goods = 1
	_player.total_processed = 1
	Upgrades.levels = [1, 0, 0]
	# 一次只推进一环，所以要多等几帧
	await _step(60)
	print("  INFO 走完之后：", Guide.count_done(), "/", Guide.total(), "，全部完成=", Guide.is_all_done())
	_check("整条链都走完了", Guide.is_all_done())
	_check("完成数等于总数", Guide.count_done() == Guide.total())
	_check("全部完成时给出交代", Guide.current_text() == "全部完成！")
	await _step(3)
	print("  INFO ", hud2.goal_text())
	_check("HUD 上显示全部完成", "全部完成" in hud2.goal_text())

	print("--- 引导进度要能存档 ---")
	var gd: Dictionary = Guide.to_save_data()
	_check("存档里记了完成的环", (gd.get("done", []) as Array).size() == 10)
	Guide.apply_save_data({})
	_check("读空存档退回一环都没做", Guide.count_done() == 0)
	Guide.apply_save_data(gd)
	_check("读回来还是 10 环", Guide.count_done() == 10)
	# 收尾：清干净，别影响别的节
	Guide.apply_save_data({})

	print("--- 种 / 浇 的生涯计数真的会加 ---")
	_player.total_planted = 0
	_player.total_watered = 0
	_land.clear_all_plants()
	await _step(2)
	var tiles4 := _farm_tiles()
	_move_to_tile(tiles4[0])
	# 直接调农田那一层：这一节要验的是"种一株会不会让计数 +1"，
	# 而不是控制器怎么按道具路由（那条路别的地方已经覆盖了）。
	_player.active_item = Player.Item.SEED
	_player.seed_type = 0
	_player.seeds[0] = 5
	var planted_ok: bool = _land.try_plant_at(tiles4[0])
	# ⚠️ **不要在两件事中间 await** —— 种下和浇水之间隔了几帧，
	#    中间那一小段里作物的状态可能被别的东西改掉（喷水器/生长计时），
	#    于是"浇上了"就会偶发失败（三遍里挂过一次）。
	var watered_ok: bool = _land.water_plant_at(tiles4[0])
	await _step(3)
	print("  INFO try_plant_at = ", planted_ok, "，total_planted = ", _player.total_planted)
	_check("种下去了", planted_ok)
	_check("种一株就 +1", _player.total_planted == 1)
	print("  INFO water_plant_at = ", watered_ok, "，total_watered = ", _player.total_watered)
	_check("浇上了", watered_ok)
	_check("浇一次就 +1", _player.total_watered == 1)
	_land.clear_all_plants()

	print("RESULT fail=", _fail)
	get_tree().quit()
