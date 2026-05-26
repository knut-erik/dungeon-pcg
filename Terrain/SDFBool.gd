extends Area3D
class_name TerrainSDFBool

enum CarveMode {
	SPHERE_CHAIN,
	BOX_AABB
}

const SDF_OPERATION_SUBTRACTION := 1

@export var terrain_path: NodePath = ^"../../JarVoxelTerrain"
@export var collision_shape_path: NodePath = ^"CollisionShape3D"
@export var auto_apply_on_ready := true
@export var apply_once := true
@export var carve_mode: CarveMode = CarveMode.SPHERE_CHAIN
@export var fallback_size := Vector3(10.0, 10.0, 30.0)
@export var fallback_local_center := Vector3.ZERO
@export var sphere_step := 3.0
@export var radius_padding := 0.75
@export var bounds_padding := 2.0
@export var debug_print := true

var _applied := false


func _ready() -> void:
	if auto_apply_on_ready:
		call_deferred("_apply_after_ready")


func _apply_after_ready() -> void:
	await get_tree().process_frame
	apply()


func apply() -> void:
	if apply_once and _applied:
		return

	var terrain: Node3D = _find_terrain()
	if terrain == null:
		push_warning("SDFBool: Could not find JarVoxelTerrain at %s." % terrain_path)
		return

	if not terrain.has_method("modify"):
		push_warning("SDFBool: Target terrain has no modify() method.")
		return

	var carve_transform: Transform3D = global_transform * Transform3D(Basis.IDENTITY, fallback_local_center)
	var carve_size: Vector3 = fallback_size

	var shape_node: CollisionShape3D = get_node_or_null(collision_shape_path) as CollisionShape3D
	if shape_node != null and shape_node.shape is BoxShape3D:
		var box_shape: BoxShape3D = shape_node.shape as BoxShape3D
		carve_transform = shape_node.global_transform
		carve_size = box_shape.size

	if carve_mode == CarveMode.BOX_AABB:
		_apply_box_aabb_carve(terrain, carve_transform, carve_size)
	else:
		_apply_sphere_chain_carve(terrain, carve_transform, carve_size)

	_applied = true


func _find_terrain() -> Node3D:
	var terrain: Node3D = get_node_or_null(terrain_path) as Node3D
	if terrain != null:
		return terrain

	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return null

	return _find_first_terrain_recursive(current_scene)


func _find_first_terrain_recursive(node: Node) -> Node3D:
	if node is Node3D and node.has_method("modify") and node.get_class() == "JarVoxelTerrain":
		return node as Node3D

	for child in node.get_children():
		var found: Node3D = _find_first_terrain_recursive(child)
		if found != null:
			return found

	return null


func _apply_sphere_chain_carve(terrain: Node3D, carve_transform: Transform3D, carve_size: Vector3) -> void:
	var axes: Array[Vector3] = _get_scaled_half_axes(carve_transform, carve_size)
	var long_axis_index: int = _longest_axis_index(axes)
	var long_axis: Vector3 = axes[long_axis_index]
	var radius := 0.0

	for i in range(axes.size()):
		if i == long_axis_index:
			continue
		radius = maxf(radius, axes[i].length())

	radius += radius_padding

	var length: float = long_axis.length() * 2.0
	var samples: int = maxi(1, ceili(length / maxf(0.1, sphere_step)))
	var bounds_radius: float = radius + bounds_padding

	for sample_index in range(samples + 1):
		var t: float = float(sample_index) / float(samples)
		var world_pos: Vector3 = carve_transform.origin + long_axis * lerpf(-1.0, 1.0, t)
		var terrain_pos: Vector3 = terrain.to_local(world_pos)

		var sphere: Resource = JarSphereSdf.new()
		sphere.set("radius", radius)
		terrain.call("modify", sphere, SDF_OPERATION_SUBTRACTION, terrain_pos, bounds_radius)

	if debug_print:
		print(
			"SDFBool: queued sphere-chain subtraction samples=",
			samples + 1,
			" radius=",
			radius,
			" length=",
			length
		)


func _apply_box_aabb_carve(terrain: Node3D, carve_transform: Transform3D, carve_size: Vector3) -> void:
	var axes: Array[Vector3] = _get_scaled_half_axes(carve_transform, carve_size)
	var extent := Vector3.ZERO

	for axis in axes:
		extent += axis.abs()

	var center: Vector3 = terrain.to_local(carve_transform.origin)
	var radius: float = extent.length() + bounds_padding

	var box: Resource = JarBoxSdf.new()
	box.set("extent", extent)
	terrain.call("modify", box, SDF_OPERATION_SUBTRACTION, center, radius)

	if debug_print:
		print("SDFBool: queued AABB subtraction extent=", extent, " radius=", radius)


func _get_scaled_half_axes(carve_transform: Transform3D, carve_size: Vector3) -> Array[Vector3]:
	var half_size: Vector3 = carve_size * 0.5
	return [
		_safe_scaled_axis(carve_transform.basis.x, half_size.x),
		_safe_scaled_axis(carve_transform.basis.y, half_size.y),
		_safe_scaled_axis(carve_transform.basis.z, half_size.z)
	]


func _safe_scaled_axis(axis: Vector3, half_extent: float) -> Vector3:
	var scale: float = axis.length()
	if scale <= 0.0001:
		return Vector3.ZERO

	return axis.normalized() * half_extent * scale


func _longest_axis_index(axes: Array[Vector3]) -> int:
	var best_index := 0
	var best_length := -INF

	for i in range(axes.size()):
		var length: float = axes[i].length()
		if length > best_length:
			best_length = length
			best_index = i

	return best_index
