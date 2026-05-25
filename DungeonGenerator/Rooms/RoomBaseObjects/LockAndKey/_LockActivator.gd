class_name LockActivator
extends LockComponent

@export var one_shot := true
@export var disabled := false

var _used := false


func _default_component_type() -> String:
	return "lock_activator"


func can_activate(_actor: Node = null) -> bool:
	if disabled:
		return false

	if _used and one_shot:
		return false

	if lock_id == &"":
		push_warning("%s has no lock_id." % name)
		return false

	return true


func activate_lock(actor: Node = null) -> void:
	if not can_activate(actor):
		return

	_used = true

	if debug_lock_events:
		print(
			"LockActivator: ",
			name,
			" activated lock_id=",
			lock_id,
			" component_id=",
			component_id,
			" component_type=",
			component_type
		)

	LockUtil.emit_lock_activation(
		get_tree(),
		lock_id,
		self,
		actor
	)


func reset_activator() -> void:
	_used = false
	disabled = false
