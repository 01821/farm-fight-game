class_name DamageNumber extends Label

## 飘字伤害数字（参考游戏里那种大号描边、往上飘再淡出的数字）。
##
## 这是一个**预建场景**，命中时 instantiate 一个、设好文字和颜色，播完自己 queue_free。
## 符合项目约定：不 new 节点，只实例化预先建好的场景。

const RISE: float = 26.0      # 整个生命周期上升多少像素
const LIFE: float = 0.55
const DRIFT: float = 18.0     # 水平漂移，避免连续命中时数字叠在一起

var _t: float = 0.0
var _start: Vector2
var _drift_phase: float = 0.0

## value 是要显示的字（数字或 "MISS" 之类），crit = 用更醒目的颜色
## ⚠️ 必须在**设好 global_position 之后**再调，因为这里会把当前位置记成飘字起点。
func setup(value: String, crit: bool = false) -> void:
	text = value
	if crit:
		add_theme_color_override("font_color", Color(1.0, 0.35, 0.2))
		add_theme_color_override("font_outline_color", Color(0.25, 0.02, 0.02))
	else:
		add_theme_color_override("font_color", Color(1.0, 0.92, 0.35))
		add_theme_color_override("font_outline_color", Color(0.22, 0.10, 0.02))
	_drift_phase = randf() * TAU
	_start = position
	scale = Vector2(0.6, 0.6)

func _ready() -> void:
	_start = position
	_drift_phase = randf() * TAU

func _process(delta: float) -> void:
	_t += delta
	var p: float = clampf(_t / LIFE, 0.0, 1.0)
	# 先弹出（0→0.18 放大到 1.15），再回落，最后淡出
	var pop: float = 0.6 + 0.55 * minf(p / 0.18, 1.0)
	if p > 0.18:
		pop = lerpf(1.15, 1.0, minf((p - 0.18) / 0.25, 1.0))
	scale = Vector2(pop, pop)
	position = _start + Vector2(sin(_drift_phase) * DRIFT * p, -RISE * p)
	modulate.a = 1.0 if p < 0.6 else lerpf(1.0, 0.0, (p - 0.6) / 0.4)
	if p >= 1.0:
		queue_free()
