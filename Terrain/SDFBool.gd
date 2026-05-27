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
@export var carve_mode: CarveMode = CarveMode.BOX_AABB
@export var fallback_size := Vector3(10.0, 10.0, 30.0)
@export var fallback_local_center := Vector3.ZERO
@export var sphere_step := 3.0
@export var radius_padding := 0.75
@export var bounds_padding := 1.0
@export var wait_for_terrain_settle := true
@export var settle_stable_frames := 60
@export var settle_timeout_seconds := 8.0
@export var force_lod_refresh_after_apply := true
@export var lod_refresh_extra_frames := 45
@export var stale_chunk_reapply_count := 4
@export var stale_chunk_reapply_interval_frames := 30
@export var debug_print := true

var _applied := false
var _queued_modify_count := 0


func _ready() -> void:
	if auto_apply_on_ready:
		call_deferred("_apply_after_ready")


func _apply_after_ready() -> void:
	await get_tree().process_frame
	if wait_for_terrain_settle:
		await _wait_for_terrain_to_settle()
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
	_queued_modify_count = 0

	var shape_node: CollisionShape3D = get_node_or_null(collision_shape_path) as CollisionShape3D
	if shape_node != null and shape_node.shape is BoxShape3D:
		var box_shape: BoxShape3D = shape_node.shape as BoxShape3D
		carve_transform = shape_node.global_transform
		carve_size = box_shape.size

	_apply_carve(terrain, carve_transform, carve_size)

	_applied = true

	if force_lod_refresh_after_apply:
		_refresh_and_reapply_for_stale_chunks(terrain, carve_transform, carve_size)


func _wait_for_terrain_to_settle() -> void:
	var terrain: Node3D = _find_terrain()
	if terrain == null:
		return

	var elapsed := 0.0
	var stable_frames := 0
	var previous_chunk_count := -1

	while elapsed < settle_timeout_seconds:
		await get_tree().process_frame
		var delta := get_process_delta_time()
		elapsed += delta

		var chunk_count := _count_terrain_chunks(terrain)
		if chunk_count > 0 and chunk_count == previous_chunk_count:
			stable_frames += 1
		else:
			stable_frames = 0

		previous_chunk_count = chunk_count

		if stable_frames >= settle_stable_frames:
			if debug_print:
				print("SDFBool: terrain settled after ", snappedf(elapsed, 0.01), "s chunks=", chunk_count)
			return

	if debug_print:
		print("SDFBool: terrain settle wait timed out after ", snappedf(elapsed, 0.01), "s")


func _count_terrain_chunks(terrain: Node) -> int:
	var count := 0

	for child: Node in terrain.get_children():
		if child.get_class() == "JarVoxelChunk":
			count += 1

	return count


func _refresh_and_reapply_for_stale_chunks(
	terrain: Node3D,
	carve_transform: Transform3D,
	carve_size: Vector3
) -> void:
	var wait_frames: int = maxi(1, _queued_modify_count + lod_refresh_extra_frames)
	await _wait_frames(wait_frames)

	if terrain != null and terrain.has_method("force_update_lod"):
		terrain.call("force_update_lod")

	for pass_index in range(stale_chunk_reapply_count):
		await _wait_frames(stale_chunk_reapply_interval_frames)

		if terrain == null:
			return

		_apply_carve(terrain, carve_transform, carve_size)

		if terrain.has_method("force_update_lod"):
			terrain.call("force_update_lod")

		if debug_print:
			print("SDFBool: stale-chunk reapply pass=", pass_index + 1)


func _wait_frames(frame_count: int) -> void:
	for _i in range(maxi(0, frame_count)):
		await get_tree().process_frame


func _apply_carve(terrain: Node3D, carve_transform: Transform3D, carve_size: Vector3) -> void:
	if carve_mode == CarveMode.BOX_AABB:
		_apply_box_aabb_carve(terrain, carve_transform, carve_size)
	else:
		_apply_sphere_chain_carve(terrain, carve_transform, carve_size)

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
	_queued_modify_count = samples + 1

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
	_queued_modify_count = 1
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
