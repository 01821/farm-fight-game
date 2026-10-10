class_name CraftPanel extends CanvasLayer

## 加工坊的配方台（**鼠标能点**）。
##
## 为什么要有它：加工坊原来是"拿着生作物按 F，价值 ×2 换成钱"。
## 那只是把农场那条线的产出换个数字，**跟矿洞毫无关系**。
## 现在它是真配方台：矿石 + 作物 + 金币 → 装备。
## 玩家在洞里背回来的石头，到这里变成了能打更深的矿的东西。
##
## 六个按钮是**预建**的（配方数是写死的常量），运行时只刷文字和可点状态。

signal crafted(id: String)

var is_open: bool = false
## 当前可达的配方下标 -> Button
@onready var backdrop: ColorRect = $Backdrop
@onready var title_label: Label = $Title
@onready var rows_root: Node = $Rows
@onready var status: Label = $Status
var _buttons: Array[Button] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("craft_panel")
	_buttons.clear()
	for i in range(RecipeData.count()):
		var b := rows_root.get_node_or_null("Row%d" % i) as Button
		if b == null:
			continue
		_buttons.append(b)
		b.pressed.connect(_on_row_pressed.bind(i))
	set_open(false)

func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("pause"):
		set_open(false)
		get_viewport().set_input_as_handled()

func set_open(open: bool) -> void:
	is_open = open
	backdrop.visible = open
	title_label.visible = open
	status.visible = open
	for b in _buttons:
		b.visible = open
	if open:
		_refresh()

func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

## 刷新每一行的文字和"能不能点"
func _refresh() -> void:
	var p := _player()
	for i in range(_buttons.size()):
		var r := RecipeData.at(i)
		var b := _buttons[i]
		if p == null or r.is_empty():
			b.text = "—"
			b.disabled = true
			continue
		var lack: String = RecipeData.missing(r, p)
		# 缺料的行**变暗且点不动** —— 玩家一眼能看出哪条现在能做
		b.disabled = lack != ""
		b.text = "  ".join([RecipeData.describe(r), "✔" if lack == "" else lack])
		b.modulate = Color(1, 1, 1, 1) if lack == "" else Color(0.62, 0.62, 0.7, 1)
	if status.text == "" and p != null:
		status.text = "矿石 %d 块" % p.ore

func _on_row_pressed(i: int) -> void:
	var p := _player()
	var r := RecipeData.at(i)
	if p == null or r.is_empty():
		return
	var lack: String = RecipeData.missing(r, p)
	if lack != "":
		status.text = lack
		return
	if RecipeData.craft(r, p):
		status.text = "做出 %s！还有 %d 块矿石" % [RecipeData.result_name(r), p.ore]
		Sfx.play("plant")
		crafted.emit(String(r.get("id", "")))
		_refresh()

## 给测试直接读的一行文字
func row_text(i: int) -> String:
	if i < 0 or i >= _buttons.size():
		return ""
	return _buttons[i].text

func row_enabled(i: int) -> bool:
	if i < 0 or i >= _buttons.size():
		return false
	return not _buttons[i].disabled

func status_text() -> String:
	return status.text

## 用鼠标"点"第 i 行（走和真点击同一条路）
func click_row(i: int) -> void:
	if i < 0 or i >= _buttons.size():
		return
	_buttons[i].emit_signal("pressed")
