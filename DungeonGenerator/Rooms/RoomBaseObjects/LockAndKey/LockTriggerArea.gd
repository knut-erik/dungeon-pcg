class_name LockTriggerArea
extends LockActivator

@export var trigger_area_path: NodePath = ^"TriggerArea"
@export var actor_group: StringName = &"player"
@export var required_actor_game_state: StringName = &""

var _area: Area3D


func _default_component_type() -> String:
	return "lock_trigger"


func _default_agent_tag() -> String:
	return "trigger"


func _ready() -> void:
	super._ready()

	add_to_group("lock_trigger")

	_area = get_node_or_null(trigger_area_path) as Area3D
	if _area != null:
		if not _area.body_entered.is_connected(_on_body_entered):
			_area.body_entered.connect(_on_body_entered)

	_sync_component_metadata()


func _on_body_entered(body: Node3D) -> void:
	if actor_group != &"" and not body.is_in_group(actor_group):
		return

	if required_actor_game_state != &"" and not _actor_has_required_state(body):
		return

	if not can_activate(body):
		return

	activate_lock(body)

	if one_shot:
		_disable_area()


func _actor_has_required_state(actor: Node) -> bool:
	if actor.has_method("has_game_state"):
		return actor.has_game_state(required_actor_game_state)

	var state = actor.get("game_state")
	return state == required_actor_game_state or state == String(required_actor_game_state)


func _disable_area() -> void:
	if _area == null:
		return

	_area.set_deferred("monitoring", false)
	_area.set_deferred("monitorable", false)
