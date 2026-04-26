# BoundingBox.gd
extends Area3D

@export var size: Vector3

@onready var collision_shape = $CollisionShape3D

func _ready() -> void:
	# Säkerställ att vi har en BoxShape3D
	if collision_shape and not collision_shape.shape:
		collision_shape.shape = BoxShape3D.new()

# Kallas från BaseRoom.gd
func set_size(new_size: Vector3) -> void:
	size = new_size
	if collision_shape and collision_shape.shape:
		collision_shape.shape.size = size
