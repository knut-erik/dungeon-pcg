class_name FalseDoorBlocker
extends AnimatedMesh


func _default_component_type() -> String:
	return "false_door"


func _default_agent_tag() -> String:
	return "door"


func _ready() -> void:
	animation_mode = AnimatedMesh.AnimationMode.FADE_OUT
	disable_collision_on_activation = true
	queue_free_after_activation = true
	toggle_on_reactivation = false
	one_shot = true

	super._ready()

	add_to_group("door")
	add_to_group("false_door")

	_sync_component_metadata()
