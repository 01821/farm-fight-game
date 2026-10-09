extends Node

var animalRegion:NavigationRegion2D

func _ready() -> void:
	animalRegion = get_tree().get_first_node_in_group("animalRegion")
