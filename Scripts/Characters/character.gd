class_name Character extends CharacterBody2D

var InputDirection : Vector2 = Vector2.ZERO
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var state_machine: StateMachine = $StateMachine
@onready var debug_label: Label = $debugLabel
@onready var sprite_2d: Sprite2D = $Sprite2D

func UpdateAnimation():
	animation_player.play(state_machine.currentState.name)
	debug_label.text = state_machine.currentState.name
	
	var workToAdd:bool = false
	if not workToAdd:
		go()
	else:
		dieOnCompany()

func UpdateFaceDirection():
	if InputDirection.x < 0:
		sprite_2d.flip_h = true
	elif InputDirection.x >= 0:
		sprite_2d.flip_h = false

func go():
	pass
func dieOnCompany():
	pass
