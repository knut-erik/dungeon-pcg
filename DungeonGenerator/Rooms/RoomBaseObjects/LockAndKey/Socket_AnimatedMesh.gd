class_name AnimatedMeshSocket
extends Node3D

@export var socket_role: String = "animated_mesh"
@export var gateway_role: String = ""
@export var allowed_component_types: Array[String] = ["hinge_door", "false_door"]


func _ready() -> void:
	set_meta("socket_role", socket_role)
	set_meta("gateway_role", gateway_role)


func can_accept_component_role(role: String) -> bool:
	return role == socket_role


func can_accept_gateway_role(role: String) -> bool:
	return gateway_role.is_empty() or gateway_role == role


func can_accept_component_type(component_type: String) -> bool:
	return allowed_component_types.is_empty() or allowed_component_types.has(component_type)
