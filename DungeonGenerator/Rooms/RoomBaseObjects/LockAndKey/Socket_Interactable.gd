class_name InteractableSocket
extends Node3D

@export var socket_role: String = "interactable"
@export var allowed_component_types: Array[String] = ["key", "lever", "coin"]


func _ready() -> void:
	set_meta("socket_role", socket_role)


func can_accept_component_role(role: String) -> bool:
	return role == socket_role


func can_accept_component_type(component_type: String) -> bool:
	return allowed_component_types.is_empty() or allowed_component_types.has(component_type)
