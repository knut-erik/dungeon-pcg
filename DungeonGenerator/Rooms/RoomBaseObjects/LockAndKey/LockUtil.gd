class_name LockUtil
extends RefCounted


static func emit_lock_activation(
	tree: SceneTree,
	lock_id: StringName,
	source: Node,
	actor: Node = null
) -> void:
	if lock_id == &"":
		push_warning("Tried to activate an empty lock_id from %s" % source.name)
		return

	var source_name := str(source.name) if source != null else "null"
	var actor_name := str(actor.name) if actor != null else "null"

	print(
		"LockUtil: emitting lock_id=",
		lock_id,
		" source=",
		source_name,
		" actor=",
		actor_name
	)

	tree.call_group(
		"lock_targets",
		"receive_lock_activation",
		lock_id,
		source,
		actor
	)
