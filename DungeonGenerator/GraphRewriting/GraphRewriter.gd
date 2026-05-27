# GraphRewriter.gd
extends RefCounted
class_name GraphRewriter

const ROUTING_ZONE_KEY := "routing_zone"

var room_library: Array[RoomBlueprint]
var num_challenges: int = 3
var create_loop: bool = true
var rng: RandomNumberGenerator
var verbose_logs := false

func _init(
		lib: Array[RoomBlueprint],
		challenge_count: int = 3,
		should_create_loop: bool = true,
		random: RandomNumberGenerator = null,
		verbose: bool = false
	):
	room_library = lib
	num_challenges = challenge_count
	create_loop = should_create_loop
	rng = random
	verbose_logs = verbose


func generate() -> LogicalGraph:
	var graph := LogicalGraph.new()
	
	if verbose_logs:
		_debug_print_room_library()
	
	var start_node := _create_basic_node("Entrance", "start_01")
	var boss_node := _create_basic_node("Boss", "boss_01")

	graph.add_node(start_node)
	graph.add_node(boss_node)

	graph._connect(start_node, boss_node, "main_path", ["main"])

	var challenge_rule := Rule_InsertChallenge.new(room_library, rng, verbose_logs)
	var applied := 0
	var attempts := 0
	var max_attempts: int = max(20, num_challenges * 20)

	while applied < num_challenges and attempts < max_attempts:
		attempts += 1

		var random_node: LogicalNode = _pick_from_array(graph.nodes)

		if challenge_rule.can_apply(graph, random_node):
			challenge_rule.apply(graph, random_node)
			applied += 1

	if applied < num_challenges:
		push_warning("GraphRewriter: Only applied %d / %d challenge rules." % [applied, num_challenges])

	var lock_rule := Rule_LockAndKey.new(room_library, rng, verbose_logs)
	for node in graph.nodes:
		if lock_rule.can_apply(graph, node):
			lock_rule.apply(graph, node)
			break

	if create_loop and graph.nodes.size() > 2:
		var boss_target: LogicalNode = _find_first_node_with_tag(graph, "Boss")

		if boss_target and graph.find_edge(boss_target, start_node) == null:
			var loop_edge := graph._connect(boss_target, start_node, "boss_return", ["loop", "boss_return"])

			loop_edge.requirements["preferred_from_gateway_role"] = "loop_return"
			loop_edge.requirements["preferred_to_gateway_role"] = "loop_return"

			var loop_lock_id := "boss_loop_%s" % loop_edge.id

			loop_edge.custom_data["lock_id"] = loop_lock_id
			loop_edge.custom_data["loop_unlocks_from_boss_side"] = true

			# Boss-side collision area. Entering this activates the linked false door.
			_add_edge_component(
				loop_edge,
				_make_lock_component_descriptor(
					"trigger_%s" % loop_edge.id,
					"lock_trigger",
					loop_lock_id,
					"lock_trigger_area",
					"trigger_volume",
					"loop_return",
					"from",
					"trigger"
				)
			)

			# Entrance-side false door. This blocks the return loop from being used early.
			_add_edge_component(
				loop_edge,
				_make_lock_component_descriptor(
					"false_door_%s" % loop_edge.id,
					"false_door",
					loop_lock_id,
					"false_door_blocker",
					"animated_mesh",
					"loop_return",
					"to",
					"door"
				)
			)

	_annotate_routing_zones(graph, start_node)
	if verbose_logs:
		_debug_print_graph(graph)
	return graph


func generate_from_config(config: Dictionary) -> LogicalGraph:
	var logical_graph: Variant = config.get("logical_graph", {})
	if not logical_graph is Dictionary:
		push_warning("GraphRewriter: Config has no logical_graph object. Falling back to generate().")
		return generate()

	var graph := _deserialize_logical_graph(logical_graph as Dictionary)

	if graph.nodes.is_empty():
		push_warning("GraphRewriter: Config logical_graph has no nodes. Falling back to generate().")
		return generate()

	var start_node := _find_start_node(graph)
	_annotate_routing_zones(graph, start_node)

	if verbose_logs:
		_debug_print_graph(graph)

	return graph


func _deserialize_logical_graph(data: Dictionary) -> LogicalGraph:
	var graph := LogicalGraph.new()
	var nodes_by_id := {}

	for node_data in data.get("nodes", []):
		if not node_data is Dictionary:
			continue

		var node := LogicalNode.new()
		node.id = str(node_data.get("id", ""))
		node.assigned_tags.assign(_to_string_array(node_data.get("assigned_tags", [])))
		node.blueprint = _find_blueprint_for_node(node_data as Dictionary)
		node.custom_data = (node_data.get("custom_data", {}) as Dictionary).duplicate(true)

		if node.id.is_empty():
			push_warning("GraphRewriter: Skipping config node with empty id.")
			continue

		graph.add_node(node)
		nodes_by_id[node.id] = node

	for edge_data in data.get("edges", []):
		if not edge_data is Dictionary:
			continue

		var from_id := str(edge_data.get("from", ""))
		var to_id := str(edge_data.get("to", ""))

		if not nodes_by_id.has(from_id) or not nodes_by_id.has(to_id):
			push_warning("GraphRewriter: Skipping config edge with missing endpoint: %s -> %s" % [from_id, to_id])
			continue

		var edge := LogicalEdge.new()
		edge.id = str(edge_data.get("id", "%s_to_%s_%d" % [from_id, to_id, graph.edges.size()]))
		edge.from_node = nodes_by_id[from_id]
		edge.to_node = nodes_by_id[to_id]
		edge.edge_type = str(edge_data.get("edge_type", "normal"))
		edge.tags.assign(_to_string_array(edge_data.get("tags", [])))
		edge.requirements = (edge_data.get("requirements", {}) as Dictionary).duplicate(true)
		edge.effects = (edge_data.get("effects", {}) as Dictionary).duplicate(true)
		edge.custom_data = (edge_data.get("custom_data", {}) as Dictionary).duplicate(true)

		graph.add_edge(edge)

	return graph


func _find_blueprint_for_node(node_data: Dictionary) -> RoomBlueprint:
	var blueprint_path := str(node_data.get("blueprint_path", ""))
	if not blueprint_path.is_empty():
		var resource := load(blueprint_path)
		if resource is RoomBlueprint:
			return resource as RoomBlueprint

	for tag in _to_string_array(node_data.get("assigned_tags", [])):
		var blueprint := _find_blueprint_by_tag(tag)
		if blueprint != null:
			return blueprint

	return null


func _find_start_node(graph: LogicalGraph) -> LogicalNode:
	for node in graph.nodes:
		if node.id == "start_01" or node.assigned_tags.has("Entrance"):
			return node

	return graph.nodes[0]


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []

	if not value is Array:
		return result

	for item in value:
		result.append(str(item))

	return result


func _create_basic_node(tag: String, id: String) -> LogicalNode:
	var node := LogicalNode.new()
	node.id = id
	node.assigned_tags.assign([tag])
	node.blueprint = _find_blueprint_by_tag(tag)
	return node


func _find_blueprint_by_tag(target_tag: String) -> RoomBlueprint:
	var valid: Array[RoomBlueprint] = []

	for blueprint in room_library:
		if blueprint.possible_tags.has(target_tag):
			valid.append(blueprint)

	return _pick_from_array(valid)

func _pick_from_array(items: Array) -> Variant:
	if items.is_empty():
		return null
	if rng == null:
		return items[0]
	return items[rng.randi_range(0, items.size() - 1)]

func _find_first_node_with_tag(graph: LogicalGraph, tag: String) -> LogicalNode:
	for node in graph.nodes:
		if node.assigned_tags.has(tag):
			return node

	return null

# ------------------------------------------------------------------------------

const COMPONENT_DESCRIPTORS_KEY := "dungeon_components"


func _add_edge_component(edge: LogicalEdge, descriptor: Dictionary) -> void:
	var components: Array = edge.custom_data.get(COMPONENT_DESCRIPTORS_KEY, [])
	components.append(descriptor)
	edge.custom_data[COMPONENT_DESCRIPTORS_KEY] = components


func _make_lock_component_descriptor(
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

func _annotate_routing_zones(graph: LogicalGraph, start_node: LogicalNode) -> void:
	var pre_lock_nodes := {}
	var queue: Array[LogicalNode] = [start_node]
	pre_lock_nodes[start_node] = true

	while not queue.is_empty():
		var node: LogicalNode = queue.pop_front()

		for edge in node.out_edges:
			if edge == null:
				continue

			if edge.edge_type == "locked":
				continue

			if edge.edge_type == "boss_return" or edge.tags.has("loop"):
				continue

			var next_node := edge.to_node
			if next_node == null or pre_lock_nodes.has(next_node):
				continue

			pre_lock_nodes[next_node] = true
			queue.append(next_node)

	for edge in graph.edges:
		if edge == null:
			continue

		if edge.edge_type == "boss_return" or edge.tags.has("loop"):
			edge.custom_data[ROUTING_ZONE_KEY] = "post_lock"
			continue

		if edge.edge_type == "locked":
			edge.custom_data[ROUTING_ZONE_KEY] = "post_lock"
			edge.custom_data["is_lock_boundary"] = true
			continue

		if pre_lock_nodes.has(edge.from_node) and pre_lock_nodes.has(edge.to_node):
			edge.custom_data[ROUTING_ZONE_KEY] = "pre_lock"
		else:
			edge.custom_data[ROUTING_ZONE_KEY] = "post_lock"


func _debug_print_room_library() -> void:
	print("")
	print("========== ROOM LIBRARY ==========")

	for blueprint in room_library:
		if blueprint == null:
			print("  null blueprint")
			continue

		print(
			"  blueprint=",
			blueprint.resource_path,
			" possible_tags=",
			blueprint.possible_tags
		)

	print("==================================")
	print("")

func _debug_print_graph(graph: LogicalGraph) -> void:
	print("")
	print("========== GENERATED LOGICAL GRAPH ==========")

	print("Nodes:")
	for node in graph.nodes:
		print(
			"  NODE id=",
			node.id,
			" assigned_tags=",
			node.assigned_tags,
			" blueprint=",
			node.blueprint.resource_path if node.blueprint else "null",
			" custom_data=",
			node.custom_data
		)

	print("Edges:")
	for edge in graph.edges:
		print(
			"  EDGE id=",
			edge.id,
			" ",
			edge.from_node.id if edge.from_node else "null",
			" -> ",
			edge.to_node.id if edge.to_node else "null",
			" type=",
			edge.edge_type,
			" tags=",
			edge.tags,
			" requirements=",
			edge.requirements,
			" effects=",
			edge.effects,
			" custom_data=",
			edge.custom_data
		)

	print("=============================================")
	print("")
