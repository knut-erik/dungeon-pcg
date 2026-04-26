extends Node3D
class_name DungeonGenerator

@export var room_library: Array[RoomBlueprint] = []

@export var num_challenges: int = 3
@export var create_loop: bool = true

# The grid size should ~match CorridorNetwork.GRID_SIZE
const GRID_SIZE := 1.0 

func _ready() -> void:
	if room_library.is_empty():
		push_error("DungeonGenerator saknar RoomBlueprints! Lägg till dem i editorn.")
		return
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var rewriter := GraphRewriter.new(room_library, num_challenges, create_loop)
	var graph: LogicalGraph = rewriter.generate()

	if not _validate_logical_graph(graph):
		return

	await _build_physical_dungeon(graph, rng)

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

func _build_physical_dungeon(graph: LogicalGraph, rng: RandomNumberGenerator) -> void:
	var physical_rooms: Array[BaseRoom] = []
	var room_map: Dictionary = {}

	if graph.nodes.is_empty():
		push_error("DungeonGenerator: LogicalGraph has no nodes.")
		return

	var start_logic: LogicalNode = graph.nodes[0]
	var start_room: BaseRoom = await _spawn_room(start_logic)
	start_room.position = Vector3.ZERO

	physical_rooms.append(start_room)
	room_map[start_logic] = start_room

	var boss_logic: LogicalNode = _find_first_node_with_tag(graph, "Boss")

	if boss_logic and boss_logic != start_logic:
		var boss_room: BaseRoom = await _spawn_room(boss_logic)

		var placed_boss := _place_room_near_room(
			boss_room,
			start_room,
			physical_rooms,
			rng,
			start_room.global_position.y,
			[14.0, 18.0, 22.0, 26.0, 30.0]
		)

		if not placed_boss:
			_place_room_fallback(
				boss_room,
				start_room,
				physical_rooms,
				rng,
				start_room.global_position.y
			)

		physical_rooms.append(boss_room)
		room_map[boss_logic] = boss_room

	var queue: Array[LogicalNode] = [start_logic]
	var visited := { start_logic: true }

	if boss_logic:
		visited[boss_logic] = true
	
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

			var child_room := await _spawn_room(child_logic)

			var target_gateway_y := curr_room.global_position.y

			# Introduce Y-height variations organically. 
			# The CorridorNetwork will intercept these deltas and build stairs automatically.
			var should_change_height := rng.randf() < 0.30
			if should_change_height:
				var direction := 1.0 if rng.randf() > 0.5 else -1.0
				target_gateway_y += rng.randf_range(4.0, 8.0) * direction

			var required_y := target_gateway_y

			var placed := _place_room_corridor_friendly(
				child_room,
				curr_room,
				physical_rooms,
				rng,
				required_y,
				edge
			)

			if not placed:
				push_warning("Failed to place room for node %s. Using fallback radial placement." % child_logic.id)
				_place_room_fallback(child_room, curr_room, physical_rooms, rng, required_y)

			physical_rooms.append(child_room)
			room_map[child_logic] = child_room

	# Place nodes not reached by directed traversal, if any.
	for node in graph.nodes:
		if room_map.has(node):
			continue

		var orphan_room := await _spawn_room(node)
		_place_room_fallback(orphan_room, start_room, physical_rooms, rng, start_room.global_position.y)
		physical_rooms.append(orphan_room)
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
	await network.build(physical_connections, room_aabbs, room_library)

	var debug := DungeonDebugDraw.new()
	add_child(debug)
	# Ensures DungeonDebugDraw._ready() has initialized its ImmediateMesh.
	await get_tree().process_frame
	debug.draw_debug(network, physical_rooms, network.get_stair_rooms())

# ==============================================================================
# DEL 3: KOLLISIONSHJÄLPARE
# ==============================================================================

func _check_aabb_overlap(test_pos: Vector3, child_room: BaseRoom, placed_rooms: Array[BaseRoom]) -> bool:
	# Breathing margin guarantees A* always has routing lanes between rooms.
	# Do not reduce below corridor_width (3.0) + some clearance.
	var margin := Vector3.ONE * 7.0

	# child_room is not yet placed — get_world_aabbs() reflects its current
	# position (likely zero). We offset each AABB by (test_pos - current_pos)
	# to simulate where it would sit if placed at test_pos. Change this?
	var placement_offset := test_pos - child_room.global_position

	for placed_room in placed_rooms:
		for c_aabb in child_room.get_world_aabbs():
			# Shift the candidate AABB to the test position, then grow by margin
			var shifted_c := AABB(c_aabb.position + placement_offset, c_aabb.size).grow(margin.x * 0.5)
			for p_aabb in placed_room.get_world_aabbs():
				var grown_p := p_aabb.grow(margin.x * 0.5)
				if shifted_c.intersects(grown_p):
					return true
	return false

func _spawn_room(logic_node) -> BaseRoom:
	var room = logic_node.blueprint.room_scene.instantiate() as BaseRoom
	add_child(room)
	if room.has_method("setup_room"):
		await room.setup_room(RandomNumberGenerator.new(), logic_node)
	return room

# ==============================================================================
# Helpers
# ==============================================================================

func _assign_physical_connections(graph: LogicalGraph, room_map: Dictionary) -> Array[PhysicalConnection]:
	var result: Array[PhysicalConnection] = []

	for edge in graph.edges:
		if not room_map.has(edge.from_node) or not room_map.has(edge.to_node):
			push_warning("Skipping edge %s because one endpoint has no physical room." % edge.id)
			continue

		var from_room: BaseRoom = room_map[edge.from_node]
		var to_room: BaseRoom = room_map[edge.to_node]

		var from_gateway := from_room.claim_gateway_for_edge(edge, true)
		var to_gateway := to_room.claim_gateway_for_edge(edge, false)

		if not from_gateway or not to_gateway:
			push_warning("Could not assign gateways for edge %s: %s -> %s" % [
				edge.id,
				edge.from_node.id,
				edge.to_node.id
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

	for node in graph.nodes:
		if not room_map.has(node):
			continue

		var room: BaseRoom = room_map[node]
		var gateway_count := room.get_gateways().size()

		if gateway_count < node.degree():
			push_warning("Room for node %s has degree %d but only %d gateways." % [
				node.id,
				node.degree(),
				gateway_count
			])

	return result

func _place_room_corridor_friendly(
		child_room: BaseRoom,
		parent_room: BaseRoom,
		physical_rooms: Array[BaseRoom],
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
		physical_rooms,
		rng,
		required_y,
		distance_steps
	)

func _place_room_near_room(
		child_room: BaseRoom,
		parent_room: BaseRoom,
		physical_rooms: Array[BaseRoom],
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

	dirs.shuffle()

	for dist in distance_steps:
		for dir in dirs:
			var base_pos: Vector3 = parent_room.global_position + dir * dist
			var test_pos := Vector3(
				snappedf(base_pos.x, GRID_SIZE),
				required_y,
				snappedf(base_pos.z, GRID_SIZE)
			)

			if not _check_aabb_overlap(test_pos, child_room, physical_rooms):
				child_room.global_position = test_pos
				return true

	return false

func _place_room_fallback(
		child_room: BaseRoom,
		parent_room: BaseRoom,
		physical_rooms: Array[BaseRoom],
		rng: RandomNumberGenerator,
		required_y: float
	) -> void:

	var test_radius: float = 20.0

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

		if not _check_aabb_overlap(test_pos, child_room, physical_rooms):
			child_room.global_position = test_pos
			return

		test_radius += 5.0

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

	return ok
