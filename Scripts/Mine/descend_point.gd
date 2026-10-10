class_name DescendPoint extends Area2D

## 下潜点：矿洞最右边的竖井。走过去就下一层。
##
## **必须先拆掉关底**才让下去 —— 这样关底就不是"顺路打一下"，
## 而是通往更深处的门票。
##
## 下潜**不补火把**。所以站在井口那一刻的抉择是真的：
## 再往下走一层收益翻倍，但可能来不及带着东西回去。

signal descended(depth: int)

## 需要先拆掉关底吗
@export var require_boss: bool = true

var _used: bool = false

@onready var hint: Label = $Hint

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_refresh_hint()

func _refresh_hint() -> void:
	if hint == null:
		return
	if MineRun.is_deepest():
		hint.text = "已是最深处"
	elif require_boss and not MineRun.boss_down:
		hint.text = "先拆掉关底"
	else:
		hint.text = "↓ 第 %d 层" % (MineRun.depth + 1)

func can_descend() -> bool:
	if not MineRun.active or MineRun.is_deepest():
		return false
	if require_boss and not MineRun.boss_down:
		return false
	return true

func _on_body_entered(body: Node2D) -> void:
	if _used or not (body is MinePlayer):
		return
	if not can_descend():
		if MineRun.is_deepest():
			print("[矿洞] 已经是最深处了")
		else:
			print("[矿洞] 井口被封着，得先拆掉关底")
		return
	if not MineRun.descend():
		return
	_used = true
	descended.emit(MineRun.depth)
	# 重新载入本场景 —— MineLevel._ready() 会按新的层数铺地图、加强敌人。
	# 测试里不能真的重载（一重载后面就没法继续跑断言了），所以走同一个开关。
	if MineRun.scene_switch_enabled:
		get_tree().reload_current_scene()
