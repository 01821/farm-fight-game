extends State

func Enter():
	super.Enter()

func Update(delta):
	super.Update(delta)
	character.UpdateAnimation()
		

	if character.InputDirection.length() > 0:
		stateMachine.SwitchTo("Move")
	
func UpdatePhysics(delta:float):
	super.UpdatePhysics(delta)
