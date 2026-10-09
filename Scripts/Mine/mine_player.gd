class_name MinePlayer extends CharacterBody2D

## 矿洞里的横版角色控制器。
##
## 手感上做了四件事，少哪一件都会"感觉不对"：
##   1) **土狼时间**（coyote time）—— 刚走出平台边缘的一小段时间里仍然能跳
##   2) **跳跃缓冲**（jump buffer）—— 落地前一点点按跳，落地瞬间自动起跳
##   3) **可变跳跃高度** —— 松开跳跃键就上升速度砍半，轻点小跳、长按大跳
##   4) 加减速分离 —— 起步有个加速过程，松手有个刹车过程，不是瞬间启停
##
## 左右沿用农场的 `left` / `right`（A / D）动作名，跳跃用新增的 `jump`（空格 / K）。
## 复用同一套 InputMap 是为了避免"进了矿洞 WASD 不动"这类经典 bug。

const SPEED: float = 112.0
const ACCEL: float = 900.0
const FRICTION: float = 1300.0
const GRAVITY: float = 760.0
const MAX_FALL: float = 420.0
const JUMP_VELOCITY: float = -238.0
## 松手时上升速度乘以这个系数（越小跳得越矮）
const JUMP_CUT: float = 0.42
const COYOTE_TIME: float = 0.10
const JUMP_BUFFER_TIME: float = 0.12

## 1 = 朝右，-1 = 朝左
var facing: int = 1

var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _was_on_floor: bool = false

@onready var sprite: Sprite2D = $Sprite2D

func _physics_process(delta: float) -> void:
	var dir: float = Input.get_axis("left", "right")

	# --- 水平：加速 / 刹车分离 ---
	if absf(dir) > 0.01:
		velocity.x = move_toward(velocity.x, dir * SPEED, ACCEL * delta)
		facing = 1 if dir > 0.0 else -1
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	# --- 重力 ---
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

	# --- 土狼时间 ---
	_was_on_floor = is_on_floor()
	if _was_on_floor:
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(0.0, _coyote - delta)

	# --- 跳跃缓冲 ---
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER_TIME
	else:
		_jump_buffer = maxf(0.0, _jump_buffer - delta)

	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0

	# --- 可变跳跃高度 ---
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT

	move_and_slide()

	if absf(velocity.x) > 1.0:
		sprite.flip_h = velocity.x < 0.0

func is_moving() -> bool:
	return absf(velocity.x) > 1.0
