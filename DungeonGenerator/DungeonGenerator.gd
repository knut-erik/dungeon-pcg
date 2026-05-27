extends Node3D
class_name DungeonGenerator

@export var room_library: Array[RoomBlueprint] = []

@export var num_challenges: int = 3
@export var create_loop: bool = true
@export var max_generation_attempts := 20
@export var generation_seed: int = 0
@export var enable_debug_draw := false
@export var verbose_generation_logs := false
var generation_config: Dictionary = {}

# The grid size should ~match CorridorNetwork.GRID_SIZE
const GRID_SIZE := 1.0

const COMPONENT_DESCRIPTORS_KEY := "dungeon_components"

const COMPONENT_SCENE_REGISTRY := {
	"key_pickup": preload("res://DungeonGenerator/Rooms/RoomBaseObjects/LockAndKey/Scenes/KeyPickup.tscn"),
	"coin": preload("res://DungeonGenerator/Rooms/RoomObjects/Coin/Coin.tscn"),
	"lever": preload("res://DungeonGenerator/Rooms/RoomBaseObjects/LockAndKey/Scenes/Lever.tscn"),
	"lock_trigger_area": preload("res://DungeonGenerator/Rooms/RoomBaseObjects/LockAndKey/Scenes/LockTriggerArea.tscn"),
	"hinge_door": preload("res://DungeonGenerator/Rooms/RoomBaseObjects/LockAndKey/Scenes/HingeDoor.tscn"),
	"false_door_blocker": preload("res://DungeonGenerator/Rooms/RoomBaseObjects/LockAndKey/Scenes/FalseDoorBlocker.tscn")
}

var room_instances_by_node_id: Dictionary = {}

func _ready() -> void:
	var base_seed := generation_seed
	if not generation_config.is_empty():
		_apply_generation_config_settings(generation_config)
		base_seed = generation_seed

	if room_library.is_empty():
		push_error("DungeonGenerator saknar RoomBlueprints! Lägg till dem i editorn.")
		return
	if base_seed == 0:
		base_seed = Time.get_ticks_usec()

	for attempt in range(maxi(1, max_generation_attempts)):
		await _clear_generated_dungeon()

		var attempt_seed := base_seed + attempt
		var rng := RandomNumberGenerator.new()
		rng.seed = attempt_seed

		var rewriter := GraphRewriter.new(room_library, num_challenges, create_loop, rng, verbose_generation_logs)
		var graph: LogicalGraph = rewriter.generate_from_config(generation_config) if not generation_config.is_empty() else rewriter.generate()

		if not _validate_logical_graph(graph):
			push_warning("DungeonGenerator: logical graph validation failed on attempt %d." % [attempt + 1])
			continue

		var generation_ok := await _build_physical_dungeon(graph, rng)
		if generation_ok:
			print(
				"DungeonGenerator: generation succeeded. base_seed=%d attempt_seed=%d attempt=%d"
				% [base_seed, attempt_seed, attempt + 1]
			)
			return

		push_warning("DungeonGenerator: generation attempt %d failed. Retrying." % [attempt + 1])

	await _clear_generated_dungeon()
	push_error("DungeonGenerator: failed to generate a fully connected dungeon after %d attempts." % max_generation_attempts)

func _apply_generation_config_settings(config: Dictionary) -> void:
	var generator_config: Variant = config.get("generator", {})
	if generator_config is Dictionary:
		generation_seed = int(generator_config.get("seed", generation_seed))
		max_generation_attempts = maxi(1, int(generator_config.get("max_generation_attempts", max_generation_attempts)))
		num_challenges = maxi(0, int(generator_config.get("num_challenges", num_challenges)))
		create_loop = bool(generator_config.get("create_loop", create_loop))

	var configured_library := _load_room_library_from_config(config)
	if not configured_library.is_empty():
		room_library = configured_library

func _load_room_library_from_config(config: Dictionary) -> Array[RoomBlueprint]:
	var result: Array[RoomBlueprint] = []
	var room_library_config: Variant = config.get("room_library", [])

	if not room_library_config is Array:
		return result

	for entry in room_library_config:
		if not entry is Dictionary:
			continue

		var path := str((entry as Dictionary).get("path", ""))
		if path.is_empty():
			continue

		var resource := load(path)
		if resource is RoomBlueprint:
			result.append(resource as RoomBlueprint)

	return result

# ==============================================================================
# DEL 1: LOGIK & GRAPH REWRITING
# ==============================================================================

'''func _generate_logical_graph() -> Array[LogicalNode]:
	var graph = LogicalGraph.new()

	var start_node = _create_basic_node("Entrance", "start_01")
	var boss_node  = _create_basic_node("Boss",     "boss_01")
	start_node.connections.append(boss_node)
	graph.add_node(start_node)
	graph.add_node(boss_node)

	var challenge_rule = Rule_InsertChallenge.new(room_library)
	var applied = 0
	while applied < num_challenges:
		var random_node = graph.nodes.pick_random()
		if challenge_rule.can_apply(graph, random_node):
			challenge_rule.apply(graph, random_node)
			applied += 1

	var lock_rule = Rule_LockAndKey.new(room_library)
	for node in graph.nodes:
		if lock_rule.can_apply(graph, node):
			lock_rule.apply(graph, node)
			break

	if create_loop and graph.nodes.size() > 2:
		var boss_target: LogicalNode = null
		for node in graph.nodes:
			if node.assigned_tags.has("Boss"):
				boss_target = node
				break
		if boss_target:
			print("Regissör: Skapar Return Path (Loop) från Boss till Entrance")
			graph.create_connection(boss_target, graph.nodes[0])

	return graph.nodes'''

'''func _create_basic_node(tag: String, id: String) -> LogicalNode:
	var node = LogicalNode.new()
	node.id = id
	node.assigned_tags.assign([tag])
	node.blueprint = _find_blueprint_by_tag(tag)
	return node

func _find_blueprint_by_tag(target_tag: String) -> RoomBlueprint:
	var valid: Array[RoomBlueprint] = []
	for blueprint in room_library:
		if blueprint.possible_tags.has(target_tag):
			valid.append(blueprint)
	return valid.pick_random() if valid.size() > 0 else null'''

# ==============================================================================
# DEL 2: FYSISK GENERERING
# ==============================================================================

func _build_physical_dungeon(graph: LogicalGraph, rng: RandomNumberGenerator) -> bool:
	var physical_rooms: Array[BaseRoom] = []
	var placed_room_aabbs: Array[AABB] = []
	var room_map: Dictionary = {}

	if graph.nodes.is_empty():
		push_error("DungeonGenerator: LogicalGraph has no nodes.")
		return false

	var start_logic: LogicalNode = graph.nodes[0]
	var start_room: BaseRoom = await _spawn_room(start_logic, rng)
	start_room.position = Vector3.ZERO

	physical_rooms.append(start_room)
	placed_room_aabbs.append_array(start_room.get_world_aabbs())
	room_map[start_logic] = start_room

	var queue: Array[LogicalNode] = [start_logic]
	var visited := {start_logic: true}
	
	# 2. Place all other rooms
	while not queue.is_empty():
		var curr_logic: LogicalNode = queue.pop_front()
		var curr_room: BaseRoom = room_map[curr_logic]

		for edge in curr_logic.out_edges:
			var child_logic: LogicalNode = edge.to_node
			if not child_logic:
				continue

			if visited.has(child_logic):
				continue

			visited[child_logic] = true
			queue.append(child_logic)

			var child_room := await _spawn_room(child_logic, rng)

			var target_gateway_y := curr_room.global_position.y

			# Introduce Y-height variations organically.
			# The CorridorNetwork will intercept these deltas and build stairs automatically.
			# Key-branch rooms must stay at the same Y as their parent: the junction
			# connecting them is in corridor space and cannot support stair injection.
			var should_change_height := rng.randf() < 0.30 and edge.edge_type != "key_branch"
			if should_change_height:
				var direction := 1.0 if rng.randf() > 0.5 else -1.0
				target_gateway_y += rng.randf_range(4.0, 8.0) * direction

			var required_y := target_gateway_y

			var placed := _place_room_corridor_friendly(
				child_room,
				curr_room,
				placed_room_aabbs,
				rng,
				required_y,
				edge
			)

			if not placed:
				push_warning("Failed to place room for node %s. Using fallback radial placement." % child_logic.id)
				_place_room_fallback(child_room, curr_room, placed_room_aabbs, rng, required_y)

			physical_rooms.append(child_room)
			placed_room_aabbs.append_array(child_room.get_world_aabbs())
			room_map[child_logic] = child_room

	# Place nodes not reached by directed traversal, if any.
	for node in graph.nodes:
		if room_map.has(node):
			continue

		var orphan_room := await _spawn_room(node, rng)
		_place_room_fallback(orphan_room, start_room, placed_room_aabbs, rng, start_room.global_position.y)
		physical_rooms.append(orphan_room)
		placed_room_aabbs.append_array(orphan_room.get_world_aabbs())
		room_map[node] = orphan_room

	# Give Godot's CSG system time to settle transforms and booleans; awaits are very important in general to make sure everything happens in the right order.
	await get_tree().create_timer(0.1).timeout

	# 3. Collect AABBs and Gateway Pairs for Network
	var room_aabbs: Array[AABB] = []
	for room in physical_rooms:
		for world_aabb in room.get_world_aabbs():
			room_aabbs.append(world_aabb)

	var physical_connections := _assign_physical_connections(graph, room_map)

	# 4. Build Corridors
	var network := CorridorNetwork.new()
	add_child(network)
	var corridor_ok: bool = await network.build(physical_connections, room_aabbs, room_library, rng)

	if not corridor_ok:
		push_warning("DungeonGenerator: corridor generation failed. Rejecting this dungeon.")
		return false

	network.seal_unused_gateways(physical_rooms)

	if enable_debug_draw:
		var debug := DungeonDebugDraw.new()
		add_child(debug)
		# Ensures DungeonDebugDraw._ready() has initialized its ImmediateMesh.
		await get_tree().process_frame
		debug.draw_debug(network, physical_rooms, network.get_stair_rooms())

	_spawn_graph_components(graph)
	return true

func _clear_generated_dungeon() -> void:
	room_instances_by_node_id.clear()

	for child in get_children():
		if child is BaseRoom or child is CorridorNetwork or child is DungeonDebugDraw:
			child.queue_free()

	await get_tree().process_frame

# ==============================================================================
# DEL 3: KOLLISIONSHJÄLPARE
# ==============================================================================

func _check_aabb_overlap(
		test_pos: Vector3,
		child_room: BaseRoom,
		child_aabbs: Array[AABB],
		placed_aabbs: Array[AABB]
	) -> bool:
	# Breathing margin guarantees A* always has routing lanes between rooms.
	# Do not reduce below corridor_width (3.0) + some clearance.
	var margin := Vector3.ONE * 7.0

	# child_room is not yet placed — get_world_aabbs() reflects its current
	# position (likely zero). We offset each AABB by (test_pos - current_pos)
	# to simulate where it would sit if placed at test_pos. Change this?
	var placement_offset := test_pos - child_room.global_position

	for c_aabb in child_aabbs:
		# Shift the candidate AABB to the test position, then grow by margin
		var shifted_c := AABB(c_aabb.position + placement_offset, c_aabb.size).grow(margin.x * 0.5)
		for p_aabb in placed_aabbs:
			var grown_p := p_aabb.grow(margin.x * 0.5)
			if shifted_c.intersects(grown_p):
				return true
	return false

func _spawn_room(logic_node: LogicalNode, rng: RandomNumberGenerator) -> BaseRoom:
	var room := logic_node.blueprint.room_scene.instantiate() as BaseRoom
	add_child(room)
	_register_room_instance(logic_node, room)
	if room.has_method("setup_room"):
		await room.setup_room(rng, logic_node)
	await get_tree().process_frame
	return room


func _register_room_instance(logical_node: LogicalNode, room_instance: BaseRoom) -> void:
	if logical_node == null or room_instance == null:
		return
	room_instances_by_node_id[logical_node.id] = room_instance
	if room_instance.has_method("bind_to_logic"):
		room_instance.bind_to_logic(logical_node)

# ==============================================================================
# Helpers
# ==============================================================================

func _assign_physical_connections(graph: LogicalGraph, room_map: Dictionary) -> Array[PhysicalConnection]:
	var result: Array[PhysicalConnection] = []
	var needs_junction: Array[LogicalEdge] = []

	for edge in graph.edges:
		if not room_map.has(edge.from_node) or not room_map.has(edge.to_node):
			push_warning("Skipping edge %s because one endpoint has no physical room." % edge.id)
			continue

		var from_room: BaseRoom = room_map[edge.from_node]
		var to_room: BaseRoom = room_map[edge.to_node]

		var from_gateway := from_room.claim_gateway_for_edge(edge, true)

		if not from_gateway:
			if edge.edge_type == "key_branch":
				needs_junction.append(edge)
			else:
				push_warning("Could not assign from_gateway for edge %s: %s -> %s" % [
					edge.id, edge.from_node.id, edge.to_node.id
				])
			continue

		var to_gateway := to_room.claim_gateway_for_edge(edge, false)

		if not to_gateway:
			push_warning("Could not assign to_gateway for edge %s: %s -> %s" % [
				edge.id, edge.from_node.id, edge.to_node.id
			])
			continue

		edge.from_gateway_id = from_gateway.gateway_id
		edge.to_gateway_id = to_gateway.gateway_id

		var from_anchor := PhysicalAnchor.from_gateway(from_gateway, edge, edge.from_node)
		var to_anchor := PhysicalAnchor.from_gateway(to_gateway, edge, edge.to_node)

		var connection := PhysicalConnection.new()
		connection.logical_edge = edge
		connection.from_node = edge.from_node
		connection.to_node = edge.to_node
		connection.from_room = from_room
		connection.to_room = to_room
		connection.from_anchor = from_anchor
		connection.to_anchor = to_anchor

		result.append(connection)

	for edge in needs_junction:
		_try_assign_corridor_junction(edge, room_map, result)

	return result


func _try_assign_corridor_junction(
	edge: LogicalEdge,
	room_map: Dictionary,
	result: Array[PhysicalConnection]
) -> void:
	var from_node: LogicalNode = edge.from_node
	var to_node: LogicalNode = edge.to_node
	var from_room: BaseRoom = room_map[from_node]
	var to_room: BaseRoom = room_map[to_node]

	var to_gateway := to_room.claim_gateway_for_edge(edge, false)
	if to_gateway == null:
		push_warning("Junction: no gateway in key room for edge %s" % edge.id)
		return

	# from_anchor is a placeholder; CorridorNetwork.build() will find the actual
	# junction point on a committed corridor polyline during Phase 2.
	var from_anchor := PhysicalAnchor.new()
	from_anchor.kind = PhysicalAnchor.AnchorKind.CORRIDOR_POINT
	from_anchor.owner_node = from_node
	from_anchor.owner_edge = edge

	var to_anchor := PhysicalAnchor.from_gateway(to_gateway, edge, to_node)
	edge.to_gateway_id = to_gateway.gateway_id

	var connection := PhysicalConnection.new()
	connection.logical_edge = edge
	connection.from_node = from_node
	connection.to_node = to_node
	connection.from_room = from_room
	connection.to_room = to_room
	connection.from_anchor = from_anchor
	connection.to_anchor = to_anchor

	result.append(connection)

func _place_room_corridor_friendly(
		child_room: BaseRoom,
		parent_room: BaseRoom,
		placed_aabbs: Array[AABB],
		rng: RandomNumberGenerator,
		required_y: float,
		edge: LogicalEdge
	) -> bool:
	var distance_steps: Array[float] = [18.0, 24.0, 30.0, 36.0, 44.0, 52.0]

	if edge.edge_type == "boss_return" or edge.tags.has("loop"):
		distance_steps = [10.0, 14.0, 18.0, 22.0, 26.0]

	return _place_room_near_room(
		child_room,
		parent_room,
		placed_aabbs,
		rng,
		required_y,
		distance_steps
	)

func _place_room_near_room(
		child_room: BaseRoom,
		parent_room: BaseRoom,
		placed_aabbs: Array[AABB],
		rng: RandomNumberGenerator,
		required_y: float,
		distance_steps: Array[float]
	) -> bool:
	var dirs: Array[Vector3] = [
		Vector3.FORWARD,
		Vector3.BACK,
		Vector3.RIGHT,
		Vector3.LEFT,
		Vector3(1, 0, 1).normalized(),
		Vector3(1, 0, -1).normalized(),
		Vector3(-1, 0, 1).normalized(),
		Vector3(-1, 0, -1).normalized()
	]

	_shuffle_array(dirs, rng)
	var child_aabbs := child_room.get_world_aabbs()

	for dist in distance_steps:
		for dir in dirs:
			var base_pos: Vector3 = parent_room.global_position + dir * dist
			var test_pos := Vector3(
				snappedf(base_pos.x, GRID_SIZE),
				required_y,
				snappedf(base_pos.z, GRID_SIZE)
			)

			if not _check_aabb_overlap(test_pos, child_room, child_aabbs, placed_aabbs):
				child_room.global_position = test_pos
				return true

	return false

func _place_room_fallback(
		child_room: BaseRoom,
		parent_room: BaseRoom,
		placed_aabbs: Array[AABB],
		rng: RandomNumberGenerator,
		required_y: float
	) -> void:
	var test_radius: float = 20.0
	var child_aabbs := child_room.get_world_aabbs()

	while true:
		var angle: float = rng.randf_range(0.0, TAU)
		var raw_pos: Vector3 = parent_room.global_position + Vector3(cos(angle), 0.0, sin(angle)) * test_radius

		# Strict Grid Snapping.
		# Forces gateways to land on perfect integer coordinates for A* integration.
		var test_pos := Vector3(
			snappedf(raw_pos.x, GRID_SIZE),
			required_y,
			snappedf(raw_pos.z, GRID_SIZE)
		)

		if not _check_aabb_overlap(test_pos, child_room, child_aabbs, placed_aabbs):
			child_room.global_position = test_pos
			return

		test_radius += 5.0

func _shuffle_array(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp

func _find_first_node_with_tag(graph: LogicalGraph, tag: String) -> LogicalNode:
	for node in graph.nodes:
		if node.assigned_tags.has(tag):
			return node
	return null

func _validate_logical_graph(graph: LogicalGraph) -> bool:
	var ok := true

	if graph.nodes.is_empty():
		push_error("DungeonGenerator: LogicalGraph has no nodes.")
		return false

	if graph.edges.is_empty():
		push_warning("DungeonGenerator: LogicalGraph has no edges.")

	for node in graph.nodes:
		if node == null:
			push_error("DungeonGenerator: LogicalGraph contains null node.")
			ok = false
			continue

		if node.id == "":
			push_warning("DungeonGenerator: LogicalNode has empty id.")

		if node.blueprint == null:
			push_error("DungeonGenerator: Node '%s' has no blueprint." % node.id)
			ok = false

	for edge in graph.edges:
		if edge == null:
			push_error("DungeonGenerator: LogicalGraph contains null edge.")
			ok = false
			continue

		if edge.from_node == null or edge.to_node == null:
			push_error("DungeonGenerator: Edge '%s' has missing endpoint." % edge.id)
			ok = false

		if edge.from_node != null and not graph.nodes.has(edge.from_node):
			push_error("DungeonGenerator: Edge '%s' from_node is not in graph.nodes." % edge.id)
			ok = false

		if edge.to_node != null and not graph.nodes.has(edge.to_node):
			push_error("DungeonGenerator: Edge '%s' to_node is not in graph.nodes." % edge.id)
			ok = false

		if edge.edge_type == "locked" and not edge.requirements.has("key_id"):
			push_warning("DungeonGenerator: Locked edge '%s' has no key_id yet." % edge.id)

	if not _validate_lock_blocks_boss(graph):
		ok = false

	if not _validate_loop_return_blockers(graph):
		ok = false

	return ok


func _validate_lock_blocks_boss(graph: LogicalGraph) -> bool:
	var has_locked_edge := false
	for edge in graph.edges:
		if edge != null and edge.edge_type == "locked":
			has_locked_edge = true
			break

	if not has_locked_edge:
		return true

	var start_node := _find_first_node_with_tag(graph, "Entrance")
	if start_node == null and not graph.nodes.is_empty():
		start_node = graph.nodes[0]

	if start_node == null:
		return true

	var queue: Array[LogicalNode] = [start_node]
	var visited := { start_node: true }

	while not queue.is_empty():
		var node: LogicalNode = queue.pop_front()
		if node.assigned_tags.has("Boss"):
			push_warning("DungeonGenerator: Boss is reachable before crossing a locked edge. Rejecting graph.")
			return false

		for edge in node.out_edges:
			if edge == null:
				continue

			if edge.edge_type == "locked":
				continue

			if edge.edge_type == "boss_return" or edge.tags.has("loop"):
				continue

			var next_node := edge.to_node
			if next_node == null or visited.has(next_node):
				continue

			visited[next_node] = true
			queue.append(next_node)

	return true


func _validate_loop_return_blockers(graph: LogicalGraph) -> bool:
	var ok := true

	for edge in graph.edges:
		if edge == null:
			continue

		if edge.edge_type != "boss_return" and not edge.tags.has("loop"):
			continue

		var has_false_door := false
		var has_boss_trigger := false

		for descriptor in _get_component_descriptors(edge.custom_data):
			if not descriptor is Dictionary:
				continue

			var component_type := str((descriptor as Dictionary).get("component_type", ""))
			var edge_side := str((descriptor as Dictionary).get("edge_side", ""))

			if component_type == "false_door" and edge_side == "to":
				has_false_door = true

			if component_type == "lock_trigger" and edge_side == "from":
				has_boss_trigger = true

		if not has_false_door or not has_boss_trigger:
			push_warning(
				"DungeonGenerator: boss return edge %s is missing its entrance false door or boss-side trigger."
				% edge.id
			)
			ok = false

	return ok

func _spawn_graph_components(graph: LogicalGraph) -> void:
	if verbose_generation_logs:
		print("")
		print("========== SPAWNING DUNGEON COMPONENTS ==========")

	for node in graph.nodes:
		_spawn_node_components(node)

	for edge in graph.edges:
		_spawn_edge_components(edge)

	if verbose_generation_logs:
		print("=================================================")
		print("")


func _spawn_node_components(logical_node: LogicalNode) -> void:
	if logical_node == null:
		return

	var room_instance := _get_room_instance_for_node(logical_node)
	if room_instance == null:
		push_warning(
			"Cannot spawn node components. No room instance for node_id=%s" % logical_node.id
		)
		return

	for descriptor in _get_component_descriptors(logical_node.custom_data):
		_spawn_component_from_descriptor(room_instance, descriptor, logical_node, null)


func _spawn_edge_components(edge: LogicalEdge) -> void:
	if edge == null:
		return

	for descriptor in _get_component_descriptors(edge.custom_data):
		var edge_side := str(descriptor.get("edge_side", ""))

		var target_node: LogicalNode
		match edge_side:
			"from":
				target_node = edge.from_node
			"to":
				target_node = edge.to_node
			_:
				push_warning(
					"Edge component %s has invalid edge_side='%s'. Expected 'from' or 'to'."
					% [str(descriptor.get("component_id", "")), edge_side]
				)
				continue

		if target_node == null:
			push_warning(
				"Edge component %s has no target node for edge_side=%s on edge=%s"
				% [str(descriptor.get("component_id", "")), edge_side, edge.id]
			)
			continue

		var room_instance := _get_room_instance_for_node(target_node)
		if room_instance == null:
			push_warning(
				"Cannot spawn edge component %s. No room instance for node_id=%s edge=%s"
				% [str(descriptor.get("component_id", "")), target_node.id, edge.id]
			)
			continue

		_spawn_component_from_descriptor(room_instance, descriptor, target_node, edge)


func _spawn_component_from_descriptor(
	room_instance: Node3D,
	descriptor: Dictionary,
	logical_node: LogicalNode,
	logical_edge: LogicalEdge = null
) -> void:
	var component_id := str(descriptor.get("component_id", ""))
	var component_type := str(descriptor.get("component_type", ""))
	var scene_key := str(descriptor.get("scene_key", ""))
	var socket_role := str(descriptor.get("socket_role", ""))
	var gateway_role := str(descriptor.get("gateway_role", ""))

	var socket := _find_component_socket(room_instance, socket_role, gateway_role, component_type)

	if socket == null:
		push_warning(
			"No socket found for component_id=%s component_type=%s scene_key=%s socket_role=%s gateway_role=%s in room=%s. Available sockets: %s"
			% [
				component_id, component_type, scene_key,
				socket_role, gateway_role, room_instance.name,
				_debug_socket_summary(room_instance)
			]
		)
		return

	var packed_scene := _get_component_scene(scene_key)
	if packed_scene == null:
		push_warning("No component scene registered for scene_key=%s" % scene_key)
		return

	var instance := packed_scene.instantiate()
	if not instance is DungeonComponent:
		push_warning(
			"Scene for scene_key=%s does not have a DungeonComponent root. Root is %s."
			% [scene_key, instance.get_class()]
		)
		instance.queue_free()
		return

	var component := instance as DungeonComponent

	if not component_id.is_empty():
		component.name = component_id

	component.bind_to_logic(logical_node, logical_edge)

	if component is LockComponent:
		(component as LockComponent).configure_from_descriptor(descriptor)
	else:
		component.component_id = component_id
		component.component_type = component_type

	component.transform = Transform3D.IDENTITY
	socket.add_child(component)

	if component_type == "false_door":
		_align_component_to_claimed_gateway(
			component,
			room_instance,
			logical_edge,
			gateway_role
		)

	if verbose_generation_logs:
		print(
			"DungeonGenerator: spawned component_id=", component_id,
			" component_type=", component_type,
			" scene_key=", scene_key,
			" room=", room_instance.name,
			" socket=", socket.name,
			" logical_node=", logical_node.id if logical_node else "",
			" logical_edge=", logical_edge.id if logical_edge else ""
		)


func _get_component_descriptors(custom_data: Dictionary) -> Array:
	var raw = custom_data.get(COMPONENT_DESCRIPTORS_KEY, [])
	if raw is Array:
		return raw
	return []


func _get_room_instance_for_node(logical_node: LogicalNode) -> Node3D:
	if logical_node == null:
		return null
	return room_instances_by_node_id.get(logical_node.id, null)


func _get_component_scene(scene_key: String) -> PackedScene:
	return COMPONENT_SCENE_REGISTRY.get(scene_key, null)


func _align_component_to_claimed_gateway(
	component: Node3D,
	room_instance: Node3D,
	logical_edge: LogicalEdge,
	gateway_role: String = ""
) -> void:
	if component == null or logical_edge == null:
		return

	if not room_instance is BaseRoom:
		return

	var gateway := _find_claimed_gateway_for_edge(
		room_instance as BaseRoom,
		logical_edge,
		gateway_role
	)

	if gateway == null:
		return

	component.global_transform = gateway.global_transform


func _find_claimed_gateway_for_edge(
	room_instance: BaseRoom,
	logical_edge: LogicalEdge,
	gateway_role: String = ""
) -> Gateway:
	var fallback: Gateway = null

	for gateway in room_instance.get_gateways():
		if gateway == null:
			continue

		if not gateway.connected_edges.has(logical_edge):
			continue

		if gateway_role.is_empty() or gateway.role == gateway_role:
			return gateway

		if fallback == null:
			fallback = gateway

	return fallback


func _find_component_socket(
	root: Node,
	socket_role: String,
	gateway_role: String = "",
	component_type: String = ""
) -> Node3D:
	var fallback_socket: Node3D = null

	for child in root.find_children("*", "", true, false):
		if not child is Node3D:
			continue

		var socket := child as Node3D

		if not _is_component_socket(socket):
			continue

		if not _socket_accepts_role(socket, socket_role):
			continue

		if not _socket_accepts_component_type(socket, component_type):
			continue

		if gateway_role.is_empty():
			return socket

		if _socket_has_exact_gateway_role(socket, gateway_role):
			return socket

		if _socket_accepts_gateway_role(socket, gateway_role):
			if fallback_socket == null:
				fallback_socket = socket

	return fallback_socket


func _is_component_socket(node: Node) -> bool:
	return node.has_method("can_accept_component_role") or node.has_meta("socket_role")


func _socket_accepts_role(socket: Node, socket_role: String) -> bool:
	if socket.has_method("can_accept_component_role"):
		return socket.can_accept_component_role(socket_role)
	if socket.has_meta("socket_role"):
		return str(socket.get_meta("socket_role")) == socket_role
	return false


func _socket_accepts_gateway_role(socket: Node, gateway_role: String) -> bool:
	if gateway_role.is_empty():
		return true
	if socket.has_method("can_accept_gateway_role"):
		return socket.can_accept_gateway_role(gateway_role)
	if socket.has_meta("gateway_role"):
		var socket_gateway_role := str(socket.get_meta("gateway_role"))
		return socket_gateway_role.is_empty() or socket_gateway_role == gateway_role
	return true


func _socket_has_exact_gateway_role(socket: Node, gateway_role: String) -> bool:
	if gateway_role.is_empty():
		return false
	if socket.has_meta("gateway_role"):
		return str(socket.get_meta("gateway_role")) == gateway_role
	var socket_gateway = socket.get("gateway_role")
	if socket_gateway != null:
		return str(socket_gateway) == gateway_role
	return false


func _socket_accepts_component_type(socket: Node, component_type: String) -> bool:
	if component_type.is_empty():
		return true
	if socket.has_method("can_accept_component_type"):
		return socket.can_accept_component_type(component_type)
	return true


func _debug_socket_summary(root: Node) -> String:
	var parts: Array[String] = []

	for child in root.find_children("*", "", true, false):
		if not _is_component_socket(child):
			continue

		var socket_role := ""
		var gateway_role := ""

		if child.has_meta("socket_role"):
			socket_role = str(child.get_meta("socket_role"))
		else:
			var value = child.get("socket_role")
			if value != null:
				socket_role = str(value)

		if child.has_meta("gateway_role"):
			gateway_role = str(child.get_meta("gateway_role"))
		else:
			var gateway_value = child.get("gateway_role")
			if gateway_value != null:
				gateway_role = str(gateway_value)

		parts.append(
			"%s(socket_role=%s,gateway_role=%s)" % [child.name, socket_role, gateway_role]
		)

	return ", ".join(parts)
