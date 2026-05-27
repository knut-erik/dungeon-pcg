class_name PixelPostProcess
extends CanvasLayer

static var global_effect_enabled := true

@export var effect_enabled := true:
	set(value):
		effect_enabled = value
		global_effect_enabled = value
		_sync_shader()

@export var toggle_key: Key = KEY_F9
@export_range(0.0, 1.0, 0.01) var mix_amount := 1.0:
	set(value):
		mix_amount = value
		_sync_shader()

@export_range(1.0, 8.0, 1.0) var pixel_size := 2.0:
	set(value):
		pixel_size = value
		_sync_shader()

@export_range(2.0, 16.0, 1.0) var color_steps := 7.0:
	set(value):
		color_steps = value
		_sync_shader()

@export_range(0.0, 1.0, 0.01) var dither_strength := 0.0:
	set(value):
		dither_strength = value
		_sync_shader()

@export_range(0.0, 1.0, 0.01) var edge_strength := 0.18:
	set(value):
		edge_strength = value
		_sync_shader()

@export_range(0.0, 2.0, 0.01) var saturation := 0.9:
	set(value):
		saturation = value
		_sync_shader()

@export_range(0.0, 2.0, 0.01) var contrast := 1.08:
	set(value):
		contrast = value
		_sync_shader()

@export var shadow_tint := Color(0.05, 0.08, 0.12):
	set(value):
		shadow_tint = value
		_sync_shader()

@export var highlight_tint := Color(0.86, 0.95, 1.0):
	set(value):
		highlight_tint = value
		_sync_shader()

@export_range(0.0, 1.0, 0.01) var tint_strength := 0.16:
	set(value):
		tint_strength = value
		_sync_shader()

@onready var overlay: ColorRect = $Overlay


func _ready() -> void:
	effect_enabled = global_effect_enabled
	_sync_shader()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == toggle_key:
			effect_enabled = not effect_enabled
			print("PixelPostProcess: enabled=", effect_enabled)


func set_effect_enabled(enabled: bool) -> void:
	effect_enabled = enabled


func _sync_shader() -> void:
	if overlay == null:
		return

	overlay.visible = effect_enabled

	var shader_material := overlay.material as ShaderMaterial
	if shader_material == null:
		return

	shader_material.set_shader_parameter("effect_enabled", effect_enabled)
	shader_material.set_shader_parameter("mix_amount", mix_amount)
	shader_material.set_shader_parameter("pixel_size", pixel_size)
	shader_material.set_shader_parameter("color_steps", color_steps)
	shader_material.set_shader_parameter("dither_strength", dither_strength)
	shader_material.set_shader_parameter("edge_strength", edge_strength)
	shader_material.set_shader_parameter("saturation", saturation)
	shader_material.set_shader_parameter("contrast", contrast)
	shader_material.set_shader_parameter("shadow_tint", shadow_tint)
	shader_material.set_shader_parameter("highlight_tint", highlight_tint)
	shader_material.set_shader_parameter("tint_strength", tint_strength)
