class_name Player extends Character

## 玩家：移动 + 农场状态 + 手持道具。
##
## 手上永远只拿着四样东西之一，用 Q 切换：
##   SEED      种子袋 —— 在耕地上使用 = 播种；在商店使用 = 买当前选中的种子
##                      （按 1-5 选择要种 / 要买的作物种类）
##   WATER_CAN 水壶   —— 在作物上使用 = 浇水
##   BASKET    收获篮 —— 在成熟作物上使用 = 收获；在商店使用 = 卖光篮子
##   SWORD     剑     —— 砍附近的野猪
##
## 种子和收获物都是**按作物种类分开计数**的数组，下标就是 CropData 的种类 id。

const WATER_CAPACITY: int = 5
const MAX_HP: int = 5
const ATTACK_COOLDOWN: float = 0.35
const SLASH_TIME: float = 0.12

enum Item { SEED, WATER_CAN, BASKET, SWORD, TOOLBOX }

const ITEM_NAMES: Array[String] = ["种子袋", "水壶", "收获篮", "长剑", "工具箱"]

signal died

var money: int = 20
## 每种作物的种子数量，下标 = CropData 的种类 id
var seeds: Array[int] = [8, 0, 0, 0, 0]
## 篮子里每种作物的数量
var harvested: Array[int] = [0, 0, 0, 0, 0]
## 当前选中的作物种类（决定播种 / 买种子的种类）
var seed_type: int = 0
var water_left: int = 0
var hp: int = MAX_HP
## 实际上限 = MAX_HP + 铁壁专精加成，_process 里同步
var max_hp: int = MAX_HP
var active_item: int = Item.SEED

## 生涯累计（成就用，不随卖作物清零）
var total_harvested: int = 0
var total_kills: int = 0
## 手里还没卖掉的动物产出（蛋/奶）
var animal_goods: int = 0
## 累计收过多少畜产（统计用，只增不减）
var total_goods: int = 0
## 篮子里**加工品**的总价值。加工品不分类别，只记值多少钱 ——
## 这样不用为每种作物单独做一套成品图标和数据。
var processed_value: int = 0
## 累计加工出来的总价值（统计用）
var total_processed: int = 0
## 生涯累计赚到的钱（**只增不减**，统计面板用；money 会因为买东西变少）
var total_earned: int = 0
## 累计种下几株（目标引导链要用）
var total_planted: int = 0
## 累计浇过几次水
var total_watered: int = 0

## 背包：物品 id -> 数量
var inventory: Dictionary = {}
## 装备槽：ItemData.Slot -> 物品 id（空串 = 没装）
var equipped: Dictionary = {}

# --- 背包 ---

func add_item(id: String, n: int = 1) -> bool:
	if not ItemData.exists(id):
		push_warning("没有这种物品：" + id)
		return false
	inventory[id] = int(inventory.get(id, 0)) + maxi(1, n)
	# 第一次拿到的装备**自动穿上空槽** —— 玩家不用自己想起来去装
	var slot: int = ItemData.slot_of(id)
	if equipped.get(slot, "") == "":
		equip(id)
	return true

func has_item(id: String) -> bool:
	return int(inventory.get(id, 0)) > 0

func item_count(id: String) -> int:
	return int(inventory.get(id, 0))

func take_item(id: String, n: int = 1) -> bool:
	var have: int = item_count(id)
	if have < n:
		return false
	if have == n:
		inventory.erase(id)
	else:
		inventory[id] = have - n
	return true

# --- 装备 ---

## 装上某件装备。返回是否真的换上了。
func equip(id: String) -> bool:
	if not ItemData.exists(id) or not has_item(id):
		return false
	var slot: int = ItemData.slot_of(id)
	equipped[slot] = id
	print("[装备] 装上 ", ItemData.name_of(id), "（", ItemData.slot_name(slot), "）")
	return true

func unequip(slot: int) -> void:
	equipped.erase(slot)

func equipped_id(slot: int) -> String:
	return String(equipped.get(slot, ""))

func equipped_name(slot: int) -> String:
	var id: String = equipped_id(slot)
	return ItemData.name_of(id) if id != "" else "无"

## 把所有装备的某一项加成加起来（key 是 dmg / def / hp）
func equip_bonus(key: String) -> int:
	var sum: int = 0
	for slot in equipped.keys():
		var id: String = String(equipped[slot])
		if id != "":
			sum += int(ItemData.get_item(id).get(key, 0))
	return sum

func total_damage_bonus() -> int:
	return equip_bonus("dmg")

func total_defense() -> int:
	return equip_bonus("def")

func total_hp_bonus() -> int:
	return equip_bonus("hp")

## 装备栏的一行摘要（HUD 和测试都读这个）
func equipment_line() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for slot in range(ItemData.SLOT_NAMES.size()):
		var id: String = equipped_id(slot)
		if id != "":
			parts.append(ItemData.name_of(id))
	return " / ".join(parts) if parts.size() > 0 else "空手"

## 当前重叠的水源数量（站在水源旁自动补水）
var _water_source_count: int = 0
var _attack_cd: float = 0.0
var _slash_time: float = 0.0
var _spawn_position: Vector2 = Vector2.ZERO
var _cycle_hooked: bool = false

@onready var slash: Polygon2D = $Slash

func _ready() -> void:
	add_to_group("player")
	_spawn_position = global_position
	_hook_day_cycle()

## DayCycle 可能排在后面，_ready 时分组还没注册，所以允许之后再补连
func _hook_day_cycle() -> void:
	if _cycle_hooked:
		return
	var cycle := get_tree().get_first_node_in_group("day_cycle") as DayCycle
	if cycle == null:
		return
	cycle.day_started.connect(_on_day_started)
	_cycle_hooked = true

func _on_day_started(day: int) -> void:
	# 储户专精：每天利息
	var interest: int = Progression.daily_interest()
	if interest > 0:
		earn(interest)
		Sfx.play("coin")
		print("[成长] 储户利息 +", interest, " 金（第 ", day, " 天）")
	# 新作物解锁提示
	for id in CropData.unlocked_kinds(day):
		if not CropData.is_unlocked(id, day - 1):
			print("[解锁] 新作物：", CropData.name_of(id), "（种子 ", CropData.seed_price(id),
				" 金，收购 ", CropData.sell_price(id), " 金）")

## 铁壁专精会加最大生命。加上限时顺手把血补上，免得永远顶着残血。
func _sync_max_hp() -> void:
	var m: int = MAX_HP + Progression.max_hp_bonus()
	if m == max_hp:
		return
	var gained: int = m - max_hp
	max_hp = m
	if gained > 0:
		hp += gained
	hp = mini(hp, max_hp)

func _unhandled_input(event: InputEvent) -> void:
	InputDirection = Input.get_vector("left", "right", "up", "down")
	UpdateFaceDirection()

func _process(delta: float) -> void:
	if not _cycle_hooked:
		_hook_day_cycle()
	_sync_max_hp()
	if _water_source_count > 0 and water_left < WATER_CAPACITY:
		water_left = WATER_CAPACITY
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_update_slash(delta)

## 刀光动画。不用 AnimationPlayer —— 它每帧被状态机抢去播 Idle/Move，
## 所以这里按剩余时间直接驱动缩放/旋转/透明度，纯数据驱动、可测。
func _update_slash(delta: float) -> void:
	if _slash_time <= 0.0:
		return
	_slash_time = maxf(0.0, _slash_time - delta)
	if _slash_time <= 0.0:
		slash.visible = false
		return
	var t: float = 1.0 - _slash_time / SLASH_TIME      # 0 -> 1
	var dir: float = -1.0 if sprite_2d.flip_h else 1.0
	var grow: float = lerpf(0.55, 1.35, t)
	slash.scale = Vector2(dir * grow, grow)
	slash.rotation = lerpf(-0.6, 0.5, t) * dir
	slash.modulate = Color(1, 1, 1, lerpf(0.95, 0.0, t))

# --- 手持道具 ---

func cycle_item() -> void:
	active_item = (active_item + 1) % ITEM_NAMES.size()

func item_name() -> String:
	if active_item == Item.SEED:
		return "种子袋·%s" % crop_name()
	return ITEM_NAMES[active_item]

# --- 作物种类 ---

func crop_name(type_id: int = -1) -> String:
	return CropData.name_of(seed_type if type_id < 0 else type_id)

## 返回是否真的换了种类
func select_seed_type(type_id: int) -> bool:
	if not CropData.is_valid(type_id) or type_id == seed_type:
		return false
	seed_type = type_id
	return true

# --- 种子 ---

func seed_count(type_id: int = -1) -> int:
	var t: int = seed_type if type_id < 0 else type_id
	if not CropData.is_valid(t):
		return 0
	return seeds[t]

func has_seed(type_id: int = -1) -> bool:
	return seed_count(type_id) > 0

func take_seed(type_id: int = -1) -> bool:
	var t: int = seed_type if type_id < 0 else type_id
	if seed_count(t) <= 0:
		return false
	seeds[t] -= 1
	return true

func add_seed(type_id: int, n: int = 1) -> void:
	if not CropData.is_valid(type_id):
		return
	seeds[type_id] = maxi(0, seeds[type_id] + n)

# --- 收获篮 ---

func basket_total() -> int:
	var n: int = 0
	for v in harvested:
		n += v
	return n + animal_goods

## 动物产出（蛋/奶）。和作物分开计数，但**在商店里一起卖** ——
## 玩家不用记"这个该去哪卖"。
func add_goods(n: int = 1) -> void:
	if n <= 0:
		return
	animal_goods += n
	total_goods += n
	print("[农场] 收了一个畜产，现在 ", animal_goods, " 个")

func goods_total() -> int:
	return animal_goods

## 加工坊做出来的成品（价值记账，不分类别）
func add_processed(value: int) -> void:
	if value <= 0:
		return
	processed_value += value
	total_processed += value

func has_processed() -> bool:
	return processed_value > 0

func add_harvest(type_id: int, n: int = 1) -> void:
	if not CropData.is_valid(type_id):
		return
	harvested[type_id] = maxi(0, harvested[type_id] + n)
	total_harvested += n

func register_kill() -> void:
	total_kills += 1

## 种下一株（目标引导链用）
func register_plant() -> void:
	total_planted += 1

## 浇了一次水
func register_water() -> void:
	total_watered += 1

## 进账（卖作物、击杀赏金等）。目标判定由 FarmController 每帧读 money，这里不用通知谁。
func earn(amount: int) -> void:
	var got: int = maxi(0, amount)
	money += got
	total_earned += got

# --- 水 ---

func has_water() -> bool:
	return water_left > 0

func consume_water() -> bool:
	if water_left <= 0:
		return false
	water_left -= 1
	return true

func add_water_source() -> void:
	_water_source_count += 1

func remove_water_source() -> void:
	_water_source_count = maxi(0, _water_source_count - 1)

# --- 战斗 ---

func can_attack() -> bool:
	return _attack_cd <= 0.0

func begin_attack_cooldown() -> void:
	_attack_cd = ATTACK_COOLDOWN
	# 刀光：复用场景里预建的 Slash 节点，只做开关 + 起始姿态，动画在 _update_slash 里推进
	var dir: float = -1.0 if sprite_2d.flip_h else 1.0
	slash.visible = true
	slash.scale = Vector2(dir * 0.55, 0.55)
	slash.rotation = -0.6 * dir
	slash.modulate = Color(1, 1, 1, 0.95)
	_slash_time = SLASH_TIME

func take_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = maxi(0, hp - amount)
	Sfx.play("hurt")
	print("[玩家] 掉血 ", amount, "，剩 ", hp, "/", max_hp)
	if hp <= 0:
		_die()

## 晕倒：损失一半金币（保险专精可免），被抬回出生点，补满血
func _die() -> void:
	var lost: int = 0
	if Progression.death_penalty_enabled():
		lost = money / 2
	money -= lost
	hp = max_hp
	water_left = 0
	global_position = _spawn_position
	velocity = Vector2.ZERO
	print("[玩家] 晕倒了！被抬回出生点，损失 ", lost, " 金，剩 ", money)
	died.emit()

# --- 存档 ---

func to_save_data() -> Dictionary:
	return {
		"money": money, "hp": hp, "water_left": water_left,
		"seeds": Array(seeds), "harvested": Array(harvested),
		"seed_type": seed_type, "active_item": active_item,
		"total_harvested": total_harvested, "total_kills": total_kills,
		"animal_goods": animal_goods, "total_goods": total_goods,
		"processed_value": processed_value, "total_processed": total_processed,
		"total_earned": total_earned,
		"total_planted": total_planted, "total_watered": total_watered,
		"inventory": inventory.duplicate(), "equipped": equipped.duplicate(),
		"pos_x": global_position.x, "pos_y": global_position.y,
	}

func apply_save_data(d: Dictionary) -> void:
	money = maxi(0, int(d.get("money", 20)))
	hp = clampi(int(d.get("hp", MAX_HP)), 0, maxi(MAX_HP, max_hp))
	water_left = clampi(int(d.get("water_left", 0)), 0, WATER_CAPACITY)
	seed_type = clampi(int(d.get("seed_type", 0)), 0, CropData.count() - 1)
	active_item = clampi(int(d.get("active_item", Item.SEED)), 0, ITEM_NAMES.size() - 1)
	total_harvested = maxi(0, int(d.get("total_harvested", 0)))
	total_kills = maxi(0, int(d.get("total_kills", 0)))
	animal_goods = maxi(0, int(d.get("animal_goods", 0)))
	total_goods = maxi(0, int(d.get("total_goods", 0)))
	processed_value = maxi(0, int(d.get("processed_value", 0)))
	total_processed = maxi(0, int(d.get("total_processed", 0)))
	total_earned = maxi(0, int(d.get("total_earned", 0)))
	total_planted = maxi(0, int(d.get("total_planted", 0)))
	total_watered = maxi(0, int(d.get("total_watered", 0)))
	# 存档是权威：先清空再读，免得旧档里没有这两个字段时留着上一局的装备
	inventory.clear()
	var inv: Variant = d.get("inventory", {})
	if typeof(inv) == TYPE_DICTIONARY:
		for k in (inv as Dictionary).keys():
			inventory[String(k)] = int((inv as Dictionary)[k])
	equipped.clear()
	var eq: Variant = d.get("equipped", {})
	if typeof(eq) == TYPE_DICTIONARY:
		for k in (eq as Dictionary).keys():
			# JSON 读回来键是字符串，统一转成 int 槽号
			equipped[int(k)] = String((eq as Dictionary)[k])
	_read_counts(d.get("seeds", null), seeds)
	_read_counts(d.get("harvested", null), harvested)
	global_position = Vector2(
		float(d.get("pos_x", global_position.x)),
		float(d.get("pos_y", global_position.y))
	)
	velocity = Vector2.ZERO

## JSON 读回来的数组是浮点，这里逐个转成非负整数（也顺手挡住越界）
func _read_counts(src: Variant, dst: Array[int]) -> void:
	if typeof(src) != TYPE_ARRAY:
		return
	var arr: Array = src
	for i in range(mini(arr.size(), dst.size())):
		dst[i] = maxi(0, int(arr[i]))
