class_name LockableHingeDoor
extends AnimatedMesh

@export var open_angle_degrees := -95.0
@export var starts_open := false
@export var close_on_second_activation := false
@export var disable_collision_when_open := true


func _default_component_type() -> String:
	return "hinge_door"


func _default_agent_tag() -> String:
	return "door"


func _ready() -> void:
	if str(animated_node_path).is_empty() and has_node("DoorPivot"):
		animated_node_path = ^"DoorPivot"

	animation_mode = AnimatedMesh.AnimationMode.ROTATE
	target_rotation_degrees = Vector3(0.0, open_angle_degrees, 0.0)
	starts_activated = starts_open
	toggle_on_reactivation = close_on_second_activation
	disable_collision_on_activation = false
	queue_free_after_activation = false

	super._ready()

	if starts_open and disable_collision_when_open:
		_set_collision_enabled(false)

	add_to_group("door")
	add_to_group("hinge_door")

	_sync_component_metadata()


func activate(source: Node = null, actor: Node = null) -> void:
	super.activate(source, actor)

	if disable_collision_when_open and _tween != null:
		_tween.tween_callback(_disable_collision_if_still_open)


func deactivate(source: Node = null, actor: Node = null) -> void:
	if disable_collision_when_open:
		_set_collision_enabled(true)

	super.deactivate(source, actor)


func _disable_collision_if_still_open() -> void:
	if _activated:
		_set_collision_enabled(false)
