class_name DialoguePanel extends CanvasLayer

## 对话框（**鼠标能点**）。农场里原来没有一张会回应的脸，
## 所有建筑都只是功能；这个面板是"有人在跟你说话"这件事的出口。
##
## 整屏预建：名字 + 台词 + 两个按钮（交谈 / 再见）。

var is_open: bool = false
var _npc: Npc

@onready var backdrop: ColorRect = $Backdrop
@onready var name_label: Label = $NameLabel
@onready var line_label: Label = $LineLabel
@onready var trade_button: Button = $Buttons/TradeButton
@onready var bye_button: Button = $Buttons/ByeButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("dialogue_panel")
	trade_button.pressed.connect(_on_trade)
	bye_button.pressed.connect(func(): set_open(false))
	set_open(false)

func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("pause"):
		set_open(false)
		get_viewport().set_input_as_handled()

## 跟某个 NPC 开始对话
func talk_to(npc: Npc) -> void:
	_npc = npc
	set_open(true)

func set_open(open: bool) -> void:
	is_open = open
	for n in [backdrop, name_label, line_label, trade_button, bye_button]:
		n.visible = open
	if open:
		_refresh()
	get_tree().paused = open

func _refresh() -> void:
	if _npc == null:
		return
	name_label.text = _npc.npc_name
	line_label.text = _npc.current_line()
	trade_button.text = _npc.request_text()
	# 不能交易时按钮变暗、点不动 —— "给不了"和"能给了"一眼能分清
	var can: bool = _npc.can_trade()
	trade_button.disabled = not can
	trade_button.modulate = Color(1, 1, 1, 1) if can else Color(0.6, 0.6, 0.68, 1)

func _on_trade() -> void:
	if _npc == null:
		return
	if _npc.trade():
		_refresh()
	else:
		line_label.text = "……不够。再下去两趟吧。"

## 给测试读的
func line_text() -> String:
	return line_label.text

func name_text() -> String:
	return name_label.text

func trade_text() -> String:
	return trade_button.text

func trade_enabled() -> bool:
	return not trade_button.disabled

func click_trade() -> void:
	trade_button.emit_signal("pressed")
