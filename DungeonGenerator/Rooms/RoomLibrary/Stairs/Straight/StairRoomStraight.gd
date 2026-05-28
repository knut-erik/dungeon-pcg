extends BaseRoom
class_name StairRoomStraight

const CORRIDOR_WIDTH := 3.0
const CORRIDOR_HEIGHT := 3.4
const STEP_HEIGHT := 0.25
const STEP_DEPTH := 0.4
const MIN_LENGTH := 4.0
const UV_SCALE := 2.0
const COLLISION_FLOOR_THICKNESS := 0.35
const COLLISION_WALL_THICKNESS := 0.3

@onready var bounding_box: Area3D = $Area3D
@onready var stair_tunnel: MeshInstance3D = $StairTunnel
@onready var static_body: StaticBody3D = $StaticBody3D
@onready var collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D


func _ready() -> void:
	gateway_in = $Target
	gateway_out = $Target2


func setup_room(_rng: RandomNumberGenerator, logic_node: LogicalNode) -> void:
	var delta_y := float(logic_node.custom_data.get("delta_y", 4.0))
	var num_steps := maxf(1.0, absf(delta_y) / STEP_HEIGHT)
	var total_length := maxf(MIN_LENGTH, num_steps * STEP_DEPTH)

	var min_y := minf(0.0, delta_y)
	var max_y := maxf(0.0, delta_y) + CORRIDOR_HEIGHT
	room_size = Vector3(CORRIDOR_WIDTH, max_y - min_y, total_length)

	var bounds_shape := bounding_box.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if bounds_shape != null and bounds_shape.shape is BoxShape3D:
		var box_shape := bounds_shape.shape.duplicate() as BoxShape3D
		bounds_shape.shape = box_shape
		box_shape.size = room_size
		bounding_box.position = Vector3(0.0, (min_y + max_y) * 0.5, 0.0)

	gateway_in.position = Vector3(0.0, 0.0, total_length * 0.5)
	gateway_in.rotation_degrees.y = 180.0

	gateway_out.position = Vector3(0.0, delta_y, -total_length * 0.5)
	gateway_out.rotation_degrees.y = 0.0

	_build_enclosed_slope(total_length, delta_y)


func _build_enclosed_slope(total_length: float, delta_y: float) -> void:
	var half_width := CORRIDOR_WIDTH * 0.5
	var z_in := total_length * 0.5
	var z_out := -total_length * 0.5
	var y_in := 0.0
	var y_out := delta_y
	var h := CORRIDOR_HEIGHT

	var floor_left_in := Vector3(-half_width, y_in, z_in)
	var floor_right_in := Vector3(half_width, y_in, z_in)
	var floor_right_out := Vector3(half_width, y_out, z_out)
	var floor_left_out := Vector3(-half_width, y_out, z_out)

	var ceil_left_in := floor_left_in + Vector3.UP * h
	var ceil_right_in := floor_right_in + Vector3.UP * h
	var ceil_right_out := floor_right_out + Vector3.UP * h
	var ceil_left_out := floor_left_out + Vector3.UP * h

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	_add_quad(
		st,
		floor_left_in, floor_right_in, floor_right_out, floor_left_out,
		Vector2.ZERO,
		Vector2(CORRIDOR_WIDTH, total_length)
	)
	_add_quad(
		st,
		ceil_left_in, ceil_left_out, ceil_right_out, ceil_right_in,
		Vector2.ZERO,
		Vector2(CORRIDOR_WIDTH, total_length)
	)
	_add_quad(
		st,
		floor_left_in, floor_left_out, ceil_left_out, ceil_left_in,
		Vector2.ZERO,
		Vector2(total_length, h)
	)
	_add_quad(
		st,
		floor_right_in, ceil_right_in, ceil_right_out, floor_right_out,
		Vector2.ZERO,
		Vector2(total_length, h)
	)

	st.generate_normals()
	st.generate_tangents()
	stair_tunnel.mesh = st.commit()
	stair_tunnel.material_override = _make_stair_material()

	_build_stable_collision(floor_left_in, floor_right_in, floor_right_out, floor_left_out)


func _build_stable_collision(
	floor_left_in: Vector3,
	floor_right_in: Vector3,
	floor_right_out: Vector3,
	floor_left_out: Vector3
) -> void:
	_clear_generated_collision_shapes()

	var floor_shape := ConvexPolygonShape3D.new()
	var floor_down := Vector3.DOWN * COLLISION_FLOOR_THICKNESS
	floor_shape.points = PackedVector3Array([
		floor_left_in,
		floor_right_in,
		floor_right_out,
		floor_left_out,
		floor_left_in + floor_down,
		floor_right_in + floor_down,
		floor_right_out + floor_down,
		floor_left_out + floor_down,
	])

	collision_shape.position = Vector3.ZERO
	collision_shape.rotation = Vector3.ZERO
	collision_shape.disabled = false
	collision_shape.shape = floor_shape

	_add_wall_collision("GeneratedLeftWallCollision", floor_left_in, floor_left_out, Vector3.LEFT)
	_add_wall_collision("GeneratedRightWallCollision", floor_right_in, floor_right_out, Vector3.RIGHT)


func _clear_generated_collision_shapes() -> void:
	for child in static_body.get_children():
		var node: Node = child as Node
		if node != null and str(node.name).begins_with("Generated"):
			node.queue_free()


func _add_wall_collision(shape_name: String, floor_start: Vector3, floor_end: Vector3, outward: Vector3) -> void:
	var wall_shape := ConvexPolygonShape3D.new()
	var wall_offset := outward.normalized() * COLLISION_WALL_THICKNESS
	var wall_up := Vector3.UP * CORRIDOR_HEIGHT
	wall_shape.points = PackedVector3Array([
		floor_start,
		floor_end,
		floor_end + wall_up,
		floor_start + wall_up,
		floor_start + wall_offset,
		floor_end + wall_offset,
		floor_end + wall_up + wall_offset,
		floor_start + wall_up + wall_offset,
	])

	var shape_node := CollisionShape3D.new()
	shape_node.name = shape_name
	shape_node.shape = wall_shape
	static_body.add_child(shape_node)


func _add_quad(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	uv_origin: Vector2,
	uv_size: Vector2
) -> void:
	var uv_a := uv_origin / UV_SCALE
	var uv_b := (uv_origin + Vector2(uv_size.x, 0.0)) / UV_SCALE
	var uv_c := (uv_origin + uv_size) / UV_SCALE
	var uv_d := (uv_origin + Vector2(0.0, uv_size.y)) / UV_SCALE

	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_b)
	st.add_vertex(b)
	st.set_uv(uv_c)
	st.add_vertex(c)

	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_c)
	st.add_vertex(c)
	st.set_uv(uv_d)
	st.add_vertex(d)


func _make_stair_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = load("res://Assets/Textures/Floors/Stone_floors/cobblestone3/cobblestone3.tres")
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
