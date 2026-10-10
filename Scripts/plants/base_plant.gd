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
var endStage: int = CropData.MAX_STAGE
var is_watered: bool = false
## 这株已经被浇了几遍。**干旱天要浇两遍才算浇透。**
##
## 为什么不是把 is_watered 直接换成计数：它是**"浇透了没有"**这个语义，
## 别处（生长计时、读档、雨水）都在按布尔量用它。
## 加一个"浇了几遍"在旁边，语义不变、老代码全不用动。
var water_passes: int = 0

func _ready() -> void:
	timer.one_shot = true
	timer.wait_time = growTime
	updateSprite()
	_updateWetMark()

func is_mature() -> bool:
	return growStage >= endStage

func can_water() -> bool:
	return not is_mature() and not is_watered

## 今天浇透需要几遍？干旱天是 2，平时是 1。
## 天气不在场时（比如单独跑作物的单元测试）按 1 算。
func water_need() -> int:
	if Weather.instance == null:
		return 1
	return Weather.instance.water_passes_needed()

## 只是被浇湿了表面、还没浇透
func is_damp() -> bool:
	return water_passes > 0 and not is_watered

## 返回 true 表示这次浇水生效了
func water() -> bool:
	if not can_water():
		return false
	water_passes += 1
	if water_passes >= water_need():
		is_watered = true
		timer.start()
		watered.emit()
	else:
		print("[农田] 只浇湿了表面（今天要浇 ", water_need(), " 遍才透）")
	_updateWetMark()
	return true

func _on_timer_timeout() -> void:
	if is_mature():
		return
	growStage += 1
	is_watered = false
	water_passes = 0
	_updateWetMark()
	updateSprite()
	stage_changed.emit(growStage)
	if is_mature():
		matured.emit()

func updateSprite() -> void:
	sprite_2d.region_rect = Rect2(16 * CropData.column_for_stage(growStage), 16 * plantType, 16, 16)

## 湿痕在"浇湿了但没透"的时候也要显示，而且调暗一点 ——
## 玩家一眼能看出"我浇过了，但还不够"，不用去猜为什么没动静。
func _updateWetMark() -> void:
	wet_mark.visible = is_watered or is_damp()
	wet_mark.modulate = Color(1, 1, 1, 1) if is_watered else Color(1, 1, 1, 0.55)

func to_save_data() -> Dictionary:
	return {
		"type": plantType, "stage": growStage,
		"watered": is_watered, "passes": water_passes,
	}

## 读档用。必须在 add_child 之后调用（此时 _ready 已经跑过，wet_mark 等已就绪）。
func apply_save_data(d: Dictionary) -> void:
	plantType = int(d.get("type", 0))
	growStage = clampi(int(d.get("stage", 0)), 0, endStage)
	is_watered = bool(d.get("watered", false)) and not is_mature()
	water_passes = maxi(0, int(d.get("passes", 0)))
	updateSprite()
	_updateWetMark()
	if is_watered:
		timer.start()
