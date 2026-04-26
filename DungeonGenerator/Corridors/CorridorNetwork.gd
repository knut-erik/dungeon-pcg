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

var _pending_polylines: Array[PackedVector3Array] = []
var _csg_root: CSGCombiner3D
var _room_aabbs: Array[AABB] = []
var _stair_rooms: Array[BaseRoom] = []
var _footprints: Array[Dictionary] = []
var _gateway_openings: Array[Dictionary] = []  # { "pos": Vector3, "dir": Vector2 }
var _room_library: Array[RoomBlueprint] = []

func build(connections: Array, room_aabbs: Array, room_library: Array[RoomBlueprint]) -> void:
	_csg_root = CSGCombiner3D.new()
	add_child(_csg_root)

	_room_aabbs.assign(room_aabbs)
	_room_library = room_library

	_footprints.clear()
	_gateway_openings.clear()
	_stair_rooms.clear()
	_pending_polylines.clear()

	for connection in connections:
		var physical_connection := connection as PhysicalConnection
		if not physical_connection:
			continue

		var ga: Marker3D = physical_connection.from_anchor.gateway
		var gb: Marker3D = physical_connection.to_anchor.gateway

		if not ga or not gb:
			push_warning("CorridorNetwork: PhysicalConnection missing gateway anchors.")
			continue
		
		_register_gateway_opening(ga)
		_register_gateway_opening(gb)
		
		# -- STAIR INJECTION INTERCEPT --
		if absf(ga.global_position.y - gb.global_position.y) > 0.1:
			var success := await _route_vertical_connection_with_stair_candidates(ga, gb)
			if not success:
				push_warning("Candidate stair routing failed. Falling back to polyline stair injection.")
				var polyline = _route_connection(ga, gb, true)
				if not polyline.is_empty():
					await _inject_stairs_and_split(polyline, ga, gb)
			continue
			
		var polyline = _route_connection(ga, gb, false)
		if not polyline.is_empty():
			_pending_polylines.append(polyline)
	
	_generate_queued_geometry()

# ── INJECTION SYSTEM ─────────────────────────────────────────────────────────

func _route_vertical_connection_with_stair_candidates(ga: Marker3D, gb: Marker3D) -> bool:
	var delta_y := gb.global_position.y - ga.global_position.y

	var stair_blueprints = _room_library.filter(func(bp): return bp.possible_tags.has("Stairs"))
	if stair_blueprints.is_empty():
		push_error("CorridorNetwork: No blueprints found with the 'Stairs' tag!")
		return false

	var chosen_blueprint = stair_blueprints.pick_random()
	var stair_room = chosen_blueprint.room_scene.instantiate() as BaseRoom
	get_parent().add_child(stair_room)

	var dummy_logic := LogicalNode.new()
	dummy_logic.custom_data["delta_y"] = delta_y
	await stair_room.setup_room(RandomNumberGenerator.new(), dummy_logic)
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

				for aabb in candidate_aabbs:
					_room_aabbs.append(aabb)

				var path_to_stairs := _route_connection(ga, stair_room.gateway_in, false)
				var path_from_stairs := _route_connection(stair_room.gateway_out, gb, false)

				if not path_to_stairs.is_empty() and not path_from_stairs.is_empty():
					_register_gateway_opening(stair_room.gateway_in)
					_register_gateway_opening(stair_room.gateway_out)

					_pending_polylines.append(path_to_stairs)
					_pending_polylines.append(path_from_stairs)

					_stair_rooms.append(stair_room)
					return true

				# Revert temporary AABB reservations.
				for i in range(candidate_aabbs.size()):
					_room_aabbs.pop_back()

	stair_room.queue_free()
	return false

func _inject_stairs_and_split(polyline: PackedVector3Array, ga: Marker3D, gb: Marker3D) -> void:
	var delta_y := gb.global_position.y - ga.global_position.y
	
	var stair_blueprints = _room_library.filter(func(bp): return bp.possible_tags.has("Stairs"))
	if stair_blueprints.is_empty():
		push_error("CorridorNetwork: No blueprints found with the 'Stairs' tag!")
		return
	var chosen_blueprint = stair_blueprints.pick_random()
	
	var stair_room = chosen_blueprint.room_scene.instantiate() as BaseRoom
	get_parent().add_child(stair_room) 
	
	var dummy_logic = LogicalNode.new()
	dummy_logic.custom_data["delta_y"] = delta_y
	await stair_room.setup_room(RandomNumberGenerator.new(), dummy_logic)
	
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
		return

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
		return
	
	for world_aabb in stair_room.get_world_aabbs():
		_room_aabbs.append(world_aabb)
	
	_register_gateway_opening(stair_room.gateway_in)
	_register_gateway_opening(stair_room.gateway_out)
	
	var path_to_stairs   = _route_connection(ga, stair_room.gateway_in, false)
	var path_from_stairs = _route_connection(stair_room.gateway_out, gb, false)
	
	if not path_to_stairs.is_empty():
		_pending_polylines.append(path_to_stairs)

	if not path_from_stairs.is_empty():
		_pending_polylines.append(path_from_stairs)
		
	_stair_rooms.append(stair_room)

# ── ROUTING ──────────────────────────────────────────────────────────────────

func _route_connection(ga: Marker3D, gb: Marker3D, ignore_y: bool) -> PackedVector3Array:
	var pos_a := ga.global_position
	var pos_b := gb.global_position
	
	if not ignore_y and absf(pos_a.y - pos_b.y) > 0.1:
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

	# Instead of finding owner AABBs, just record the gateway grid positions.
	# Only these exact cells get exempted from collision — not entire room footprints.
	var start_owner := _find_owner_aabb_index(pos_a)
	var goal_owner := _find_owner_aabb_index(pos_b)

	var path2i = _directional_astar(
		start2i,
		goal2i,
		dir_ai,
		dir_bi,
		min_y,
		max_y,
		start_owner,
		goal_owner
	)
	
	# Fallback: if strict routing fails, relax the goal approach direction.
	# This handles same-facing gateways at close range where a U-path is geometrically
	# impossible due to room AABBs blocking the required swing-out space.
	if path2i.is_empty():
		push_warning("Strict routing failed, retrying with relaxed goal constraint.")
		path2i = _directional_astar(
		start2i,
		goal2i,
		dir_ai,
		Vector2i.ZERO,
		min_y,
		max_y,
		start_owner,
		goal_owner
	)
		
	if path2i.is_empty():
		push_warning("Corridor failed: No orthogonal route from %s to %s." % [start2i, goal2i])
		return PackedVector3Array()
		
	var p3 := PackedVector3Array()
	for p in path2i:
		p3.append(Vector3(float(p.x) / GRID_SCALE, pos_a.y, float(p.y) / GRID_SCALE))
		
	return _clean_collinear(p3)


func _find_owner_aabb_index(world_pos: Vector3) -> int:
	for i in range(_room_aabbs.size()):
		if _room_aabbs[i].grow(0.35).has_point(world_pos):
			return i

	push_warning("_find_owner_aabb: No AABB contains point %s" % world_pos)
	return -1

# ── STRICT INTEGER A* WITH MIN-HEAP ──────────────────────────────────────────

func _directional_astar(start: Vector2i, goal: Vector2i, out_a: Vector2i, out_b: Vector2i, min_y: float, max_y: float, start_owner: int, goal_owner: int) -> Array[Vector2i]:
	if start == goal:
		return [start, goal]
	
	var heap := _BinHeap.new()
	var came_from := {}
	var g_score := {start: 0.0}
	var dist_from_start := {start: 0}  # track step count from start
	var counter := 0
	
	var start_h := float(absi(start.x - goal.x) + absi(start.y - goal.y))
	heap.push([start_h, counter, start])
	counter += 1
	
	var dirs := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	var iterations := 0
	
	while not heap.is_empty() and iterations < 50000: # was 25000 (faster, but less accurate)
		iterations += 1
		var current_data = heap.pop()
		var curr: Vector2i = current_data[2]
		
		if curr == goal:
			var path: Array[Vector2i] = [curr]
			while came_from.has(curr):
				curr = came_from[curr]
				path.insert(0, curr)
			return path
			
		var is_start := (curr == start)
		var steps_from_start: int = dist_from_start.get(curr, 999)
		var steps_to_goal: int = absi(curr.x - goal.x) + absi(curr.y - goal.y)
		
		for d in dirs:
			var nxt : Vector2i = curr + d
			var is_goal : bool = (nxt == goal)
			
			# Directional Edge Constraints
			if is_start and d != out_a:
				continue 
			# Goal constraint — skip if out_b is zero (relaxed mode - direction doesn't matter, only position does)
			if is_goal and out_b != Vector2i.ZERO and d != -out_b:
				continue
			
			# Skip AABB checks near gateways — the direction constraint ensures
			# we're exiting the room, not routing back through it.
			var ignored_aabb_indices: Array[int] = []

			if start_owner != -1 and _edge_in_gateway_throat(curr, nxt, start, out_a):
				ignored_aabb_indices.append(start_owner)

			if goal_owner != -1 and out_b != Vector2i.ZERO and _edge_in_gateway_throat(curr, nxt, goal, out_b):
				ignored_aabb_indices.append(goal_owner)

			if not _is_edge_valid(curr, nxt, min_y, max_y, ignored_aabb_indices):
				continue
				
			var tentative_g = g_score[curr] + 1.0
			if came_from.has(curr) and (curr - came_from[curr]) != d:
					tentative_g += 0.5 # Turn penalty favors straight lines
					
			if not g_score.has(nxt) or tentative_g < g_score[nxt]:
				came_from[nxt] = curr
				g_score[nxt] = tentative_g
				dist_from_start[nxt] = steps_from_start + 1
				var h := float(absi(nxt.x - goal.x) + absi(nxt.y - goal.y))
				heap.push([tentative_g + h, counter, nxt])
				counter += 1
					

	push_warning("A* exhausted after %d iterations. start=%s goal=%s out_a=%s out_b=%s\n" % [
		iterations, start, goal, out_a, out_b])
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
			var p = (i - 1) / 2
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

func _is_edge_valid( p1: Vector2i, p2: Vector2i, min_y: float, max_y: float, ignored_aabb_indices: Array[int]) -> bool:
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

	for i in range(_room_aabbs.size()):
		if ignored_aabb_indices.has(i):
			continue

		var aabb := _room_aabbs[i]

		if aabb.position.y + aabb.size.y <= corr_bottom or aabb.position.y >= corr_top:
			continue

		var room_rect := Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z)

		if rect.intersects(room_rect):
			return false

	return true

# ── GEOMETRY GENERATION ──────────────────────────────────────────────────────

func _generate_queued_geometry() -> void:
	_footprints.clear()

	for polyline in _pending_polylines:
		_register_footprints(polyline)

	for polyline in _pending_polylines:
		_generate_slabs(polyline)

	for polyline in _pending_polylines:
		_generate_walls(polyline)

func _register_footprints(polyline: PackedVector3Array) -> void:
	var w := CORRIDOR_WIDTH

	# Corner/junction squares.
	for i in range(1, polyline.size() - 1):
		var p := polyline[i]
		_footprints.append({
			"rect": Rect2(p.x - w / 2.0, p.z - w / 2.0, w, w),
			"y": p.y
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
			"y": fa.y
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

func _generate_walls(polyline: PackedVector3Array) -> void:
	var w := CORRIDOR_WIDTH
	var h := CORRIDOR_HEIGHT

	for i in range(polyline.size() - 1):
		var fa := polyline[i]
		var fb := polyline[i + 1]
		var is_x: bool = absf(fa.x - fb.x) > absf(fa.z - fb.z)
		
		# Expand wall interval by half corridor width so convex (outer) corners close.
		if is_x:
			var x_min := minf(fa.x, fb.x) - w / 2.0
			var x_max := maxf(fa.x, fb.x) + w / 2.0

			for sign_dir in [-1.0, 1.0]:
				var wall_z: float = fa.z + sign_dir * w * 0.5
				var intervals := _get_exposed_intervals(
					x_min,
					x_max,
					wall_z,
					true,
					sign_dir,
					fa.y
				)

				for iv in intervals:
					var wlen: float = iv[1] - iv[0]
					var wx: float = (iv[0] + iv[1]) * 0.5
					_make_box(Vector3(wlen, h, SLAB_T), Vector3(wx, fa.y + h / 2.0, wall_z))
		else:
			var z_min := minf(fa.z, fb.z) - w / 2.0
			var z_max := maxf(fa.z, fb.z) + w / 2.0

			for sign_dir in [-1.0, 1.0]:
				var wall_x: float = fa.x + sign_dir * w * 0.5
				var intervals := _get_exposed_intervals(
					z_min,
					z_max,
					wall_x,
					false,
					sign_dir,
					fa.y
				)

				for iv in intervals:
					var wlen: float = iv[1] - iv[0]
					var wz: float = (iv[0] + iv[1]) * 0.5
					_make_box(Vector3(SLAB_T, h, wlen), Vector3(wall_x, fa.y + h / 2.0, wz))


# ── HELPERS ──────────────────────────────────────────────────────────────────

func _candidate_aabbs_hit_pending_corridors(candidate_aabbs: Array[AABB]) -> bool:
	for candidate in candidate_aabbs:
		for polyline in _pending_polylines:
			for corridor_aabb in _polyline_to_corridor_aabbs(polyline):
				if candidate.grow(0.15).intersects(corridor_aabb.grow(0.15)):
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

func _register_gateway_opening(gateway: Marker3D) -> void:
	if not gateway:
		return

	var dir3 := _snap_to_cardinal(-gateway.global_transform.basis.z)

	_gateway_openings.append({
		"pos": gateway.global_position,
		"dir": Vector2(dir3.x, dir3.z)
	})

func _get_exposed_intervals(
		start: float,
		end: float,
		orthogonal_pos: float,
		is_horizontal: bool,
		outside_sign: float,
		wall_y: float
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

		# Important:
		# Use an inclusive/grown test. Stair rooms are exactly corridor-width,
		# so side walls often lie exactly on the AABB boundary.
		if orthogonal_pos >= rm_ortho_min - ROOM_WALL_CUT_MARGIN and orthogonal_pos <= rm_ortho_max + ROOM_WALL_CUT_MARGIN:
			uncovered = _subtract_interval_list(
				uncovered,
				rm_start - ROOM_WALL_CUT_MARGIN,
				rm_end + ROOM_WALL_CUT_MARGIN
			)

	# Subtract gateway openings only from side walls that are parallel to the
	# room/stair wall and face back toward the gateway.
	#
	# This preserves walls on corridors that run directly into the gateway,
	# while still opening the side wall of a parallel corridor passing by it.
	for gw_data: Dictionary in _gateway_openings:
		var gw_pos: Vector3 = gw_data["pos"]
		var gw_dir: Vector2 = gw_data["dir"]

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

func get_room_aabbs() -> Array[AABB]:
	return _room_aabbs

func get_stair_rooms() -> Array[BaseRoom]:
	return _stair_rooms

func _candidate_aabbs_hit_rooms(candidate_aabbs: Array[AABB]) -> bool:
	for candidate in candidate_aabbs:
		for existing in _room_aabbs:
			if candidate.grow(0.25).intersects(existing.grow(0.25)):
				return true

	return false
