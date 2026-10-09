class_name MinePlayer extends CharacterBody2D

## 矿洞里的横版角色控制器。
##
## 移动手感上做了四件事，少哪一件都会"感觉不对"：
##   1) **土狼时间**（coyote time）—— 刚走出平台边缘的一小段时间里仍然能跳
##   2) **跳跃缓冲**（jump buffer）—— 落地前一点点按跳，落地瞬间自动起跳
##   3) **可变跳跃高度** —— 松开跳跃键就上升速度砍半，轻点小跳、长按大跳
##   4) 加减速分离 —— 起步有个加速过程，松手有个刹车过程，不是瞬间启停
##
## 打击感上做了四件事（阶段 B）：
##   闪白 / 受击硬直 / 击退 / **飘字伤害数字** —— 少一个都会"打上去没感觉"。
##
## 左右沿用农场的 `left` / `right`（A / D）动作名，跳跃用 `jump`（空格 / K），
## 攻击用农场的 `use_item`（F / J）。复用同一套 InputMap 是为了避免
## "进了矿洞 WASD 不动"这类经典 bug。

signal attacked(hit_count: int)
signal damaged(amount: int)
signal died

const MAX_HP: int = 6
## 受伤后的无敌时间。没有它的话贴着怪会一秒掉光血，手感极差。
const INVULN_TIME: float = 0.8
## 被撞飞时的初速度
const HURT_KNOCKBACK_X: float = 120.0
const HURT_KNOCKBACK_Y: float = -150.0

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

const ATTACK_COOLDOWN: float = 0.34
const ATTACK_TIME: float = 0.14
const ATTACK_DAMAGE: int = 1
## 判定框相对角色中心的水平偏移（朝右时；朝左时取负）
const ATTACK_OFFSET: float = 13.0

## 飘字场景，在场景文件里预先接好，不在代码里 load
@export var damage_number_scene: PackedScene

## 1 = 朝右，-1 = 朝左
var facing: int = 1

var hp: int = MAX_HP

var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _attack_cd: float = 0.0
var _slash_time: float = 0.0
var _invuln: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var slash: Polygon2D = $Slash
## 判定框是**预建的 Area2D**，一直开着当查询区域用 ——
## 这样 get_overlapping_bodies() 拿到的就是当前这一帧的重叠结果，
## 不用等一帧、也不用在运行时创建任何节点。
@onready var attack_box: Area2D = $AttackBox

func _ready() -> void:
	add_to_group("mine_player")

func _physics_process(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_update_invuln(delta)
	_update_slash(delta)

	var dir: float = Input.get_axis("left", "right")
	# 先定朝向，判定框才知道该摆在哪边
	if absf(dir) > 0.01:
		facing = 1 if dir > 0.0 else -1
	attack_box.position.x = ATTACK_OFFSET * float(facing)

	if Input.is_action_just_pressed("use_item"):
		attack()

	# --- 水平：加速 / 刹车分离 ---
	if absf(dir) > 0.01:
		velocity.x = move_toward(velocity.x, dir * SPEED, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	# --- 重力 ---
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

	# --- 土狼时间 ---
	if is_on_floor():
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

# --- 攻击 ---

## 挥砍。返回这一刀打中了几只；**冷却没到就返回 0**。
## 冷却检查放在这里而不是调用方 —— 这样无论谁调（键盘、AI、测试）都绕不过去。
func attack() -> int:
	if _attack_cd > 0.0:
		return 0
	_attack_cd = ATTACK_COOLDOWN
	_slash_time = ATTACK_TIME
	slash.visible = true
	var dir: float = float(facing)
	slash.scale = Vector2(dir * 0.55, 0.55)
	slash.modulate = Color(1, 1, 1, 0.95)

	var hit: int = 0
	for body in attack_box.get_overlapping_bodies():
		var enemy := body as MineEnemy
		if enemy == null or not is_instance_valid(enemy) or enemy.is_dead():
			continue
		enemy.take_damage(ATTACK_DAMAGE, global_position)
		spawn_damage_number(ATTACK_DAMAGE, enemy.global_position + Vector2(0, -24))
		hit += 1

	if hit > 0:
		Sfx.play("hit")
	else:
		print("[矿洞] 挥空了")
	attacked.emit(hit)
	return hit

## 在指定位置飘一个伤害数字。会实例化**预建的**飘字场景，不 new 节点。
func spawn_damage_number(amount: int, at: Vector2) -> void:
	if damage_number_scene == null:
		return
	var n := damage_number_scene.instantiate() as DamageNumber
	if n == null:
		return
	get_parent().add_child(n)
	n.global_position = at
	n.setup(str(amount))

func can_attack() -> bool:
	return _attack_cd <= 0.0

# --- 受伤 ---

## 返回这次有没有真的吃到伤害（无敌帧内会返回 false）
func take_damage(amount: int, from: Vector2 = Vector2.INF) -> bool:
	if _invuln > 0.0 or hp <= 0 or amount <= 0:
		return false
	hp = maxi(0, hp - amount)
	_invuln = INVULN_TIME
	Sfx.play("hurt")
	# 被撞飞一下，给玩家一个"被打到了"的即时反馈，也顺便拉开距离
	if from.is_finite():
		var dx: float = signf(global_position.x - from.x)
		if absf(dx) < 0.01:
			dx = -float(facing)
		velocity = Vector2(dx * HURT_KNOCKBACK_X, HURT_KNOCKBACK_Y)
	print("[矿洞] 玩家掉血 ", amount, "，剩 ", hp, "/", MAX_HP)
	damaged.emit(amount)
	if hp <= 0:
		print("[矿洞] 玩家倒下了")
		died.emit()
	return true

func is_invulnerable() -> bool:
	return _invuln > 0.0

## 无敌期间让角色一闪一闪，玩家一眼就知道"现在是安全的"
func _update_invuln(delta: float) -> void:
	if _invuln <= 0.0:
		return
	_invuln = maxf(0.0, _invuln - delta)
	if _invuln <= 0.0:
		sprite.modulate = Color.WHITE
	else:
		var blink: bool = fmod(_invuln, 0.16) < 0.08
		sprite.modulate = Color(1, 1, 1, 0.35) if blink else Color.WHITE

func _update_slash(delta: float) -> void:
	if _slash_time <= 0.0:
		return
	_slash_time = maxf(0.0, _slash_time - delta)
	if _slash_time <= 0.0:
		slash.visible = false
		return
	var t: float = 1.0 - _slash_time / ATTACK_TIME
	var dir: float = float(facing)
	var grow: float = lerpf(0.55, 1.35, t)
	slash.scale = Vector2(dir * grow, grow)
	slash.rotation = lerpf(-0.6, 0.5, t) * dir
	slash.modulate = Color(1, 1, 1, lerpf(0.95, 0.0, t))

func is_moving() -> bool:
	return absf(velocity.x) > 1.0
