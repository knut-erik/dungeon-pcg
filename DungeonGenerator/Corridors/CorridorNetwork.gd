extends Node3D
class_name CorridorNetwork

const CORRIDOR_WIDTH  := 3.0
const CORRIDOR_HEIGHT := 3.4
const MIN_EXIT        := 8.0
const SLAB_T          := 0.15

var _csg_root: CSGCombiner3D
var _footprints: Array = []

# connections: Array of [Marker3D gateway_a, Marker3D gateway_b]
func build(connections: Array) -> void:
	_csg_root = CSGCombiner3D.new()
	add_child(_csg_root)

	var all_segments: Array = []
	for pair in connections:
		var segs = _route_connection(pair[0], pair[1])
		all_segments.append_array(segs)

	_place_floors_and_ceilings(all_segments)
	_place_walls(all_segments)

# ── Routing ────────────────────────────────────────────────────────────────────

func _snap_to_cardinal(dir: Vector3) -> Vector3:
	if abs(dir.x) >= abs(dir.z):
		return Vector3(signf(dir.x), 0.0, 0.0)
	return Vector3(0.0, 0.0, signf(dir.z))

func _route_connection(ga: Marker3D, gb: Marker3D) -> Array:
	var pos_a := ga.global_position
	var pos_b := gb.global_position
	var dir_a := _snap_to_cardinal(-ga.global_transform.basis.z)
	var dir_b := _snap_to_cardinal(-gb.global_transform.basis.z)
	var y     := pos_a.y

	var stub_a := Vector3(pos_a.x + dir_a.x * MIN_EXIT, y, pos_a.z + dir_a.z * MIN_EXIT)
	var stub_b := Vector3(pos_b.x + dir_b.x * MIN_EXIT, y, pos_b.z + dir_b.z * MIN_EXIT)

	var segments: Array = []
	_try_add(segments, pos_a, stub_a, y)
	_try_add(segments, pos_b, stub_b, y)

	var dx: float = absf(stub_b.x - stub_a.x)
	var dz: float = absf(stub_b.z - stub_a.z)

	if dx < 0.05 or dz < 0.05:
		# Already aligned on one axis — straight shot
		_try_add(segments, stub_a, stub_b, y)
	else:
		var elbow_xz := Vector3(stub_b.x, y, stub_a.z)
		var elbow_zx := Vector3(stub_a.x, y, stub_b.z)
		var use_xz   := (elbow_xz - stub_a).dot(dir_a) >= 0.0
		var elbow    := elbow_xz if use_xz else elbow_zx
		_try_add(segments, stub_a, elbow, y)
		_try_add(segments, elbow, stub_b, y)

	return segments

func _try_add(segments: Array, a: Vector3, b: Vector3, y: float) -> void:
	if a.distance_to(b) < 0.05:
		return
	var delta := b - a
	var axis  := 0 if abs(delta.x) >= abs(delta.z) else 2
	segments.append({"from": a, "to": b, "axis": axis, "y": y})

# ── Pass 1: floors, ceilings, footprints ───────────────────────────────────────

func _place_floors_and_ceilings(all_segments: Array) -> void:
	var W := CORRIDOR_WIDTH
	for seg in all_segments:
		var fa: Vector3  = seg["from"]
		var fb: Vector3  = seg["to"]
		var sy: float    = seg["y"]
		var axis: int    = seg["axis"]
		var cx: float    = (fa.x + fb.x) * 0.5
		var cz: float    = (fa.z + fb.z) * 0.5
		var length: float = fa.distance_to(fb)

		var slab: Vector3
		if axis == 0:
			slab = Vector3(length, SLAB_T, W)
		else:
			slab = Vector3(W, SLAB_T, length)

		_make_box(slab, Vector3(cx, sy + SLAB_T * 0.5,                   cz))
		_make_box(slab, Vector3(cx, sy + CORRIDOR_HEIGHT - SLAB_T * 0.5, cz))

		if axis == 0:
			_footprints.append({
				"x_min": min(fa.x, fb.x), "x_max": max(fa.x, fb.x),
				"z_min": fa.z - W * 0.5,  "z_max": fa.z + W * 0.5,
				"y": sy
			})
		else:
			_footprints.append({
				"x_min": fa.x - W * 0.5, "x_max": fa.x + W * 0.5,
				"z_min": min(fa.z, fb.z), "z_max": max(fa.z, fb.z),
				"y": sy
			})

# ── Pass 2: walls (ceiling-check junction suppression) ─────────────────────────

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

# Returns x-ranges of [x_start, x_end] NOT covered by any footprint at wall_z.
# A footprint "covers" wall_z only if wall_z is strictly interior to its Z range
# (boundary touches are the wall's own footprint — not a junction).
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

# Returns z-ranges of [z_start, z_end] NOT covered by any footprint at wall_x.
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

# Subtract a list of [start,end] covers from [base_start, base_end].
# Returns an Array of [start,end] pairs that remain uncovered.
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
		if iv[1] - iv[0] > 0.05:
			filtered.append(iv)
	return filtered

# ── Rendering helper ───────────────────────────────────────────────────────────

func _make_box(size: Vector3, world_center: Vector3) -> void:
	var box := CSGBox3D.new()
	box.size     = size
	box.position = to_local(world_center)
	_csg_root.add_child(box)
