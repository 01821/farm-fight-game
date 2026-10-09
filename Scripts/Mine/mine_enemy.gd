class_name MineEnemy extends CharacterBody2D

## 矿洞里的怪。共用一套脚本，靠 `kind` 换外观和数值。
##
## 行为很朴素（左右巡逻 + 撞墙掉头），因为阶段 B 的重点是**打击感**：
## 挨打要有闪白、硬直、击退、飘字，这四样少一个都会"打上去没感觉"。

signal died(enemy: MineEnemy)

const GRAVITY: float = 760.0
const MAX_FALL: float = 420.0
const HIT_STUN: float = 0.22
const KNOCKBACK_SPEED: float = 130.0
const KNOCKBACK_DECAY: float = 8.0
const FLASH_TIME: float = 0.12
const CONTACT_DAMAGE: int = 1
const CONTACT_COOLDOWN: float = 1.0

## 角色图集是 24×24 的 9 列 × 3 行网格
const CELL: int = 24

## kind → {名称, 图集格, 血量, 速度, 伤害, 是否飞行}
const KINDS: Array[Dictionary] = [
	{"name": "绿机兵", "cell": Vector2i(0, 0), "hp": 3, "speed": 26.0, "damage": 1, "fly": false},
	{"name": "蓝机兵", "cell": Vector2i(2, 0), "hp": 4, "speed": 20.0, "damage": 1, "fly": false},
	{"name": "红炸怪", "cell": Vector2i(6, 1), "hp": 2, "speed": 34.0, "damage": 1, "fly": false},
	{"name": "蝙蝠", "cell": Vector2i(7, 2), "hp": 2, "speed": 42.0, "damage": 1, "fly": true},
]

@export var kind: int = 0
## 巡逻方向，1 = 右
@export var patrol_dir: int = 1

var hp: int = 3
var max_hp: int = 3

var _speed: float = 26.0
var _damage: int = 1
var _flying: bool = false
var _knockback: Vector2 = Vector2.ZERO
var _stun: float = 0.0
var _flash: float = 0.0
var _contact_cd: float = 0.0
var _dead: bool = false
var _spawn: Vector2
## 显示用的名字。**不要用 node.name** —— 运行时给节点改名会让 get_node("EnemyA") 之
## 类的路径查找失效（踩过一次：敌人全部找不到了，还以为是分组没注册）。
var _title: String = "怪"

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("mine_enemy")
	_apply_kind()
	_spawn = global_position

func _apply_kind() -> void:
	var k: int = clampi(kind, 0, KINDS.size() - 1)
	var d: Dictionary = KINDS[k]
	var cell: Vector2i = d["cell"]
	sprite.region_rect = Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL)
	max_hp = int(d["hp"])
	hp = max_hp
	_speed = float(d["speed"])
	_damage = int(d["damage"])
	_flying = bool(d["fly"])
	_title = String(d["name"])

func display_name() -> String:
	return _title

func _physics_process(delta: float) -> void:
	_update_flash(delta)
	_contact_cd = maxf(0.0, _contact_cd - delta)

	# 击退优先：被打飞的这段时间不巡逻
	if _knockback.length() > 2.0:
		velocity = _knockback
		move_and_slide()
		_knockback = _knockback.lerp(Vector2.ZERO, minf(1.0, KNOCKBACK_DECAY * delta))
		return

	# 受击硬直：站住不动
	if _stun > 0.0:
		_stun = maxf(0.0, _stun - delta)
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		_apply_gravity(delta)
		move_and_slide()
		return

	_apply_gravity(delta)
	if not _flying and is_on_wall():
		patrol_dir = -patrol_dir
	velocity.x = float(patrol_dir) * _speed
	move_and_slide()
	if absf(velocity.x) > 0.01:
		sprite.flip_h = velocity.x < 0.0

func _apply_gravity(delta: float) -> void:
	if _flying:
		velocity.y = 0.0
		return
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

func _update_flash(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(0.0, _flash - delta)
	sprite.modulate = Color(3.0, 3.0, 3.0) if _flash > 0.0 else Color.WHITE

## amount = 伤害；from = 攻击者位置（决定往哪边飞，给 Vector2.INF 就不击退）
## 返回这次是不是**打死了**
func take_damage(amount: int, from: Vector2 = Vector2.INF) -> bool:
	if _dead or amount <= 0:
		return false
	hp = maxi(0, hp - amount)
	_flash = FLASH_TIME
	_stun = HIT_STUN
	if from.is_finite():
		var away: Vector2 = global_position - from
		if away.length() > 0.01:
			var dir: Vector2 = away.normalized()
			# 主要往水平方向推，避免把怪顶到天上
			_knockback = Vector2(dir.x, dir.y * 0.25).normalized() * KNOCKBACK_SPEED
	print("[矿洞] ", display_name(), " 挨了 ", amount, " 点，剩 ", hp, "/", max_hp)
	if hp <= 0:
		_dead = true
		died.emit(self)
		queue_free()
		return true
	return false

func is_dead() -> bool:
	return _dead

func is_stunned() -> bool:
	return _stun > 0.0

func knockback_len() -> float:
	return _knockback.length()
