class_name AnimatedMesh
extends LockComponent

enum AnimationMode {
	NONE,
	ROTATE,
	TRANSLATE,
	SCALE,
	FADE_OUT
}

@export_enum("None", "Rotate", "Translate", "Scale", "Fade Out")
var animation_mode: int = AnimationMode.ROTATE

@export var animated_node_path: NodePath

@export var animation_seconds := 0.55
@export var one_shot := true
@export var toggle_on_reactivation := false

@export var target_rotation_degrees := Vector3.ZERO
@export var target_position_offset := Vector3.ZERO
@export var target_scale_multiplier := Vector3.ONE

@export var starts_activated := false
@export var disable_collision_on_activation := false
@export var reenable_collision_on_deactivation := true
@export var queue_free_after_activation := false

var _animated_node: Node3D
var _base_rotation_degrees := Vector3.ZERO
var _base_position := Vector3.ZERO
var _base_scale := Vector3.ONE

var _activated := false
var _tween: Tween
var _fade_materials: Array[StandardMaterial3D] = []
var _current_alpha := 1.0


func _default_component_type() -> String:
	return "animated_mesh"


func _default_agent_tag() -> String:
	return "animated"


func _ready() -> void:
	super._ready()

	add_to_group("lock_targets")
	add_to_group("animated_mesh")

	_animated_node = get_node_or_null(animated_node_path) as Node3D
	if _animated_node == null:
		_animated_node = self

	_base_rotation_degrees = _animated_node.rotation_degrees
	_base_position = _animated_node.position
	_base_scale = _animated_node.scale

	if animation_mode == AnimationMode.FADE_OUT:
		_prepare_fade_materials()

	if starts_activated:
		_activated = true
		_apply_final_state()

	_sync_component_metadata()


func receive_lock_activation(
	incoming_lock_id: StringName,
	source: Node = null,
	actor: Node = null
) -> void:
	if incoming_lock_id != lock_id:
		return
	var source_name := str(source.name) if source != null else "null"
	if debug_lock_events:
		print(
			"AnimatedMesh: ",
			name,
			" received lock_id=",
			incoming_lock_id,
			" from=",
			source_name,
			" component_id=",
			component_id,
			" component_type=",
			component_type
		)

	if _activated:
		if toggle_on_reactivation:
			deactivate(source, actor)
		elif one_shot:
			return
		else:
			activate(source, actor)
	else:
		activate(source, actor)


func activate(_source: Node = null, _actor: Node = null) -> void:
	_activated = true

	if disable_collision_on_activation:
		_set_collision_enabled(false)

	_play_animation(true)


func deactivate(_source: Node = null, _actor: Node = null) -> void:
	_activated = false

	if reenable_collision_on_deactivation:
		_set_collision_enabled(true)

	_play_animation(false)


func _play_animation(to_activated: bool) -> void:
	if _tween != null:
		_tween.kill()

	_tween = create_tween()

	match animation_mode:
		AnimationMode.NONE:
			pass

		AnimationMode.ROTATE:
			var target_rotation := _base_rotation_degrees
			if to_activated:
				target_rotation += target_rotation_degrees

			_tween.tween_property(
				_animated_node,
				"rotation_degrees",
				target_rotation,
				animation_seconds
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

		AnimationMode.TRANSLATE:
			var target_position := _base_position
			if to_activated:
				target_position += target_position_offset

			_tween.tween_property(
				_animated_node,
				"position",
				target_position,
				animation_seconds
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

		AnimationMode.SCALE:
			var target_scale := _base_scale
			if to_activated:
				target_scale = Vector3(
					_base_scale.x * target_scale_multiplier.x,
					_base_scale.y * target_scale_multiplier.y,
					_base_scale.z * target_scale_multiplier.z
				)

			_tween.tween_property(
				_animated_node,
				"scale",
				target_scale,
				animation_seconds
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

		AnimationMode.FADE_OUT:
			var target_alpha := 0.0 if to_activated else 1.0

			_tween.tween_method(
				_set_alpha,
				_current_alpha,
				target_alpha,
				animation_seconds
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if to_activated and queue_free_after_activation:
		_tween.tween_callback(queue_free)


func _apply_final_state() -> void:
	match animation_mode:
		AnimationMode.ROTATE:
			_animated_node.rotation_degrees = _base_rotation_degrees + target_rotation_degrees

		AnimationMode.TRANSLATE:
			_animated_node.position = _base_position + target_position_offset

		AnimationMode.SCALE:
			_animated_node.scale = Vector3(
				_base_scale.x * target_scale_multiplier.x,
				_base_scale.y * target_scale_multiplier.y,
				_base_scale.z * target_scale_multiplier.z
			)

		AnimationMode.FADE_OUT:
			_set_alpha(0.0)

	if disable_collision_on_activation:
		_set_collision_enabled(false)


func _set_collision_enabled(enabled: bool) -> void:
	for shape in find_children("*", "CollisionShape3D", true, false):
		shape.set_deferred("disabled", not enabled)


func _prepare_fade_materials() -> void:
	_fade_materials.clear()

	for mesh_instance in find_children("*", "MeshInstance3D", true, false):
		var mesh_node := mesh_instance as MeshInstance3D
		if mesh_node.mesh == null:
			continue

		for surface_index in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_surface_override_material(surface_index)

			if material == null:
				material = mesh_node.get_active_material(surface_index)

			var fade_material := _make_fade_material(material)
			mesh_node.set_surface_override_material(surface_index, fade_material)
			_fade_materials.append(fade_material)

	for csg_shape in find_children("*", "CSGShape3D", true, false):
		var csg := csg_shape as CSGShape3D
		var fade_material := _make_fade_material(csg.material)
		csg.material = fade_material
		_fade_materials.append(fade_material)


func _make_fade_material(source_material: Material) -> StandardMaterial3D:
	var material: StandardMaterial3D

	if source_material is StandardMaterial3D:
		material = source_material.duplicate() as StandardMaterial3D
	else:
		material = StandardMaterial3D.new()

	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var color := material.albedo_color
	color.a = 1.0
	material.albedo_color = color

	return material


func _set_alpha(alpha: float) -> void:
	_current_alpha = alpha

	for material in _fade_materials:
		var color := material.albedo_color
		color.a = alpha
		material.albedo_color = color
