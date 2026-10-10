class_name SpikeTrap extends Area2D

## 地刺。踩上去持续掉血。
##
## 为什么用 Polygon2D 画而不是贴图：**Kenney 这套图集里没有地刺**
## （它只有地形、道具、角色，没有陷阱）。所以用预建的多边形三角条自己画，
## 和项目里那个刀光 `Slash` 是同一种做法 —— 既不引入第三方素材，
## 也不用为了几个三角去外部找图。
##
## 伤害用**每帧轮询重叠**而不是只在 `body_entered` 打一下：
## 站着不动也应该持续疼。频率由玩家自己的无敌帧兜底，不用另写冷却。

@export var damage: int = 1

func _ready() -> void:
	add_to_group("mine_hazard")

func _physics_process(_delta: float) -> void:
	# 无敌帧会自动限制频率，所以这里无脑每帧试就行
	for b in get_overlapping_bodies():
		var p := b as MinePlayer
		if p != null:
			# 从刺尖往上推：让玩家被"弹"一下，而不是黏在刺上
			p.take_damage(damage, global_position + Vector2(0, 10))
