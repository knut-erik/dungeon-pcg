class_name FirstPersonViewModel
extends Node3D

@export var viewmodel_layers: int = 2
@export var overlay_canvas_layer: int = 200
@export var disable_shadows: bool = true
@export var swing_rotation_degrees: Vector3 = Vector3(-18.0, 0.0, -28.0)
@export var swing_duration: float = 0.09
@export var swing_return_duration: float = 0.13


var _main_camera: Camera3D
var _canvas_layer: CanvasLayer
var _overlay_viewport: SubViewport
var _overlay_camera: Camera3D
var _viewmodel_copy: Node3D
var _active_world: World3D
var _rest_transform: Transform3D
var _swing_tween: Tween


func _ready() -> void:
	_main_camera = _find_owner_camera()
	if _main_camera == null:
		push_warning("FirstPersonViewModel: no active Camera3D found.")
		return

	_main_camera.make_current()
	_rest_transform = transform
	_create_overlay_viewport()
	_create_viewmodel_copy()
	_set_render_visible(self, false)
	_sync_overlay()


func swing() -> void:
	if is_instance_valid(_swing_tween):
		_swing_tween.kill()

	transform = _rest_transform

	var swing_transform: Transform3D = _rest_transform
	swing_transform.basis = swing_transform.basis.rotated(Vector3.RIGHT, deg_to_rad(swing_rotation_degrees.x))
	swing_transform.basis = swing_transform.basis.rotated(Vector3.UP, deg_to_rad(swing_rotation_degrees.y))
	swing_transform.basis = swing_transform.basis.rotated(Vector3.FORWARD, deg_to_rad(swing_rotation_degrees.z))

	_swing_tween = create_tween()
	_swing_tween.tween_property(self, "transform", swing_transform, swing_duration)
	_swing_tween.tween_property(self, "transform", _rest_transform, swing_return_duration)


func _process(_delta: float) -> void:
	if _main_camera == null:
		return

	if not is_instance_valid(_canvas_layer) or not is_instance_valid(_overlay_viewport) or not is_instance_valid(_overlay_camera):
		_destroy_overlay()
		_create_overlay_viewport()

	if not is_instance_valid(_viewmodel_copy):
		_create_viewmodel_copy()

	if not is_instance_valid(_overlay_camera) or not is_instance_valid(_viewmodel_copy):
		return

	if not _main_camera.current:
		_main_camera.make_current()

	_sync_overlay()


func _exit_tree() -> void:
	_destroy_overlay()


func _destroy_overlay() -> void:
	if is_instance_valid(_canvas_layer):
		_canvas_layer.queue_free()

	_canvas_layer = null
	_overlay_viewport = null
	_overlay_camera = null
	_viewmodel_copy = null
	_active_world = null


func _create_overlay_viewport() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "ViewModelOverlay"
	_canvas_layer.layer = overlay_canvas_layer
	get_tree().root.add_child(_canvas_layer)

	var container: SubViewportContainer = SubViewportContainer.new()
	container.name = "ViewModelViewportContainer"
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.stretch = true
	container.anchor_right = 1.0
	container.anchor_bottom = 1.0
	_canvas_layer.add_child(container)

	_overlay_viewport = SubViewport.new()
	_overlay_viewport.name = "ViewModelViewport"
	_overlay_viewport.transparent_bg = true
	_overlay_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_overlay_viewport)
	_sync_overlay_world()

	_overlay_camera = Camera3D.new()
	_overlay_camera.name = "ViewModelCamera"
	_overlay_camera.cull_mask = viewmodel_layers
	_overlay_camera.current = true
	_overlay_viewport.add_child(_overlay_camera)


func _create_viewmodel_copy() -> void:
	_viewmodel_copy = duplicate(DUPLICATE_USE_INSTANTIATION | DUPLICATE_SCRIPTS) as Node3D
	if _viewmodel_copy == null:
		push_warning("FirstPersonViewModel: could not duplicate viewmodel.")
		return

	_viewmodel_copy.name = "%sOverlay" % name
	_viewmodel_copy.set_script(null)
	_overlay_camera.add_child(_viewmodel_copy)
	_apply_viewmodel_render_settings(_viewmodel_copy)


func _sync_overlay() -> void:
	_sync_overlay_size()
	_sync_overlay_world()
	_sync_overlay_camera()

	if _viewmodel_copy != null:
		_viewmodel_copy.transform = _main_camera.global_transform.affine_inverse() * global_transform


func _sync_overlay_size() -> void:
	if _overlay_viewport == null:
		return

	var rect_size: Vector2 = get_viewport().get_visible_rect().size
	var viewport_size: Vector2i = Vector2i(roundi(rect_size.x), roundi(rect_size.y))
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return

	if _overlay_viewport.size != viewport_size:
		_overlay_viewport.size = viewport_size


func _sync_overlay_camera() -> void:
	if _overlay_camera == null or _main_camera == null:
		return

	_overlay_camera.global_transform = _main_camera.global_transform
	_overlay_camera.projection = _main_camera.projection
	_overlay_camera.fov = _main_camera.fov
	_overlay_camera.size = _main_camera.size
	_overlay_camera.near = _main_camera.near
	_overlay_camera.far = _main_camera.far
	_overlay_camera.keep_aspect = _main_camera.keep_aspect


func _sync_overlay_world() -> void:
	if _overlay_viewport == null:
		return

	var current_world: World3D = get_viewport().world_3d
	if current_world == null or current_world == _active_world:
		return

	_active_world = current_world
	_overlay_viewport.world_3d = _active_world


func _set_render_visible(node: Node, should_be_visible: bool) -> void:
	if node is VisualInstance3D:
		var visual: VisualInstance3D = node as VisualInstance3D
		visual.visible = should_be_visible

	for child: Node in node.get_children():
		_set_render_visible(child, should_be_visible)


func _apply_viewmodel_render_settings(node: Node) -> void:
	if node is VisualInstance3D:
		var visual: VisualInstance3D = node as VisualInstance3D
		visual.visible = true
		visual.layers = viewmodel_layers

	if disable_shadows and node is GeometryInstance3D:
		var geometry: GeometryInstance3D = node as GeometryInstance3D
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for child: Node in node.get_children():
		_apply_viewmodel_render_settings(child)


func _find_owner_camera() -> Camera3D:
	var parent_node: Node = get_parent()

	while parent_node != null:
		for child: Node in parent_node.get_children():
			if child is Camera3D:
				return child as Camera3D

		parent_node = parent_node.get_parent()

	return get_viewport().get_camera_3d()
