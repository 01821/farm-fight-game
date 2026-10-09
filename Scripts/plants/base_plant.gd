class_name BasePlant extends Node2D

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var timer: Timer = $Timer

@export var plantType:int = 0
@export var growTime:int = 3

var growStage:int = 0
var endStage:int = 4

func _ready() -> void:
	updateSprite()
	timer.wait_time = growTime
	timer.start()

func updateSprite():
	var _rect2 = Rect2(64 + 16 * growStage,16 * plantType,16,16)
	sprite_2d.set_region_rect(_rect2)

func _on_timer_timeout() -> void:
	growStage += 1
	if growStage == 3:
		growStage = 4
	updateSprite()
	if growStage == endStage:
		timer.stop()
