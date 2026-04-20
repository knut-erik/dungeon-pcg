extends Node3D
class_name CorridorNetwork

const CORRIDOR_WIDTH  := 3.0
const CORRIDOR_HEIGHT := 3.4
const MIN_EXIT        := 3.0   # stub length: one corridor-width from gateway
const SLAB_T          := 0.15

var _csg_root: CSGCombiner3D
var _footprints: Array = []
var _room_aabbs: Array = []

# connections : Array of [Marker3D gateway_a, Marker3D gateway_b]
# room_aabbs  : Array of AABB (world-space) for every placed room
func build(connections: Array, room_aabbs: Array = []) -> void:
	_room_aabbs = room_aabbs
	_csg_root   = CSGCombiner3D.new()
	add_child(_csg_root)

	var all_segments: Array = []
	var all_elbows:   Array = []
	for pair in connections:
		var result := _route_connection(pair[0], pair[1])
		all_segments.append_array(result["segments"])
		all_elbows.append_array(result["elbows"])

	_place_floors_and_ceilings(all_segments)
	_place_corner_caps(all_elbows)
	_place_walls(all_segments)
	_place_corner_walls(all_elbows)

# ── Routing ────────────────────────────────────────────────────────────────────

func _snap_to_cardinal(dir: Vector3) -> Vector3:
	if absf(dir.x) >= absf(dir.z):
		return Vector3(signf(dir.x), 0.0, 0.0)
	return Vector3(0.0, 0.0, signf(dir.z))

# Returns {"segments": Array, "elbows": Array}.
# Route: pos_a → exit_a → [L-shape] → exit_b → pos_b
# Stubs guarantee each gateway is exited perpendicular to its wall.
# The L-shape between exits avoids routing through intermediate rooms.
func _route_connection(ga: Marker3D, gb: Marker3D) -> Dictionary:
	var pos_a := ga.global_position
	var pos_b := gb.global_position
	var dir_a := _snap_to_cardinal(-ga.global_transform.basis.z)
	var dir_b := _snap_to_cardinal(-gb.global_transform.basis.z)
	var y     := pos_a.y

	var exit_a := pos_a + dir_a * MIN_EXIT
	var exit_b := pos_b + dir_b * MIN_EXIT

	var segments: Array = []
	var elbows:   Array = []

	# Stub segments: exit each gateway in its outward direction.
	_try_add(segments, pos_a, exit_a, y)
	_try_add(segments, pos_b, exit_b, y)

	# Corner caps at the stub/connector junctions (outer corner gap filler).
	elbows.append({"pos": exit_a, "y": y})
	elbows.append({"pos": exit_b, "y": y})

	# Connect exit_a → exit_b with a straight segment or one L-turn.
	var dx: float = absf(exit_b.x - exit_a.x)
	var dz: float = absf(exit_b.z - exit_a.z)

	if dx < 0.05 or dz < 0.05:
		_try_add(segments, exit_a, exit_b, y)
	else:
		var elbow_xz := Vector3(exit_b.x, y, exit_a.z)
		var elbow_zx := Vector3(exit_a.x, y, exit_b.z)

		# Prefer the elbow whose first leg continues in dir_a from exit_a.
		var xz_aligned: bool = (elbow_xz - exit_a).dot(dir_a) >= 0.0
		# exit_a/exit_b are MIN_EXIT outside the rooms, so these clips now
		# correctly detect only intermediate-room collisions.
		var xz_clips: bool   = _l_clips_rooms(exit_a, elbow_xz, exit_b)
		var zx_clips: bool   = _l_clips_rooms(exit_a, elbow_zx, exit_b)

		var use_xz: bool
		if   not xz_clips and     xz_aligned: use_xz = true
		elif not zx_clips and not xz_aligned: use_xz = false
		elif not xz_clips:                    use_xz = true
		elif not zx_clips:                    use_xz = false
		else:                                 use_xz = xz_aligned

		var elbow: Vector3 = elbow_xz if use_xz else elbow_zx

		_try_add(segments, exit_a, elbow, y)
		_try_add(segments, elbow, exit_b, y)
		elbows.append({"pos": elbow, "y": y})

	return {"segments": segments, "elbows": elbows}

func _try_add(segments: Array, a: Vector3, b: Vector3, y: float) -> void:
	if a.distance_to(b) < 0.05:
		return
	var delta := b - a
	var axis  := 0 if absf(delta.x) >= absf(delta.z) else 2
	segments.append({"from": a, "to": b, "axis": axis, "y": y})

# ── Room-collision helpers ─────────────────────────────────────────────────────

func _l_clips_rooms(a: Vector3, elbow: Vector3, b: Vector3) -> bool:
	return _segment_clips_rooms(a, elbow) or _segment_clips_rooms(elbow, b)

func _segment_clips_rooms(a: Vector3, b: Vector3) -> bool:
	if _room_aabbs.is_empty() or a.distance_to(b) < 0.05:
		return false
	var W   := CORRIDOR_WIDTH
	var seg := AABB(
		Vector3(minf(a.x, b.x) - W * 0.5, a.y,              minf(a.z, b.z) - W * 0.5),
		Vector3(absf(b.x - a.x) + W,       CORRIDOR_HEIGHT,  absf(b.z - a.z) + W)
	)
	for r: AABB in _room_aabbs:
		if seg.intersects(r):
			return true
	return false

# ── Pass 1: floors, ceilings, footprints ───────────────────────────────────────

func _place_floors_and_ceilings(all_segments: Array) -> void:
	var W := CORRIDOR_WIDTH
	for seg in all_segments:
		var fa: Vector3   = seg["from"]
		var fb: Vector3   = seg["to"]
		var sy: float     = seg["y"]
		var axis: int     = seg["axis"]
		var cx: float     = (fa.x + fb.x) * 0.5
		var cz: float     = (fa.z + fb.z) * 0.5
		var length: float = fa.distance_to(fb)

		var slab: Vector3 = Vector3(length, SLAB_T, W) if axis == 0 else Vector3(W, SLAB_T, length)

		_make_box(slab, Vector3(cx, sy + SLAB_T * 0.5,                   cz))
		_make_box(slab, Vector3(cx, sy + CORRIDOR_HEIGHT - SLAB_T * 0.5, cz))

		if axis == 0:
			_footprints.append({
				"x_min": minf(fa.x, fb.x), "x_max": maxf(fa.x, fb.x),
				"z_min": fa.z - W * 0.5,   "z_max": fa.z + W * 0.5,
				"y": sy
			})
		else:
			_footprints.append({
				"x_min": fa.x - W * 0.5,   "x_max": fa.x + W * 0.5,
				"z_min": minf(fa.z, fb.z),  "z_max": maxf(fa.z, fb.z),
				"y": sy
			})

# ── Pass 2: corner caps (W×W square at each elbow / stub-exit junction) ────────

func _place_corner_caps(elbows: Array) -> void:
	var W := CORRIDOR_WIDTH
	for elbow_data in elbows:
		var ep: Vector3 = elbow_data["pos"]
		var sy: float   = elbow_data["y"]
		var cap: Vector3 = Vector3(W, SLAB_T, W)

		_make_box(cap, Vector3(ep.x, sy + SLAB_T * 0.5,                   ep.z))
		_make_box(cap, Vector3(ep.x, sy + CORRIDOR_HEIGHT - SLAB_T * 0.5, ep.z))

		_footprints.append({
			"x_min": ep.x - W * 0.5, "x_max": ep.x + W * 0.5,
			"z_min": ep.z - W * 0.5, "z_max": ep.z + W * 0.5,
			"y": sy
		})

# ── Pass 3: segment walls (footprint-based junction suppression) ───────────────

func _place_walls(all_segments: Array) -> void:
	var W := CORRIDOR_WIDTH
	for seg in all_segments:
		var fa: Vector3 = seg["from"]
		var fb: Vector3 = seg["to"]
		var sy: float   = seg["y"]
		var axis: int   = seg["axis"]

		if axis == 0:  # X-aligned — walls on ±Z sides
			var x_min := minf(fa.x, fb.x)
			var x_max := maxf(fa.x, fb.x)
			var seg_z := fa.z
			for sign_z: int in [-1, 1]:
				var wall_z: float = seg_z + sign_z * W * 0.5
				for iv in _uncovered_x(x_min, x_max, wall_z, sy):
					var wlen: float = float(iv[1]) - float(iv[0])
					var wx: float   = (float(iv[0]) + float(iv[1])) * 0.5
					_make_box(Vector3(wlen, CORRIDOR_HEIGHT, SLAB_T),
							  Vector3(wx, sy + CORRIDOR_HEIGHT * 0.5, wall_z))
		else:  # Z-aligned — walls on ±X sides
			var z_min := minf(fa.z, fb.z)
			var z_max := maxf(fa.z, fb.z)
			var seg_x := fa.x
			for sign_x: int in [-1, 1]:
				var wall_x: float = seg_x + sign_x * W * 0.5
				for iv in _uncovered_z(z_min, z_max, wall_x, sy):
					var wlen: float = float(iv[1]) - float(iv[0])
					var wz: float   = (float(iv[0]) + float(iv[1])) * 0.5
					_make_box(Vector3(SLAB_T, CORRIDOR_HEIGHT, wlen),
							  Vector3(wall_x, sy + CORRIDOR_HEIGHT * 0.5, wz))

# ── Pass 4: corner walls (4-sided, footprint suppresses inner faces) ───────────

func _place_corner_walls(elbows: Array) -> void:
	var W  := CORRIDOR_WIDTH
	var H  := CORRIDOR_HEIGHT
	var ST := SLAB_T
	for elbow_data in elbows:
		var ep: Vector3 = elbow_data["pos"]
		var sy: float   = elbow_data["y"]
		var half: float = W * 0.5

		for sign_z: int in [-1, 1]:
			var wall_z: float = ep.z + sign_z * half
			for iv in _uncovered_x(ep.x - half, ep.x + half, wall_z, sy):
				var wlen: float = float(iv[1]) - float(iv[0])
				var wx: float   = (float(iv[0]) + float(iv[1])) * 0.5
				_make_box(Vector3(wlen, H, ST), Vector3(wx, sy + H * 0.5, wall_z))

		for sign_x: int in [-1, 1]:
			var wall_x: float = ep.x + sign_x * half
			for iv in _uncovered_z(ep.z - half, ep.z + half, wall_x, sy):
				var wlen: float = float(iv[1]) - float(iv[0])
				var wz: float   = (float(iv[0]) + float(iv[1])) * 0.5
				_make_box(Vector3(ST, H, wlen), Vector3(wall_x, sy + H * 0.5, wz))

# ── Interval helpers ───────────────────────────────────────────────────────────

func _uncovered_x(x_start: float, x_end: float, wall_z: float, sy: float) -> Array:
	var covers: Array = []
	for fp in _footprints:
		if not _y_matches(fp["y"], sy):
			continue
		if fp["z_min"] + 0.01 < wall_z and fp["z_max"] - 0.01 > wall_z:
			var c0 := maxf(x_start, fp["x_min"])
			var c1 := minf(x_end,   fp["x_max"])
			if c1 > c0 + 0.05:
				covers.append([c0, c1])
	return _subtract(x_start, x_end, covers)

func _uncovered_z(z_start: float, z_end: float, wall_x: float, sy: float) -> Array:
	var covers: Array = []
	for fp in _footprints:
		if not _y_matches(fp["y"], sy):
			continue
		if fp["x_min"] + 0.01 < wall_x and fp["x_max"] - 0.01 > wall_x:
			var c0 := maxf(z_start, fp["z_min"])
			var c1 := minf(z_end,   fp["z_max"])
			if c1 > c0 + 0.05:
				covers.append([c0, c1])
	return _subtract(z_start, z_end, covers)

func _y_matches(a: float, b: float) -> bool:
	return absf(a - b) < 0.2

func _subtract(base_start: float, base_end: float, covers: Array) -> Array:
	var result: Array = [[base_start, base_end]]
	for cover in covers:
		var cs: float = cover[0]
		var ce: float = cover[1]
		var next: Array = []
		for iv in result:
			if cs > iv[0]:
				next.append([iv[0], minf(iv[1], cs)])
			if ce < iv[1]:
				next.append([maxf(iv[0], ce), iv[1]])
		result = next
	var filtered: Array = []
	for iv in result:
		if float(iv[1]) - float(iv[0]) > 0.05:
			filtered.append(iv)
	return filtered

# ── Rendering helper ───────────────────────────────────────────────────────────

func _make_box(size: Vector3, world_center: Vector3) -> void:
	var box := CSGBox3D.new()
	box.size     = size
	box.position = to_local(world_center)
	_csg_root.add_child(box)
