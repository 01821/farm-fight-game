extends State

var target_pos:Vector2
var speed:float 
var direction:Vector2

@onready var navigation_agent_2d: NavigationAgent2D = $"../../NavigationAgent2D"
const SPEED_MAX = 50
const SPEED_Min = 10
func Enter():
	super.Enter()
	var _points = Level.animalRegion.navigation_polygon.get_vertices()
	target_pos = _points[randi_range(0,_points.size()-1)]
	navigation_agent_2d.target_position = target_pos
	character.InputDirection = (target_pos - character.global_position).normalized()
	character.UpdateFaceDirection()
	
func Update(delta):
	super.Update(delta)
	character.UpdateAnimation()
	speed = randi_range(SPEED_Min,SPEED_MAX)

func UpdatePhysics(delta: float):
	super.UpdatePhysics(delta)
	direction = character.global_position.direction_to(navigation_agent_2d.get_next_path_position())

	if navigation_agent_2d.is_target_reached() == false:
		character.velocity = character.velocity.lerp(direction * speed,delta)
		character.InputDirection = direction
		character.UpdateFaceDirection()
		character.move_and_slide()
	else:
		character.state_machine.SwitchTo("Idle")
		character.move_timer.start()


func _on_navigation_agent_2d_velocity_computed(safe_velocity: Vector2) -> void:
	if stateMachine.currentState == self and navigation_agent_2d.is_target_reached() == false:
		character.velocity += safe_velocity * get_physics_process_delta_time()
