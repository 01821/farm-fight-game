class_name StateMachine extends Node

var currentState:State

func _ready() -> void:
	for child in get_children():
		var childState = child as State
		childState.stateMachine = self
		childState.character = get_parent()
		childState.Ready()
	await get_tree().create_timer(0.0).timeout
	currentState = get_child(0)
	currentState.Enter()
	
func _physics_process(delta: float) -> void:
	if currentState:
		currentState.UpdatePhysics(delta)

func _process(delta: float) -> void:
	if currentState:
		currentState.Update(delta)

func SwitchTo(tragetState:String):
	var nextStateNode = get_node(tragetState) as State
	
	if !nextStateNode:
		print("Can not find the state")
		return
	currentState.Exit()
	currentState = nextStateNode
	nextStateNode.Enter()
	
	
