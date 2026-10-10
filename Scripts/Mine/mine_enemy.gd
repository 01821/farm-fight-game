class_name MineEnemy extends CharacterBody2D

## 矿洞里的怪。共用一套脚本，靠 `kind` 换外观和数值。
##
## 状态很简单：**巡逻 → 发现玩家就追 → 贴上去造成接触伤害**。
## 挨打时的**闪白 + 硬直 + 击退**在阶段 B 就做好了，这里只管"怎么动"。
##
## 飞行怪（蝙蝠）不吃重力，会缓慢地把自己的高度对齐玩家，再水平压过去。

signal died(enemy: MineEnemy)

const GRAVITY: float = 760.0
const MAX_FALL: float = 420.0
const HIT_STUN: float = 0.22
const KNOCKBACK_SPEED: float = 130.0
const KNOCKBACK_DECAY: float = 8.0
const FLASH_TIME: float = 0.12
const CONTACT_COOLDOWN: float = 0.9
## 发现玩家的范围（水平和垂直分开判，免得隔着几层平台就追过来）
const DETECT_RANGE: float = 96.0
const DETECT_HEIGHT: float = 44.0
const CHASE_SPEED_MULT: float = 1.45
const CONTACT_RANGE: float = 15.0
## 飞行怪追踪玩家高度的速度（像素/秒）
const FLY_TRACK_SPEED: float = 34.0

## 角色图集是 24×24 的 9 列 × 3 行网格
const CELL: int = 24

## kind → {名称, 图集格, 血量, 速度, 伤害, 是否飞行}
const KINDS: Array[Dictionary] = [
	{"name": "绿机兵", "cell": Vector2i(0, 0), "hp": 3, "speed": 26.0, "damage": 1, "fly": false},
	{"name": "蓝机兵", "cell": Vector2i(2, 0), "hp": 4, "speed": 20.0, "damage": 1, "fly": false},
	{"name": "红炸怪", "cell": Vector2i(6, 1), "hp": 2, "speed": 34.0, "damage": 1, "fly": false},
	{"name": "蝙蝠", "cell": Vector2i(7, 2), "hp": 2, "speed": 42.0, "damage": 1, "fly": true},
]

enum State { PATROL, CHASE }

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
var _state: int = State.PATROL
## 显示用的名字。**不要用 node.name** —— 运行时给节点改名会让 get_node("EnemyA") 之
## 类的路径查找失效（踩过一次：敌人全部找不到了，还以为是分组没注册）。
## 挨打僵直时间的倍率。Boss 会覆盖成很小的值 ——
## 不然玩家可以把它连击锁死，Boss 战变成"按住 F 不放"。
var stun_scale: float = 1.0
var _title: String = "怪"
var _player: MinePlayer

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	# ⚠️ Boss **不进 "mine_enemy" 分组**。它虽然继承了这个脚本，但概念上不是小怪 ——
	#    混进去会把所有"数小怪"的地方都算错（踩过一次，四个不相关的测试一起红）。
	#    Boss 自己加进 "mine_boss"，关卡会分别 hook 两个分组。
	if not is_boss():
		add_to_group("mine_enemy")
	_apply_kind()

## 子类覆盖成 true（Boss）
func is_boss() -> bool:
	return false

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

func state_name() -> String:
	return "追击" if _state == State.CHASE else "巡逻"

func is_chasing() -> bool:
	return _state == State.CHASE

func is_flying() -> bool:
	return _flying

func _physics_process(delta: float) -> void:
	_update_flash(delta)
	_contact_cd = maxf(0.0, _contact_cd - delta)
	_touch_player()

	# 击退优先：被打飞的这段时间不思考
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

	_player = _resolve_player()
	_think(delta)

	move_and_slide()
	if absf(velocity.x) > 0.01:
		sprite.flip_h = velocity.x < 0.0

## 「想什么、怎么动」都在这里。**子类覆盖这个方法就能换行为**（Boss 就是这么做的），
## 闪白 / 硬直 / 击退 / 受伤结算这些公共部分不用重写。
func _think(delta: float) -> void:
	var chasing: bool = _player != null and _can_see(_player)
	_state = State.CHASE if chasing else State.PATROL
	if chasing:
		_do_chase(delta)
	else:
		_do_patrol()

## 玩家只在矿洞场景里存在，缓存一下别每帧找
func _resolve_player() -> MinePlayer:
	if _player != null and is_instance_valid(_player):
		return _player
	return get_tree().get_first_node_in_group("mine_player") as MinePlayer

func _can_see(p: MinePlayer) -> bool:
	var d: Vector2 = p.global_position - global_position
	if absf(d.x) > DETECT_RANGE:
		return false
	# 飞行怪可以垂直追，地面怪只认差不多同一层的
	if _flying:
		return absf(d.y) < DETECT_HEIGHT * 2.0
	return absf(d.y) < DETECT_HEIGHT

func _do_chase(delta: float) -> void:
	var dx: float = _player.global_position.x - global_position.x
	var dir: float = signf(dx)
	if absf(dx) < 4.0:
		dir = 0.0
	_apply_gravity(delta)
	velocity.x = dir * _speed * CHASE_SPEED_MULT
	_fly_track(delta)

func _do_patrol() -> void:
	if not _flying and is_on_wall():
		patrol_dir = -patrol_dir
	velocity.x = float(patrol_dir) * _speed
	if _flying:
		# 飞行怪没有地面，用"撞到天花板/地面"来掉头，外加一点上下起伏
		velocity.y = sin(float(Engine.get_physics_frames()) * 0.06) * 18.0

## 飞行怪：把自己的高度缓慢对齐玩家
func _fly_track(delta: float) -> void:
	if not _flying:
		return
	var dy: float = _player.global_position.y - 12.0 - global_position.y
	velocity.y = clampf(dy * 3.0, -FLY_TRACK_SPEED, FLY_TRACK_SPEED)

func _apply_gravity(delta: float) -> void:
	if _flying:
		return
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

func _touch_player() -> void:
	if _contact_cd > 0.0:
		return
	var p := _resolve_player()
	if p == null or not is_instance_valid(p):
		return
	if global_position.distance_to(p.global_position) <= CONTACT_RANGE:
		if p.take_damage(_damage, global_position):
			_contact_cd = CONTACT_COOLDOWN

func _update_flash(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(0.0, _flash - delta)
	sprite.modulate = Color(3.0, 3.0, 3.0) if _flash > 0.0 else Color.WHITE

## amount = 伤害；from = 攻击者位置（决定往哪边飞，给 Vector2.INF 就不击退）
## knock = 击退强度，不同武器/技能给的不一样（巨剑推得比短剑远）
## 返回这次是不是**打死了**
func take_damage(amount: int, from: Vector2 = Vector2.INF, knock: float = KNOCKBACK_SPEED) -> bool:
	if _dead or amount <= 0:
		return false
	hp = maxi(0, hp - amount)
	_flash = FLASH_TIME
	_stun = HIT_STUN * stun_scale
	if from.is_finite():
		var away: Vector2 = global_position - from
		if away.length() > 0.01:
			var dir: Vector2 = away.normalized()
			# 主要往水平方向推，避免把怪顶到天上
			_knockback = Vector2(dir.x, dir.y * 0.25).normalized() * knock
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
