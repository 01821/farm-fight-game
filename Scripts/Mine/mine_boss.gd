class_name MineBoss extends MineEnemy

## 矿洞深处的关底 Boss：一台老式采掘机械。
##
## 继承 MineEnemy，把闪白 / 硬直 / 击退 / 掉落这些公共部分白拿；
## 只覆盖 `_think()` —— 也就是"想什么、怎么动"。
##
## 行为循环：
##   IDLE（没发现玩家）→ CHASE（慢慢逼近）→ WINDUP（原地蓄力，**闪红预警**）
##   → CHARGE（高速冲撞，撞到伤害更高）→ RECOVER（硬直喘息）→ 回 CHASE
##
## 蓄力那一步是刻意的：**Boss 的动作必须能被预判**，否则玩家只会觉得"莫名其妙被撞飞"。
## 不预告的攻击不叫难度，叫不讲理。

signal engaged

enum Phase { IDLE, CHASE, WINDUP, CHARGE, RECOVER }

## 进入战斗的距离
const ENGAGE_RANGE: float = 170.0
const CHASE_SPEED: float = 20.0
const WINDUP_TIME: float = 0.7
const CHARGE_TIME: float = 0.62
const CHARGE_SPEED: float = 235.0
const RECOVER_TIME: float = 0.85
## 两次冲撞之间至少隔这么久
const CHARGE_COOLDOWN: float = 2.4
## 「逼近」相位每隔这么久重新判断一次要不要冲。
## ⚠️ 不能给逼近设一个很大的计时器 —— 相位推进是靠"计时到了"触发的，
##    设成 999 会让它永远卡在逼近、**一次都不冲**（踩过）。
const CHASE_RECHECK: float = 0.25
## 蓄力时闪的颜色（预警）
const WARN_COLOR := Color(2.4, 0.7, 0.5)

@export var boss_hp: int = 24
@export var boss_name: String = "采掘机械"
## 冲撞时撞到人的伤害（平时接触是 1）
@export var charge_damage: int = 2

var _phase: int = Phase.IDLE
var _phase_t: float = 0.0
var _charge_cd: float = 0.0
var _charge_dir: float = 1.0
var _engaged: bool = false

## 角色图集是 24×24 的 9 列 × 3 行网格
## （注意：父类 MineEnemy 已经有同名的 CELL 常量，所以这里换个名字）
const BOSS_CELL_PX: int = 24
## 行 2 列 4 = 那台大型蓝色机械，是图集里最像"关底"的一张
const BOSS_CELL := Vector2i(4, 2)

func _apply_kind() -> void:
	# Boss **不走 KINDS 表**：外观和数值都由自己决定
	sprite.region_rect = Rect2(BOSS_CELL.x * BOSS_CELL_PX, BOSS_CELL.y * BOSS_CELL_PX, BOSS_CELL_PX, BOSS_CELL_PX)
	_title = boss_name

func _ready() -> void:
	super._ready()
	# Boss 不进 "mine_enemy"（父类已经按 is_boss() 跳过了），自己一个分组
	add_to_group("mine_boss")
	# 覆盖掉表里的数值 —— 它是 Boss，不该跟小怪一个量级
	max_hp = boss_hp
	hp = max_hp
	_speed = CHASE_SPEED
	# 硬直抗性：小怪挨打僵 0.22s，Boss 只僵一点点，不然会被连击锁死
	stun_scale = 0.22

func display_name() -> String:
	return boss_name

func is_boss() -> bool:
	return true

func phase_name() -> String:
	match _phase:
		Phase.IDLE: return "待机"
		Phase.CHASE: return "逼近"
		Phase.WINDUP: return "蓄力"
		Phase.CHARGE: return "冲撞"
		Phase.RECOVER: return "喘息"
	return "?"

func is_engaged() -> bool:
	return _engaged

## 血量比例（给 HUD 画血条）
func hp_ratio() -> float:
	if max_hp <= 0:
		return 0.0
	return clampf(float(hp) / float(max_hp), 0.0, 1.0)

func _think(delta: float) -> void:
	_charge_cd = maxf(0.0, _charge_cd - delta)
	_phase_t -= delta

	if _player == null:
		velocity.x = 0.0
		_apply_gravity(delta)
		return

	var dx: float = _player.global_position.x - global_position.x
	var dist: float = absf(dx)

	if not _engaged:
		if dist < ENGAGE_RANGE:
			_engaged = true
			_set_phase(Phase.CHASE)
			print("[矿洞] ", boss_name, " 醒了！")
			engaged.emit()
		else:
			velocity.x = 0.0
			_apply_gravity(delta)
			return

	if _phase_t <= 0.0:
		_advance_phase(dist, dx)
	_apply_phase_motion(delta, dx)
	sprite.modulate = WARN_COLOR if _phase == Phase.WINDUP else (Color(3.0, 3.0, 3.0) if _flash > 0.0 else Color.WHITE)

func _set_phase(p: int) -> void:
	_phase = p
	match p:
		Phase.CHASE:
			_phase_t = CHASE_RECHECK
		Phase.WINDUP:
			_phase_t = WINDUP_TIME
			velocity = Vector2.ZERO
			print("[矿洞] ", boss_name, " 在蓄力……")
		Phase.CHARGE:
			_phase_t = CHARGE_TIME
			_charge_dir = signf(_player.global_position.x - global_position.x) if _player != null else 1.0
			if absf(_charge_dir) < 0.01:
				_charge_dir = 1.0
			print("[矿洞] ", boss_name, " 冲过来了！")
		Phase.RECOVER:
			_phase_t = RECOVER_TIME
			_charge_cd = CHARGE_COOLDOWN
			velocity = Vector2.ZERO

## 相位推进：只有在"逼近"里待够冷却才允许再冲一次
func _advance_phase(dist: float, dx: float) -> void:
	match _phase:
		Phase.CHASE:
			if _charge_cd <= 0.0 and dist < ENGAGE_RANGE * 0.9:
				_set_phase(Phase.WINDUP)
		Phase.WINDUP:
			_set_phase(Phase.CHARGE)
		Phase.CHARGE:
			_set_phase(Phase.RECOVER)
		Phase.RECOVER:
			_set_phase(Phase.CHASE)

func _apply_phase_motion(delta: float, dx: float) -> void:
	_apply_gravity(delta)
	match _phase:
		Phase.CHASE:
			var dir: float = signf(dx)
			if absf(dx) < 6.0:
				dir = 0.0
			velocity.x = dir * CHASE_SPEED
		Phase.CHARGE:
			velocity.x = _charge_dir * CHARGE_SPEED
			# 冲撞时伤害更高（_touch_player 会读 _damage）
			_damage = charge_damage
			return
		_:
			velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
	_damage = 1
