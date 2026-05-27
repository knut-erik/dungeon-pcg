extends BaseRoom
class_name StairRoomCavern

var path: Path3D
var cave_mesh: MeshInstance3D
@onready var bounding_box = $Area3D 

# Called when the node enters the scene tree for the first time.
func _ready() -> void:

	gateway_in = $Target
	gateway_out = $Target2


func setup_room(_rng: RandomNumberGenerator, logic_node: LogicalNode):
	var delta_y = logic_node.custom_data.get("delta_y", 4.0)

	var cave_radius: float = 3.0
	var floor_percent: float = 65.0

	var floor_vertical_offset: float = -cave_radius * clamp(floor_percent, 0.0, 100.0) / 100.0
	var path_center_offset_y: float = -floor_vertical_offset

	path = create_random_path(_rng, Vector3(0.0, path_center_offset_y, 0.0), delta_y, 10, 3.5)

	create_floor_mesh_along_path(path, 0.75, cave_radius, floor_percent)
	create_walkable_floor_collision_along_path(path, 0.75, cave_radius, floor_percent)

	gateway_in.position = path.curve.get_point_position(0) + Vector3(0.0, floor_vertical_offset, 0.0)
	gateway_in.rotation_degrees.y = 180
	
	gateway_out.position = path.curve.get_point_position(path.curve.point_count - 1) + Vector3(0.0, floor_vertical_offset, 0.0)
	gateway_out.rotation_degrees.y = 0
	
	_update_bounding_box_from_path(path, cave_radius, delta_y)

	var cave := MeshInstance3D.new()
	cave.mesh = create_noisy_tube_mesh_along_path(
		_rng,
		path,
		0.75,
		24,
		cave_radius,
		0.45
	)

	var material := StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = load("res://Assets/Textures/grass.png")
	cave.material_override = material
	path.add_child(cave)
	
func create_walkable_floor_collision_along_path(
	path: Path3D,
	spacing: float = 0.75,
	radius: float = 3.0,
	floor_percent: float = 65.0
) -> void:
	var curve := path.curve
	if curve == null:
		return

	var baked_length := curve.get_baked_length()
	if baked_length <= spacing:
		return

	var percent: float = clamp(floor_percent, 0.0, 100.0) / 100.0
	var vertical_offset: float = -radius * percent
	var half_width: float = sqrt(max(0.0, radius * radius - vertical_offset * vertical_offset))

	var static_body := StaticBody3D.new()
	static_body.name = "CaveFloorCollision"
	path.add_child(static_body)

	var segment_count := int(baked_length / spacing)

	for i in range(segment_count):
		var d0: float = float(i) * spacing
		var d1: float = min(float(i + 1) * spacing, baked_length)
		var mid_d: float = (d0 + d1) * 0.5

		var p0 := curve.sample_baked(d0, true)
		var p1 := curve.sample_baked(d1, true)
		var center := curve.sample_baked(mid_d, true)

		var tangent := (p1 - p0).normalized()
		if tangent.length() < 0.001:
			continue

		var world_up := Vector3.UP
		if abs(tangent.dot(world_up)) > 0.95:
			world_up = Vector3.RIGHT

		var right := world_up.cross(tangent).normalized()
		var up := tangent.cross(right).normalized()

		var floor_center := center + up * vertical_offset

		var shape := BoxShape3D.new()
		shape.size = Vector3(
			half_width * 2.0,
			0.25,
			max(spacing, 0.25)
		)

		var collision := CollisionShape3D.new()
		collision.shape = shape

		# Box local axes:
		# X = right/width, Y = up/thickness, Z = tangent/length.
		var basis := Basis()
		basis.x = right
		basis.y = up
		basis.z = -tangent
		basis = basis.orthonormalized()

		collision.transform = Transform3D(basis, floor_center)

		static_body.add_child(collision)

func _update_bounding_box_from_path(path: Path3D, cave_radius: float, delta_y: float) -> void:
	var curve := path.curve
	if curve == null:
		return

	var baked_points := curve.get_baked_points()
	if baked_points.is_empty():
		return

	var min_pos: Vector3 = baked_points[0]
	var max_pos: Vector3 = baked_points[0]

	for p in baked_points:
		min_pos.x = min(min_pos.x, p.x)
		min_pos.y = min(min_pos.y, p.y)
		min_pos.z = min(min_pos.z, p.z)

		max_pos.x = max(max_pos.x, p.x)
		max_pos.y = max(max_pos.y, p.y)
		max_pos.z = max(max_pos.z, p.z)

	var start_pos := curve.get_point_position(0)
	var end_pos := curve.get_point_position(curve.point_count - 1)

	# Add cave radius sideways and vertically.
	min_pos.x -= cave_radius
	max_pos.x += cave_radius
	min_pos.y -= cave_radius
	max_pos.y += cave_radius

	# But keep the entry/exit faces exactly on the gateways.
	# This assumes the stair mainly runs along local Z, like StairRoomStraight.
	min_pos.z = min(start_pos.z, end_pos.z)
	max_pos.z = max(start_pos.z, end_pos.z)

	room_size = max_pos - min_pos

	var collision_shape := bounding_box.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape != null and collision_shape.shape is BoxShape3D:
		collision_shape.shape = collision_shape.shape.duplicate()
		collision_shape.shape.size = room_size

	bounding_box.position = (min_pos + max_pos) * 0.5

func create_noisy_tube_mesh_along_path(
	rng: RandomNumberGenerator,
	path: Path3D,
	spacing: float = 0.75,
	ring_segments: int = 24,
	radius: float = 3.0,
	noise_strength: float = 0.4
) -> ArrayMesh:
	var curve := path.curve
	if curve == null:
		return ArrayMesh.new()

	var baked_length := curve.get_baked_length()
	if baked_length <= spacing:
		return ArrayMesh.new()

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var ring_count := int(baked_length / spacing) + 1

	for i in range(ring_count):
		var d: float = min(float(i) * spacing, baked_length)
		
		var center: Vector3 = curve.sample_baked(d, true)
		var next_d: float = min(d + 0.1, baked_length)
		var prev_d: float = max(d - 0.1, 0.0)

		var p_next := curve.sample_baked(next_d, true)
		var p_prev := curve.sample_baked(prev_d, true)

		var tangent := (p_next - p_prev).normalized()

		# Build a local coordinate frame around the path.
		var world_up := Vector3.UP
		if abs(tangent.dot(world_up)) > 0.95:
			world_up = Vector3.RIGHT

		var right := world_up.cross(tangent).normalized()
		var up := tangent.cross(right).normalized()

		for j in range(ring_segments):
			var t := float(j) / float(ring_segments)
			var angle := t * TAU

			var radial_dir := right * cos(angle) + up * sin(angle)

			var noisy_radius := radius + rng.randf_range(-noise_strength, noise_strength)

			var pos := center + radial_dir * noisy_radius

			vertices.append(pos)
			normals.append(radial_dir.normalized())
			uvs.append(Vector2(t, float(i) / float(ring_count - 1)))

	for i in range(ring_count - 1):
		for j in range(ring_segments):
			var a := i * ring_segments + j
			var b := i * ring_segments + ((j + 1) % ring_segments)
			var c := (i + 1) * ring_segments + j
			var d := (i + 1) * ring_segments + ((j + 1) % ring_segments)

			# Reverse these if the mesh appears inside-out.
			indices.append_array([a, c, b])
			indices.append_array([b, c, d])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return mesh

# Creates a random 3D path starting at start_position
# and draws it as a visible line in the scene.
func create_random_path(
	rng: RandomNumberGenerator,
	start_position: Vector3,
	delta_y: float,
	point_count: int = 8,
	step_length: float = 4.0
) -> Path3D:
	var path := Path3D.new()
	add_child(path)
	path.position = Vector3.ZERO

	var curve := Curve3D.new()
	path.curve = curve

	var total_length: float = float(point_count - 1) * step_length

	var start_point := Vector3(0.0, start_position.y, total_length / 2.0)
	var end_point := Vector3(0.0, delta_y + start_position.y, -total_length / 2.0)

	# Length of straight connector sections at both ends.
	var end_straight_length: float = step_length

	var start_anchor := start_point + Vector3(0.0, 0.0, -end_straight_length)
	var end_anchor := end_point + Vector3(0.0, 0.0, end_straight_length)

	curve.add_point(start_point)
	curve.add_point(start_anchor)

	var middle_count: int = max(0, point_count - 4)

	for i in range(middle_count):
		var t: float = float(i + 1) / float(middle_count + 1)

		var base_pos := start_anchor.lerp(end_anchor, t)

		# Keep randomness away from the ends.
		var fade: float = sin(t * PI)

		var side_offset := Vector3(
			rng.randf_range(-2.0, 2.0) * fade,
			rng.randf_range(-1.0, 1.0) * fade,
			rng.randf_range(-1.0, 1.0) * fade
		)

		curve.add_point(base_pos + side_offset)

	curve.add_point(end_anchor)
	curve.add_point(end_point)

	# Smooth middle points, but keep the first and last tangents aligned with Z.
	for i in range(curve.point_count):
		if i > 0 and i < curve.point_count - 1:
			var prev_pos := curve.get_point_position(i - 1)
			var next_pos := curve.get_point_position(i + 1)

			var tangent := (next_pos - prev_pos).normalized()
			var handle_size := step_length * 0.35

			curve.set_point_in(i, -tangent * handle_size)
			curve.set_point_out(i, tangent * handle_size)

	# Force start/end bezier handles to point along local Z.
	var end_handle_size: float = end_straight_length * 0.5

	curve.set_point_out(0, Vector3(0.0, 0.0, -end_handle_size))
	curve.set_point_in(1, Vector3(0.0, 0.0, end_handle_size))

	var last := curve.point_count - 1
	curve.set_point_out(last - 1, Vector3(0.0, 0.0, -end_handle_size))
	curve.set_point_in(last, Vector3(0.0, 0.0, end_handle_size))

	#_draw_curve(path)

	return path


#func _draw_curve(path: Path3D) -> void:
	#var curve := path.curve
	#if curve == null:
		#return
#
	#var baked_points := curve.get_baked_points()
	#if baked_points.size() < 2:
		#return
#
	#var mesh := ImmediateMesh.new()
	#mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
#
	#for p in baked_points:
		#mesh.surface_add_vertex(p)
#
	#mesh.surface_end()
#
	#var mesh_instance := MeshInstance3D.new()
	#mesh_instance.mesh = mesh
	#path.add_child(mesh_instance)
#
	#var material := StandardMaterial3D.new()
	#material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	#material.albedo_color = Color(1.0, 0.2, 0.2)
	#material.vertex_color_use_as_albedo = false
#
	#mesh_instance.material_override = material

func create_floor_mesh_along_path(
	path: Path3D,
	spacing: float = 0.75,
	radius: float = 3.0,
	floor_percent: float = 0.0
) -> float:
	var curve := path.curve
	if curve == null:
		return 0

	var baked_length: float = curve.get_baked_length()
	if baked_length <= spacing:
		return 0

	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()

	var point_count: int = int(baked_length / spacing) + 1

	var percent: float = clamp(floor_percent, 0.0, 100.0) / 100.0

	# 0% gives height 0, meaning through the cave center.
	# 100% gives height -radius, meaning lowest point of the cave.
	var vertical_offset: float = -radius * percent

	# Half-width of a circle chord at this vertical offset.
	# At center: full width = diameter.
	# At bottom: width becomes 0, mathematically.
	var half_width: float = sqrt(max(0.0, radius * radius - vertical_offset * vertical_offset))

	for i in range(point_count):
		var distance: float = float(i) * spacing
		if distance > baked_length:
			distance = baked_length

		var center: Vector3 = curve.sample_baked(distance, true)

		var next_distance: float = distance + 0.1
		if next_distance > baked_length:
			next_distance = baked_length

		var prev_distance: float = distance - 0.1
		if prev_distance < 0.0:
			prev_distance = 0.0

		var p_next: Vector3 = curve.sample_baked(next_distance, true)
		var p_prev: Vector3 = curve.sample_baked(prev_distance, true)

		var tangent: Vector3 = (p_next - p_prev).normalized()

		var world_up: Vector3 = Vector3.UP
		if abs(tangent.dot(world_up)) > 0.95:
			world_up = Vector3.RIGHT

		var right: Vector3 = world_up.cross(tangent).normalized()
		var up: Vector3 = tangent.cross(right).normalized()

		var floor_center: Vector3 = center + up * vertical_offset

		var left_pos: Vector3 = floor_center + right * half_width
		var right_pos: Vector3 = floor_center - right * half_width

		vertices.append(left_pos)
		vertices.append(right_pos)

		normals.append(up)
		normals.append(up)

		var v: float = float(i) / float(point_count - 1)
		uvs.append(Vector2(0.0, v))
		uvs.append(Vector2(1.0, v))

	for i in range(point_count - 1):
		var left_a: int = i * 2
		var right_a: int = i * 2 + 1
		var left_b: int = i * 2 + 2
		var right_b: int = i * 2 + 3

		indices.append_array([left_a, right_a, left_b])
		indices.append_array([right_a, right_b, left_b])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	path.add_child(mesh_instance)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.28, 0.2)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	return vertical_offset
