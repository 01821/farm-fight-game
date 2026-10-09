extends State

func Enter():
	super.Enter()
	character.UpdateAnimation()
	character.move_timer.wait_time = randi_range(1.5,3.5)
	character.move_timer.start()

func _on_move_timer_timeout() -> void:
	character.move_timer.stop()
	stateMachine.SwitchTo("Move")
