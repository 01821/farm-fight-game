extends Sprite2D

## 水源（水桶 / 水缸）：玩家站进 InteractionArea 就自动把水壶补满。
## InteractionArea 与 ActiveSprite 都是场景里预先建好的节点，这里只做开关。

@onready var area: Area2D = $InteractionArea
@onready var active_sprite: Sprite2D = $ActiveSprite

func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	active_sprite.visible = false

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		body.add_water_source()
		active_sprite.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		body.remove_water_source()
		active_sprite.visible = false
