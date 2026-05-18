# GraphRule.gd (Bas-klass)
extends RefCounted
class_name GraphRule

var room_library: Array[RoomBlueprint]

func _init(lib: Array[RoomBlueprint]):
	room_library = lib

# Ska överskridas av specifika regler
func can_apply(_graph: LogicalGraph, _target_node: LogicalNode) -> bool:
	return false
	
func apply(_graph: LogicalGraph, _target_node: LogicalNode) -> void:
	pass

# Hjälpfunktion för att hämta rum
func get_blueprint(tag: String) -> RoomBlueprint:
	var valid = []
	for bp in room_library:
		if bp.possible_tags.has(tag):
			valid.append(bp)
	return valid.pick_random() if valid.size() > 0 else null

#---------------------------------------------------------------------------------------------------

const COMPONENT_DESCRIPTORS_KEY := "dungeon_components"


func add_node_component(node: LogicalNode, descriptor: Dictionary) -> void:
	var components: Array = node.custom_data.get(COMPONENT_DESCRIPTORS_KEY, [])
	components.append(descriptor)
	node.custom_data[COMPONENT_DESCRIPTORS_KEY] = components


func add_edge_component(edge: LogicalEdge, descriptor: Dictionary) -> void:
	var components: Array = edge.custom_data.get(COMPONENT_DESCRIPTORS_KEY, [])
	components.append(descriptor)
	edge.custom_data[COMPONENT_DESCRIPTORS_KEY] = components


func make_lock_component_descriptor(
	component_id: String,
	component_type: String,
	lock_id: String,
	scene_key: String,
	socket_role: String = "",
	gateway_role: String = "",
	edge_side: String = "",
	agent_tag: String = "",
	agent_tags: Array[String] = []
) -> Dictionary:
	var descriptor := {
		"component_id": component_id,
		"component_type": component_type,
		"lock_id": lock_id,
		"scene_key": scene_key,
		"socket_role": socket_role,
		"gateway_role": gateway_role,
		"edge_side": edge_side
	}
	if not agent_tag.is_empty():
		descriptor["agent_tag"] = agent_tag
	if not agent_tags.is_empty():
		descriptor["agent_tags"] = agent_tags
	return descriptor
