extends Node2D

## 自动试玩机器人（不是单元测试，是**节奏测量**）。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/playtest.tscn --quit-after 40000
##
## 让一个贪心策略的机器人从零开始真的把游戏打通，然后看数据回答「好不好玩」：
##   - 多久能打到 300 金的目标
##   - 第一次收获要多久（新手多久能尝到甜头）
##   - 一天里到底在做几件事（操作密度）
##   - **有多少时间是在干等作物长大**（农场游戏最大的乐趣杀手）
##
## 机器人不作弊：走路靠设 InputDirection 让玩家自己 move_and_slide，
## 干活靠 _ctl.use_held_item()，和玩家按键走的是同一条路径。

const MAX_DAYS: int = 12
const ARRIVE_DIST: float = 12.0
const GOAL: int = 300
## 攻击范围外一点就停下来打，免得贴着怪被顶
const FIGHT_DIST: float = 22.0

enum Job { WAIT, FIGHT, HARVEST, WATER, REFILL, PLANT, SELL, BUY }

var _level: Node2D
var _player: Player
var _land: FarmLand
var _market: Market
var _ctl: FarmController
var _cycle: DayCycle
var _water_src: Node2D

var _job: int = Job.WAIT
var _target: Vector2 = Vector2.ZERO
var _target_tile: Vector2i = Vector2i(-999999, -999999)

# --- 统计 ---
var _frames: int = 0
var _wait_frames: int = 0
var _walk_frames: int = 0
var _work_frames: int = 0
var _first_harvest_frame: int = -1
var _goal_frame: int = -1
var _acts := {"种": 0, "浇": 0, "收": 0, "卖": 0, "买": 0, "战": 0}
var _done: bool = false

## 机器人策略开关，用命令行传：
##   godot --headless --path . res://Tests/playtest.tscn -- cheapest nofight
##   cheapest = 只买最便宜的作物（新手策略）；默认是「买得起的最贵」
##   nofight  = 完全不打害兽，用来量出「害兽税」到底有多重
var _buy_cheapest: bool = false
var _fight_enabled: bool = true
var _debug: bool = false
## -1 = 不选专精；0 = 每次都选第一项；1 = 每次都选第二项
var _perk_choice: int = -1

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "cheapest":
			_buy_cheapest = true
		elif a == "nofight":
			_fight_enabled = false
		elif a == "debug":
			_debug = true
		elif a == "perks0":
			_perk_choice = 0
		elif a == "perks1":
			_perk_choice = 1
	Progression.reset()
	_level = (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	var save_sys := _level.get_node("SaveSystem") as SaveSystem
	save_sys.auto_load = false
	save_sys.auto_save_on_dawn = false
	_player = _level.get_node("level/Player")
	_land = _level.get_node("Land")
	_market = _level.get_node("level/Static/Market")
	_ctl = _level.get_node("FarmController")
	_cycle = _level.get_node("DayCycle")
	# 测试场景不是主场景，自动加载 Level 拿不到导航区域，必须手动补（否则动物的 Move 状态会报错）
	if Level.animalRegion == null:
		Level.animalRegion = _level.get_node("level/animalRegion2D")
	_water_src = _level.get_node_or_null("level/Static/waterBucket") as Node2D
	if _water_src == null:
		_water_src = _level.get_node_or_null("level/Static/WaterContainer") as Node2D
	print("=== 自动试玩开始（目标 ", GOAL, " 金）===")
	print("  [策略] ", "只买最便宜" if _buy_cheapest else "买得起的最贵", " / ",
		"会打害兽" if _fight_enabled else "**完全不打害兽**")
	print("  [水点] ", "已找到" if _water_src != null else "没找到！补水会卡住")

func _physics_process(delta: float) -> void:
	if _done:
		return
	_frames += 1

	if _cycle.day > MAX_DAYS:
		_finish("超过 %d 天还没通关" % MAX_DAYS)
		return
	if _player.money >= GOAL and _goal_frame < 0:
		_goal_frame = _frames
		_finish("通关")
		return

	_decide()
	# 升级了就选（真实玩家会按键，机器人直接调接口）
	if _perk_choice >= 0 and Progression.pending_choice >= 0:
		Progression.choose(_perk_choice)
	if _debug and _frames % 180 == 0:
		print("[dbg] f=", _frames, " job=", _job,
			" dist=%.1f" % _player.global_position.distance_to(_target),
			" pos=", _player.global_position.round(), " target=", _target.round(),
			" 种子=", _player.seed_count(), " 在店内=", _market.is_player_inside(),
			" 空位=", _find_tile(false, false, true), " 要浇=", _find_tile(false, true, false),
			" 玩家格=", _land.get_player_tile(), " 目标格=", _target_tile)
	_act(delta)

# --- 决策：优先级从高到低 ---

func _decide() -> void:
	# 1) 有害兽正在祸害作物 → 去打
	if _fight_enabled:
		var pest := _nearest_pest()
		if pest != null:
			_job = Job.FIGHT
			_target = pest.global_position
			return

	# 2) 有熟了的 → 收（先尝到甜头）
	var t: Vector2i = _find_tile(true, false, false)
	if t != _invalid():
		_job = Job.HARVEST
		_target_tile = t
		_target = _tile_pos(t)
		return

	# 3) 有要浇的但水壶空了 → 去补水
	var thirsty: Vector2i = _find_tile(false, true, false)
	if thirsty != _invalid() and _player.water_left <= 0:
		_job = Job.REFILL
		_target = _water_src.global_position if _water_src != null else _player.global_position
		return

	# 4) 有要浇的 → 浇
	if thirsty != _invalid():
		_job = Job.WATER
		_target_tile = thirsty
		_target = _tile_pos(thirsty)
		return

	# 5) 有种子 + 有空地 → 种
	if _player.has_seed():
		var empty: Vector2i = _find_tile(false, false, true)
		if empty != _invalid():
			_job = Job.PLANT
			_target_tile = empty
			_target = _tile_pos(empty)
			return

	# 6) 篮子里有货 → 卖
	if _player.basket_total() > 0:
		_job = Job.SELL
		_target = _market.global_position
		return

	# 7) 没种子 → 买
	if not _player.has_seed():
		_job = Job.BUY
		_target = _market.global_position
		return

	# 8) 真的没事干：等作物长大
	_job = Job.WAIT
	_wait_frames += 1
	_target = _player.global_position

# --- 执行 ---

func _act(delta: float) -> void:
	if _job == Job.WAIT:
		_player.InputDirection = Vector2.ZERO
		return

	var to: Vector2 = _target - _player.global_position
	var dist: float = to.length()
	# 到达判定必须和游戏自己的规则一致：
	# 农活看的是 get_player_tile() 是否**正好**落在目标格，光靠「离得够近」会站在隔壁格上白按 F。
	var arrived: bool
	match _job:
		Job.FIGHT:
			arrived = dist <= FIGHT_DIST
		Job.PLANT, Job.WATER, Job.HARVEST:
			arrived = _land.get_player_tile() == _target_tile
		_:
			arrived = dist <= ARRIVE_DIST
	if not arrived:
		_player.InputDirection = to.normalized()
		_walk_frames += 1
		return

	_player.InputDirection = Vector2.ZERO
	_work_frames += 1

	match _job:
		Job.FIGHT:
			_player.active_item = Player.Item.SWORD
			if _ctl.use_held_item():
				_acts["战"] += 1
		Job.HARVEST:
			_player.active_item = Player.Item.BASKET
			if _ctl.use_held_item():
				_acts["收"] += 1
				if _first_harvest_frame < 0:
					_first_harvest_frame = _frames
		Job.WATER:
			_player.active_item = Player.Item.WATER_CAN
			if _ctl.use_held_item():
				_acts["浇"] += 1
		Job.REFILL:
			pass  # 站进 InteractionArea 会自动补满
		Job.PLANT:
			if _market.is_player_inside():
				return  # 站在商店里按 F 会被商店分支抢走
			_player.active_item = Player.Item.SEED
			if _ctl.use_held_item():
				_acts["种"] += 1
		Job.SELL:
			_player.active_item = Player.Item.BASKET
			if _ctl.use_held_item():
				_acts["卖"] += 1
		Job.BUY:
			_ctl.select_seed(_best_crop())
			_player.active_item = Player.Item.SEED
			if _ctl.use_held_item():
				_acts["买"] += 1

# --- 查询辅助 ---

func _invalid() -> Vector2i:
	return Vector2i(-999999, -999999)

func _tile_pos(t: Vector2i) -> Vector2:
	return _land.to_global(_land.map_to_local(t))

func _nearest_pest() -> Pest:
	var best: Pest = null
	var best_d: float = INF
	for n in get_tree().get_nodes_in_group("pest"):
		var p := n as Pest
		if p == null or not is_instance_valid(p):
			continue
		var d: float = _player.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best

## kind: 0=熟了的 1=要浇水的 2=空着的
func _find_tile(want_ripe: bool, want_thirsty: bool, want_empty: bool) -> Vector2i:
	var best: Vector2i = _invalid()
	var best_d: float = INF
	for c in _land.get_used_cells():
		if not _land.is_farmland(c):
			continue
		var p: BasePlant = _land.plants.get(c)
		var ok: bool = false
		if want_empty:
			ok = (p == null)
		elif p != null and is_instance_valid(p):
			if want_ripe:
				ok = p.is_mature()
			elif want_thirsty:
				ok = (not p.is_mature()) and p.can_water()
		if not ok:
			continue
		var pos: Vector2 = _tile_pos(c)
		var d: float = _player.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = c
	return best

## 买得起的最贵的已解锁作物（cheapest 策略下改成最便宜的）
func _best_crop() -> int:
	var kinds := CropData.unlocked_kinds(_cycle.day)
	if kinds.is_empty():
		return 0
	if _buy_cheapest:
		return kinds[0]
	var best: int = 0
	for id in kinds:
		if CropData.seed_price(id) <= _player.money:
			best = id
	return best

# --- 收尾报告 ---

func _finish(reason: String) -> void:
	if _done:
		return
	_done = true
	var sec: float = float(_frames) / 60.0
	print("")
	print("=== 试玩结果：", reason, " ===")
	print("模拟时长        : %.1f 秒（%.2f 天）" % [sec, sec / _cycle.day_length if _cycle.day_length > 0.0 else 0.0])
	print("结束状态        : 第 %d 天 %s，金币 %d，成就 %d" % [
		_cycle.day, _cycle.phase_name(), _player.money,
		(_level.get_node("Achievements") as Achievements).count()])
	if _first_harvest_frame >= 0:
		print("第一次收获      : 第 %.1f 秒" % (float(_first_harvest_frame) / 60.0))
	else:
		print("第一次收获      : **一次都没收获到**")
	if _goal_frame >= 0:
		print("达成 %d 金      : 第 %.1f 秒" % [GOAL, float(_goal_frame) / 60.0])
	print("操作次数        : 种 %d / 浇 %d / 收 %d / 卖 %d / 买 %d / 战 %d" % [
		_acts["种"], _acts["浇"], _acts["收"], _acts["卖"], _acts["买"], _acts["战"]])
	var ops: int = _acts["种"] + _acts["浇"] + _acts["收"] + _acts["卖"] + _acts["买"] + _acts["战"]
	print("操作密度        : 每分钟 %.1f 次有效操作" % (float(ops) / sec * 60.0 if sec > 0.0 else 0.0))
	print("时间去向        : 走路 %.0f%% / 干活 %.0f%% / **干等 %.0f%%**" % [
		float(_walk_frames) / _frames * 100.0,
		float(_work_frames) / _frames * 100.0,
		float(_wait_frames) / _frames * 100.0])
	# 最终局面
	var empty: int = 0
	var growing: int = 0
	var ripe: int = 0
	for c in _land.get_used_cells():
		if not _land.is_farmland(c):
			continue
		var p: BasePlant = _land.plants.get(c)
		if p == null:
			empty += 1
		elif p.is_mature():
			ripe += 1
		else:
			growing += 1
	print("收尾田地        : 熟 %d / 长 %d / 空 %d" % [ripe, growing, empty])
	print("技能等级        : 农耕 %d / 战斗 %d / 经营 %d（专精 %d 个）" % [
		Progression.level_of(Progression.Skill.FARM),
		Progression.level_of(Progression.Skill.COMBAT),
		Progression.level_of(Progression.Skill.TRADE),
		Progression.perk_count()])
	get_tree().quit()
