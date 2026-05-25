class_name LockLever
extends LockActivator

@export var handle_path: NodePath
@export var activated_rotation_degrees := Vector3(-55.0, 0.0, 0.0)
@export var animation_seconds := 0.25

var _handle: Node3D
var _initial_rotation_degrees: Vector3


func _default_component_type() -> String:
	return "lever"


func _default_agent_tag() -> String:
	return "lever"


func _ready() -> void:
	super._ready()

	add_to_group("interactable")
	add_to_group("lever")

	_handle = get_node_or_null(handle_path) as Node3D
	if _handle != null:
		_initial_rotation_degrees = _handle.rotation_degrees

	_sync_component_metadata()


func interact(actor: Node) -> void:
	if not can_activate(actor):
		return

	_animate_lever()
	activate_lock(actor)


func _animate_lever() -> void:
	if _handle == null:
		return

	var tween := create_tween()
	tween.tween_property(
		_handle,
		"rotation_degrees",
		_initial_rotation_degrees + activated_rotation_degrees,
		animation_seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
