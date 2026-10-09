extends Character

func _unhandled_input(event: InputEvent) -> void:
	InputDirection = Input.get_vector("left","right","up","down")
	UpdateFaceDirection()
