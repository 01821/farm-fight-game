class_name BasePlant extends Node2D

## 作物：种下后不会自己生长，必须浇水。
## 一次浇水推进一个生长阶段，随后自动变干（下一级要再浇一次）。

signal stage_changed(stage: int)
signal matured
signal watered

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var timer: Timer = $Timer
@onready var wet_mark: Polygon2D = $WetMark

@export var plantType: int = 0
@export var growTime: float = 3.0

var growStage: int = 0
var endStage: int = 4
var is_watered: bool = false

func _ready() -> void:
	timer.one_shot = true
	timer.wait_time = growTime
	updateSprite()
	_updateWetMark()

func is_mature() -> bool:
	return growStage >= endStage

func can_water() -> bool:
	return not is_mature() and not is_watered

## 返回 true 表示这次浇水生效了
func water() -> bool:
	if not can_water():
		return false
	is_watered = true
	_updateWetMark()
	timer.start()
	watered.emit()
	return true

func _on_timer_timeout() -> void:
	if is_mature():
		return
	growStage += 1
	is_watered = false
	_updateWetMark()
	updateSprite()
	stage_changed.emit(growStage)
	if is_mature():
		matured.emit()

func updateSprite() -> void:
	sprite_2d.region_rect = Rect2(64 + 16 * growStage, 16 * plantType, 16, 16)

func _updateWetMark() -> void:
	wet_mark.visible = is_watered
