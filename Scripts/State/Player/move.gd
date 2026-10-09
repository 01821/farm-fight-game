extends State

const SPEED = 150
const ACCELLERATE = 15

func Enter():
	super.Enter()


func Update(delta):
	super.Update(delta)
	character.UpdateAnimation()
	if character.InputDirection == Vector2.ZERO:
		stateMachine.SwitchTo("Idle")
	
func UpdatePhysics(delta:float):
	super.UpdatePhysics(delta)
	character.velocity = character.velocity.lerp(character.InputDirection * SPEED,ACCELLERATE *delta)
	character.move_and_slide()
