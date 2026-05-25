class_name LockComponent
extends DungeonComponent

@export var lock_id: StringName

@export_category("Agent Metadata")
@export var agent_tag: String = ""
@export var agent_tags: Array[String] = []
@export var propagate_agent_metadata_to_children := true
@export var debug_lock_events := true


func _ready() -> void:
	if component_type.is_empty():
		component_type = _default_component_type()

	if agent_tag.is_empty():
		agent_tag = _default_agent_tag()

	_sync_component_metadata()


func bind_to_logic(_node: LogicalNode, _edge: LogicalEdge = null) -> void:
	super.bind_to_logic(_node, _edge)
	_sync_component_metadata()


func configure_lock(
	_lock_id: StringName,
	_component_id: String = "",
	_component_type: String = ""
) -> void:
	lock_id = _lock_id

	if not _component_id.is_empty():
		component_id = _component_id

	if not _component_type.is_empty():
		component_type = _component_type

	if agent_tag.is_empty():
		agent_tag = _default_agent_tag()

	_sync_component_metadata()


func configure_from_descriptor(descriptor: Dictionary) -> void:
	configure_lock(
		StringName(str(descriptor.get("lock_id", ""))),
		str(descriptor.get("component_id", "")),
		str(descriptor.get("component_type", ""))
	)

	if descriptor.has("agent_tag"):
		agent_tag = str(descriptor["agent_tag"])

	if descriptor.has("agent_tags"):
		agent_tags.clear()
		for tag in descriptor["agent_tags"]:
			agent_tags.append(str(tag))

	_sync_component_metadata()


func get_rl_tags() -> Array[String]:
	var tags: Array[String] = []

	if not agent_tag.is_empty():
		tags.append(agent_tag)

	for tag in agent_tags:
		if not tags.has(tag):
			tags.append(tag)

	if not component_type.is_empty() and not tags.has(component_type):
		tags.append(component_type)

	return tags


func get_agent_metadata() -> Dictionary:
	return {
		"component_id": component_id,
		"component_type": component_type,
		"lock_id": String(lock_id),
		"agent_tag": agent_tag,
		"agent_tags": get_rl_tags(),
		"logical_node_id": logical_node.id if logical_node else "",
		"logical_edge_id": logical_edge.id if logical_edge else ""
	}


func _default_component_type() -> String:
	return "lock_component"


func _default_agent_tag() -> String:
	return component_type


func _sync_component_metadata() -> void:
	_apply_metadata_to_node(self)

	if propagate_agent_metadata_to_children:
		for child in find_children("*", "", true, false):
			if child is Node:
				_apply_metadata_to_node(child)


func _apply_metadata_to_node(node: Node) -> void:
	node.set_meta("is_dungeon_component", true)

	if not component_id.is_empty():
		node.set_meta("component_id", component_id)

	if not component_type.is_empty():
		node.set_meta("component_type", component_type)

	if lock_id != &"":
		node.set_meta("lock_id", String(lock_id))

	if logical_node != null:
		node.set_meta("logical_node_id", logical_node.id)

	if logical_edge != null:
		node.set_meta("logical_edge_id", logical_edge.id)

	var tags := get_rl_tags()
	node.set_meta("agent_tags", tags)

	if not agent_tag.is_empty():
		node.set_meta("semantic_tag", agent_tag)

	for tag in tags:
		var group_name := "tag_%s" % tag
		if not node.is_in_group(group_name):
			node.add_to_group(group_name)
