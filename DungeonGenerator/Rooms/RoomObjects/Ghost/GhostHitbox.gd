class_name GhostHitbox
extends Area3D

@export var ghost_path: NodePath = ^".."


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("interactable")
	set_meta("agent_tags", get_rl_tags())
	set_meta("semantic_tag", "enemy")
	set_meta("component_type", "enemy")

	for tag: String in get_rl_tags():
		var group_name: String = "tag_%s" % tag
		if not is_in_group(group_name):
			add_to_group(group_name)


func interact(actor: Node) -> void:
	var ghost: Node = get_node_or_null(ghost_path)
	if ghost != null and ghost.has_method("interact"):
		ghost.interact(actor)


func get_rl_tags() -> Array[String]:
	return ["enemy", "ghost"]
