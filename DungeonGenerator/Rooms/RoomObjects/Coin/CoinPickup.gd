class_name CoinPickup
extends KeyPickup

@export var money_value := 1
@export var spin_degrees_per_second := 120.0
@export var visual_root_path: NodePath = ^"CoinVisual"
@export var emit_lock_activation := false

var _visual_root: Node3D


func _default_component_type() -> String:
	return "coin"


func _default_agent_tag() -> String:
	return "coin"


func _ready() -> void:
	if lock_id == &"":
		lock_id = &"coin_pickup"

	collect_on_touch = true
	queue_free_on_pickup = true

	super._ready()

	remove_from_group("key")
	add_to_group("coin")

	_visual_root = get_node_or_null(visual_root_path) as Node3D
	_sync_component_metadata()


func _process(delta: float) -> void:
	if _visual_root != null:
		_visual_root.rotate_y(deg_to_rad(spin_degrees_per_second) * delta)


func _collect(actor: Node) -> void:
	if not can_activate(actor):
		return

	if actor != null and actor.has_method("add_money"):
		actor.add_money(money_value)
	else:
		push_warning("CoinPickup: pickup actor has no add_money(amount) method.")

	if emit_lock_activation:
		activate_lock(actor)
	else:
		_used = true

	hide()
	_disable_collision()

	if queue_free_on_pickup:
		queue_free()
