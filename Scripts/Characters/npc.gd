class_name Npc extends Node2D

## 会说话的角色。农场里原来**没有一张会回应的脸** —— 所有建筑都只是功能。
## 老铁是个退休矿工，站在矿洞口旁边：他提要求、给东西、还会根据你的进度换台词。
##
## 台词**跟着游戏状态走**（去过矿洞没有、拆过关底没有），
## 所以他不只是个告示牌 —— 你说的话他记得。

signal talked(line: String)

## 他开口要的东西：3 块矿石
const WANT_ORE: int = 3
## 给了之后送的东西
const GIFT: String = "lucky_charm"
## 存档标记
const FLAG: String = "old_iron"

@export var npc_name: String = "老铁"

@onready var talk_area: Area2D = $TalkArea
@onready var sprite: Sprite2D = $Sprite

func _ready() -> void:
	add_to_group("npc")

func is_player_inside() -> bool:
	if talk_area == null:
		return false
	for b in talk_area.get_overlapping_bodies():
		if b.is_in_group("player"):
			return true
	return false

func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

## 他已经收过礼了没有
func gift_given() -> bool:
	var p := _player()
	return p != null and p.npc_done.has(FLAG)

## 他现在缺不缺矿石（还没给过礼，且矿石不够）
func needs_ore() -> bool:
	if gift_given():
		return false
	var p := _player()
	return p != null and p.ore < WANT_ORE

## 可以交矿石了
func can_trade() -> bool:
	if gift_given():
		return false
	var p := _player()
	return p != null and p.ore >= WANT_ORE

## 当前该说的话。**跟着状态变** —— 这就是"人味"的来源。
func current_line() -> String:
	var p := _player()
	if p == null:
		return "……"
	if gift_given():
		if MineRun.total_boss > 0:
			return "你把那台采掘机械拆了？好小子。我当年就是被它撵出来的。"
		return "那护身符是我唯一能给你的了。下面的事，靠你自己。"
	if p.ore >= WANT_ORE:
		return "哟，手上那石头……给我 %d 块，我这儿有件老物件换给你。" % WANT_ORE
	if MineRun.total_runs > 0:
		return "下去过了吧。听着 —— 火把烧完它自己会把你拽回来，别硬撑。"
	return "你也是冲那矿洞去的？我这条腿就是在那儿丢的。"

## 按一下之后的次要台词（测试和 UI 都用它）
func request_text() -> String:
	if gift_given():
		return "（他已经把东西给你了）"
	if can_trade():
		return "给他 %d 块矿石  →  %s" % [WANT_ORE, ItemData.name_of(GIFT)]
	return "他要 %d 块矿石（你有 %d）" % [WANT_ORE, (_player().ore if _player() != null else 0)]

## 真的把矿石交出去。成功返回 true。
## ⚠️ 先验后扣 —— 不够的时候**一样东西都不能动**。
func trade() -> bool:
	if not can_trade():
		return false
	var p := _player()
	p.ore -= WANT_ORE
	p.add_item(GIFT, 1)
	p.npc_done[FLAG] = true
	Sfx.play("coin")
	print("[NPC] ", npc_name, "：成交。", ItemData.name_of(GIFT), " 归你了")
	talked.emit(current_line())
	return true

## 对着他按 F 的时候调这个：能交就交，不能交就只是说话
func interact() -> String:
	var line: String = current_line()
	if can_trade():
		trade()
		line = current_line()
	print("[NPC] ", npc_name, "：", line)
	talked.emit(line)
	return line
