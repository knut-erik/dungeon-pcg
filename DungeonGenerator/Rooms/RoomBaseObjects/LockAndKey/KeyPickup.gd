class_name KeyPickup
extends LockActivator

@export var pickup_area_path: NodePath = ^"PickupArea"
@export var collect_on_touch := true
@export var player_group: StringName = &"player"
@export var queue_free_on_pickup := true

var _area: Area3D


func _default_component_type() -> String:
	return "key"


func _default_agent_tag() -> String:
	return "key"


func _ready() -> void:
	super._ready()

	add_to_group("interactable")
	add_to_group("key")

	_area = get_node_or_null(pickup_area_path) as Area3D

	if _area != null and collect_on_touch:
		if not _area.body_entered.is_connected(_on_body_entered):
			_area.body_entered.connect(_on_body_entered)

	_sync_component_metadata()


func interact(actor: Node) -> void:
	_collect(actor)


func _on_body_entered(body: Node3D) -> void:
	if player_group != &"" and not body.is_in_group(player_group):
		return

	_collect(body)


func _collect(actor: Node) -> void:
	if not can_activate(actor):
		return

	activate_lock(actor)

	hide()
	_disable_collision()

	if queue_free_on_pickup:
		queue_free()


func _disable_collision() -> void:
	if _area != null:
		_area.set_deferred("monitoring", false)
		_area.set_deferred("monitorable", false)

	for shape in find_children("*", "CollisionShape3D", true, false):
		shape.set_deferred("disabled", true)
