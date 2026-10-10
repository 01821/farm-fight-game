class_name MinePlayer extends CharacterBody2D

## 矿洞里的横版角色控制器。
##
## 移动手感（阶段 A）—— 少哪一件都会"感觉不对"：
##   土狼时间 / 跳跃缓冲 / 可变跳跃高度 / 加减速分离
## 打击感（阶段 B）—— 少哪一个都会"打上去没感觉"：
##   闪白 / 硬直 / 击退 / 飘字伤害数字
## 战斗系统（阶段 D）：
##   `L` 换武器（短剑 ↔ 巨剑，伤害/射程/速度都不同）
##   `H U I O` 四个技能：重斩 / 旋风斩 / 冲刺 / 治疗（有冷却和能量）
##
## 键位刻意和农场的 `1~5 选作物` **错开** —— 两套动作在同一个 InputMap 里，
## 共用键位会在矿洞里误触发"选作物"。

signal attacked(hit_count: int)
signal damaged(amount: int)
signal died
signal weapon_changed(id: int)
signal skill_used(id: int)

const SPEED: float = 112.0
const ACCEL: float = 900.0
const FRICTION: float = 1300.0
const GRAVITY: float = 760.0
const MAX_FALL: float = 420.0
const JUMP_VELOCITY: float = -238.0
const JUMP_CUT: float = 0.42
const COYOTE_TIME: float = 0.10
const JUMP_BUFFER_TIME: float = 0.12

const ATTACK_TIME: float = 0.14
## 判定框竖直中心相对角色脚底的高度
const BOX_CENTER_Y: float = -10.0

const MAX_HP: int = 6
## 受伤后的无敌时间。没有它的话贴着怪会一秒掉光血，手感极差。
const INVULN_TIME: float = 0.8
const HURT_KNOCKBACK_X: float = 120.0
const HURT_KNOCKBACK_Y: float = -150.0

## 冲刺撞到敌人时的伤害和击退
const DASH_DAMAGE: int = 1
const DASH_KNOCK: float = 90.0

## --- 手感：屏幕震动 ---
## 幅度用"像素"、时间用"秒"。**取最强的那一次，不累加** ——
## 连续的小震动叠成一个大抖会让人头晕。
const SHAKE_HIT: float = 2.6
const SHAKE_HIT_TIME: float = 0.12
const SHAKE_HURT: float = 4.2
const SHAKE_HURT_TIME: float = 0.26
const SHAKE_SKILL: float = 5.0
const SHAKE_SKILL_TIME: float = 0.2
const SHAKE_DEATH: float = 7.0
const SHAKE_DEATH_TIME: float = 0.5
## 落地扬尘的最小下落速度（轻轻跳一下不该扬尘）
const LAND_DUST_SPEED: float = 150.0

## 消耗品：三种药，分别绑在 1 / 2 / 3 上。
## 和技能是**两套分开的资源**（参考游戏里技能是 H U I O、物品是 1/2/3）：
## 技能吃能量，药吃瓶数。
enum Potion { HEAL, ENERGY, POWER }

const POTION_START: Array[int] = [3, 2, 1]
const POTION_INFO: Array[Dictionary] = [
	{"name": "回血药", "key": "1", "desc": "回 2 点生命"},
	{"name": "能量药", "key": "2", "desc": "回 12 点能量"},
	{"name": "全力药", "key": "3", "desc": "生命与能量全满"},
]
const HEAL_AMOUNT: int = 2
const ENERGY_AMOUNT: int = 12

## 飘字场景，在场景文件里预先接好，不在代码里 load
@export var damage_number_scene: PackedScene

var facing: int = 1
var hp: int = MAX_HP
var weapon_id: int = 0
var energy: float = float(MineCombatData.ENERGY_MAX)
## 三种药各剩几瓶
var potions: Array[int] = [3, 2, 1]
## P 键技能表开着没有
var skill_list_open: bool = false
## 每个技能的剩余冷却
var skill_cd: Array[float] = [0.0, 0.0, 0.0, 0.0]

var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _attack_cd: float = 0.0
var _slash_time: float = 0.0
var _invuln: float = 0.0
var _dash_time: float = 0.0
var _dash_speed: float = 0.0
var _dash_hit: Dictionary = {}
var _reach: float = 24.0

## 屏幕震动：剩余时间 / 总时长 / 幅度
var _shake_left: float = 0.0
var _shake_len: float = 0.001
var _shake_amp: float = 0.0
## 上一帧是否站在地上（用来判断"刚落地"）
var _was_on_floor: bool = true
## 上一帧的下落速度（决定落地时扬不扬尘）
var _last_fall_speed: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var slash: Polygon2D = $Slash
## 判定框是**预建的 Area2D**，一直开着当查询区域用 ——
## 这样 get_overlapping_bodies() 拿到的就是当前这一帧的重叠结果。
@onready var attack_box: Area2D = $AttackBox
@onready var _attack_shape_node: CollisionShape2D = $AttackBox/CollisionShape2D
@onready var camera: Camera2D = $Camera2D
@onready var hit_sparks: CPUParticles2D = $HitSparks
@onready var dust_puff: CPUParticles2D = $DustPuff

## 技能的判定范围是**每次都不一样**的（重斩是长条、旋风斩是方块），
## 而 Area2D 的重叠结果要等一个物理帧才刷新，技能判定不能等。
## 所以技能用**形状查询**即时结算。
## 注意：这里创建的是 RectangleShape2D / PhysicsShapeQueryParameters2D，
## 都是 Resource 不是 Node —— 项目约定禁止的是动态创建节点。
var _skill_shape: RectangleShape2D
var _skill_query: PhysicsShapeQueryParameters2D

func _ready() -> void:
	add_to_group("mine_player")
	# 让判定框的形状成为本实例独有的：换武器要改它的尺寸，
	# 而 .tscn 里的 sub_resource 默认是多个实例共享的。
	if _attack_shape_node.shape != null:
		_attack_shape_node.shape = _attack_shape_node.shape.duplicate()
	_skill_shape = RectangleShape2D.new()
	_skill_shape.size = Vector2(24, 24)
	_skill_query = PhysicsShapeQueryParameters2D.new()
	_skill_query.shape = _skill_shape
	_skill_query.collision_mask = 4     # 只找敌人层
	_skill_query.collide_with_areas = false
	_apply_weapon()

func _physics_process(delta: float) -> void:
	_tick_timers(delta)

	var dir: float = Input.get_axis("left", "right")
	if absf(dir) > 0.01 and _dash_time <= 0.0:
		facing = 1 if dir > 0.0 else -1
	attack_box.position = Vector2(_reach * 0.5 * float(facing), BOX_CENTER_Y)

	# --- 冲刺中：接管一切移动 ---
	if _dash_time > 0.0:
		_dash_time = maxf(0.0, _dash_time - delta)
		velocity = Vector2(float(facing) * _dash_speed, 0.0)
		_dash_damage_touch()
		move_and_slide()
		return

	# --- 输入 ---
	if Input.is_action_just_pressed("switch_weapon"):
		switch_weapon()
	if Input.is_action_just_pressed("use_item"):
		attack()
	if Input.is_action_just_pressed("skill_list"):
		skill_list_open = not skill_list_open
		print("[矿洞] 技能表 ", "打开" if skill_list_open else "收起")
	if Input.is_action_just_pressed("item_1"):
		use_potion(Potion.HEAL)
	if Input.is_action_just_pressed("item_2"):
		use_potion(Potion.ENERGY)
	if Input.is_action_just_pressed("item_3"):
		use_potion(Potion.POWER)
	for i in range(MineCombatData.skill_count()):
		if Input.is_action_just_pressed("skill_%d" % (i + 1)):
			cast_skill(i)

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

	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT

	move_and_slide()
	_last_fall_speed = velocity.y
	_check_landing()

	if absf(velocity.x) > 1.0:
		sprite.flip_h = velocity.x < 0.0

func _tick_timers(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_update_invuln(delta)
	_update_slash(delta)
	_update_shake(delta)
	energy = minf(energy + MineCombatData.ENERGY_REGEN * delta, float(MineCombatData.ENERGY_MAX))
	for i in range(skill_cd.size()):
		skill_cd[i] = maxf(0.0, skill_cd[i] - delta)

# --- 手感：屏幕震动与打击粒子 ---

## 抖一下屏幕。**取更强的那一次，不累加** —— 连续小震动叠成大抖会让人晕。
func shake(amp: float, dur: float) -> void:
	if amp >= _shake_amp or _shake_left <= 0.0:
		_shake_amp = amp
		_shake_len = maxf(dur, 0.001)
	_shake_left = maxf(_shake_left, dur)

func is_shaking() -> bool:
	return _shake_left > 0.0

## 震动的幅度随时间线性衰减到 0，抖完把摄像机偏移归零
func _update_shake(delta: float) -> void:
	if _shake_left <= 0.0:
		if camera.offset != Vector2.ZERO:
			camera.offset = Vector2.ZERO
		_shake_amp = 0.0
		return
	_shake_left = maxf(0.0, _shake_left - delta)
	var k: float = _shake_amp * (_shake_left / _shake_len)
	camera.offset = Vector2(randf_range(-k, k), randf_range(-k, k))

## 在指定位置炸一簇火星。用的是**预建的粒子节点**，只改位置然后重播。
func spawn_hit_sparks(at: Vector2) -> void:
	if hit_sparks == null:
		return
	hit_sparks.global_position = at
	hit_sparks.restart()

## 脚底扬尘
func spawn_land_dust() -> void:
	if dust_puff == null:
		return
	dust_puff.global_position = global_position + Vector2(0, -2)
	dust_puff.restart()

## 从空中落到地面时扬一次尘。轻轻跳一下（下落速度不够）不扬。
func _check_landing() -> void:
	var on_floor: bool = is_on_floor()
	if on_floor and not _was_on_floor and _last_fall_speed > LAND_DUST_SPEED:
		spawn_land_dust()
	_was_on_floor = on_floor

# --- 武器 ---

func switch_weapon() -> int:
	weapon_id = (weapon_id + 1) % MineCombatData.weapon_count()
	_apply_weapon()
	print("[矿洞] 换成 ", MineCombatData.weapon_name(weapon_id))
	weapon_changed.emit(weapon_id)
	return weapon_id

func _apply_weapon() -> void:
	var w := MineCombatData.get_weapon(weapon_id)
	_reach = float(w["reach"])
	if _attack_shape_node != null and _attack_shape_node.shape is RectangleShape2D:
		(_attack_shape_node.shape as RectangleShape2D).size = Vector2(_reach, float(w["box_height"]))
	slash.color = w["color"]

func weapon_name() -> String:
	return MineCombatData.weapon_name(weapon_id)

# --- 普攻 ---

## 挥砍。返回这一刀打中了几只；**冷却没到就返回 0**。
## 冷却检查放在这里而不是调用方 —— 这样无论谁调（键盘、AI、测试）都绕不过去。
func attack() -> int:
	if _attack_cd > 0.0:
		return 0
	var w := MineCombatData.get_weapon(weapon_id)
	_attack_cd = float(w["cooldown"])
	_slash_time = ATTACK_TIME
	slash.visible = true
	slash.scale = Vector2(float(facing) * 0.55, 0.55)
	slash.modulate = Color(1, 1, 1, 0.95)

	var dmg: int = int(w["damage"])
	var knock: float = float(w["knock"])
	var hit: int = 0
	for body in attack_box.get_overlapping_bodies():
		var enemy := body as MineEnemy
		if enemy == null or not is_instance_valid(enemy) or enemy.is_dead():
			continue
		enemy.take_damage(dmg, global_position, knock)
		spawn_damage_number(dmg, enemy.global_position + Vector2(0, -24))
		hit += 1

	if hit > 0:
		Sfx.play("hit")
		# 打中的手感：火星 + 抖屏
		spawn_hit_sparks(global_position + Vector2(float(facing) * _reach * 0.6, BOX_CENTER_Y))
		shake(SHAKE_HIT, SHAKE_HIT_TIME)
	else:
		print("[矿洞] 挥空了")
	attacked.emit(hit)
	return hit

func can_attack() -> bool:
	return _attack_cd <= 0.0

# --- 消耗品 ---

## 用一瓶药。返回有没有用成（没药 / 用了也是白用 都会返回 false）。
## **白用的情况不扣药** —— 满血喝回血药、满能量喝能量药都会被拒。
func use_potion(id: int) -> bool:
	if id < 0 or id >= potions.size():
		return false
	if potions[id] <= 0:
		print("[矿洞] ", String(POTION_INFO[id]["name"]), " 用完了")
		return false
	if not _potion_has_effect(id):
		print("[矿洞] ", String(POTION_INFO[id]["name"]), " 现在用是浪费，留着吧")
		return false
	potions[id] -= 1
	var before_hp: int = hp
	var before_en: float = energy
	match id:
		Potion.HEAL:
			hp = mini(hp + HEAL_AMOUNT, MAX_HP)
		Potion.ENERGY:
			energy = minf(energy + float(ENERGY_AMOUNT), float(MineCombatData.ENERGY_MAX))
		Potion.POWER:
			hp = MAX_HP
			energy = float(MineCombatData.ENERGY_MAX)
	Sfx.play("buy")
	print("[矿洞] 用了 ", String(POTION_INFO[id]["name"]),
		"：血 ", before_hp, "→", hp, "，能量 ", int(before_en), "→", int(energy),
		"，还剩 ", potions[id], " 瓶")
	return true

## 这瓶药现在有没有意义（满了就不该浪费）
func _potion_has_effect(id: int) -> bool:
	match id:
		Potion.HEAL:
			return hp < MAX_HP
		Potion.ENERGY:
			return energy < float(MineCombatData.ENERGY_MAX)
		Potion.POWER:
			return hp < MAX_HP or energy < float(MineCombatData.ENERGY_MAX)
	return false

func can_use_potion(id: int) -> bool:
	if id < 0 or id >= potions.size():
		return false
	return potions[id] > 0 and _potion_has_effect(id)

func potion_count(id: int) -> int:
	if id < 0 or id >= potions.size():
		return 0
	return potions[id]

func potion_name(id: int) -> String:
	if id < 0 or id >= POTION_INFO.size():
		return "?"
	return String(POTION_INFO[id]["name"])

# --- 技能 ---

func skill_ready(id: int) -> bool:
	if not MineCombatData.is_valid_skill(id):
		return false
	return skill_cd[id] <= 0.0 and energy >= float(MineCombatData.skill_field(id, "cost", 0))

## 放技能。返回有没有放出去（冷却中 / 能量不够都会返回 false）。
func cast_skill(id: int) -> bool:
	if not skill_ready(id):
		return false
	var s := MineCombatData.get_skill(id)
	energy -= float(s["cost"])
	skill_cd[id] = float(s["cooldown"])
	match String(s["kind"]):
		"heavy":
			_skill_heavy(s)
		"spin":
			_skill_spin(s)
		"dash":
			_skill_dash(s)
		"heal":
			_skill_heal(s)
	shake(SHAKE_SKILL, SHAKE_SKILL_TIME)
	print("[矿洞] 放技能 ", MineCombatData.skill_name(id), "（剩能量 ", int(energy), "）")
	skill_used.emit(id)
	return true

func _skill_heavy(s: Dictionary) -> void:
	var size := Vector2(float(s["reach"]), float(s["box_height"]))
	var center := Vector2(float(facing) * float(s["reach"]) * 0.5, BOX_CENTER_Y)
	var dmg: int = int(s["damage"])
	var n: int = 0
	for e in query_rect(size, center):
		e.take_damage(dmg, global_position, 240.0)
		spawn_damage_number(dmg, e.global_position + Vector2(0, -24))
		n += 1
	_flash_slash(size, center, Color(1.0, 0.55, 0.25))
	print("[矿洞] 重斩命中 ", n, " 只")

func _skill_spin(s: Dictionary) -> void:
	var r: float = float(s["radius"])
	var size := Vector2(r * 2.0, r * 2.0)
	var dmg: int = int(s["damage"])
	var n: int = 0
	for e in query_rect(size, Vector2(0, BOX_CENTER_Y)):
		e.take_damage(dmg, global_position, 200.0)
		spawn_damage_number(dmg, e.global_position + Vector2(0, -24))
		n += 1
	_flash_slash(size, Vector2(0, BOX_CENTER_Y), Color(0.7, 0.9, 1.0))
	print("[矿洞] 旋风斩命中 ", n, " 只")

func _skill_dash(s: Dictionary) -> void:
	_dash_time = float(s["duration"])
	_dash_speed = float(s["speed"])
	_dash_hit.clear()
	# 突进期间无敌（用无敌帧实现，顺便让角色闪起来）
	_invuln = maxf(_invuln, _dash_time + 0.06)
	velocity = Vector2(float(facing) * _dash_speed, 0.0)
	print("[矿洞] 冲刺")

## 冲刺途中撞到谁就伤谁，但同一个目标一次冲刺只吃一下
func _dash_damage_touch() -> void:
	for e in query_rect(Vector2(22, 24), Vector2(0, BOX_CENTER_Y)):
		var key: int = e.get_instance_id()
		if _dash_hit.has(key):
			continue
		_dash_hit[key] = true
		e.take_damage(DASH_DAMAGE, global_position, DASH_KNOCK)
		spawn_damage_number(DASH_DAMAGE, e.global_position + Vector2(0, -24))

func _skill_heal(s: Dictionary) -> void:
	var amount: int = int(s["heal"])
	var before: int = hp
	hp = mini(hp + amount, MAX_HP)
	print("[矿洞] 治疗 ", hp - before, " 点（", before, " -> ", hp, "）")

# --- 判定辅助 ---

## 在角色周围做一次矩形范围查询，立刻拿到结果（不等物理帧）
func query_rect(size: Vector2, offset: Vector2) -> Array[MineEnemy]:
	var out: Array[MineEnemy] = []
	if _skill_query == null:
		return out
	_skill_shape.size = size
	_skill_query.transform = Transform2D(0.0, global_position + offset)
	for r in get_world_2d().direct_space_state.intersect_shape(_skill_query, 16):
		var e := r.get("collider") as MineEnemy
		if e != null and is_instance_valid(e) and not e.is_dead():
			out.append(e)
	return out

## 技能命中时用 Slash 节点闪一下，形状和后坐力跟着技能走
func _flash_slash(size: Vector2, offset: Vector2, color: Color) -> void:
	slash.visible = true
	slash.color = color
	slash.position = offset + Vector2(0, -2)
	slash.scale = size / 24.0
	slash.rotation = 0.0
	slash.modulate = Color(1, 1, 1, 0.85)
	_slash_time = 0.2

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

# --- 受伤 ---

## 返回这次有没有真的吃到伤害（无敌帧内会返回 false）
func take_damage(amount: int, from: Vector2 = Vector2.INF) -> bool:
	if _invuln > 0.0 or hp <= 0 or amount <= 0:
		return false
	hp = maxi(0, hp - amount)
	_invuln = INVULN_TIME
	Sfx.play("hurt")
	shake(SHAKE_HURT, SHAKE_HURT_TIME)
	if from.is_finite():
		var dx: float = signf(global_position.x - from.x)
		if absf(dx) < 0.01:
			dx = -float(facing)
		velocity = Vector2(dx * HURT_KNOCKBACK_X, HURT_KNOCKBACK_Y)
	print("[矿洞] 玩家掉血 ", amount, "，剩 ", hp, "/", MAX_HP)
	damaged.emit(amount)
	if hp <= 0:
		shake(SHAKE_DEATH, SHAKE_DEATH_TIME)
		print("[矿洞] 玩家倒下了")
		died.emit()
	return true

func is_invulnerable() -> bool:
	return _invuln > 0.0

func is_dashing() -> bool:
	return _dash_time > 0.0

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
	if t < 0.0:
		t = 0.0
	var dir: float = float(facing)
	var grow: float = lerpf(0.55, 1.35, minf(t, 1.0))
	slash.scale = Vector2(dir * grow, grow)
	slash.rotation = lerpf(-0.6, 0.5, minf(t, 1.0)) * dir
	slash.modulate = Color(1, 1, 1, lerpf(0.95, 0.0, minf(t, 1.0)))

func is_moving() -> bool:
	return absf(velocity.x) > 1.0
