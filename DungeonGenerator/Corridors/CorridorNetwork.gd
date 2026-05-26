extends Node3D
class_name CorridorNetwork

const CORRIDOR_WIDTH  := 3.0
const CORRIDOR_HEIGHT := 3.4
const SLAB_T          := 0.15 # T for threshold 

# TODO: Explain constants with comments
const GRID_SCALE      := 2.0  # SCALE = 2.0 means 1 Grid Unit = 0.5 World Units. This perfectly captures 0.5 offset gateways without floating point errors!
const WALL_MERGE_EPS := 0.08
const Y_EPS := 0.15
const ROOM_WALL_CUT_MARGIN := 0.20
const GATEWAY_EXEMPT_STEPS := 6 # How many grid steps from start/goal are exempt from AABB collision. CORRIDOR_WIDTH=3.0, GRID_SCALE=2.0 → wall thickness is ~2 grid units. 6 gives a safe margin to clear the room wall before collision kicks in.
const GATEWAY_SIDEWALL_ALIGN_TOL := 0.30
const GATEWAY_SIDEWALL_DOT_LIMIT := -0.75
const GATEWAY_RESERVED_THROAT_STEPS := 6
const GATEWAY_RESERVED_THROAT_HALF_WIDTH := CORRIDOR_WIDTH * 0.5 + 0.10
const GATEWAY_CORNER_PLUG_OVERLAP := 0.30
const GATEWAY_CORNER_PLUG_DEPTH := SLAB_T * 2.0
const STAIR_CLEARANCE_MARGIN := CORRIDOR_WIDTH * 0.5 + ROOM_WALL_CUT_MARGIN + WALL_MERGE_EPS

const ROUTING_ZONE_KEY := "routing_zone"

var _pending_polylines: Array[PackedVector3Array] = []
var _pending_corridor_aabbs: Array[AABB] = []
var _pending_polyline_records: Array[Dictionary] = []
var _pending_corridor_records: Array[Dictionary] = []
var _active_routing_zone: String = "default"
var _csg_root: CSGCombiner3D
var _room_aabbs: Array[AABB] = []
var _room_aabb_records: Array[Dictionary] = []
var _stair_rooms: Array[BaseRoom] = []
var _stair_aabbs: Array[AABB] = []
var _stair_clearance_aabbs: Array[AABB] = []
var _footprints: Array[Dictionary] = []
var _gateway_openings: Array[Dictionary] = []  # { "pos": Vector3, "dir": Vector2 }
var _room_library: Array[RoomBlueprint] = []
var _rng: RandomNumberGenerator
var _active_edge_id: String = ""
var _reserved_gateway_throats: Array[Dictionary] = []
var _gateway_corner_plug_count := 0

const ASTAR_SEARCH_MARGIN_GRID := 80
const ASTAR_MAX_ITERATIONS := 50000


# Candidate stair routes should fail fast.
# If a stair candidate needs a huge detour, it is a bad candidate.
const ASTAR_CANDIDATE_SEARCH_MARGIN_GRID := 28
const ASTAR_CANDIDATE_MAX_ITERATIONS := 4000

func build(
		connections: Array,
		room_aabbs: Array,
		room_library: Array[RoomBlueprint],
		rng: RandomNumberGenerator = null
	) -> bool:
	_csg_root = CSGCombiner3D.new()
	add_child(_csg_root)
	var route_failed := false
	_rng = rng
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = 1
	
	# Collision generation is expensive while many CSG children are still being added.
	# seal_unused_gateways() enables it once final corridor geometry is complete.
	_csg_root.use_collision = false
	
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://Assets/texture/RockPillar/Color.png")
	mat.normal_enabled = true
	mat.normal_texture = load("res://Assets/texture/RockPillar/Normal.png")
	mat.heightmap_enabled = true
	mat.heightmap_texture = load("res://Assets/texture/RockPillar/Displacement.exr")
	mat.heightmap_scale = 0.15
	_csg_root.material_override = mat
	
	_room_aabbs.assign(room_aabbs)
	_rebuild_room_aabb_records()
	_room_library = room_library

	_footprints.clear()
	_gateway_openings.clear()
	_stair_rooms.clear()
	_stair_aabbs.clear()
	_stair_clearance_aabbs.clear()
	_pending_polylines.clear()
	_pending_corridor_aabbs.clear()
	_pending_polyline_records.clear()
	_pending_corridor_records.clear()
	_reserved_gateway_throats.clear()
	_gateway_corner_plug_count = 0
	_active_routing_zone = "default"
	_active_edge_id = ""

	# Phase 1: route all normal gateway-to-gateway connections.
	# Junction connections (CORRIDOR_POINT) are deferred to Phase 2 so they can
	# find their branch point on already-committed corridor polylines.
	var gateway_connections: Array[PhysicalConnection] = []
	var junction_connections: Array[PhysicalConnection] = []

	for connection in connections:
		var pc := connection as PhysicalConnection
		if not pc:
			continue

		if pc.from_anchor.kind == PhysicalAnchor.AnchorKind.CORRIDOR_POINT:
			junction_connections.append(pc)
		else:
			gateway_connections.append(pc)

	_pre_register_connection_gateways(connections)

	for pc in gateway_connections:
		_active_routing_zone = _get_edge_routing_zone(pc.logical_edge)
		_active_edge_id = pc.logical_edge.id if pc.logical_edge != null else ""

		var ga: Marker3D = pc.from_anchor.gateway
		var gb: Marker3D = pc.to_anchor.gateway

		if not ga or not gb:
			push_warning("CorridorNetwork: PhysicalConnection missing gateway anchors.")
			route_failed = true
			continue
		
		# -- STAIR INJECTION INTERCEPT --
		if absf(ga.global_position.y - gb.global_position.y) > 0.1:
			var success := await _route_vertical_connection_with_stair_candidates(ga, gb)
			if success:
				_register_gateway_opening(ga, pc.logical_edge)
				_register_gateway_opening(gb, pc.logical_edge)
			else:
				push_warning("Candidate stair routing failed. Falling back to polyline stair injection.")
				var fallback_polyline = _route_connection(ga, gb, true, true)
				if fallback_polyline.is_empty():
					push_warning("CorridorNetwork: vertical route failed; no fallback polyline for edge %s" % _active_edge_id)
					route_failed = true
					continue

				var injected := await _inject_stairs_and_split(fallback_polyline, ga, gb)
				if not injected:
					push_warning("CorridorNetwork: vertical route failed; stair injection failed for edge %s" % _active_edge_id)
					route_failed = true
					continue

				_register_gateway_opening(ga, pc.logical_edge)
				_register_gateway_opening(gb, pc.logical_edge)
			continue

		var flat_polyline = _route_connection(ga, gb, false)
		if flat_polyline.is_empty():
			push_warning("CorridorNetwork: flat route failed for edge %s" % _active_edge_id)
			route_failed = true
			continue

		_register_gateway_opening(ga, pc.logical_edge)
		_register_gateway_opening(gb, pc.logical_edge)
		_commit_polyline(flat_polyline)

	# Phase 2: route junction (key-branch) connections.
	# All main-path corridors are now committed so _find_junction_point can
	# locate a real corridor point to branch from.
	# Not a coroutine — call directly, no await.
	for pc in junction_connections:
		_active_routing_zone = _get_edge_routing_zone(pc.logical_edge)
		_active_edge_id = pc.logical_edge.id if pc.logical_edge != null else ""
		var junction_success := _route_junction_connection(pc)
		if not junction_success:
			push_warning("CorridorNetwork: junction route failed for edge %s" % _active_edge_id)
			route_failed = true

	_active_routing_zone = "default"

	print(
		"CorridorNetwork: committed_polylines=",
		_pending_polylines.size(),
		" committed_gateway_openings=",
		_gateway_openings.size(),
		" reserved_gateway_throats=",
		_reserved_gateway_throats.size(),
		" route_failed=",
		route_failed
	)

	if route_failed:
		return false

	_generate_queued_geometry()
	return true

# ── JUNCTION ROUTING ─────────────────────────────────────────────────────────

func _find_junction_point(key_room_pos: Vector3, routing_zone: String = "default") -> Vector3:
	var best := Vector3(INF, INF, INF)
	var best_dist := INF
	var target_y := key_room_pos.y

	for record in _pending_polyline_records:
		var other_zone := str(record.get("routing_zone", "default"))

		if not _corridor_zones_can_merge(routing_zone, other_zone):
			continue

		var polyline := record["polyline"] as PackedVector3Array

		# Skip index 0 and size-1: those are gateway positions sitting inside
		# room AABBs. A* can't start from inside a room without the
		# gateway-throat exemption, which only applies to real room gateways.
		for i in range(1, polyline.size() - 1):
			var point := polyline[i]
			if absf(point.y - target_y) > Y_EPS:
				continue
			var d := Vector2(point.x - key_room_pos.x, point.z - key_room_pos.z).length()
			if d < best_dist:
				best_dist = d
				best = point

	return best


func _route_junction_connection(pc: PhysicalConnection) -> bool:
	var gb: Marker3D = pc.to_anchor.gateway
	if not gb:
		push_warning("Junction: no to_gateway for edge %s" % pc.logical_edge.id)
		return false

	var key_pos := gb.global_position
	var junction_pos := _find_junction_point(key_pos, _active_routing_zone)

	if junction_pos.x == INF:
		push_warning("Junction: no committed corridor at Y=%.1f to branch from." % key_pos.y)
		return false

	# Use key room Y exactly so there is no height mismatch.
	junction_pos.y = key_pos.y

	var polyline := _route_from_point(junction_pos, gb)
	if polyline.is_empty():
		return false

	_register_gateway_opening(gb, pc.logical_edge)
	_commit_polyline(polyline)
	return true


func _route_from_point(start_pos: Vector3, gb: Marker3D, quiet: bool = false) -> PackedVector3Array:
	# Route from an arbitrary interior corridor position to a room gateway.
	# No direction constraint on the start side — A* exits freely.
	# The gateway direction constraint on gb is preserved.
	if absf(start_pos.y - gb.global_position.y) > 0.1:
		if not quiet:
			push_error("_route_from_point: Y mismatch start=%.2f goal=%.2f" % [start_pos.y, gb.global_position.y])
		return PackedVector3Array()

	var pos_b := gb.global_position
	var out_dir_b := _snap_to_cardinal(-gb.global_transform.basis.z)
	var dir_bi := Vector2i(roundi(out_dir_b.x), roundi(out_dir_b.z))

	var start2i := Vector2i(roundi(start_pos.x * GRID_SCALE), roundi(start_pos.z * GRID_SCALE))
	var goal2i  := Vector2i(roundi(pos_b.x  * GRID_SCALE), roundi(pos_b.z  * GRID_SCALE))

	var goal_owner := _find_owner_aabb_index(pos_b, true)

	var path2i := _directional_astar(
		start2i, goal2i,
		Vector2i.ZERO, dir_bi,   # ZERO = no first-step constraint on junction side
		start_pos.y, start_pos.y,
		-1, goal_owner,          # junction is in open corridor space, no start exemption
		quiet,
		ASTAR_MAX_ITERATIONS,
		ASTAR_SEARCH_MARGIN_GRID
	)

	if path2i.is_empty():
		# Retry with relaxed goal direction so nearby placements can still connect.
		path2i = _directional_astar(
			start2i, goal2i,
			Vector2i.ZERO, Vector2i.ZERO,
			start_pos.y, start_pos.y,
			-1, goal_owner,
			quiet,
			ASTAR_MAX_ITERATIONS,
			ASTAR_SEARCH_MARGIN_GRID
		)

	if path2i.is_empty():
		if not quiet:
			push_warning("Junction route failed: %s → %s" % [start_pos, pos_b])
		return PackedVector3Array()

	var p3 := PackedVector3Array()
	for p in path2i:
		p3.append(Vector3(float(p.x) / GRID_SCALE, start_pos.y, float(p.y) / GRID_SCALE))
	return _clean_collinear(p3)


# ── INJECTION SYSTEM ─────────────────────────────────────────────────────────

func _route_vertical_connection_with_stair_candidates(ga: Marker3D, gb: Marker3D) -> bool:
	var delta_y := gb.global_position.y - ga.global_position.y

	var stair_blueprints = _room_library.filter(func(bp): return bp.possible_tags.has("Stairs"))
	if stair_blueprints.is_empty():
		push_error("CorridorNetwork: No blueprints found with the 'Stairs' tag!")
		return false

	var chosen_blueprint = stair_blueprints[_rng.randi_range(0, stair_blueprints.size() - 1)]
	var stair_room = chosen_blueprint.room_scene.instantiate() as BaseRoom
	get_parent().add_child(stair_room)

	var dummy_logic := LogicalNode.new()
	dummy_logic.custom_data["delta_y"] = delta_y
	await stair_room.setup_room(_rng, dummy_logic)
	await get_tree().process_frame

	var gw_in_local : Vector3 = stair_room.gateway_in.position
	var gw_out_local : Vector3 = stair_room.gateway_out.position
	var req_length := Vector2(gw_in_local.x, gw_in_local.z).distance_to(Vector2(gw_out_local.x, gw_out_local.z))

	var candidate_dirs := [
		Vector3.FORWARD,
		Vector3.BACK,
		Vector3.RIGHT,
		Vector3.LEFT
	]

	var candidate_origins := [
		ga.global_position,
		gb.global_position,
		(ga.global_position + gb.global_position) * 0.5
	]

	var candidate_offsets := [
		req_length * 0.5 + CORRIDOR_WIDTH,
		req_length * 0.5 + CORRIDOR_WIDTH * 2.0,
		req_length * 0.5 + CORRIDOR_WIDTH * 3.0
	]

	var room_aabb_count_before_search := _room_aabbs.size()

	for origin in candidate_origins:
		for dir in candidate_dirs:
			for offset in candidate_offsets:
				var center_pos : Vector3 = origin + dir * offset
				center_pos.x = snappedf(center_pos.x, 1.0)
				center_pos.z = snappedf(center_pos.z, 1.0)

				stair_room.global_position = Vector3(center_pos.x, ga.global_position.y, center_pos.z)
				stair_room.look_at(stair_room.global_position + dir, Vector3.UP)

				await get_tree().process_frame

				var candidate_aabbs: Array[AABB] = []
				for world_aabb in stair_room.get_world_aabbs():
					candidate_aabbs.append(world_aabb)

				if _candidate_aabbs_hit_pending_corridors(candidate_aabbs):
					continue

				if _candidate_aabbs_hit_rooms(candidate_aabbs):
					continue

				var room_aabb_count_before_candidate := _room_aabbs.size()

				for aabb in candidate_aabbs:
					_append_room_aabb(aabb)

				var path_to_stairs := _route_connection(
					ga,
					stair_room.gateway_in,
					false,
					true,
					ASTAR_CANDIDATE_MAX_ITERATIONS,
					ASTAR_CANDIDATE_SEARCH_MARGIN_GRID
				)

				if path_to_stairs.is_empty():
					_truncate_room_aabbs(room_aabb_count_before_candidate)
					continue

				var path_from_stairs := _route_connection(
					stair_room.gateway_out,
					gb,
					false,
					true,
					ASTAR_CANDIDATE_MAX_ITERATIONS,
					ASTAR_CANDIDATE_SEARCH_MARGIN_GRID
				)

				if not path_from_stairs.is_empty():
					_register_gateway_opening(stair_room.gateway_in)
					_register_gateway_opening(stair_room.gateway_out)

					_commit_polyline(path_to_stairs)
					_commit_polyline(path_from_stairs)

					_stair_rooms.append(stair_room)
					_remember_stair_aabbs(stair_room)
					return true

				_truncate_room_aabbs(room_aabb_count_before_candidate)

	_truncate_room_aabbs(room_aabb_count_before_search)
	stair_room.queue_free()
	return false

func _gateway_has_clear_first_step(from_gateway: Marker3D, to_gateway: Marker3D) -> bool:
	var pos_a := from_gateway.global_position
	var pos_b := to_gateway.global_position

	var out_dir_a := _snap_to_cardinal(-from_gateway.global_transform.basis.z)

	var start2i := Vector2i(roundi(pos_a.x * GRID_SCALE), roundi(pos_a.z * GRID_SCALE))
	var first_step := start2i + Vector2i(roundi(out_dir_a.x), roundi(out_dir_a.z))

	var min_y := minf(pos_a.y, pos_b.y)
	var max_y := maxf(pos_a.y, pos_b.y)

	var start_owner := _find_owner_aabb_index(pos_a)
	var ignored := -1

	if start_owner != -1 and _edge_in_gateway_throat(start2i, first_step, start2i, Vector2i(roundi(out_dir_a.x), roundi(out_dir_a.z))):
		ignored = start_owner

	return _is_edge_valid(start2i, first_step, min_y, max_y, ignored)

func _inject_stairs_and_split(polyline: PackedVector3Array, ga: Marker3D, gb: Marker3D) -> bool:
	var delta_y := gb.global_position.y - ga.global_position.y
	
	var stair_blueprints = _room_library.filter(func(bp): return bp.possible_tags.has("Stairs"))
	if stair_blueprints.is_empty():
		push_error("CorridorNetwork: No blueprints found with the 'Stairs' tag!")
		return false
	var chosen_blueprint = stair_blueprints[_rng.randi_range(0, stair_blueprints.size() - 1)]
	
	var stair_room = chosen_blueprint.room_scene.instantiate() as BaseRoom
	get_parent().add_child(stair_room) 
	
	var dummy_logic = LogicalNode.new()
	dummy_logic.custom_data["delta_y"] = delta_y
	await stair_room.setup_room(_rng, dummy_logic)
	
	await get_tree().process_frame
	
	var gw_in_local: Vector3 = stair_room.gateway_in.position
	var gw_out_local: Vector3 = stair_room.gateway_out.position
	var req_length: float = Vector2(gw_in_local.x, gw_in_local.z).distance_to(Vector2(gw_out_local.x, gw_out_local.z))
	
	var segment_indices: Array[int] = []

	for i in range(polyline.size() - 1):
		var length := polyline[i].distance_to(polyline[i + 1])
		if length >= req_length + 2.0:
			segment_indices.append(i)

	if segment_indices.is_empty():
		push_warning("Stair Injection Failed! No XZ segment long enough for stairs %.1f." % req_length)
		stair_room.queue_free()
		return false

	segment_indices.sort_custom(func(a: int, b: int) -> bool:
		return polyline[a].distance_to(polyline[a + 1]) > polyline[b].distance_to(polyline[b + 1])
	)

	var t_values: Array[float] = [0.5, 0.35, 0.65, 0.25, 0.75]
	var placed_stairs := false

	for seg_i in segment_indices:
		var p1: Vector3 = polyline[seg_i]
		var p2: Vector3 = polyline[seg_i + 1]
		var seg_len: float = p1.distance_to(p2)
		var dir: Vector3 = (p2 - p1).normalized()

		var min_t := clampf((req_length * 0.5 + CORRIDOR_WIDTH) / seg_len, 0.05, 0.45)

		for t in t_values:
			if t < min_t or t > 1.0 - min_t:
				continue

			var center_pos := p1.lerp(p2, t)

			stair_room.global_position = Vector3(center_pos.x, ga.global_position.y, center_pos.z)
			stair_room.look_at(stair_room.global_position + dir, Vector3.UP)

			await get_tree().process_frame

			var candidate_aabbs: Array[AABB] = []
			for world_aabb in stair_room.get_world_aabbs():
				candidate_aabbs.append(world_aabb)

			if _candidate_aabbs_hit_pending_corridors(candidate_aabbs):
				continue

			placed_stairs = true
			break

		if placed_stairs:
			break

	if not placed_stairs:
		push_warning("Stair Injection Failed! Stair room would overlap an already-routed corridor.")
		stair_room.queue_free()
		return false
	
	var room_aabb_count_before_stair := _room_aabbs.size()

	for world_aabb in stair_room.get_world_aabbs():
		_append_room_aabb(world_aabb)

	var path_to_stairs := _route_connection(ga, stair_room.gateway_in, false)
	var path_from_stairs := _route_connection(stair_room.gateway_out, gb, false)

	if path_to_stairs.is_empty() or path_from_stairs.is_empty():
		push_warning("Stair Injection Failed! Could not route both sides of injected stair.")
		_truncate_room_aabbs(room_aabb_count_before_stair)
		stair_room.queue_free()
		return false

	_remember_stair_aabbs(stair_room)

	_register_gateway_opening(stair_room.gateway_in)
	_register_gateway_opening(stair_room.gateway_out)

	_commit_polyline(path_to_stairs)
	_commit_polyline(path_from_stairs)

	_stair_rooms.append(stair_room)
	return true

# ── ROUTING ──────────────────────────────────────────────────────────────────

func _route_connection(
		ga: Marker3D,
		gb: Marker3D,
		ignore_y: bool,
		quiet: bool = false,
		max_iterations: int = ASTAR_MAX_ITERATIONS,
		search_margin_grid: int = ASTAR_SEARCH_MARGIN_GRID
	) -> PackedVector3Array:
	var pos_a := ga.global_position
	var pos_b := gb.global_position
	
	if not ignore_y and absf(pos_a.y - pos_b.y) > 0.1:
		if not quiet:
			push_error("Height Mismatch! Y1: ", pos_a.y, " Y2: ", pos_b.y)
		return PackedVector3Array()
		
	var out_dir_a := _snap_to_cardinal(-ga.global_transform.basis.z)
	var out_dir_b := _snap_to_cardinal(-gb.global_transform.basis.z)
	
	var start2i := Vector2i(roundi(pos_a.x * GRID_SCALE), roundi(pos_a.z * GRID_SCALE))
	var goal2i  := Vector2i(roundi(pos_b.x * GRID_SCALE), roundi(pos_b.z * GRID_SCALE))
	var dir_ai  := Vector2i(roundi(out_dir_a.x), roundi(out_dir_a.z))
	var dir_bi  := Vector2i(roundi(out_dir_b.x), roundi(out_dir_b.z))
	
	var min_y := minf(pos_a.y, pos_b.y)
	var max_y := maxf(pos_a.y, pos_b.y)

	# Owner AABB is used only for gateway-throat exemptions; -1 is safe and
	# expected for corridor junction points. Always quiet to avoid noise.
	var start_owner := _find_owner_aabb_index(pos_a, true)
	var goal_owner := _find_owner_aabb_index(pos_b, true)

	var path2i = _directional_astar(
		start2i,
		goal2i,
		dir_ai,
		dir_bi,
		min_y,
		max_y,
		start_owner,
		goal_owner,
		quiet,
		max_iterations,
		search_margin_grid
	)
	
	# Fallback: if strict routing fails, relax the goal approach direction.
	# This handles same-facing gateways at close range where a U-path is geometrically
	# impossible due to room AABBs blocking the required swing-out space.
	if path2i.is_empty():
		if not quiet:
			push_warning("Strict routing failed, retrying with relaxed goal constraint.")

		path2i = _directional_astar(
			start2i,
			goal2i,
			dir_ai,
			Vector2i.ZERO,
			min_y,
			max_y,
			start_owner,
			goal_owner,
			quiet,
			max_iterations,
			search_margin_grid
		)
		
	if path2i.is_empty():
		if not quiet:
			push_warning("Corridor failed: No orthogonal route from %s to %s." % [start2i, goal2i])
		return PackedVector3Array()
		
	var p3 := PackedVector3Array()
	for p in path2i:
		p3.append(Vector3(float(p.x) / GRID_SCALE, pos_a.y, float(p.y) / GRID_SCALE))
		
	return _clean_collinear(p3)


func _find_owner_aabb_index(world_pos: Vector3, quiet: bool = false) -> int:
	for i in range(_room_aabb_records.size()):
		var grown_aabb := _room_aabb_records[i]["grown_aabb"] as AABB
		if grown_aabb.has_point(world_pos):
			return i

	if not quiet:
		push_warning("_find_owner_aabb: No AABB contains point %s" % world_pos)
	return -1

# ── STRICT INTEGER A* WITH MIN-HEAP ──────────────────────────────────────────

func _directional_astar(
		start: Vector2i,
		goal: Vector2i,
		out_a: Vector2i,
		out_b: Vector2i,
		min_y: float,
		max_y: float,
		start_owner: int,
		goal_owner: int,
		quiet: bool = false,
		max_iterations: int = ASTAR_MAX_ITERATIONS,
		search_margin_grid: int = ASTAR_SEARCH_MARGIN_GRID
	) -> Array[Vector2i]:

	if start == goal:
		return [start, goal]

	# Key optimization:
	# If the goal has a required outward direction, do not search for the
	# gateway cell itself. Search for the required approach cell instead,
	# then append the final step into the gateway.
	var astar_goal := goal
	if out_b != Vector2i.ZERO:
		astar_goal = goal + out_b

	# Special case: source is already on the required approach cell.
	if astar_goal == start:
		var final_step := goal - start

		if out_a != Vector2i.ZERO and final_step != out_a:
			return []

		var ignored_final := -1
		if goal_owner != -1 and _edge_in_gateway_throat(start, goal, goal, out_b):
			ignored_final = goal_owner

		if _is_edge_valid(start, goal, min_y, max_y, ignored_final):
			return [start, goal]

		return []

	var heap := _BinHeap.new()
	var came_from := {}
	var g_score := { start: 0.0 }
	var dist_from_start := { start: 0 }
	var closed := {}
	var counter := 0

	var start_h := float(absi(start.x - astar_goal.x) + absi(start.y - astar_goal.y))
	heap.push([start_h, counter, start])
	counter += 1

	var dirs := [
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(-1, 0)
	]

	var min_bound_x := mini(mini(start.x, astar_goal.x), goal.x) - search_margin_grid
	var max_bound_x := maxi(maxi(start.x, astar_goal.x), goal.x) + search_margin_grid
	var min_bound_y := mini(mini(start.y, astar_goal.y), goal.y) - search_margin_grid
	var max_bound_y := maxi(maxi(start.y, astar_goal.y), goal.y) + search_margin_grid

	var iterations := 0

	while not heap.is_empty() and iterations < max_iterations:
		iterations += 1

		var current_data = heap.pop()
		var curr: Vector2i = current_data[2]

		if closed.has(curr):
			continue

		closed[curr] = true

		if curr == astar_goal:
			var path: Array[Vector2i] = [curr]

			while came_from.has(curr):
				curr = came_from[curr]
				path.insert(0, curr)

			if astar_goal != goal:
				var ignored_final := -1

				if goal_owner != -1 and _edge_in_gateway_throat(astar_goal, goal, goal, out_b):
					ignored_final = goal_owner

				if not _is_edge_valid(astar_goal, goal, min_y, max_y, ignored_final):
					return []

				path.append(goal)

			return path

		var is_start := curr == start
		var steps_from_start: int = dist_from_start.get(curr, 999)

		for d in dirs:
			var nxt: Vector2i = curr + d

			if nxt.x < min_bound_x or nxt.x > max_bound_x or nxt.y < min_bound_y or nxt.y > max_bound_y:
				continue

			# If we are using an approach cell, do not enter the real goal
			# from a wrong side during search.
			if astar_goal != goal and nxt == goal:
				continue

			if closed.has(nxt):
				continue

			# First movement must leave the source gateway in its facing direction.
			if is_start and out_a != Vector2i.ZERO and d != out_a:
				continue

			var ignored_aabb_a := -1
			var ignored_aabb_b := -1

			if start_owner != -1 and _edge_in_gateway_throat(curr, nxt, start, out_a):
				ignored_aabb_a = start_owner

			if goal_owner != -1 and out_b != Vector2i.ZERO and _edge_in_gateway_throat(curr, nxt, goal, out_b):
				ignored_aabb_b = goal_owner

			if not _is_edge_valid(curr, nxt, min_y, max_y, ignored_aabb_a, ignored_aabb_b):
				continue

			var tentative_g: float = g_score[curr] + 1.0

			if came_from.has(curr) and curr - came_from[curr] != d:
				tentative_g += 0.5

			if not g_score.has(nxt) or tentative_g < g_score[nxt]:
				came_from[nxt] = curr
				g_score[nxt] = tentative_g
				dist_from_start[nxt] = steps_from_start + 1

				var h := float(absi(nxt.x - astar_goal.x) + absi(nxt.y - astar_goal.y))
				heap.push([tentative_g + h, counter, nxt])
				counter += 1

	if not quiet:
		push_warning("A* exhausted after %d iterations. start=%s goal=%s astar_goal=%s out_a=%s out_b=%s\n" % [
			iterations,
			start,
			goal,
			astar_goal,
			out_a,
			out_b
		])

	return []

func _edge_in_gateway_throat(p1: Vector2i, p2: Vector2i, gateway: Vector2i, out_dir: Vector2i) -> bool:
	if out_dir == Vector2i.ZERO:
		return false

	return (
		_point_in_gateway_throat(p1, gateway, out_dir)
		and _point_in_gateway_throat(p2, gateway, out_dir)
	)

func _point_in_gateway_throat(p: Vector2i, gateway: Vector2i, out_dir: Vector2i) -> bool:
	var d := p - gateway

	if out_dir.x != 0:
		if d.y != 0:
			return false
		return d.x * out_dir.x >= 0 and absi(d.x) <= GATEWAY_EXEMPT_STEPS

	if out_dir.y != 0:
		if d.x != 0:
			return false
		return d.y * out_dir.y >= 0 and absi(d.y) <= GATEWAY_EXEMPT_STEPS

	return false

# Fast Min-Heap replaces array.pop(), stopping Godot Engine Timeouts
class _BinHeap:
	var _data: Array = []
	func is_empty() -> bool: return _data.is_empty()
	func push(item: Array) -> void:
		_data.append(item)
		_sift_up(_data.size() - 1)
	func pop() -> Array:
		var top = _data[0]
		var last = _data.pop_back()
		if not _data.is_empty():
			_data[0] = last
			_sift_down(0)
		return top
	func _sift_up(i: int) -> void:
		while i > 0:
			var p := floori(float(i - 1) / 2.0)
			if _data[i][0] < _data[p][0]:
				var tmp = _data[i]
				_data[i] = _data[p]
				_data[p] = tmp
				i = p
			else: break
	func _sift_down(i: int) -> void:
		var n = _data.size()
		while true:
			var l = 2 * i + 1
			var r = 2 * i + 2
			var s = i
			if l < n and _data[l][0] < _data[s][0]: s = l
			if r < n and _data[r][0] < _data[s][0]: s = r
			if s == i: break
			var tmp = _data[i]
			_data[i] = _data[s]
			_data[s] = tmp
			i = s

# ── EXACT COLLISION CHECKING ─────────────────────────────────────────────────

func _is_edge_valid(
	p1: Vector2i,
	p2: Vector2i,
	min_y: float,
	max_y: float,
	ignored_aabb_a: int = -1,
	ignored_aabb_b: int = -1
) -> bool:
	var w   := CORRIDOR_WIDTH
	var p1f := Vector2(p1) / GRID_SCALE
	var p2f := Vector2(p2) / GRID_SCALE

	var rect: Rect2
	if p1.x == p2.x: # Z movement
		var min_z := minf(p1f.y, p2f.y)
		var max_z := maxf(p1f.y, p2f.y)
		rect = Rect2(p1f.x - w/2.0, min_z - w/2.0, w, (max_z - min_z) + w)
	else: # X movement
		var min_x := minf(p1f.x, p2f.x)
		var max_x := maxf(p1f.x, p2f.x)
		rect = Rect2(min_x - w/2.0, p1f.y - w/2.0, (max_x - min_x) + w, w)

	rect = rect.grow(-0.05)

	var corr_top    := max_y + CORRIDOR_HEIGHT
	var corr_bottom := min_y

	for i in range(_room_aabb_records.size()):
		if i == ignored_aabb_a or i == ignored_aabb_b:
			continue

		var record := _room_aabb_records[i]
		var y_min := float(record["y_min"])
		var y_max := float(record["y_max"])

		if y_max <= corr_bottom or y_min >= corr_top:
			continue

		var room_rect := record["rect"] as Rect2

		if rect.intersects(room_rect):
			return false

	for stair_clearance in _stair_clearance_aabbs:
		if stair_clearance.position.y + stair_clearance.size.y <= corr_bottom:
			continue

		if stair_clearance.position.y >= corr_top:
			continue

		var stair_clearance_rect := Rect2(
			stair_clearance.position.x,
			stair_clearance.position.z,
			stair_clearance.size.x,
			stair_clearance.size.z
		)

		if rect.intersects(stair_clearance_rect):
			return false

	# Same-zone corridors may merge freely at the same height (T-junctions, overlaps).
	# Cross-zone corridors (pre_lock vs post_lock) are always blocked.
	for record in _pending_corridor_records:
		var corridor_aabb := record["aabb"] as AABB
		var other_zone := str(record.get("routing_zone", "default"))

		if corridor_aabb.position.y + corridor_aabb.size.y <= corr_bottom:
			continue

		if corridor_aabb.position.y >= corr_top:
			continue

		if absf(min_y - corridor_aabb.position.y) < Y_EPS:
			if _corridor_zones_can_merge(_active_routing_zone, other_zone):
				continue

		var c_rect := Rect2(
			corridor_aabb.position.x, corridor_aabb.position.z,
			corridor_aabb.size.x, corridor_aabb.size.z
		)
		if rect.intersects(c_rect):
			return false

	if _edge_blocks_reserved_gateway_throat(p1, p2, min_y, max_y, _active_edge_id):
		return false

	return true

# ── GEOMETRY GENERATION ──────────────────────────────────────────────────────

func _generate_queued_geometry() -> void:
	_footprints.clear()

	for record in _pending_polyline_records:
		var polyline := record["polyline"] as PackedVector3Array
		var routing_zone := str(record.get("routing_zone", "default"))
		_register_footprints(polyline, routing_zone)

	for polyline in _pending_polylines:
		_generate_slabs(polyline)

	for record in _pending_polyline_records:
		var polyline := record["polyline"] as PackedVector3Array
		var routing_zone := str(record.get("routing_zone", "default"))
		_generate_walls(polyline, routing_zone)
	
	_generate_gateway_corner_plugs()

func _register_footprints(polyline: PackedVector3Array, routing_zone: String) -> void:
	var w := CORRIDOR_WIDTH

	# Corner/junction squares.
	for i in range(1, polyline.size() - 1):
		var p := polyline[i]
		_footprints.append({
			"rect": Rect2(p.x - w / 2.0, p.z - w / 2.0, w, w),
			"y": p.y,
			"routing_zone": routing_zone
		})

	# Segment rectangles.
	for i in range(polyline.size() - 1):
		var fa := polyline[i]
		var fb := polyline[i + 1]

		var dist := fa.distance_to(fb)
		var is_x: bool = absf(fa.x - fb.x) > absf(fa.z - fb.z)

		var fp_x := minf(fa.x, fb.x) - (0.0 if is_x else w / 2.0) + 0.01
		var fp_z := minf(fa.z, fb.z) - (w / 2.0 if is_x else 0.0) + 0.01
		var fp_w := (dist if is_x else w) - 0.02
		var fp_h := (w if is_x else dist) - 0.02

		_footprints.append({
			"rect": Rect2(fp_x, fp_z, fp_w, fp_h),
			"y": fa.y,
			"routing_zone": routing_zone
		})

func _generate_slabs(polyline: PackedVector3Array) -> void:
	var w := CORRIDOR_WIDTH
	var h := CORRIDOR_HEIGHT

	for i in range(1, polyline.size() - 1):
		var p := polyline[i]
		_make_box(Vector3(w, SLAB_T, w), Vector3(p.x, p.y + SLAB_T / 2.0, p.z))
		_make_box(Vector3(w, SLAB_T, w), Vector3(p.x, p.y + h - SLAB_T / 2.0, p.z))

	for i in range(polyline.size() - 1):
		var fa := polyline[i]
		var fb := polyline[i + 1]

		var dist := fa.distance_to(fb)
		var mid := (fa + fb) * 0.5
		var is_x: bool = absf(fa.x - fb.x) > absf(fa.z - fb.z)

		var size := Vector3(dist, SLAB_T, w) if is_x else Vector3(w, SLAB_T, dist)

		_make_box(size, Vector3(mid.x, fa.y + SLAB_T / 2.0, mid.z))
		_make_box(size, Vector3(mid.x, fa.y + h - SLAB_T / 2.0, mid.z))

func _generate_walls(polyline: PackedVector3Array, routing_zone: String) -> void:
	var w := CORRIDOR_WIDTH
	var h := CORRIDOR_HEIGHT

	for i in range(polyline.size() - 1):
		var fa := polyline[i]
		var fb := polyline[i + 1]
		var is_x: bool = absf(fa.x - fb.x) > absf(fa.z - fb.z)
		
		# Expand wall interval by half corridor width so convex (outer) corners close.
		if is_x:
			var extend_a := w / 2.0 if i > 0 else 0.0
			var extend_b := w / 2.0 if i < polyline.size() - 2 else 0.0

			var a_main := fa.x
			var b_main := fb.x

			var x_min: float
			var x_max: float

			if a_main <= b_main:
				x_min = a_main - extend_a
				x_max = b_main + extend_b
			else:
				x_min = b_main - extend_b
				x_max = a_main + extend_a

			for sign_dir in [-1.0, 1.0]:
				var wall_z: float = fa.z + sign_dir * w * 0.5
				var intervals := _get_exposed_intervals(
					x_min,
					x_max,
					wall_z,
					true,
					sign_dir,
					fa.y,
					routing_zone
				)

				for iv in intervals:
					var wlen: float = iv[1] - iv[0]
					var wx: float = (iv[0] + iv[1]) * 0.5
					_make_box(Vector3(wlen, h, SLAB_T), Vector3(wx, fa.y + h / 2.0, wall_z))
		else:
			var extend_a := w / 2.0 if i > 0 else 0.0
			var extend_b := w / 2.0 if i < polyline.size() - 2 else 0.0

			var a_main := fa.z
			var b_main := fb.z

			var z_min: float
			var z_max: float

			if a_main <= b_main:
				z_min = a_main - extend_a
				z_max = b_main + extend_b
			else:
				z_min = b_main - extend_b
				z_max = a_main + extend_a

			for sign_dir in [-1.0, 1.0]:
				var wall_x: float = fa.x + sign_dir * w * 0.5
				var intervals := _get_exposed_intervals(
					z_min,
					z_max,
					wall_x,
					false,
					sign_dir,
					fa.y,
					routing_zone
				)

				for iv in intervals:
					var wlen: float = iv[1] - iv[0]
					var wz: float = (iv[0] + iv[1]) * 0.5
					_make_box(Vector3(SLAB_T, h, wlen), Vector3(wall_x, fa.y + h / 2.0, wz))


# ── HELPERS ──────────────────────────────────────────────────────────────────

func _commit_polyline(polyline: PackedVector3Array, routing_zone: String = "") -> void:
	if routing_zone.is_empty():
		routing_zone = _active_routing_zone

	_pending_polylines.append(polyline)
	_pending_polyline_records.append({
		"polyline": polyline,
		"routing_zone": routing_zone
	})

	for aabb in _polyline_to_corridor_aabbs(polyline):
		_pending_corridor_aabbs.append(aabb)
		_pending_corridor_records.append({
			"aabb": aabb,
			"routing_zone": routing_zone
		})


func _candidate_aabbs_hit_pending_corridors(candidate_aabbs: Array[AABB]) -> bool:
	for candidate in candidate_aabbs:
		var grown_candidate := candidate.grow(0.15)
		for corridor_aabb in _pending_corridor_aabbs:
			if grown_candidate.intersects(corridor_aabb.grow(0.15)):
				return true

	return false

func _polyline_to_corridor_aabbs(polyline: PackedVector3Array) -> Array[AABB]:
	var result: Array[AABB] = []

	var w := CORRIDOR_WIDTH
	var h := CORRIDOR_HEIGHT

	for i in range(1, polyline.size() - 1):
		var p := polyline[i]
		result.append(AABB(
			Vector3(p.x - w / 2.0, p.y, p.z - w / 2.0),
			Vector3(w, h, w)
		))

	for i in range(polyline.size() - 1):
		var fa := polyline[i]
		var fb := polyline[i + 1]

		var is_x := absf(fa.x - fb.x) > absf(fa.z - fb.z)

		if is_x:
			var x_min := minf(fa.x, fb.x)
			var x_max := maxf(fa.x, fb.x)

			result.append(AABB(
				Vector3(x_min, fa.y, fa.z - w / 2.0),
				Vector3(x_max - x_min, h, w)
			))
		else:
			var z_min := minf(fa.z, fb.z)
			var z_max := maxf(fa.z, fb.z)

			result.append(AABB(
				Vector3(fa.x - w / 2.0, fa.y, z_min),
				Vector3(w, h, z_max - z_min)
			))

	return result

func _register_gateway_opening(gateway: Marker3D, owner_edge: LogicalEdge = null) -> void:
	if gateway == null:
		return

	if _gateway_opening_already_registered(gateway, owner_edge):
		return

	var dir3 := _snap_to_cardinal(-gateway.global_transform.basis.z)
	var dir2 := Vector2(dir3.x, dir3.z)

	_gateway_openings.append({
		"pos": gateway.global_position,
		"dir": dir2,
		"owner_edge_id": owner_edge.id if owner_edge != null else "",
		"routing_zone": _active_routing_zone
	})

func _get_exposed_intervals(
		start: float,
		end: float,
		orthogonal_pos: float,
		is_horizontal: bool,
		outside_sign: float,
		wall_y: float,
		routing_zone: String
	) -> Array:

	var uncovered := [[start, end]]

	# Probe just outside the wall, not exactly on the wall line.
	# This detects adjacent/touching corridor footprints without the current
	# corridor suppressing its own perimeter wall.
	var probe_orthogonal_pos := orthogonal_pos + outside_sign * WALL_MERGE_EPS

	# Subtract other corridor footprints at the same elevation.
	for fp_data in _footprints:
		var fp_y := float(fp_data["y"])
		if absf(fp_y - wall_y) > Y_EPS:
			continue

		var other_zone := str(fp_data.get("routing_zone", "default"))
		if not _corridor_zones_can_merge(routing_zone, other_zone):
			continue

		var fp := fp_data["rect"] as Rect2

		var fp_start: float = fp.position.x if is_horizontal else fp.position.y
		var fp_end: float = fp_start + (fp.size.x if is_horizontal else fp.size.y)

		var fp_ortho_min: float = fp.position.y if is_horizontal else fp.position.x
		var fp_ortho_max: float = fp_ortho_min + (fp.size.y if is_horizontal else fp.size.x)

		if probe_orthogonal_pos > fp_ortho_min and probe_orthogonal_pos < fp_ortho_max:
			uncovered = _subtract_interval_list(uncovered, fp_start, fp_end)

	# Subtract room AABB footprints so walls do not poke into rooms/stairs.
	for aabb in _room_aabbs:
		var wall_bottom := wall_y
		var wall_top := wall_y + CORRIDOR_HEIGHT

		if aabb.position.y + aabb.size.y <= wall_bottom or aabb.position.y >= wall_top:
			continue

		var rm_start: float = aabb.position.x if is_horizontal else aabb.position.z
		var rm_end: float = rm_start + (aabb.size.x if is_horizontal else aabb.size.z)

		var rm_ortho_min: float = aabb.position.z if is_horizontal else aabb.position.x
		var rm_ortho_max: float = rm_ortho_min + (aabb.size.z if is_horizontal else aabb.size.x)

		var is_stair := _is_stair_aabb(aabb)
		
		if is_stair:
			continue
		else:
			# Only cut walls when the corridor center is well inside the room's
			# orthogonal extent. A half-corridor-width inset prevents false cuts
			# from corridors that merely graze the room boundary.
			if orthogonal_pos > rm_ortho_min + CORRIDOR_WIDTH * 0.5 and orthogonal_pos < rm_ortho_max - CORRIDOR_WIDTH * 0.5:
				uncovered = _subtract_interval_list(
					uncovered,
					rm_start,
					rm_end
				)

	# Subtract gateway openings only from side walls that are parallel to the
	# room/stair wall and face back toward the gateway.
	#
	# This preserves walls on corridors that run directly into the gateway,
	# while still opening the side wall of a parallel corridor passing by it.
	for gw_data: Dictionary in _gateway_openings:
		var gw_pos: Vector3 = gw_data["pos"]
		var gw_dir: Vector2 = gw_data["dir"]
		var gw_zone := str(gw_data.get("routing_zone", "default"))

		if not _corridor_zones_can_merge(routing_zone, gw_zone):
			continue

		if absf(gw_pos.y - wall_y) > CORRIDOR_HEIGHT:
			continue

		if gw_dir == Vector2.ZERO:
			continue

		var wall_out_normal := Vector2.ZERO

		if is_horizontal:
			# Wall runs along X, normal points along ±Z.
			wall_out_normal = Vector2(0.0, outside_sign)
		else:
			# Wall runs along Z, normal points along ±X.
			wall_out_normal = Vector2(outside_sign, 0.0)

		# Gateway dir points out of the room into the corridor.
		# The corridor wall that faces the gateway has outward normal opposite that.
		if wall_out_normal.dot(gw_dir) > GATEWAY_SIDEWALL_DOT_LIMIT:
			continue

		var gw_main: float = gw_pos.x if is_horizontal else gw_pos.z
		var gw_ortho: float = gw_pos.z if is_horizontal else gw_pos.x

		# Important: this should be tight.
		# The wall must lie on the gateway plane, not merely within half corridor width.
		if absf(gw_ortho - orthogonal_pos) <= GATEWAY_SIDEWALL_ALIGN_TOL:
			var gap_start := gw_main - CORRIDOR_WIDTH * 0.5
			var gap_end := gw_main + CORRIDOR_WIDTH * 0.5
			uncovered = _subtract_interval_list(uncovered, gap_start, gap_end)

	return uncovered.filter(func(iv): return iv[1] - iv[0] > 0.05)

func _subtract_interval_list(intervals: Array, cut_start: float, cut_end: float) -> Array:
	var result := []

	for iv in intervals:
		var a: float = iv[0]
		var b: float = iv[1]

		if cut_end <= a or cut_start >= b:
			result.append(iv)
			continue

		if cut_start > a:
			result.append([a, minf(b, cut_start)])

		if cut_end < b:
			result.append([maxf(a, cut_end), b])

	return result

func _get_edge_routing_zone(edge: LogicalEdge) -> String:
	if edge == null:
		return "default"
	return str(edge.custom_data.get(ROUTING_ZONE_KEY, "default"))


func _corridor_zones_can_merge(zone_a: String, zone_b: String) -> bool:
	if zone_a.is_empty() or zone_b.is_empty():
		return true
	if zone_a == "default" or zone_b == "default":
		return true
	return zone_a == zone_b


func _clean_collinear(pts: PackedVector3Array) -> PackedVector3Array:
	if pts.size() <= 2: return pts
	var out := PackedVector3Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var prev := out[-1]
		var curr := pts[i]
		var next := pts[i+1]
		
		var d1 := Vector3(signf(curr.x - prev.x), 0, signf(curr.z - prev.z))
		var d2 := Vector3(signf(next.x - curr.x), 0, signf(next.z - curr.z))
		
		if d1 != d2:
			out.append(curr)
	out.append(pts[-1])
	return out

func _snap_to_cardinal(dir: Vector3) -> Vector3:
	if absf(dir.x) >= absf(dir.z): return Vector3(signf(dir.x), 0, 0)
	return Vector3(0, 0, signf(dir.z))

func _make_box(size: Vector3, pos: Vector3) -> void:
	var box := CSGBox3D.new()
	box.size = size
	box.position = to_local(pos)
	_csg_root.add_child(box)

func seal_unused_gateways(rooms: Array) -> void:
	if _csg_root == null:
		push_warning("CorridorNetwork: seal_unused_gateways called before build()")
		return
	_csg_root.use_collision = false
	for room in rooms:
		if not room is BaseRoom:
			continue
		for gateway in (room as BaseRoom).get_gateways():
			if gateway.connected_edges.is_empty():
				_seal_gateway(gateway)
	_csg_root.use_collision = true


func _seal_gateway(gateway: Gateway) -> void:
	var dir3 := _snap_to_cardinal(-gateway.global_transform.basis.z)
	var base_pos := gateway.global_position
	var depth := SLAB_T * 6.0
	var size: Vector3
	if absf(dir3.x) > 0.5:
		size = Vector3(depth, CORRIDOR_HEIGHT, CORRIDOR_WIDTH)
	else:
		size = Vector3(CORRIDOR_WIDTH, CORRIDOR_HEIGHT, depth)
	var center_pos := base_pos + dir3 * (depth * 0.5)
	center_pos.y += CORRIDOR_HEIGHT * 0.5
	_make_box(size, center_pos)


func get_room_aabbs() -> Array[AABB]:
	return _room_aabbs

func get_stair_rooms() -> Array[BaseRoom]:
	return _stair_rooms

func _candidate_aabbs_hit_rooms(candidate_aabbs: Array[AABB]) -> bool:
	for candidate in candidate_aabbs:
		var grown_candidate := candidate.grow(0.25)
		for record in _room_aabb_records:
			var existing := record["aabb"] as AABB
			if grown_candidate.intersects(existing.grow(0.25)):
				return true

	return false

func _append_room_aabb(aabb: AABB) -> void:
	_room_aabbs.append(aabb)
	_room_aabb_records.append(_make_room_aabb_record(aabb))

func _rebuild_room_aabb_records() -> void:
	_room_aabb_records.clear()
	for aabb in _room_aabbs:
		_room_aabb_records.append(_make_room_aabb_record(aabb))

func _make_room_aabb_record(aabb: AABB) -> Dictionary:
	return {
		"aabb": aabb,
		"grown_aabb": aabb.grow(0.35),
		"rect": Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z),
		"y_min": aabb.position.y,
		"y_max": aabb.position.y + aabb.size.y
	}

func _truncate_room_aabbs(target_size: int) -> void:
	while _room_aabbs.size() > target_size:
		_room_aabbs.pop_back()
	while _room_aabb_records.size() > target_size:
		_room_aabb_records.pop_back()

func _remember_stair_aabbs(stair_room: BaseRoom) -> void:
	for world_aabb in stair_room.get_world_aabbs():
		_stair_aabbs.append(world_aabb)
		_stair_clearance_aabbs.append(world_aabb.grow(STAIR_CLEARANCE_MARGIN))

func _is_stair_aabb(aabb: AABB) -> bool:
	for stair_aabb in _stair_aabbs:
		if _aabbs_same_footprint(aabb, stair_aabb):
			return true

	return false

func _aabbs_same_footprint(a: AABB, b: AABB) -> bool:
	return (
		a.position.distance_to(b.position) < 0.1
		and a.size.distance_to(b.size) < 0.1
	)

func _edge_blocks_reserved_gateway_throat(
	p1: Vector2i,
	p2: Vector2i,
	min_y: float,
	max_y: float,
	ignored_gateway_owner_edge_id: String = ""
) -> bool:
	var p1f := Vector2(p1) / GRID_SCALE
	var p2f := Vector2(p2) / GRID_SCALE

	var edge_rect: Rect2
	var w := CORRIDOR_WIDTH

	if p1.x == p2.x:
		var min_z := minf(p1f.y, p2f.y)
		var max_z := maxf(p1f.y, p2f.y)
		edge_rect = Rect2(
			p1f.x - w * 0.5,
			min_z - w * 0.5,
			w,
			(max_z - min_z) + w
		)
	else:
		var min_x := minf(p1f.x, p2f.x)
		var max_x := maxf(p1f.x, p2f.x)
		edge_rect = Rect2(
			min_x - w * 0.5,
			p1f.y - w * 0.5,
			(max_x - min_x) + w,
			w
		)

	for gateway_data in _reserved_gateway_throats:
		var owner_edge_id := str(gateway_data.get("owner_edge_id", ""))

		if not ignored_gateway_owner_edge_id.is_empty() and owner_edge_id == ignored_gateway_owner_edge_id:
			continue

		var other_zone := str(gateway_data.get("routing_zone", "default"))

		# Critical:
		# Reserved gateway throats only block cross-zone routing.
		# Same-zone corridors are allowed to merge freely.
		if _corridor_zones_can_merge(_active_routing_zone, other_zone):
			continue

		var gw_pos: Vector3 = gateway_data["pos"]
		var gw_dir: Vector2 = gateway_data["dir"]

		if gw_dir == Vector2.ZERO:
			continue

		if gw_pos.y + CORRIDOR_HEIGHT <= min_y:
			continue

		if gw_pos.y >= max_y + CORRIDOR_HEIGHT:
			continue

		var throat_rect := _gateway_throat_rect(gw_pos, gw_dir)

		if edge_rect.intersects(throat_rect):
			return true

	return false

func _gateway_throat_rect(gw_pos: Vector3, gw_dir: Vector2) -> Rect2:
	var length := float(GATEWAY_RESERVED_THROAT_STEPS) / GRID_SCALE
	var half_w := GATEWAY_RESERVED_THROAT_HALF_WIDTH

	var x := gw_pos.x
	var z := gw_pos.z

	if absf(gw_dir.x) > absf(gw_dir.y):
		var x_min := x if gw_dir.x > 0.0 else x - length
		return Rect2(
			x_min,
			z - half_w,
			length,
			half_w * 2.0
		)

	var z_min := z if gw_dir.y > 0.0 else z - length
	return Rect2(
		x - half_w,
		z_min,
		half_w * 2.0,
		length
	)

func _pre_register_connection_gateways(connections: Array) -> void:
	for connection in connections:
		var pc := connection as PhysicalConnection
		if pc == null:
			continue

		var edge := pc.logical_edge
		var old_zone := _active_routing_zone
		var old_edge_id := _active_edge_id

		_active_routing_zone = _get_edge_routing_zone(edge)
		_active_edge_id = edge.id if edge != null else ""

		if pc.from_anchor != null and pc.from_anchor.gateway != null:
			_register_reserved_gateway_throat(pc.from_anchor.gateway, edge)

		if pc.to_anchor != null and pc.to_anchor.gateway != null:
			_register_reserved_gateway_throat(pc.to_anchor.gateway, edge)

		_active_routing_zone = old_zone
		_active_edge_id = old_edge_id

func _register_reserved_gateway_throat(gateway: Marker3D, owner_edge: LogicalEdge = null) -> void:
	if gateway == null:
		return

	if _reserved_gateway_throat_already_registered(gateway, owner_edge):
		return

	var dir3 := _snap_to_cardinal(-gateway.global_transform.basis.z)
	var dir2 := Vector2(dir3.x, dir3.z)

	_reserved_gateway_throats.append({
		"pos": gateway.global_position,
		"dir": dir2,
		"owner_edge_id": owner_edge.id if owner_edge != null else "",
		"routing_zone": _active_routing_zone
	})

func _reserved_gateway_throat_already_registered(gateway: Marker3D, owner_edge: LogicalEdge = null) -> bool:
	if gateway == null:
		return true

	var edge_id := owner_edge.id if owner_edge != null else ""
	var pos := gateway.global_position

	for data in _reserved_gateway_throats:
		var existing_pos: Vector3 = data["pos"]

		if existing_pos.distance_to(pos) > 0.05:
			continue

		if str(data.get("owner_edge_id", "")) == edge_id:
			return true

	return false

func _gateway_opening_already_registered(gateway: Marker3D, owner_edge: LogicalEdge = null) -> bool:
	var edge_id := owner_edge.id if owner_edge != null else ""
	var pos := gateway.global_position

	for data in _gateway_openings:
		var existing_pos: Vector3 = data["pos"]
		if existing_pos.distance_to(pos) > 0.05:
			continue

		if str(data.get("owner_edge_id", "")) == edge_id:
			return true

	return false

func _generate_gateway_corner_plugs() -> void:
	for gw_data in _gateway_openings:
		var gw_pos: Vector3 = gw_data["pos"]
		var gw_dir: Vector2 = gw_data["dir"]

		if gw_dir == Vector2.ZERO:
			continue

		var room_aabb := _find_gateway_room_aabb(gw_pos)
		if room_aabb.size == Vector3.ZERO:
			continue

		_generate_gateway_corner_plugs_for(gw_pos, gw_dir, room_aabb)

	print("CorridorNetwork: gateway_corner_plugs=", _gateway_corner_plug_count)

func _find_gateway_room_aabb(gw_pos: Vector3) -> AABB:
	var best := AABB()
	var best_dist := INF

	for aabb in _room_aabbs:
		if gw_pos.y < aabb.position.y - CORRIDOR_HEIGHT:
			continue

		if gw_pos.y > aabb.position.y + aabb.size.y + CORRIDOR_HEIGHT:
			continue

		var gw_flat := Vector2(gw_pos.x, gw_pos.z)
		var rect := Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z).grow(0.35)
		if not rect.has_point(gw_flat):
			continue

		var center := aabb.position + aabb.size * 0.5
		var dist := Vector2(gw_pos.x - center.x, gw_pos.z - center.z).length()
		if dist < best_dist:
			best_dist = dist
			best = aabb

	return best

func _generate_gateway_corner_plugs_for(gw_pos: Vector3, gw_dir: Vector2, room_aabb: AABB) -> void:
	var h := CORRIDOR_HEIGHT
	var t := SLAB_T
	var half_w := CORRIDOR_WIDTH * 0.5

	var side_a := Vector2(-gw_dir.y, gw_dir.x)
	var side_b := -side_a

	_try_make_gateway_side_plug(gw_pos, gw_dir, side_a, room_aabb, half_w, h, t)
	_try_make_gateway_side_plug(gw_pos, gw_dir, side_b, room_aabb, half_w, h, t)

func _try_make_gateway_side_plug(
	gw_pos: Vector3,
	gw_dir: Vector2,
	side_dir: Vector2,
	room_aabb: AABB,
	half_w: float,
	h: float,
	_t: float
) -> void:
	var side_point := Vector2(gw_pos.x, gw_pos.z) + side_dir * half_w

	if _gateway_side_is_supported_by_room(side_point, side_dir, room_aabb):
		return

	var overhang := _gateway_side_overhang(side_point, side_dir, room_aabb)
	if overhang <= 0.05:
		return

	var plug_span := overhang + GATEWAY_CORNER_PLUG_OVERLAP * 2.0
	var plug_center_2d := Vector2(gw_pos.x, gw_pos.z)
	plug_center_2d += side_dir * (half_w - overhang * 0.5)
	plug_center_2d += gw_dir * (GATEWAY_CORNER_PLUG_DEPTH * 0.5)

	var size: Vector3
	var pos := Vector3(plug_center_2d.x, gw_pos.y + h * 0.5, plug_center_2d.y)

	if absf(gw_dir.x) > absf(gw_dir.y):
		# Gateway opens along X, so the cap lies on the room wall plane and spans Z.
		size = Vector3(GATEWAY_CORNER_PLUG_DEPTH, h, plug_span)
	else:
		# Gateway opens along Z, so the cap lies on the room wall plane and spans X.
		size = Vector3(plug_span, h, GATEWAY_CORNER_PLUG_DEPTH)

	_make_box(size, pos)
	_gateway_corner_plug_count += 1

func _gateway_side_overhang(side_point: Vector2, side_dir: Vector2, room_aabb: AABB) -> float:
	if absf(side_dir.x) > 0.5:
		if side_dir.x > 0.0:
			return side_point.x - (room_aabb.position.x + room_aabb.size.x)
		return room_aabb.position.x - side_point.x

	if side_dir.y > 0.0:
		return side_point.y - (room_aabb.position.z + room_aabb.size.z)
	return room_aabb.position.z - side_point.y

func _gateway_side_is_supported_by_room(side_point: Vector2, side_dir: Vector2, room_aabb: AABB) -> bool:
	var margin := 0.05

	if absf(side_dir.x) > 0.5:
		var min_x := room_aabb.position.x - margin
		var max_x := room_aabb.position.x + room_aabb.size.x + margin
		return side_point.x >= min_x and side_point.x <= max_x

	var min_z := room_aabb.position.z - margin
	var max_z := room_aabb.position.z + room_aabb.size.z + margin
	return side_point.y >= min_z and side_point.y <= max_z
