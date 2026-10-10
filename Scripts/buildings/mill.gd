class_name Mill extends Node2D

## 加工坊：把**生的作物**做成**成品**，价值翻倍。
##
## 为什么要有它：作物直接卖是"种得多赚得多"，一条直线。
## 加工给了第二条曲线 —— 同样的地，**愿不愿意多跑一趟**换双倍价钱。
## 成品不占作物的格子，只记一个"价值"，所以不用为每种作物单独做成品图标。
##
## 交互方式照抄商店 / 水源：预建的 InteractionArea + body_entered/exited。

## 加工后的价值倍率
const MULTIPLIER: float = 2.0
const PRODUCT_NAME: String = "加工品"

var _player_inside: bool = false

@onready var area: Area2D = $InteractionArea
@onready var active_sprite: Sprite2D = $ActiveSprite

func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func is_player_inside() -> bool:
	return _player_inside

## 把篮子里的生作物全部加工掉。
## 返回这次加工出来的价值；没东西可加工就返回 0。
func process_crops(player: Player) -> int:
	if player == null:
		return 0
	var base: int = 0
	var count: int = 0
	var detail: String = ""
	for type_id in range(player.harvested.size()):
		var n: int = player.harvested[type_id]
		if n <= 0:
			continue
		base += n * CropData.sell_price(type_id)
		count += n
		if detail != "":
			detail += "、"
		detail += "%s x%d" % [CropData.name_of(type_id), n]
		player.harvested[type_id] = 0
	if count <= 0:
		print("[加工坊] 篮子里没有生作物，先去收点东西")
		return 0
	var value: int = int(round(float(base) * MULTIPLIER))
	player.add_processed(value)
	Sfx.play("buy")
	print("[加工坊] 把 ", detail, " 做成了 ", PRODUCT_NAME, "：", base, " → ", value,
		" 金（x", MULTIPLIER, "）")
	return value

## 现在加工能多赚多少（给提示文字用）
func preview_gain(player: Player) -> int:
	if player == null:
		return 0
	var base: int = 0
	for type_id in range(player.harvested.size()):
		base += player.harvested[type_id] * CropData.sell_price(type_id)
	return int(round(float(base) * MULTIPLIER)) - base

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player_inside = true
		if active_sprite != null:
			active_sprite.visible = true
		print("[加工坊] 按 F 把篮里的作物做成", PRODUCT_NAME, "（价值 x", MULTIPLIER, "）")

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_player_inside = false
		if active_sprite != null:
			active_sprite.visible = false
