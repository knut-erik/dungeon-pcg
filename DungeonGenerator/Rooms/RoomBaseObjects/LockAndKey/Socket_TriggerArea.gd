class_name TriggerVolumeSocket
extends Node3D

@export var socket_role: String = "trigger_volume"
@export var gateway_role: String = ""


func _ready() -> void:
	set_meta("socket_role", socket_role)
	set_meta("gateway_role", gateway_role)


func can_accept_component_role(role: String) -> bool:
	return role == socket_role


func can_accept_gateway_role(role: String) -> bool:
	return gateway_role.is_empty() or gateway_role == role
