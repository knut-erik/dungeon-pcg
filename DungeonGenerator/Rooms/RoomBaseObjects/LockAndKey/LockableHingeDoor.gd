class_name LockableHingeDoor
extends AnimatedMesh

@export var open_angle_degrees := -95.0
@export var starts_open := false
@export var close_on_second_activation := false


func _default_component_type() -> String:
	return "hinge_door"


func _default_agent_tag() -> String:
	return "door"


func _ready() -> void:
	animation_mode = AnimatedMesh.AnimationMode.ROTATE
	target_rotation_degrees = Vector3(0.0, open_angle_degrees, 0.0)
	starts_activated = starts_open
	toggle_on_reactivation = close_on_second_activation
	disable_collision_on_activation = false
	queue_free_after_activation = false

	super._ready()

	add_to_group("door")
	add_to_group("hinge_door")

	_sync_component_metadata()
